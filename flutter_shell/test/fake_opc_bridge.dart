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
    // query verbs carry results through nextError exactly like the bridge
    // does (rc=0 + last_error = payload) — the wrapper's contract test
    final Object? carried = switch (verb) {
      'approvals_list' =>
        approvalsListResult ?? const [{'id': 'fake-approval', 'title': 't'}],
      // v1.4 ledger rides the SAME array channel (same default rows)
      'history_list' =>
        approvalsListResult ?? const [{'id': 'fake-approval', 'title': 't'}],
      // v1.5 shelf: its own field, default row carries the existsNow verdict
      'deliverables_list' =>
        deliverablesListResult ??
            const [
              {
                'id': 'fake-shelf', 'title': 't', 'kind': 'report',
                'path': '/tmp/t', 'existsNow': true,
                'createdAt': 1757000000,
              }
            ],
      'terminal_digest' => digestResult ?? const <String, dynamic>{},
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
