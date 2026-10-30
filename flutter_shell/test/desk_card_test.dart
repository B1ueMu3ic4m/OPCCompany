import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.27.0 the shell's desk door: the Desk button pulls the SELECTED
// employee's working surface on demand; nothing selected refuses
// locally with zero bridge traffic; a malformed desk never renders as
// if it were facts.

Map<String, dynamic> snapshot(String product) => {
      'schemaVersion': 14,
      'selectedProductID': product,
      'products': [
        {'id': product, 'name': product},
      ],
      'agents': [
        {'id': 'A1', 'displayName': 'Eve', 'status': 'coding'},
      ],
      'tasks': <Object>[],
      'approvals': <Object>[],
    };

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(2000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester, FakeOpcBridge fake) async {
  await tester
      .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('select then Desk pulls the surface and renders the facts',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..deskResult = const {
        'displayName': 'Eve',
        'role': '代码工程师',
        'onTeam': true,
        'profileChips': [
          {'label': '状态', 'value': 'coding'},
        ],
        'assignedTasks': <dynamic>[],
        'workQueue': <dynamic>[],
        'pendingInboxCount': 0,
        'pendingInbox': <dynamic>[],
      };
    await _pump(tester, fake);
    expect(find.byKey(const ValueKey('desk-card')), findsNothing);

    await tester.tap(find.textContaining('Eve · coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('desk-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('desk-card')), findsOneWidget);
    expect(find.text('Eve — 代码工程师'), findsOneWidget);
    expect(find.textContaining('session: not running'), findsOneWidget);
    expect(find.textContaining('assigned tasks: 0'), findsOneWidget);
    expect(fake.commands.any((c) => c.$1 == 'desk'), isTrue);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('nothing selected refuses locally with zero bridge traffic',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'));
    await _pump(tester, fake);

    await tester.tap(find.byKey(const ValueKey('desk-button')));
    await tester.pumpAndSettle();

    expect(fake.commands.where((c) => c.$1 == 'desk'), isEmpty,
        reason: 'a desk with no employee must never reach the bridge');
    expect(find.textContaining('desk: empty'), findsOneWidget);
  });

  testWidgets('a malformed desk lands as a verbatim refusal',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..deskResult = const {
        'displayName': 'Eve',
        'role': 42, // malformed for the v1.17 contract
      };
    await _pump(tester, fake);
    await tester.tap(find.textContaining('Eve · coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('desk-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('desk-card')), findsNothing,
        reason: 'a malformed desk never renders as if it were facts');
    expect(find.textContaining('desk: refused'), findsOneWidget);
    expect(fake.unfreed, isEmpty);
  });
}
