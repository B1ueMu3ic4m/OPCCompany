import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opc_flutter_shell/main.dart';
import 'package:opc_flutter_shell/opc_bridge_bindings.dart';

import 'fake_opc_bridge.dart';

Map<String, dynamic> _snap({
  String selectedProductID = 'P1',
  int taskCount = 3,
  List<Map<String, dynamic>> approvals = const [],
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
    'agents': [
      {'id': 'A1', 'displayName': 'Eve', 'status': 'coding'},
      {'id': 'A2', 'displayName': 'Adam', 'status': 'idle'},
    ],
    'approvals': approvals,
  };
}

Widget _app(OpcBridge bridge) => MaterialApp(home: CompanyHome(bridge: bridge));

void main() {
  testWidgets('renders the snapshot the bridge provides', (tester) async {
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
    final fake = FakeOpcBridge(initialSnapshot: _snap(taskCount: 3));
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ship v1');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    // NOTE: compare fields, not tuples — record == uses Map identity for the
    // payload field, so a tuple literal NEVER equals a decoded map.
    expect(fake.commands, hasLength(1));
    expect(fake.commands.single.$1, 'goal');
    expect(fake.commands.single.$2, {'text': 'ship v1'});
    expect(find.textContaining('goal "ship v1": ok'), findsOneWidget);
    // the input clears after a successful send (read the controller itself:
    // typed text is not findable as a Text widget)
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('empty goal is refused locally — zero bridge traffic',
      (tester) async {
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(fake.commands, isEmpty); // never even reached the bridge
    expect(find.textContaining('goal: empty'), findsOneWidget);
  });

  testWidgets('goal refusal prints the core reason verbatim', (tester) async {
    final fake = FakeOpcBridge(initialSnapshot: _snap())
      ..nextCommandResult = OpcBridge.refused
      ..nextError = 'snapshot is shared with the desktop app';
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining('refused — snapshot is shared'), findsOneWidget);
  });

  testWidgets('approve button decides with the row\'s id and approved=true',
      (tester) async {
    final fake = FakeOpcBridge(initialSnapshot: _snap(approvals: [
      {'id': 'AP1', 'productID': 'P1', 'title': 'Spend budget', 'reason': 'costs 100', 'status': 'pending'},
    ]));
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();

    expect(find.text('Spend budget'), findsOneWidget);
    await tester.tap(find.byTooltip('approve'));
    await tester.pumpAndSettle();

    expect(fake.commands, hasLength(1));
    expect(fake.commands.single.$1, 'decide');
    expect(fake.commands.single.$2, {'approvalID': 'AP1', 'approved': true});
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('reject button sends approved=false', (tester) async {
    final fake = FakeOpcBridge(initialSnapshot: _snap(approvals: [
      {'id': 'AP9', 'productID': 'P1', 'title': 'Risky', 'status': 'pending'},
    ]));
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('reject'));
    await tester.pumpAndSettle();

    expect(fake.commands.single.$2['approved'], false);
    expect(fake.commands.single.$2['approvalID'], 'AP9');
  });

  testWidgets('advance button hits the advance verb', (tester) async {
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Let the CTO advance'));
    await tester.pumpAndSettle();

    expect(fake.commands, hasLength(1));
    expect(fake.commands.single.$1, 'advance');
    expect(fake.commands.single.$2, isEmpty);
    expect(find.textContaining('advance: ok'), findsOneWidget);
  });

  testWidgets('approval of another product stays out of the queue',
      (tester) async {
    final fake = FakeOpcBridge(initialSnapshot: _snap(approvals: [
      {'id': 'OTHER', 'productID': 'P2', 'title': 'Not ours', 'status': 'pending'},
    ]));
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pumpAndSettle();

    expect(find.text('Not ours'), findsNothing);
    expect(find.textContaining('Nothing needs your decision'), findsOneWidget);
  });
}
