import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v0.11.0 "the catch-up" — the shell's one-page card + the string-
// channel wrapper contract. Same discipline as the standup/shelf files:
// the page comes from the STORE's doors verbatim (the shell renders,
// never recomputes); an old core or refused verb renders the honest
// "no catch-up page" card, NOT a fabricated page.
// ignore_for_file: lines_longer_than_80_chars

Map<String, dynamic> _snap() => {
      'schemaVersion': 14,
      'selectedProductID': 'P1',
      'products': [
        {'id': 'P1', 'name': 'Demo'}
      ],
      'tasks': <Map<String, dynamic>>[],
      'agents': <Map<String, dynamic>>[],
      'approvals': <Map<String, dynamic>>[],
    };

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(2000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('wrapper carries the page STRING verbatim through the channel', () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    fake.catchupMdResult = '# Catch-up — Demo\n\n## Traffic (last 24h)\n';
    final page = bridge.catchupMd();
    expect(page, isNotNull);
    expect(page!, startsWith('# Catch-up — Demo'));
    expect(fake.commands.map((c) => c.$1), contains('catchup_md'));
    expect(fake.unfreed, isEmpty);
  });

  test('an old core (unknown verb) answers null — never a fake page', () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    fake.catchupRefused = true;
    expect(bridge.catchupMd(), isNull);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('the card renders the page verbatim and selectable',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    fake.catchupMdResult = '# Catch-up — Demo\n\n## Traffic (last 24h)\n'
        '- new work: 2\n\n## Waiting on you (1)\n- 等批 — raised by Alice\n';
    await tester.pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.text('Catch-up — one page'), findsOneWidget);
    expect(find.textContaining('# Catch-up — Demo'), findsOneWidget);
    // desk rows ride the page: the store's own words, not the shell's
    expect(find.textContaining('等批'), findsOneWidget);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('an old core renders the honest no-page card',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    fake.catchupRefused = true;
    await tester.pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.text('No catch-up page from this core.'), findsOneWidget);
    expect(find.textContaining('# Catch-up'), findsNothing);
    expect(fake.unfreed, isEmpty);
  });
}
