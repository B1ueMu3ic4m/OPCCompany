import 'dart:io';

import 'package:flutter/material.dart';

import 'opc_bridge_bindings.dart';
import 'shell_smoke.dart';

/// M3 skeleton: the desktop shell is a thin, honest mirror of the bridge —
/// zero business logic; every widget renders snapshot JSON the core owns,
/// every button calls a bridge verb. The bridge hops onto the main queue
/// internally (any thread may call), and this shell's platform thread pumps
/// it — that is the host contract a bare `dart run` VM cannot satisfy, so
/// the behavioral smoke lives HERE, not in bin/.
void main() => runApp(const OpcShellApp());

class OpcShellApp extends StatelessWidget {
  const OpcShellApp({super.key});

  /// Dark identity aligned with the macOS app's palette (ContentView
  /// Palette constants — same hexes, so shell and app read as one product):
  /// deep slate background, warm gold accent, muted steels for secondary.
  static final ThemeData _theme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFD8C79A),
      secondary: Color(0xFF63C7D4),
      surface: Color(0xFF121821),
      onSurface: Color(0xFFEEF2F6),
      onSurfaceVariant: Color(0xFFB7C0CC),
    ),
    scaffoldBackgroundColor: const Color(0xFF06080B),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0A0F14),
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: const CardThemeData(
      color: Color(0xFF11151C),
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFF070A0E),
    ),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'OPC Company',
        theme: _theme,
        home: const CompanyHome(),
      );
}

class CompanyHome extends StatefulWidget {
  const CompanyHome({super.key, this.bridge});

  /// Widget-test seam: inject a fake; production passes null → real bridge.
  final OpcBridge? bridge;

  @override
  State<CompanyHome> createState() => _CompanyHomeState();
}

class _CompanyHomeState extends State<CompanyHome> {
  late final OpcBridge _bridge = widget.bridge ?? OpcBridge();
  final TextEditingController _goalController = TextEditingController();
  final FocusNode _goalFocus = FocusNode();
  OpcSnapshot? _snap;
  String? _lastAction;

  // ── transcript surface (#70 option A) ─────────────────────────────
  // Deliberately event-driven (no timer): every snapshot refresh — manual
  // button or post-verb — pulls a byte digest and only fetches windows that
  // grew. A poll loop is M5 polish; the cursor protocol is already
  // increment-friendly either way.
  final Map<String, int> _cursors = {}; // lowercased agentID -> byte offset
  final Map<String, String> _transcripts = {}; // agentID -> accumulated text
  String? _selectedAgentID;
  String? _transcriptProductID;
  final ScrollController _transcriptScroll = ScrollController();
  bool _followTail = true;

