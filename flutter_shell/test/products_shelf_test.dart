import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.37.0 the product shelf (bridge v1.27): every product with its
// lifecycle stage — the fact the snapshot's switcher doesn't carry. The
// selected row is marked; an old core says so; a malformed row refuses
// the WHOLE shelf (never a partial one); an empty shelf says so.

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(2000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(FakeOpcBridge fake) =>
    MaterialApp(home: CompanyHome(bridge: fake.asBridge()));

void main() {
  testWidgets('the shelf renders each product with its stage and marks '
      'the selected one', (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge();
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();

    expect(find.textContaining('Alpha · building'), findsOneWidget);
    expect(find.textContaining('Beta · shipping'), findsOneWidget,
        reason: 'the stage is the fact the snapshot switcher lacks');
    expect(find.byIcon(Icons.check_circle), findsOneWidget,
        reason: 'exactly the selected product carries the mark');
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('an old core says so — never a fabricated shelf',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge()..productsRefused = true;
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();

    expect(find.text('No product shelf from this core.'), findsOneWidget);
    expect(find.textContaining('Alpha'), findsNothing);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('a malformed row refuses the whole shelf — never partial',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge()
      ..productsListResult = [
        {'id': 'P1', 'name': 'Alpha', 'stage': 'building', 'selected': true},
        'not-a-map',
      ];
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();

    expect(find.text('No product shelf from this core.'), findsOneWidget,
        reason: 'wholesale refusal — a partial shelf never renders');
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('an empty shelf says so', (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge()..productsListResult = <Map<String, dynamic>>[];
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();

    expect(find.text('No products yet — the shelf is empty.'), findsOneWidget);
    expect(fake.unfreed, isEmpty);
  });
}
