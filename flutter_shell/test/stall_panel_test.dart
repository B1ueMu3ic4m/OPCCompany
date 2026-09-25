import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v0.10.0 "the stall watch" — the panel's contract, mirroring the team
// discipline. Rows arrive ALREADY ordered from the store's door (longest-
// frozen first, the named unattributed row LAST); the shell renders that
// order verbatim and never re-sorts or invents blame. A refused verb (a
// core without stalls_list) says so plainly; it NEVER fakes a quiet
// office, and an empty watch is a genuinely unstuck one.

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
  test('wrapper carries rows verbatim, refuses malformed payloads', () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    fake.stallsResult = [
      {
        'itemID': 'j1', 'agentID': 'a', 'name': 'Alice',
        'status': 'waitingApproval', 'dwellMinutes': 90,
        'waitingOnYou': true,
      }
    ];
    final rows = bridge.stallsList();
    expect(rows, isNotNull);
    expect(rows!.single['dwellMinutes'], 90);
    expect(rows.single['waitingOnYou'], true);
    // the threshold knob rides the payload when asked for
    bridge.stallsList(overMinutes: 15);
    final cmd = fake.commands.lastWhere((c) => c.$1 == 'stalls_list');
    expect(cmd.$2['over_minutes'], 15);
    // an object payload (wrong channel) => WHOLESALE null
    final liar = FakeOpcBridge()..rawCarryOverride = '{"not": "a list"}';
    expect(liar.asBridge().stallsList(), isNull);
    // a non-map element poisons the batch
    final poison = FakeOpcBridge()..stallsResult = null;
    poison.rawCarryOverride = '[{"name": "ok"}, "bare string"]';
    expect(poison.asBridge().stallsList(), isNull);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('door order is kept; WAITS ON YOU rides the row fact',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    fake.stallsResult = [
      {
        'itemID': 'j1', 'agentID': 'a1', 'name': 'Alice',
        'status': 'waitingApproval', 'dwellMinutes': 90,
        'waitingOnYou': true,
      },
      {
        'itemID': 'j2', 'name': 'Bob', 'status': 'running',
        'dwellMinutes': 45, 'waitingOnYou': false,
      },
    ];
    // the team panel shares the column — keep its finders out of the way
    fake.teamStatsResult = [];
    await tester.pumpWidget(
        MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.textContaining('90 min — waitingApproval · WAITS ON YOU'),
        findsOneWidget);
    expect(find.textContaining('45 min — running'), findsOneWidget);
    // door order preserved verbatim: longest-frozen renders ABOVE
    final ninety = tester.getTopLeft(find.textContaining('90 min')).dy;
    final fortyFive = tester.getTopLeft(find.textContaining('45 min')).dy;
    expect(ninety, lessThan(fortyFive));
  });

  testWidgets('an empty watch says nothing parked — honestly',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    fake.stallsResult = [];
    await tester.pumpWidget(
        MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();
    expect(find.text('Nothing parked over 30 min.'), findsOneWidget);
  });

  testWidgets('an old core gets no-stall-watch, NOT a quiet office',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    fake.stallsRefused = true;
    await tester.pumpWidget(
        MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();
    expect(find.text('No stall watch from this core.'), findsOneWidget);
    expect(find.text('Nothing parked over 30 min.'), findsNothing);
  });
}
