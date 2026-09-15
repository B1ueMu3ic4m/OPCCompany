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

  int _snapshotCalls = 0;
  final Set<int> _live = {};

  /// Addresses of fake-allocated strings the wrapper never freed.
  List<int> get unfreed => _live.toList();

  int create() => createResult;

  void destroy() {}

  Pointer<Utf8> lastError() => _dup(nextError);

  Pointer<Utf8> snapshotJson() {
    final index = _snapshotCalls.clamp(0, snapshots.length - 1);
    _snapshotCalls++;
    return _dup(snapshots.isEmpty ? '{}' : jsonEncode(snapshots[index]));
  }

  int command(Pointer<Utf8> verbPtr, Pointer<Utf8> payloadPtr) {
    final verb = verbPtr.toDartString();
    final payload = (jsonDecode(payloadPtr.toDartString()) as Map)
        .cast<String, dynamic>();
    commands.add((verb, payload));
    final rc = nextCommandResult;
    nextCommandResult = OpcBridge.ok;
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
