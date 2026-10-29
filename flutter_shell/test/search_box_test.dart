import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.26.0 the shell's search box: the query IS the ask — an empty field
// refuses locally (zero bridge traffic), hits render with their door
// names, a refusal (or an old core) lands verbatim, and zero hits say
// so honestly.

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
  testWidgets('the box asks on demand and hits name their doors',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'));
    await _pump(tester, fake);
    expect(find.byKey(const ValueKey('search-hits')), findsNothing);

    await tester.enterText(
        find.byKey(const ValueKey('search-field')), 'goals 门');
    await tester.tap(find.byKey(const ValueKey('search-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('search-hits')), findsOneWidget);
    expect(find.textContaining('[task] 实现 goals 门'), findsOneWidget);
    expect(find.textContaining('[event] goals 门编译失败'), findsOneWidget);
    expect(
        fake.commands
            .where((c) => c.$1 == 'search')
            .every((c) => c.$2['query'] == 'goals 门'),
        isTrue);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('empty refuses locally with zero bridge traffic',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'));
    await _pump(tester, fake);

    await tester.tap(find.byKey(const ValueKey('search-button')));
    await tester.pumpAndSettle();

    expect(fake.commands.where((c) => c.$1 == 'search'), isEmpty,
        reason: 'an empty query must never reach the bridge');
    expect(find.textContaining('search: empty'), findsOneWidget);
  });

  testWidgets('a refusal lands verbatim; zero hits say so honestly',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..searchResult = const [
        'not-a-map', // malformed row → wholesale refusal
      ];
    await _pump(tester, fake);
    await tester.enterText(
        find.byKey(const ValueKey('search-field')), 'anything');
    await tester.tap(find.byKey(const ValueKey('search-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-hits')), findsNothing,
        reason: 'a malformed page never renders as if it were facts');
    expect(find.textContaining('search: refused'), findsOneWidget);

    fake.searchResult = const <dynamic>[];
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('search-field')), 'nothing-matches');
    await tester.tap(find.byKey(const ValueKey('search-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No hits'), findsOneWidget);
    expect(fake.unfreed, isEmpty);
  });
}
