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

  String? get selectedProductID => raw['selectedProductID'] as String?;

  /// Approvals of the selected product still awaiting the boss.
  List<Map<String, dynamic>> get pendingApprovals => approvals
      .whereType<Map<String, dynamic>>()
      .where((a) =>
          a['status'] == 'pending' &&
          (selectedProductID == null || a['productID'] == selectedProductID))
      .toList();

  /// v0.5.0: pending count per raising agent (requesterID → N), the shell
  /// twin of the office's ×N hand-raise badge. Keyed lowercase to match
  /// the roster's selection convention; unattributed rows count nowhere.
  Map<String, int> get approvalCountsByRequester {
    final counts = <String, int>{};
    for (final a in pendingApprovals) {
      final r = (a['requesterID'] as String?)?.toLowerCase();
      if (r != null && r.isNotEmpty) counts[r] = (counts[r] ?? 0) + 1;
    }
    return counts;
  }

  /// tasks of the selected product grouped by their status rawValue.
  Map<String, List<Map<String, dynamic>>> get tasksByStatus {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final t in tasks.whereType<Map<String, dynamic>>()) {
      if (selectedProductID != null && t['productID'] != selectedProductID) {
        continue;
      }
      grouped.putIfAbsent(t['status'] as String? ?? '?', () => []).add(t);
    }
    return grouped;
  }

  /// employees (id, name, working state) of the snapshot. IDs are the raw
  /// snapshot UUID strings; terminal digests key them lowercased.
  List<(String, String, String)> get roster => [
        for (final a in agents.whereType<Map<String, dynamic>>())
          (
            a['id'] as String? ?? '?',
            a['displayName'] as String? ?? '?',
            a['status'] as String? ?? '?'
          ),
      ];

  /// (id, name) pairs of every product workspace, in core order (the raw
  /// list lives in [products]). The id strings are exactly what
  /// product_select and selectedProductID carry — the snapshot's Swift
  /// encoder is the single formatting authority.
  List<(String, String)> get productList => [
        for (final p in (raw['products'] as List? ?? const []))
          if (p is Map<String, dynamic>)
            (p['id'] as String? ?? '?', p['name'] as String? ?? '?'),
      ];
}

/// Thin object wrapper over the six C entry points. All calls are synchronous
/// and, by contract, must run on the host's main/platform thread.
class OpcBridge {
  OpcBridge([DynamicLibrary? lib]) {
    final resolved = lib ?? openOpcBridge();
    create =
        resolved.lookupFunction<CreateNative, CreateDart>('opc_bridge_create');
    _destroy = resolved
        .lookupFunction<DestroyNative, DestroyDart>('opc_bridge_destroy');
    _lastError = resolved.lookupFunction<LastErrorNative, LastErrorDart>(
        'opc_bridge_last_error');
    _snapshotJson =
        resolved.lookupFunction<SnapshotJsonNative, SnapshotJsonDart>(
            'opc_bridge_snapshot_json');
    _command = resolved
        .lookupFunction<CommandNative, CommandDart>('opc_bridge_command');
    _free = resolved.lookupFunction<FreeNative, FreeDart>('opc_bridge_free');
  }

  /// Widget-test seam: the six function slots supplied directly, so the UI
  /// can be driven against a scripted fake of the C ABI (no dlopen, no
  /// singleton, no main-thread contract). The free callback receives every
  /// pointer the wrapper hands back, exactly like the real bridge.
  /// (Named forTesting rather than annotated @visibleForTesting: this library
  /// stays Flutter/meta-free by design — see the header comment.)
  OpcBridge.forTesting({
    required this.create,
    required DestroyDart destroy,
    required LastErrorDart lastError,
    required SnapshotJsonDart snapshotJson,
    required CommandDart command,
    required FreeDart free,
  })  : _destroy = destroy,
        _lastError = lastError,
        _snapshotJson = snapshotJson,
        _command = command,
        _free = free;

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
    // The C singleton contract refuses double-destroy; wrapper state must
    // mirror it (create-failure paths leave _alive=false — a destroy there
    // is misuse AND noise; the widget-test seam hits exactly this).
    if (!_alive) return;
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

  // ---- ergonomic wrappers over the five documented verbs ----
  int sendGoal(String text) => command('goal', {'text': text});
  int advance() => command('advance');
  int save() => command('save');
  int selectProduct(String productID) =>
      command('product_select', {'productID': productID});
  int decide(String approvalID, {bool approved = true}) =>
      command('decide', {'approvalID': approvalID, 'approved': approved});

  // ---- query verbs (#70 option A): results ride lastError by contract ----
  // Success returns ok AND fills lastError with the JSON payload — callers
  // must branch on rc, never on emptiness (documented in opc_bridge.h).