  @override
  void initState() {
    super.initState();
    final rc = _bridge.start();
    if (rc != OpcBridge.ok) {
      _lastAction = 'bridge create failed: ${_bridge.lastError()}';
    } else {
      _snap = _bridge.snapshot();
    }
    // CI/headless shell smoke: after first frame (run loop confirmed
    // turning), run the full behavioral cycle and exit with the verdict.
    if (Platform.environment['OPC_SHELL_SMOKE'] == '1') {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await finishShellSmoke(_bridge);
      });
    }
  }

  @override
  void dispose() {
    _goalController.dispose();
    _goalFocus.dispose();
    _transcriptScroll.dispose();
    _bridge.stop();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _snap = _bridge.snapshot();
      _syncTranscripts();
    });
  }

  /// Pull the byte digest and advance windows ONLY where logs grew
  /// (shrank => clear the local copy and restart at 0 — truncation/
  /// cleared log must not leave stale text in the viewer).
  void _syncTranscripts() {
    final productID = _snap?.raw['selectedProductID'] as String?;
    if (productID != _transcriptProductID) {
      // Employee IDs can be shared by products. Invalidate before querying,
      // including on failure, so old product text cannot remain visible.
      _cursors.clear();
      _transcripts.clear();
      _transcriptProductID = productID;
      _followTail = true;
    }
    if (productID == null) return;
    final digest = _bridge.terminalDigest();
    if (digest == null) {
      return; // digest failure: transcripts simply don't update this cycle
    }
    _cursors.removeWhere((key, _) => !digest.containsKey(key));
    _transcripts.removeWhere((key, _) => !digest.containsKey(key));
    digest.forEach((agentKey, length) {
      final had = _cursors[agentKey] ?? 0;
      if (length < had) {
        _cursors.remove(agentKey);
        _transcripts.remove(agentKey);
      }
      while ((_cursors[agentKey] ?? 0) < length) {
        final tail = _bridge.terminalTail(agentKey,
            afterOffset: _cursors[agentKey] ?? 0, maxBytes: 65536);
        if (tail == null || tail.nextOffset <= (_cursors[agentKey] ?? 0)) {
          break; // cursor stalled (bridge guarantees progress; belt & braces)
        }
        _transcripts[agentKey] = (_transcripts[agentKey] ?? '') + tail.text;
        _cursors[agentKey] = tail.nextOffset;
      }
    });
    if (_followTail && _transcriptScroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_transcriptScroll.hasClients) {
          _transcriptScroll.jumpTo(_transcriptScroll.position.maxScrollExtent);
        }
      });
    }
  }

  /// One action pipeline: run a bridge verb, surface refusal verbatim,
  /// reload the snapshot. The core is the only source of truth.
  void _run(String label, int Function() action) {
    setState(() {
      final rc = action();
      _lastAction = rc == OpcBridge.ok
          ? '$label: ok'
          : '$label: refused — ${_bridge.lastError()}';
      _snap = _bridge.snapshot();
      _syncTranscripts();
    });
  }

  void _sendGoal() {
    final text = _goalController.text.trim();
    if (text.isEmpty) {
      setState(() => _lastAction = 'goal: empty — nothing sent');
      return;
    }
    _run('goal "$text"', () => _bridge.sendGoal(text));
    _goalController.clear();
    _goalFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    return Scaffold(
      appBar: AppBar(
        title: Text(snap == null
            ? 'OPC Company — shell (no snapshot)'
            : 'OPC Company — shell · schema v${snap.schemaVersion}'),
        actions: [
          if (snap != null) _productMenu(snap),
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: snap == null
          ? Center(child: Text(_lastAction ?? 'no snapshot'))
          : Column(children: [
              _goalBar(),
              Expanded(child: _body(snap)),
              _statusBar(),
            ]),
    );
  }

  /// AppBar product switcher. Shows the selected workspace's name; the menu
  /// offers every other product. A tap rides the bridge's product_select
  /// verb — never a local optimistic flip: if the core refuses (unknown id,
  /// writer guard), the refusal must show in the status bar instead of a
  /// UI that prettied over a store that didn't move.
  Widget _productMenu(OpcSnapshot snap) {
    final selectedID = snap.raw['selectedProductID'] as String?;
    final products = snap.productList;
    final current = products.where((p) => p.$1 == selectedID);
    final label = current.isEmpty ? 'Products' : current.first.$2;
    return PopupMenuButton<String>(
      tooltip: 'Switch product',
      initialValue: label,
      onSelected: (productID) =>
          _run('switch product', () => _bridge.selectProduct(productID)),
      itemBuilder: (_) => [
        for (final (id, name) in products)
          if (id != selectedID) PopupMenuItem(value: id, child: Text(name)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.apps, size: 18),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall),
          ),
          const Icon(Icons.arrow_drop_down, size: 20),
        ]),
      ),
    );
  }

  Widget _goalBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _goalController,
              focusNode: _goalFocus,
              onSubmitted: (_) => _sendGoal(),
              decoration: const InputDecoration(
                labelText: 'Give the CTO a goal',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.campaign_outlined),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _sendGoal,
            icon: const Icon(Icons.send),
            label: const Text('Send'),
          ),
        ]),
      );

  Widget _body(OpcSnapshot snap) {
    final pending = snap.pendingApprovals;
    final byStatus = snap.tasksByStatus;
    final running = (byStatus['running'] ?? []).length +
        (byStatus['assigned'] ?? []).length;
    final done = (byStatus['done'] ?? []).length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // left: task board grouped by status
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Tasks (${snap.tasks.length})',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (byStatus.isEmpty)
                      const Card(
                          child: ListTile(
                              title: Text('No tasks yet — send a goal above.')))
                    else
                      for (final entry in byStatus.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Text('${entry.key} · ${entry.value.length}',
                              style: Theme.of(context).textTheme.labelLarge),
                        ),
                        for (final t in entry.value)
                          Card(
                            child: ListTile(
                              dense: true,
                              leading: Icon(_taskIcon(entry.key)),
                              title: Text(t['title'] as String? ?? '?',
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                      ],
                    const SizedBox(height: 12),
                    Text('Employees — tap to watch the transcript',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (id, name, status) in snap.roster)
                          ChoiceChip(
                            avatar: Icon(_agentIcon(status), size: 16),
                            selected: _selectedAgentID == id.toLowerCase(),
                            label: Text(
                                '$name · $status${_pendingBadge(snap, id, status)}'),
                            onSelected: (_) => setState(() {
                              _selectedAgentID = id.toLowerCase();
                              _syncTranscripts();
                            }),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              _transcriptPanel(),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // right: boss queue — approvals decide() can resolve
        Expanded(
          flex: 2,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Awaiting you ($running running · $done done)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (pending.isEmpty)
                const Card(
                    child: ListTile(
                        leading: Icon(Icons.check_circle_outline),
                        title: Text('Nothing needs your decision.')))
              else
                for (final a in pending)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.how_to_reg),
                      title: Text(a['title'] as String? ?? '?'),
                      subtitle: (a['reason'] as String?) == null
                          ? null
                          : Text(a['reason'] as String,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'approve',
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () => _run(
                                'approve ${a['title']}',
                                () => _bridge.decide(a['id'] as String? ?? '',
                                    approved: true)),
                          ),
                          IconButton(
                            tooltip: 'reject',
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () => _run(
                                'reject ${a['title']}',
                                () => _bridge.decide(a['id'] as String? ?? '',
                                    approved: false)),
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _run('advance', _bridge.advance),
                icon: const Icon(Icons.fast_forward),
                label: const Text('Let the CTO advance'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Bottom transcript surface for the tapped employee: monospace, auto-
  /// follows the tail unless the boss scrolled up (classic log-viewer UX —
  /// reading history must not fight the stream).
  Widget _transcriptPanel() {
    final agentID = _selectedAgentID;
    final text = agentID == null ? null : _transcripts[agentID];
    return Container(
      height: 160,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(width: 1, color: Colors.black26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Row(
              children: [
                Icon(Icons.terminal,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    agentID == null
                        ? 'Tap an employee chip to watch their terminal.'
                        : 'Transcript · ${text == null || text.isEmpty ? '(no output yet)' : '${text.split('\n').length} lines'}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                if (agentID != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _followTail = !_followTail;
                      if (_followTail) _syncTranscripts();
                    }),
                    child: Text(_followTail ? 'following' : 'paused'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: GestureDetector(
              onPanDown: (_) {
                if (_followTail) setState(() => _followTail = false);
              },
              child: ListView(
                controller: _transcriptScroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                children: [
                  SelectableText(
                    text ?? '',
                    style: const TextStyle(
                        fontFamily: 'Menlo, monospace',
                        fontSize: 11,
                        height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _taskIcon(String status) => switch (status) {
        'done' => Icons.check_circle,
        'running' => Icons.play_circle,
        'blocked' => Icons.block,
        'failed' => Icons.error,
        'needsApproval' => Icons.hourglass_top,
        _ => Icons.radio_button_unchecked,
      };

  IconData _agentIcon(String status) => switch (status) {
    'coding' => Icons.code,
    'thinking' => Icons.psychology,
    'reviewing' => Icons.fact_check,
    _ => Icons.person_outline,
  };

  /// v0.5.0 "the office talks back", shell twin of the ×N hand-raise
  /// badge: a waitingApproval employee with stacked requests shows the
  /// count right on the roster chip. Derived from the snapshot the same
  /// render already holds — zero extra bridge calls on the paint path.
  String _pendingBadge(OpcSnapshot snap, String id, String status) {
    if (status != 'waitingApproval') return '';
    final n = snap.approvalCountsByRequester[id.toLowerCase()] ?? 0;
    return n > 1 ? ' ×$n' : '';
  }

  Widget _statusBar() => Material(
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(_lastAction ?? 'idle',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      );
}
