import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.18.0 the shell's risk ledger: the card renders the door's boss-view
// rows and never invents a risk. A malformed payload (a non-Map row)
// renders the honest refusal state, not a partial ledger.

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

void main() {
  testWidgets('the risks card renders the boss view verbatim',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..risksListResult = const [
        {
          'id': 'r1',
          'title': '编译失败：主链路',
          'detail': '模块 A 编译错误',
          'agentID': 'A1',
          'createdAt': 1757000900,
        },
      ];
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.text('编译失败：主链路'), findsOneWidget);
    expect(find.textContaining('模块 A 编译错误'), findsOneWidget);
    expect(fake.commands.any((c) => c.$1 == 'risks_list'), isTrue);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('an empty ledger says quiet office; malformed never renders',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..risksListResult = const <dynamic>[];
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();
    expect(find.text('No risks on the boss desk — quiet office.'),
        findsOneWidget);

    fake.risksListResult = const ['not-a-map'];
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.textContaining('编译失败'), findsNothing,
        reason: 'a malformed ledger never renders as if it were facts');
    expect(fake.unfreed, isEmpty);
  });
}
