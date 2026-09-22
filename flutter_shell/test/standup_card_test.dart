import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opc_flutter_shell/main.dart';
import 'package:opc_flutter_shell/opc_bridge_bindings.dart';

import 'fake_opc_bridge.dart';

// v0.8.0 "the morning standup" — the shell's standup card + the object-
// channel wrapper contract. Same discipline as the ledger/shelf files:
// the window sentence is built from the STORE's counts (never the
// shell's math); a refused or malformed payload renders the honest "no
// standup" card, NOT zero counts dressed up as a quiet company.
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
  test('wrapper carries the seven-count window as ints', () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    fake.standupResult = {
      'hours': 24, 'newWork': 3, 'decisions': 1, 'deliveries': 2,
      'missing': 1, 'risks': 0, 'awaitingNow': 4,
    };
    final w = bridge.standupWindow();
    expect(w, isNotNull);
    expect(w!['newWork'], 3);
    expect(w['awaitingNow'], 4);
    expect(fake.commands.map((c) => c.$1), contains('standup_window'));
    expect(fake.unfreed, isEmpty);
  });

  test('a bad object refuses WHOLESALE — never partial counts', () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    for (final bad in <Map<String, dynamic>>[
      {'hours': 24}, // six contractual fields missing
      {
        'hours': 24, 'newWork': 'three', 'decisions': 0, 'deliveries': 0,
        'missing': 0, 'risks': 0, 'awaitingNow': 0, // non-int count
      },
    ]) {
      fake.standupResult = bad;
      expect(bridge.standupWindow(), isNull);
    }
    // rc refusal also yields null (one-shot, consumed by this very verb)
    final refused = FakeOpcBridge()
      ..nextCommandResult = OpcBridge.refused
      ..nextError = 'bridge not created';
    expect(refused.asBridge().standupWindow(), isNull);
  });

  testWidgets('traffic reads as ONE sentence; owed approvals surface',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    fake.standupResult = {
      'hours': 24, 'newWork': 3, 'decisions': 1, 'deliveries': 2,
      'missing': 1, 'risks': 0, 'awaitingNow': 4,
    };
    await tester.pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.textContaining('3 new'), findsOneWidget);
    expect(find.textContaining('1 decided'), findsOneWidget);
    expect(find.textContaining('2 delivered (1 MISSING)'), findsOneWidget);
    // 'last 24h' may appear twice (header + card title): assert the CARD's
    // own sentence, not a global count
    expect(find.textContaining('last 24h'), findsWidgets);
    expect(find.textContaining('4 approval(s) awaiting YOU'), findsOneWidget);
  });

  testWidgets('quiet answers quiet', (tester) async {
    _wide(tester);
    final quiet = FakeOpcBridge(initialSnapshot: _snap());
    // standupResult stays null => the fake's all-zero default window:
    // a company that DID nothing must read 'nothing', and 'awaiting YOU'
    // must not appear.
    await tester.pumpWidget(MaterialApp(home: CompanyHome(bridge: quiet.asBridge())));
    await tester.pumpAndSettle();
    expect(find.textContaining('nothing in the last 24h'), findsOneWidget);
    expect(find.textContaining('awaiting YOU'), findsNothing);
  });

  testWidgets('an unanswered bridge fakes NOTHING', (tester) async {
    _wide(tester);
    // a core older than v1.6 refuses the verb (_standup stays null) — it
    // must show the honest no-standup card, NOT zero counts. Separate
    // testWidgets: a fresh tree, not a previous widget's leftover state.
    final old = FakeOpcBridge(initialSnapshot: _snap())
      ..standupRefused = true;
    await tester.pumpWidget(MaterialApp(home: CompanyHome(bridge: old.asBridge())));
    await tester.pumpAndSettle();
    expect(find.text('No standup from this core.'), findsOneWidget);
    expect(find.textContaining('nothing in the last'), findsNothing);
  });
}
