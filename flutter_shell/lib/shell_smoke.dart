import 'dart:convert';
import 'dart:io';

import 'opc_bridge_bindings.dart';

/// Startup self-check for the Flutter host (the "三命令冒烟" runner).
///
/// Enabled with env OPC_SHELL_SMOKE=1 (+ OPC_SHELL_SMOKE_OUT=<result file>).
/// The app launches normally — which pumps the main runloop the bridge hops
/// onto — runs the full create/snapshot/goal/save/destroy cycle exactly like
/// a user session would, writes machine-readable results, then exits.
/// This is the Windows/Linux shell's CI story: same script, same binary.
class SmokeResult {
  SmokeResult(this.name, this.pass, [this.detail = '']);
  final String name;
  final bool pass;
  final String detail;
  Map<String, dynamic> toJson() =>
      {'name': name, 'pass': pass, 'detail': detail};
}

Future<List<SmokeResult>> runShellSmoke(OpcBridge bridge) async {
  final results = <SmokeResult>[];
  void add(String name, bool pass, [String detail = '']) =>
      results.add(SmokeResult(name, pass, detail));

  // The shell's initState already created the bridge — the strongest proof
  // it worked is that a second create is refused with the exact "already"
  // message (both facts in one call).
  final rcAgain = bridge.start();
  add(
      'create active + double-create refused',
      rcAgain == OpcBridge.refused && bridge.lastError().contains('already'),
      'rc=$rcAgain');

  final snap = bridge.snapshot();
  add('snapshot parses', snap != null);
  if (snap != null) {
    add('schemaVersion present', snap.schemaVersion >= 7,
        'v${snap.schemaVersion}');
  }

  final goal = 'Flutter shell smoke ${DateTime.now().millisecondsSinceEpoch}';
  final before = snap?.tasks.length ?? 0;
  add('goal accepted', bridge.sendGoal(goal) == OpcBridge.ok);
  final after = bridge.snapshot()?.tasks.length ?? 0;
  add('supervisor chain +4', after == before + 4, '$before -> $after');
  add(
      'goal text round-trips',
      jsonEncode(bridge.snapshot()?.raw['tasks'] ?? [])
          .contains('Flutter shell smoke'));

  final advanceRc = bridge.advance(); // 0 or -1; both are real executions
  add(
      'advance executed',
      advanceRc == OpcBridge.ok || advanceRc == OpcBridge.refused,
      'rc=$advanceRc');
  add('save persists', bridge.save() == OpcBridge.ok);

  add(
      'unknown verb refused',
      bridge.command('bogus') == OpcBridge.refused &&
          bridge.lastError().contains('unknown bridge verb'));

  // Query verbs (#70 option A): results ride last_error through the REAL
  // ABI — the widget tests cover the wrapper, this proves the C-string
  // smuggling round-trips on the host platform (Windows CI included).
  final digest = bridge.terminalDigest();
  add('terminal_digest answers', digest != null);
  final rosterIDs = snap?.roster ?? const [];
  if (digest != null && rosterIDs.isNotEmpty) {
    final agentID = rosterIDs.first.$1;
    final tail = bridge.terminalTail(agentID);
    add(
        'terminal_tail cursor shape',
        tail != null && tail.length == (digest[agentID.toLowerCase()] ?? 0),
        tail == null ? 'null' : 'len=${tail.length}');
  }

  // Nonempty fixture coverage: rebuild each scoped log through tiny windows
  // across the real ABI. Compare with the original snapshot, not the wrapper.
  final scopedLogs = snap?.raw['productTerminalLogs'];
  final productID = snap?.raw['selectedProductID'];
  if (digest != null && scopedLogs is Map && productID is String) {
    for (final entry in digest.entries.where((entry) => entry.value > 0)) {
      var offset = 0;
      var valid = true;
      final rebuilt = StringBuffer();
      while (offset < entry.value) {
        final tail =
            bridge.terminalTail(entry.key, afterOffset: offset, maxBytes: 7);
        if (tail == null ||
            tail.nextOffset <= offset ||
            tail.length != entry.value ||
            utf8.encode(tail.text).length != tail.nextOffset - offset) {
          valid = false;
          break;
        }
        rebuilt.write(tail.text);
        offset = tail.nextOffset;
      }
      final expected = scopedLogs['${productID.toLowerCase()}:${entry.key}'];
      add(
          'nonempty terminal UTF-8 round-trip',
          valid && expected is String && rebuilt.toString() == expected,
          'bytes=$offset');
    }
  }

  bridge.stop();
  final reopened = OpcBridge();
  reopened.start();
  add('durability after recreate',
      (reopened.snapshot()?.tasks.length ?? -1) == after);
  reopened.stop();
  return results;
}

/// Called by main() when OPC_SHELL_SMOKE=1. Writes results JSON and exits.
/// The write is best-effort: a failure must NOT strand the app without an
/// exit or a diagnosis (first run revealed exactly that — a sandboxed write
/// threw before exit(), so the runner only saw a timeout). The verdict is
/// always printed + drives the exit code regardless of the file.
Future<void> finishShellSmoke(OpcBridge bridge) async {
  final results = await runShellSmoke(bridge);
  final allPass = results.every((r) => r.pass);
  final payload = {
    'ok': allPass,
    'checks': results.map((r) => r.toJson()).toList(),
  };
  final encoded = jsonEncode(payload);
  final outFile = Platform.environment['OPC_SHELL_SMOKE_OUT'];
  if (outFile != null && outFile.isNotEmpty) {
    try {
      await File(outFile).writeAsString(encoded);
    } catch (e) {
      stderr.writeln('smoke-result write failed ($e); relying on stdout');
    }
  }
  // ignore: avoid_print
  print(encoded);
  exit(allPass ? 0 : 1);
}