  /// {agentID: byteLength} of the selected product's agent logs.
  Map<String, int>? terminalDigest() {
    if (command('terminal_digest') != ok) return null;
    final raw = _json(lastError());
    if (raw == null) return null;
    final result = <String, int>{};
    for (final entry in raw.entries) {
      final length = entry.value;
      if (length is! int || length < 0) return null;
      result[entry.key] = length;
    }
    return result;
  }

  /// v1.3 query: the current product's pending approvals — the same rows
  /// the SwiftUI popover reads, without re-fetching the full snapshot.
  /// Malformed JSON returns null (never a partial list).
  List<Map<String, dynamic>>? approvalsList() =>
      _listVerb('approvals_list');

  /// v1.4 decision ledger: RESOLVED approvals of the current product,
  /// newest-first, capped at 50 by the bridge. Each row: id/title/reason/
  /// status/approved|rejected, decidedAt (epoch seconds, absent for legacy
  /// rows), requesterID (absent when the core recorded no asker). Read-only.
  List<Map<String, dynamic>>? historyList() => _listVerb('history_list');

  /// v1.5 delivery shelf: recorded deliveries of the current product,
  /// newest-first, capped at 50. Each row: id/title/kind/path/createdAt +
  /// existsNow — computed by the bridge AT READ TIME, so the shell's row
  /// flips [OK]->[MISSING] the moment someone deletes the file, without
  /// any snapshot change. Read-only.
  List<Map<String, dynamic>>? deliverablesList() =>
      _listVerb('deliverables_list');

  /// v1.7 the name behind the work: per-employee TRAFFIC of the current
  /// product over the window (default 24h, optional [hours]). Rows arrive
  /// in the door's order — traffic desc, and the unattributed row (no
  /// agentID key, 未分配) LAST. Each row: name/assigned/deliveries/missing/
  /// asked/risks/activeNow (+agentID when attributed). missing rides the
  /// existence door at read time. Read-only.
  List<Map<String, dynamic>>? teamStatsList({int? hours}) {
    if (command('team_stats_list',
            hours == null ? const {} : {'hours': hours}) != ok) {
      return null;
    }
    final source = lastError();
    if (source.isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return null;
      final rows = decoded.whereType<Map<String, dynamic>>().toList();
      return rows.length == decoded.length ? rows : null;
    } on FormatException {
      return null;
    }
  }

  /// v1.6 morning standup: one rolling 24h window of company TRAFFIC as
  /// seven integer counts {hours,newWork,decisions,deliveries,missing,
  /// risks,awaitingNow}, computed live by the store's own door. Unlike
  /// the *_list verbs this payload is an OBJECT — a missing or non-int
  /// field refuses WHOLESALE (null), never half a standup.
  Map<String, int>? standupWindow() {
    if (command('standup_window') != ok) return null;
    final raw = _json(lastError());
    if (raw == null) return null;
    const keys = [
      'hours', 'newWork', 'decisions', 'deliveries', 'missing', 'risks',
      'awaitingNow',
    ];
    final result = <String, int>{};
    for (final key in keys) {
      final value = raw[key];
      if (value is! int) return null;
      result[key] = value;
    }
    return result;
  }

  /// The JSON-array verbs' shared door (v1.3/v1.4): rc decides, a torn or
  /// malformed payload refuses WHOLESALE — half a list is worse than none.
  List<Map<String, dynamic>>? _listVerb(String verb) {
    if (command(verb) != ok) return null;
    final source = lastError();
    if (source.isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return null;
      final rows = decoded.whereType<Map<String, dynamic>>().toList();
      return rows.length == decoded.length ? rows : null;
    } on FormatException {
      return null;
    }
  }

  /// Window of one agent's transcript from [afterOffset].
  TerminalTail? terminalTail(String agentID,
      {int afterOffset = 0, int maxBytes = 16384}) {
    final rc = command('terminal_tail', {
      'agentID': agentID,
      'afterOffset': afterOffset,
      'maxBytes': maxBytes,
    });
    if (rc != ok) {
      return null;
    }
    final raw = _json(lastError());
    if (raw == null) return null;
    final text = raw['text'];
    final nextOffset = raw['nextOffset'];
    final length = raw['length'];
    if (text is! String ||
        nextOffset is! int ||
        length is! int ||
        nextOffset < 0 ||
        length < nextOffset) {
      return null;
    }
    return TerminalTail(text: text, nextOffset: nextOffset, length: length);
  }

  Map<String, dynamic>? _json(String source) {
    if (source.isEmpty) return null;
    try {
      final d = jsonDecode(source);
      return d is Map<String, dynamic> ? d : null;
    } on FormatException {
      return null;
    }
  }
}

/// One terminal_tail window (see OpcBridge.terminalTail).
class TerminalTail {
  TerminalTail({
    required this.text,
    required this.nextOffset,
    required this.length,
  });
  final String text;
  final int nextOffset;
  final int length;

  /// True when the caller is caught up (offset at/after end of log).
  bool get atEnd => nextOffset >= length;
}
