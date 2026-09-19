import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opc_flutter_shell/main.dart';
import 'package:opc_flutter_shell/opc_bridge_bindings.dart';

import 'fake_opc_bridge.dart';

Map<String, dynamic> _snap({
  String selectedProductID = 'P1',
  int taskCount = 3,
  List<Map<String, dynamic>> approvals = const [],
  List<Map<String, dynamic>>? agents,
}) {
  return {
    'schemaVersion': 14,
    'selectedProductID': selectedProductID,
    'products': [
      {'id': 'P1', 'name': 'Demo'}
    ],
    'tasks': [
      for (var i = 0; i < taskCount; i++)
        {'id': 'T$i', 'productID': 'P1', 'title': 'Task $i', 'status': i == 0 ? 'running' : 'planned'}
    ],
    'agents': agents ?? [
      {'id': 'A1', 'displayName': 'Eve', 'status': 'coding'},
      {'id': 'A2', 'displayName': 'Adam', 'status': 'idle'},
    ],
    'approvals': approvals,
  };
}

Widget _app(OpcBridge bridge) => MaterialApp(home: CompanyHome(bridge: bridge));

/// The employee roster lives below the task board in a lazily-built
/// ListView; the default 800x600 test viewport never realizes it (chips
/// simply don't exist until scrolled into view). Roomy virtual screen so
/// structural assertions test content, not scroll mechanics.
void _useBigViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(2000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// write-verb commands only. The query doors follow a NAMING RULE baked
/// into the bridge contract (v1.3+ array verbs are `*_list`, logs are
/// `terminal_*`) — enforce the rule, not an ever-growing list. A new
/// query verb that ignores the naming rule will break HERE, loudly.
const _queryVerbPrefixes = ['terminal_', 'snapshot'];
List<(String, Map<String, dynamic>)> writeCmds(FakeOpcBridge f) =>
    f.commands
        .where((c) =>
            !_queryVerbPrefixes.any(c.$1.startsWith) &&
            !c.$1.endsWith('_list'))
        .toList();

void main() {
  testWidgets('renders the snapshot the bridge provides', (tester) async {
    _useBigViewport(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap(taskCount: 3));
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();

    expect(find.text('OPC Company — shell · schema v14'), findsOneWidget);
    expect(find.text('Task 0'), findsOneWidget);
    expect(find.text('Eve · coding'), findsOneWidget);
    expect(find.text('Adam · idle'), findsOneWidget);
    // the wrapper freed every snapshot string it was handed
    expect(fake.unfreed, isEmpty, reason: 'snapshot string leaked by wrapper');
  });

  testWidgets('create failure surfaces the reason and stops the loop',
      (tester) async {
    _useBigViewport(tester);
    final fake = FakeOpcBridge(createResult: OpcBridge.refused)
      ..nextError = 'bridge already created';
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pump();

    expect(find.textContaining('bridge create failed'), findsOneWidget);
    // a bridge that never came alive must never be destroyed (C singleton
    // misuse; the wrapper's _alive guard is the seal)
    expect(fake.destroyCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sending a goal calls sendGoal and reloads', (tester) async {
    _useBigViewport(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap(taskCount: 3));
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ship v1');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    // NOTE: compare fields, not tuples — record == uses Map identity for the
    // payload field, so a tuple literal NEVER equals a decoded map.
    expect(writeCmds(fake), hasLength(1));
    expect(writeCmds(fake).single.$1, 'goal');
    expect(writeCmds(fake).single.$2, {'text': 'ship v1'});
    expect(find.textContaining('goal "ship v1": ok'), findsOneWidget);
    // the input clears after a successful send (read the controller itself:
    // typed text is not findable as a Text widget)
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('empty goal is refused locally — zero bridge traffic',
      (tester) async {
    _useBigViewport(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send'));
    await tester.pump();

    // never even reached the bridge as a WRITE — boot's ledger pull
    // (history_list) is the only traffic allowed here, by construction.
    expect(writeCmds(fake), isEmpty);
    expect(find.textContaining('goal: empty'), findsOneWidget);
  });

  testWidgets('goal refusal prints the core reason verbatim', (tester) async {
    _useBigViewport(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();
    // arm AFTER boot settled: a query verb pulled during init would
    // otherwise eat the one-shot rc before the goal command sees it
    fake.nextCommandResult = OpcBridge.refused;
    fake.nextError = 'snapshot is shared with the desktop app';

    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining('refused — snapshot is shared'), findsOneWidget);
  });

  testWidgets('approve button decides with the row\'s id and approved=true',
      (tester) async {
    _useBigViewport(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap(approvals: [
      {'id': 'AP1', 'productID': 'P1', 'title': 'Spend budget', 'reason': 'costs 100', 'status': 'pending'},
    ]));
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();

    expect(find.text('Spend budget'), findsOneWidget);
    await tester.tap(find.byTooltip('approve'));
    await tester.pumpAndSettle();

    expect(writeCmds(fake), hasLength(1));
    expect(writeCmds(fake).single.$1, 'decide');
    expect(writeCmds(fake).single.$2, {'approvalID': 'AP1', 'approved': true});
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('reject button sends approved=false', (tester) async {
    _useBigViewport(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap(approvals: [
      {'id': 'AP9', 'productID': 'P1', 'title': 'Risky', 'status': 'pending'},
    ]));
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('reject'));
    await tester.pumpAndSettle();

    expect(writeCmds(fake).single.$2['approved'], false);
    expect(writeCmds(fake).single.$2['approvalID'], 'AP9');
  });

  testWidgets('advance button hits the advance verb', (tester) async {
    _useBigViewport(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Let the CTO advance'));
    await tester.pumpAndSettle();

    expect(writeCmds(fake), hasLength(1));
    expect(writeCmds(fake).single.$1, 'advance');
    expect(writeCmds(fake).single.$2, isEmpty);
    expect(find.textContaining('advance: ok'), findsOneWidget);
  });

  testWidgets('approval of another product stays out of the queue',
      (tester) async {
    _useBigViewport(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap(approvals: [
      {'id': 'OTHER', 'productID': 'P2', 'title': 'Not ours', 'status': 'pending'},
    ]));
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();

    expect(find.text('Not ours'), findsNothing);
    expect(find.textContaining('Nothing needs your decision'), findsOneWidget);
  });

  testWidgets('transcript flow: digest → tail → render for tapped employee',
      (tester) async {
    _useBigViewport(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap())
      ..digestResult = {'a1': 11};
    // scripted tail: one window covers the whole log
    fake.tailResult = {'text': 'hello from seat', 'nextOffset': 11, 'length': 11};
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();

    // roster ids are raw snapshot strings; the UI lowercases them for digest
    // keys — _snap uses 'A1', so the cursor key is 'a1'
    await tester.tap(find.text('Eve · coding'));
    await tester.pumpAndSettle();

    final tails = fake.commands.where((c) => c.$1 == 'terminal_tail').toList();
    expect(tails, isNotEmpty);
    expect(tails.first.$2['agentID'], 'a1');
    expect(find.textContaining('hello from seat'), findsOneWidget);

    // cursor protocol: unchanged digest must NOT refetch
    fake.digestResult = {'a1': 11}; // same length => no growth
    final beforeTails = tails.length;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    final afterTails = fake.commands
        .where((c) => c.$1 == 'terminal_tail' && c.$2['agentID'] == 'a1')
        .length;
    expect(afterTails, beforeTails, reason: 'unchanged digest must not refetch');
  });

  testWidgets('log shrink resets the viewer instead of showing stale text',
      (tester) async {
    _useBigViewport(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap())
      ..digestResult = {'a1': 11};
    fake.tailResult = {'text': 'OLD CONTENT', 'nextOffset': 11, 'length': 11};
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eve · coding'));
    await tester.pumpAndSettle();
    expect(find.textContaining('OLD CONTENT'), findsOneWidget);

    // core cleared/truncated the log: digest drops to 3
    fake.digestResult = {'a1': 3};
    fake.tailResult = {'text': 'new', 'nextOffset': 3, 'length': 3};
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(find.textContaining('OLD CONTENT'), findsNothing);
    expect(find.textContaining('new'), findsOneWidget);
    // and the refetch started from 0, not the stale cursor
    final lastTail = fake.commands.lastWhere((c) => c.$1 == 'terminal_tail');
    expect(lastTail.$2['afterOffset'], 0);
  });

  testWidgets('v0.5.0 badge: a waitingApproval employee with stacked '
      'requests shows ×N on the roster chip — a plain or single-request '
      'employee never does', (tester) async {
    _useBigViewport(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap(
      agents: [
        {'id': 'A1', 'displayName': 'Eve', 'status': 'waitingApproval'},
        {'id': 'A2', 'displayName': 'Adam', 'status': 'waitingApproval'},
        {'id': 'A3', 'displayName': 'Ivan', 'status': 'idle'},
      ],
      approvals: [
        // Eve stacks two (requesterIDs vary in case on purpose — the
        // roster's ids are lowercase-matched); Adam has one — a lone
        // request is already obvious from the raised hand, no badge.
        {'id': 'AP1', 'productID': 'P1', 'title': 'One', 'status': 'pending',
         'requesterID': 'A1'},
        {'id': 'AP2', 'productID': 'P1', 'title': 'Two', 'status': 'pending',
         'requesterID': 'a1'},
        {'id': 'AP3', 'productID': 'P1', 'title': 'Solo', 'status': 'pending',
         'requesterID': 'A2'},
      ],
    ));
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();

    expect(find.text('Eve · waitingApproval ×2'), findsOneWidget);
    expect(find.text('Adam · waitingApproval'), findsOneWidget); // single: no badge
    expect(find.text('Ivan · idle'), findsOneWidget);
  });
}
