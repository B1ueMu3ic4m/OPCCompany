import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

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

void main() {
  testWidgets('removed digest entry clears visible transcript', (tester) async {
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..digestResult = {'a1': 3}
      ..tailResult = {'text': 'OLD', 'nextOffset': 3, 'length': 3};
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eve · coding'));
    await tester.pumpAndSettle();
    expect(find.text('OLD'), findsOneWidget);
    fake.digestResult = {};
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.text('OLD'), findsNothing);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('same-length logs never cross product boundaries',
      (tester) async {
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..digestResult = {'a1': 3}
      ..tailResult = {'text': 'OLD', 'nextOffset': 3, 'length': 3};
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eve · coding'));
    await tester.pumpAndSettle();
    expect(find.text('OLD'), findsOneWidget);

    fake.snapshots.add(snapshot('P2'));
    fake.tailResult = {'text': 'NEW', 'nextOffset': 3, 'length': 3};
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.text('OLD'), findsNothing,
        reason: 'a previous product transcript must never remain visible');
    await tester.tap(find.text('Eve · coding'));
    await tester.pumpAndSettle();
    expect(find.text('NEW'), findsOneWidget);
    final tails = fake.commands.where((c) => c.$1 == 'terminal_tail').toList();
    expect(tails, hasLength(2));
    expect(tails.last.$2['afterOffset'], 0);
    expect(fake.unfreed, isEmpty);
  });
}
