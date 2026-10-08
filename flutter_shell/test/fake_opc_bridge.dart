import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:opc_flutter_shell/opc_bridge_bindings.dart';

/// A scripted fake of the six C entry points for widget tests.
///
/// Mirrors the real bridge's ownership contract so the wrapper's marshalling
/// is exercised, not stubbed:
///  - strings the fake returns (lastError, snapshotJson) are malloc-allocated
///    and tracked by address; the wrapper MUST hand each back to `free`.
///    [unfreed] lists any the wrapper leaked — assert it empty.
///  - pointers the WRAPPER allocates (command's verb/payload via
///    toNativeUtf8) also arrive at `free`; those aren't tracked (the fake
///    never saw them born) but are still malloc.freed, so no test-process
///    leak either way.
class FakeOpcBridge {
  FakeOpcBridge({
    this.createResult = OpcBridge.ok,
    Map<String, dynamic>? initialSnapshot,
  }) : snapshots = [
          if (initialSnapshot != null) initialSnapshot,
        ];

  final int createResult;

  /// Successive snapshot payloads; the last repeats once exhausted (the real
  /// core just re-serializes current state on every call).
  final List<Map<String, dynamic>> snapshots;

  /// (verb, payload) the UI sent, in order.
  final List<(String verb, Map<String, dynamic> payload)> commands = [];

  /// rc returned by the NEXT command (then resets to ok) — script a refusal.
  int nextCommandResult = OpcBridge.ok;
  String nextError = '';

  /// scripted query payloads: set before terminal_digest()/terminalTail()
  Map<String, dynamic>? digestResult;

  /// v1.7: team_stats_list rows; defaults to a busy-but-honest office.
  List<Map<String, dynamic>>? teamStatsResult;

  /// true => simulate a core older than v1.7 (unknown verb, rc=-1).
  bool teamStatsRefused = false;

  /// v1.8: stalls_list rows; defaults to a jammed-but-honest watch.
  List<Map<String, dynamic>>? stallsResult;

  /// true => simulate a core older than v1.8 (unknown verb, rc=-1).
  bool stallsRefused = false;

  /// v1.9: catchup_md page (plain UTF-8 string, NOT JSON); null => the
  /// default one-page composition below.
  String? catchupMdResult;

  /// true => simulate a core older than v1.9 (unknown verb, rc=-1).
  bool catchupRefused = false;

  /// v1.10: weight_json object; null => the default light snapshot.
  Map<String, dynamic>? weightResult;

  /// true => simulate a core older than v1.10 (unknown verb, rc=-1).
  bool weightRefused = false;

  /// v1.11 seat steering: null => success (lastError reset to ''); a
  /// string => the verbatim refusal the next terminal_send returns.
  /// Every attempt is recorded in [terminalSends].
  String? terminalSendRefusal;
  final List<(String agentID, String line)> terminalSends = [];

  /// v1.12 seat lifecycle: per-verb refusal knobs (null => success),
  /// every start/stop recorded in [seatCommands].
  String? seatSpawnRefusal;
  String? seatStopRefusal;
  final List<(String verb, String agentID)> seatCommands = [];

  /// v1.13 seat roster: null => the default honest empty office {}.
  /// Typed dynamic so tests can script a MALFORMED payload (a non-bool
  /// value) and pin the wrapper's wholesale refusal.
  Map<String, dynamic>? seatListResult;

  /// v1.14 transcript door: null => the default two-line visible log.
  /// Typed dynamic so tests can script a MALFORMED payload (a non-String
  /// line) and pin the wrapper's wholesale refusal. A refusal string
  /// rides verbatim; every ask is recorded in [transcriptCalls].
  Map<String, dynamic>? transcriptResult;
  String? transcriptRefusal;
  final List<(String agentID, int tail)> transcriptCalls = [];

  /// v1.15 the shell's autopilot: null => success (lastError reset to
  /// ''); a string => the verbatim refusal the next call returns. Every
  /// dispatch is recorded in [autopilotCalls].
  String? autopilotRefusal;
  int autopilotCalls = 0;

  /// v1.16 the shell's checkpoint: null => success; a string => the
  /// verbatim refusal. Every (reason) ask is recorded in
  /// [checkpointReasons].
  String? checkpointRefusal;
  List<String> checkpointReasons = [];

  /// v1.22 the task file door: null => the default one-edge file below.
  /// Typed dynamic so tests can script a MALFORMED payload (a non-List
  /// workItems) and pin the wrapper's wholesale refusal.
  Map<String, dynamic>? taskShowResult;

