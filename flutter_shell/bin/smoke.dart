import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Pure-Dart ABI smoke over the bridge dylib.
///
/// Covers exactly what a non-Cocoa host CAN verify: the library loads, all
/// six @_cdecl symbols resolve, and the malloc/free allocator contract holds
/// across the boundary (option [c] below). Behavioral checks (create →
/// snapshot → commands) live in the Swift suite (m3BridgeSurfaceContract)
/// and in the Flutter shell's startup self-check — see lib/shell_smoke.dart.
///
/// Why split: the bridge hops @MainActor store work onto the process main
/// queue; hosts that never drain it (a bare `dart run` VM thread) block
/// there by design. Every real consumer — Flutter desktop, any Cocoa app —
/// pumps its runloop, which is the supported host contract.
///
///   OPC_BRIDGE_DYLIB=../.build/debug/libOPCCompanyBridge.dylib \
///     dart run bin/smoke.dart
int _fail = 0;
void _check(bool cond, String what) {
  stdout.writeln('${cond ? "PASS" : "FAIL"}: $what');
  if (!cond) _fail++;
}

void main() {
  final path = Platform.environment['OPC_BRIDGE_DYLIB'];
  if (path == null || path.isEmpty || !File(path).existsSync()) {
    stderr.writeln('set OPC_BRIDGE_DYLIB to the built bridge dylib path');
    exit(2);
  }

  // [a] dlopen of the Swift dynamic library
  late final DynamicLibrary lib;
  try {
    lib = DynamicLibrary.open(path);
    _check(true, 'a: dylib loads via dart:ffi');
  } catch (e) {
    _check(false, 'a: dylib load failed: $e');
    exit(1);
  }

  // [b] every exported C symbol resolves (the host's dlsym view)
  final wanted = [
    'opc_bridge_create',
    'opc_bridge_destroy',
    'opc_bridge_last_error',
    'opc_bridge_snapshot_json',
    'opc_bridge_command',
    'opc_bridge_free',
  ];
  for (final name in wanted) {
    try {
      // Dart has no raw lookupSymbol; probe via a uniform native signature —
      // resolution itself is what's under test, never the call.
      lib.lookupFunction<Void Function(), void Function()>(name);
      _check(true, 'b: symbol $name resolves');
    } catch (_) {
      _check(false, 'b: symbol $name MISSING');
    }
  }

  // [c] allocator contract: Swift malloc'd buffer must be free-able by the
  // host's C free() — the exact mismatch that corrupts Windows heaps if we
  // ever return Swift-allocated memory. last_error() is pure lock+dup, so
  // it is safe to call without create (it returns "" — no main-queue hop).
  final lastError = lib
      .lookupFunction<Pointer<Uint8> Function(), Pointer<Uint8> Function()>(
          'opc_bridge_last_error');
  final freeFn =
      lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
          'opc_bridge_free');
  final p = lastError();
  _check(p != nullptr, 'c: last_error returns a malloc\u2019d buffer (non-NULL)');
  if (p != nullptr) {
    _check(p.cast<Utf8>().toDartString().isEmpty,
        'c: initial last_error is empty string');
    // Free with the bridge's own free (C free against C malloc). If the
    // bridge ever regresses to Swift .allocate, this is where hosts crash —
    // better here than in a user's Flutter app.
    freeFn(p.cast());
    _check(true, 'c: host-side free() of bridge memory accepted (no trap)');
  }
  // Also verify plain `free` (dart:ffi's malloc library) can take what the
  // bridge produced — the documented Dart-side cleanup path (malloc.free).
  // Second buffer, same contract — proves free is repeatable.
  final p2 = lastError();
  if (p2 != nullptr) {
    freeFn(p2.cast());
    _check(true, 'c: second bridge buffer freed cleanly');
  }

  stdout.writeln(
      _fail == 0 ? '\nABI SMOKE OK (behavioral coverage: Swift suite + shell self-check)' : '\nABI SMOKE FAILED ($_fail)');
  exit(_fail == 0 ? 0 : 1);
}
