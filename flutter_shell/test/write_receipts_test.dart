import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.35.0 the write-receipt family lands in the status line: goal
// (v1.29), decide (v1.30), checkpoint (v1.31) answer with their JSON
// object on SUCCESS — verbatim, never dressed up; plain writes stay
// plain (channel empty → bare ok); refusals ride their reason exactly
// as before.

Map<String, dynamic> _snap({List<Map<String, dynamic>> approvals = const []}) =>
    {
      'schemaVersion': 14,
      'selectedProductID': 'P1',
      'products': [
        {'id': 'P1', 'name': 'Alpha'},
      ],
      'agents': [
        {'id': 'A1', 'displayName': 'Eve', 'status': 'coding'},
      ],
      'tasks': <Object>[],
      'approvals': approvals,
    };

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(2000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('a goal send answers with its receipt chain',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('goal-field')), 'ship it');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining('goal "ship it": ok — {"goal"'), findsOneWidget);
    expect(find.textContaining('"tasks"'), findsOneWidget,
        reason: 'the chain rides verbatim — the ids a script round-trips');
    expect(fake.goalWrites, ['ship it']);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('an approval answers with its decision receipt',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap(approvals: [
      {
        'id': 'AP1',
        'productID': 'P1',
        'title': 'Spend budget',
        'reason': 'costs 100',
        'status': 'pending',
      },
    ]));
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('approve'));
    await tester.pumpAndSettle();

    expect(find.textContaining('approve Spend budget: ok — {"approvalID"'),
        findsOneWidget);
    expect(find.textContaining('"status":"approved"'), findsOneWidget);
    expect(fake.decideCalls.single, ('AP1', true));
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('a refusal stays verbatim — never a receipt', (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap())
      ..goalRefusal = 'snapshot is shared with the desktop app';
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('goal-field')), 'ship it');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining('goal "ship it": refused — snapshot is shared'),
        findsOneWidget);
    expect(find.textContaining('{"goal"'), findsNothing,
        reason: 'a refusal never dresses up as a receipt');
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('a plain write stays plain — advance leaves the channel empty',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Let the CTO advance'));
    await tester.pumpAndSettle();

    expect(find.text('advance: ok'), findsOneWidget,
        reason: 'no receipt on the channel — no decoration pretended');
    expect(fake.unfreed, isEmpty);
  });
}