  /// v1.23 the ack door: null => success (lastError reset to ''); a
  /// string => the verbatim refusal. Every (messageID, agentID) ask is
  /// recorded in [ackCalls].
  String? messageAckRefusal;
  final List<(String messageID, String agentID)> ackCalls = [];

  /// v1.21 the message bus: null => the default one-message bus below.
  /// Typed dynamic so tests can script a MALFORMED payload (a non-Map
  /// row) and pin the wrapper's wholesale refusal.
  List<dynamic>? messagesListResult;

  /// v1.20 the risk ledger: null => the default one-risk ledger below.
  /// Typed dynamic so tests can script a MALFORMED payload (a non-Map
  /// row) and pin the wrapper's wholesale refusal.
  List<dynamic>? risksListResult;

  /// v1.19 the goal ledger: null => the default one-goal ledger below.
  /// Typed dynamic so tests can script a MALFORMED payload (a non-Map
  /// row) and pin the wrapper's wholesale refusal.
  List<dynamic>? goalsListResult;

  /// v1.18 the doctor door: null => the default honest healthy-office
  /// report below. Typed dynamic so tests can script a MALFORMED payload
  /// (a non-String contractVersion) and pin the wrapper's wholesale
  /// refusal.
  Map<String, dynamic>? doctorResult;

  /// v1.6 standup window payload (seven integer counts); null => the
  /// default quiet-but-valid window below.
  Map<String, dynamic>? standupResult;

  /// simulate a core OLDER than v1.6: the verb is simply not registered
  bool standupRefused = false;
  Map<String, dynamic>? tailResult;

  /// v1.3+ array verbs (approvals/history/deliverables) carry a JSON ARRAY.
  List<dynamic>? approvalsListResult;

  /// v1.5: deliverables_list rows (existsNow rides along); defaults to a
  /// one-row shelf shaped like the bridge's answer when unset.
  List<dynamic>? deliverablesListResult;

  /// Raw text to smuggle INSTEAD of the JSON-encoded result (tear/truncate
  /// simulation across the C boundary — nothing else can produce that).
  String? rawCarryOverride;

  /// Fake default: query verbs ALWAYS answer with a JSON object (rc=0 +
  /// payload) — the wrapper contract (result-or-reason by rc) needs the
  /// fake structurally truthful even when a test scripts nothing. Tail
  /// echoes afterOffset so cursor math is exercisable.
  static const Map<String, dynamic> _defaultTail = {
    'text': '',
    'nextOffset': 0,
    'length': 0,
  };

  static const String _defaultCatchupPage = '# Catch-up — Demo\n'
      '\n'
      '## Traffic (last 24h)\n'
      '- new work: 0\n'
      '- a quiet window — nothing moved.\n'
      '\n'
      '## Waiting on you (0)\n'
      '- nothing — your desk is clear.\n';

  int _snapshotCalls = 0;
  final Set<int> _live = {};

  /// Addresses of fake-allocated strings the wrapper never freed.
  List<int> get unfreed => _live.toList();

  int create() => createResult;

  int destroyCalls = 0;
  void destroy() {
    destroyCalls++;
  }

  Pointer<Utf8> lastError() => _dup(nextError);

  Pointer<Utf8> snapshotJson() {
    if (snapshots.isEmpty) return _dup('{}');
    final index = _snapshotCalls.clamp(0, snapshots.length - 1);
    _snapshotCalls++;
    return _dup(jsonEncode(snapshots[index]));
  }

