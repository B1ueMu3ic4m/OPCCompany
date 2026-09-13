import 'dart:io';

import 'package:flutter/material.dart';

import 'opc_bridge_bindings.dart';
import 'shell_smoke.dart';

/// M3 skeleton: the desktop shell is a thin, honest mirror of the bridge —
/// no local state beyond what the core snapshot provides. The bridge hops
/// onto the main queue internally (any thread may call), and this shell's
/// platform thread pumps it — that is the host contract a bare `dart run`
/// VM cannot satisfy, so the behavioral smoke lives HERE, not in bin/.
void main() => runApp(const OpcShellApp());

class OpcShellApp extends StatelessWidget {
  const OpcShellApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'OPC Company',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: const CompanyHome(),
      );
}

class CompanyHome extends StatefulWidget {
  const CompanyHome({super.key});
  @override
  State<CompanyHome> createState() => _CompanyHomeState();
}

class _CompanyHomeState extends State<CompanyHome> {
  final OpcBridge _bridge = OpcBridge();
  OpcSnapshot? _snap;
  String? _lastAction;

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
    _bridge.stop();
    super.dispose();
  }

  void _run(String label, int Function() action) {
    setState(() {
      final rc = action();
      _lastAction = rc == OpcBridge.ok
          ? '$label: ok'
          : '$label: refused — ${_bridge.lastError()}';
      _snap = _bridge.snapshot();
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    final pending = snap?.approvals
            .whereType<Map<String, dynamic>>()
            .where((a) => a['status'] == 'pending')
            .length ??
        0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('OPC Company — shell (M3 skeleton)'),
      ),
      body: Center(
        child: snap == null
            ? Text(_lastAction ?? 'no snapshot')
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('schema v${snap.schemaVersion}',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(spacing: 24, children: [
                    _stat('products', snap.products.length),
                    _stat('employees', snap.agents.length),
                    _stat('tasks', snap.tasks.length),
                    _stat('awaiting boss', pending),
                  ]),
                  const SizedBox(height: 24),
                  Text(_lastAction ?? '',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'refresh',
            onPressed: () => setState(() => _snap = _bridge.snapshot()),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'advance',
            onPressed: () => _run('advance', _bridge.advance),
            icon: const Icon(Icons.fast_forward),
            label: const Text('Advance CTO'),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, int value) => Column(children: [
        Text('$value', style: Theme.of(context).textTheme.headlineSmall),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
