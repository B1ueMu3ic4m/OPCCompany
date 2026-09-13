/// dart:ffi bindings for the OPC Company C-ABI bridge.
///
/// Single source of truth for the ABI is `OPCBridge.swift` (@_cdecl names),
/// mirrored by `include/opc_bridge.h` (the root test
/// `m3BridgeCHeaderMatchesSwiftExports` keeps them in sync). This file mirrors
/// the same six symbols on the Dart side.
///
/// This library intentionally depends only on `dart:ffi`, `dart:io`,
/// `dart:convert` and `package:ffi` — NOT Flutter — so the headless smoke
/// tests run on a plain Dart VM. The GUI (`main.dart`) layers Flutter on top.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// ---- C function typedefs (native <-> Dart) ----
typedef CreateNative = Int32 Function();
typedef CreateDart = int Function();

typedef DestroyNative = Void Function();
typedef DestroyDart = void Function();

typedef LastErrorNative = Pointer<Utf8> Function();
typedef LastErrorDart = Pointer<Utf8> Function();

typedef SnapshotJsonNative = Pointer<Utf8> Function();
typedef SnapshotJsonDart = Pointer<Utf8> Function();

typedef CommandNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef CommandDart = int Function(Pointer<Utf8>, Pointer<Utf8>);

typedef FreeNative = Void Function(Pointer<Void>);
typedef FreeDart = void Function(Pointer<Void>);

/// Locate the bridge dynamic library.
///
/// Resolution order:
///   1. `OPC_BRIDGE_DYLIB` env var (absolute path) — used by the smoke tests
///      pointing at the SwiftPM build output;
///   2. the OS-standard search for a bare soname (`OPCCompanyBridge`), which
///      resolves once the library is shipped inside the app bundle / system
///      path (Flutter packs it alongside the executable).
String _defaultLibraryName() {
  if (Platform.isMacOS || Platform.isIOS) return 'libOPCCompanyBridge.dylib';
  if (Platform.isWindows) return 'OPCCompanyBridge.dll';
  return 'libOPCCompanyBridge.so'; // Linux & other POSIX
}

DynamicLibrary openOpcBridge() {
  final override = Platform.environment['OPC_BRIDGE_DYLIB'];
  if (override != null && override.isNotEmpty) {
    return DynamicLibrary.open(override);
  }
  return DynamicLibrary.open(_defaultLibraryName());
}

/// A decoded company snapshot (subset relevant to the shell).
class OpcSnapshot {
  OpcSnapshot(this.raw);
  final Map<String, dynamic> raw;

  int get schemaVersion => (raw['schemaVersion'] as num?)?.toInt() ?? 0;
  List get agents => (raw['agents'] as List?) ?? const [];
  List get tasks => (raw['tasks'] as List?) ?? const [];
  List get products => (raw['products'] as List?) ?? const [];
  List get approvals => (raw['approvals'] as List?) ?? const [];
}

/// Thin object wrapper over the six C entry points. All calls are synchronous
/// and, by contract, must run on the host's main/platform thread.
class OpcBridge {
  OpcBridge([DynamicLibrary? lib]) : _lib = lib ?? openOpcBridge() {
    create = _lib.lookupFunction<CreateNative, CreateDart>('opc_bridge_create');
    _destroy = _lib.lookupFunction<DestroyNative, DestroyDart>('opc_bridge_destroy');
    _lastError = _lib.lookupFunction<LastErrorNative, LastErrorDart>('opc_bridge_last_error');
    _snapshotJson = _lib.lookupFunction<SnapshotJsonNative, SnapshotJsonDart>('opc_bridge_snapshot_json');
    _command = _lib.lookupFunction<CommandNative, CommandDart>('opc_bridge_command');
    _free = _lib.lookupFunction<FreeNative, FreeDart>('opc_bridge_free');
  }

  final DynamicLibrary _lib;

  late final CreateDart create;
  late final DestroyDart _destroy;
  late final LastErrorDart _lastError;
  late final SnapshotJsonDart _snapshotJson;
  late final CommandDart _command;
  late final FreeDart _free;

  bool _alive = false;
  bool get isAlive => _alive;

  /// Result of a command attempt.
  static const int ok = 0;
  static const int refused = -1;

  int start() {
    final rc = create();
    if (rc == ok) _alive = true;
    return rc;
  }

  void stop() {
    _destroy();
    _alive = false;
  }

  /// Verbatim reason for the last refusal ("" if none). Marshals + frees.
  String lastError() {
    final p = _lastError();
    if (p == nullptr) return '';
    final s = p.toDartString();
    _free(p.cast());
    return s;
  }

  /// Full snapshot as a decoded map, or null if no bridge / bad payload.
  OpcSnapshot? snapshot() {
    final p = _snapshotJson();
    if (p == nullptr) return null;
    final text = p.toDartString();
    _free(p.cast());
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return OpcSnapshot(decoded);
    } on FormatException {
      return null;
    }
    return null;
  }

  /// Fire a boss command. `payload` is an arbitrary JSON-serializable map.
  /// Returns [ok]/[refused]; on refused, [lastError] explains why.
  int command(String verb, [Map<String, dynamic> payload = const {}]) {
    final verbPtr = verb.toNativeUtf8();
    final payloadPtr = jsonEncode(payload).toNativeUtf8();
    try {
      return _command(verbPtr, payloadPtr);
    } finally {
      _free(verbPtr.cast());
      _free(payloadPtr.cast());
    }
  }

  // ---- ergonomic wrappers over the four documented verbs ----
  int sendGoal(String text) => command('goal', {'text': text});
  int advance() => command('advance');
  int save() => command('save');
  int decide(String approvalID, {bool approved = true}) =>
      command('decide', {'approvalID': approvalID, 'approved': approved});
}