  int command(Pointer<Utf8> verbPtr, Pointer<Utf8> payloadPtr) {
    final verb = verbPtr.toDartString();
    final payload =
        (jsonDecode(payloadPtr.toDartString()) as Map).cast<String, dynamic>();
    commands.add((verb, payload));
    final rc = nextCommandResult;
    nextCommandResult = OpcBridge.ok;
    if (rc != OpcBridge.ok) return rc; // preserve the scripted refusal text
    // a core older than v1.6: the verb simply does not exist (rc=-1),
    // exactly what a pre-standup dylib answers
    if (verb == 'standup_window' && standupRefused) return -1;
    if (verb == 'team_stats_list' && teamStatsRefused) return -1;
    if (verb == 'stalls_list' && stallsRefused) return -1;
    if (verb == 'catchup_md' && catchupRefused) return -1;
    if (verb == 'weight_json' && weightRefused) return -1;
    // v1.12: seat lifecycle writes — same contract as terminal_send.
    if (verb == 'seat_spawn' || verb == 'seat_stop') {
      final agentID = payload['agentID'];
      if (agentID is! String) {
        nextError = '$verb requires agentID';
        return -1;
      }
      seatCommands.add((verb, agentID));
      final refusal = verb == 'seat_spawn' ? seatSpawnRefusal : seatStopRefusal;
      if (refusal != null) {
        nextError = refusal;
        return -1;
      }
      nextError = '';
      return rc;
    }
    // v1.16 the shell's checkpoint: a write — '' on success, refusal
    // verbatim; the reason is recorded either way.
    if (verb == 'checkpoint') {
      final reason = payload['reason'];
      if (reason is! String || reason.trim().isEmpty) {
        nextError = 'checkpoint requires a non-empty reason';
        return -1;
      }
      checkpointReasons.add(reason);
      if (checkpointRefusal != null) {
        nextError = checkpointRefusal!;
        return -1;
      }
      nextError = '';
      return rc;
    }
    // v1.15 the shell's autopilot: ONE full dispatch per call — a write
    // with the same ''-on-success contract; recorded either way.
    if (verb == 'autopilot') {
      autopilotCalls++;
      if (autopilotRefusal != null) {
        nextError = autopilotRefusal!;
        return -1;
      }
      nextError = '';
      return rc;
    }
    // v1.23 the shell's ack: a write — '' on success, refusal verbatim;
    // the ask is recorded either way.
    if (verb == 'message_ack') {
      final messageID = payload['messageID'];
      final agentID = payload['agentID'];
      if (messageID is! String || agentID is! String) {
        nextError = 'message_ack requires messageID and agentID';
        return -1;
      }
      ackCalls.add((messageID, agentID));
      if (messageAckRefusal != null) {
        nextError = messageAckRefusal!;
        return -1;
      }
      nextError = '';
      return rc;
    }
    // v1.11: a WRITE — success is lastError reset to '', a refusal rides
    // its reason verbatim; the attempt is recorded either way.
    if (verb == 'terminal_send') {
      final agentID = payload['agentID'];
      final line = payload['line'];
      if (agentID is! String || line is! String) {
        nextError = 'terminal_send requires agentID and line';
        return -1;
      }
      terminalSends.add((agentID, line));
      if (terminalSendRefusal != null) {
        nextError = terminalSendRefusal!;
        return -1;
      }
      nextError = '';
      return rc;
    }
    // v1.9: the page rides the channel as a RAW string — the real bridge
    // stores it in last_error WITHOUT jsonEncode (the page IS the payload),
    // so the fake must not wrap it in quotes either.
    if (verb == 'catchup_md') {
      nextError = rawCarryOverride ?? (catchupMdResult ?? _defaultCatchupPage);
      return rc;
    }
    // v1.14 the transcript door: a query — the object rides the smuggle
    // channel JSON-encoded; the ask is recorded either way.
    if (verb == 'transcript') {
      final agentID = payload['agentID'];
      final tail = payload['tail'];
      if (agentID is! String || tail is! int) {
        nextError = 'transcript requires agentID and tail';
        return -1;
      }
      transcriptCalls.add((agentID, tail));
      if (transcriptRefusal != null) {
        nextError = transcriptRefusal!;
        return -1;
      }
      nextError = jsonEncode(transcriptResult ??
          {
            'agentID': agentID,
            'displayName': 'Fake Employee',
            'totalLines': 2,
            'tail': tail,
            'lines': ['visible-line-one', 'visible-line-two'],
          });
      return rc;
    }
    // query verbs carry results through nextError exactly like the bridge
    // does (rc=0 + last_error = payload) — the wrapper's contract test
    final Object? carried = switch (verb) {
      'approvals_list' => approvalsListResult ??
          const [
            {'id': 'fake-approval', 'title': 't'}
          ],
      // v1.4 ledger rides the SAME array channel (same default rows)
      'history_list' => approvalsListResult ??
          const [
            {'id': 'fake-approval', 'title': 't'}
          ],
      // v1.5 shelf: its own field, default row carries the existsNow verdict
      'deliverables_list' => deliverablesListResult ??
          const [
            {
              'id': 'fake-shelf',
              'title': 't',
              'kind': 'report',
              'path': '/tmp/t',
              'existsNow': true,
              'createdAt': 1757000000,
            }
          ],
      'weight_json' => weightResult ??
          const {
            'totalBytes': 54024,
            'sections': [
              {'name': 'events', 'bytes': 34171},
              {'name': 'productTerminalLogs', 'bytes': 10131},
            ],
            'advisoryBytes': 20971520,
            'exceedsAdvisory': false,
            'terminalLogBytes': 10131,
            'logSharePercent': 18,
          },
      'terminal_digest' => digestResult ?? const <String, dynamic>{},
      // v1.13 seat roster: a {uuid: bool} object rides the smuggle channel
      'seat_list' => seatListResult ?? const <String, bool>{},
      // v1.18 the doctor: the facts object rides the same smuggle channel
      'messages_list' => messagesListResult ??
          const [
            {
              'id': 'fake-msg',
              'kind': 'taskDispatched',
              'status': 'pending',
              'from': 'Codex 技术负责人',
              'to': 'Alice',
              'subject': '派发：实现 goals 门',
              'createdAt': 1757001000,
            },
          ],
      'risks_list' => risksListResult ??
          const [
            {
              'id': 'fake-risk',
              'title': '编译失败：主链路',
              'detail': '模块 A 编译错误',
              'agentID': 'fake-alice',
              'createdAt': 1757000900,
            },
          ],
      'goals_list' => goalsListResult ??
          const [
            {
              'goalID': 'fake-goal',
              'goal': 'ship the demo',
              'status': 'warning',
              'completionScore': 42,
              'steps': [
                {
                  'id': 'task-graph',
                  'title': '任务图',
                  'status': 'passed',
                  'detail': '技术负责人、执行、审查、老板审批任务 4/4。'
                },
              ],
              'counts': {
                'tasks': 4,
                'messages': 2,
                'approvals': 0,
                'artifacts': 0,
                'verifications': 0
              },
              'createdAt': 1757000000,
              'updatedAt': 1757000600,
            },
          ],
      // v1.22 the task file: the object rides the smuggle channel
      'task_show' => taskShowResult ??
          {
            'taskID': payload['taskID'],
            'title': '实现 goals 门',
            'status': 'running',
            'owner': 'Alice',
            'successCriteria': 'opc goals 能读出链',
            'artifactPath': null,
            'workItems': [
              {
                'itemID': 'wi1',
                'status': 'running',
                'agent': 'Alice',
                'promptPreview': '写实现'
              },
            ],
            'artifacts': [
              {
                'id': 'a1',
                'title': '实现报告',
                'kind': 'report',
                'path': '/tmp/ship.md',
                'existsNow': true
              },
            ],
            'approvals': <dynamic>[],
            'messages': <dynamic>[],
          },
      'doctor' => doctorResult ??
          const {
            'contractVersion': 'v1.18',
            'supportDir': '/tmp/fake-office',
            'stateFileExists': true,
            'stateFileBytes': 8192,
            'tmuxAvailable': true,
            'seatsRunning': 0,
            'seatsAliveButExited': 0,
            'appRunning': false,
            'overrideSet': false,
            'warnings': <String>[],
          },
      // v1.6 standup: an OBJECT rides the same smuggle channel
      'stalls_list' => stallsResult ??
          const [
            {
              'itemID': 'fake-jam',
              'agentID': 'fake-alice',
              'name': 'Alice',
              'status': 'waitingApproval',
              'dwellMinutes': 90,
              'waitingOnYou': true,
            },
            {
              'itemID': 'fake-lost',
              'name': '未分配',
              'status': 'running',
              'dwellMinutes': 45,
              'waitingOnYou': false
            },
          ],
      'team_stats_list' => teamStatsResult ??
          const [
            {
              'agentID': 'fake-alice',
              'name': 'Alice',
              'assigned': 2,
              'deliveries': 1,
              'missing': 0,
              'asked': 1,
              'risks': 0,
              'activeNow': 1,
            },
            {
              'name': '未分配',
              'assigned': 0,
              'deliveries': 1,
              'missing': 1,
              'asked': 0,
              'risks': 0,
              'activeNow': 0
            },
          ],
      'standup_window' => standupResult ??
          const <String, dynamic>{
            'hours': 24,
            'newWork': 0,
            'decisions': 0,
            'deliveries': 0,
            'missing': 0,
            'risks': 0,
            'awaitingNow': 0,
          },
      'terminal_tail' => tailResult ??
          {
            ..._defaultTail,
            'nextOffset': payload['afterOffset'] ?? 0,
            'length': payload['afterOffset'] ?? 0,
          },
      _ => null,
    };
    if (carried != null) {
      nextError = rawCarryOverride ?? jsonEncode(carried);
    }
    return rc;
  }

  void freePointer(Pointer<Void> p) {
    _live.remove(p.address);
    malloc.free(p.cast<Utf8>());
  }

  OpcBridge asBridge() => OpcBridge.forTesting(
        create: create,
        destroy: destroy,
        lastError: lastError,
        snapshotJson: snapshotJson,
        command: command,
        free: freePointer,
      );

  Pointer<Utf8> _dup(String s) {
    final p = s.toNativeUtf8();
    _live.add(p.address);
    return p;
  }
}
