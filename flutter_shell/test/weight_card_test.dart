import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v0.15.0 "the weight door" — the shell's one-line weight card + the
// object-channel wrapper contract. The threshold is NOT the shell's
// opinion: the card quotes the core's own advisory flag (exceedsAdvisory),
// and an old core honestly says "no weight report".
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
  test('wrapper carries the six-key object or refuses wholesale', () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    fake.weightResult = {
      'totalBytes': 100,
      'sections': [
        {'name': 'events', 'bytes': 80},
      ],
      'advisoryBytes': 20971520,
      'exceedsAdvisory': false,
      'terminalLogBytes': 10,
      'logSharePercent': 10,
    };
    final w = bridge.weightJson();
    expect(w, isNotNull);
    expect(w!['totalBytes'], 100);
    expect(fake.commands.map((c) => c.$1), contains('weight_json'));

    // a non-int total refuses WHOLESALE — never half a report
    fake.weightResult = {
      'totalBytes': 'heavy',
      'sections': <dynamic>[],
      'advisoryBytes': 1,
      'exceedsAdvisory': false,
      'terminalLogBytes': 0,
      'logSharePercent': 0,
    };
    expect(bridge.weightJson(), isNull);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('the card quotes the core numbers and the advisory flag',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await tester.pumpWidget(
        MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.text('Snapshot weight'), findsOneWidget);
    // the default fake: 54024 bytes ≈ 53 KB, logs 18%
    expect(find.textContaining('53 KB snapshot — terminal logs 18%'),
        findsOneWidget);
    expect(find.textContaining('advisory: 20.0 MB'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an over-advisory core shows the warning state',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    fake.weightResult = {
      'totalBytes': 25000000,
      'sections': <dynamic>[],
      'advisoryBytes': 20971520,
      'exceedsAdvisory': true,
      'terminalLogBytes': 100,
      'logSharePercent': 0,
    };
    await tester.pumpWidget(
        MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.textContaining('OVER the'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an old core renders the honest no-report card',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    fake.weightRefused = true;
    await tester.pumpWidget(
        MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.text('No weight report from this core.'), findsOneWidget);
    expect(fake.unfreed, isEmpty);
  });
}
