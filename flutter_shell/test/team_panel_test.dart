import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v0.9.0 "the name behind the work" — the team panel's contract. Rows
// arrive ALREADY ordered from the store's door (traffic desc, the named
// unattributed bucket LAST); the shell must render that order verbatim
// and never invent people. A refused verb (a core without team_stats_list)
// says so; it never fakes a quiet office.

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
    fake.teamStatsResult = [
      {
        'agentID': 'a', 'name': 'Alice', 'assigned': 2, 'deliveries': 1,
        'missing': 1, 'asked': 0, 'risks': 0, 'activeNow': 3,
      }
    ];
    final rows = bridge.teamStatsList();
    expect(rows, isNotNull);
    expect(rows!.single['name'], 'Alice');
    expect(rows.single['assigned'], 2);
    // hours rides the payload when asked for
    bridge.teamStatsList(hours: 48);
    final cmd = fake.commands.lastWhere((c) => c.$1 == 'team_stats_list');
    expect(cmd.$2['hours'], 48);
    // an object payload (wrong channel) => WHOLESALE null
    final liar = FakeOpcBridge()..rawCarryOverride = '{"not": "a list"}';
    expect(liar.asBridge().teamStatsList(), isNull);
    // a non-map element poisons the batch: rows.length != decoded.length
    final poison = FakeOpcBridge()..teamStatsResult = null;
    poison.rawCarryOverride = '[{"name": "ok"}, "bare string"]';
    expect(poison.asBridge().teamStatsList(), isNull);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('door order is kept; MISSING rides the read-time verdict',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    fake.teamStatsResult = [
      {
        'agentID': 'x', 'name': 'Alice', 'assigned': 2, 'deliveries': 1,
        'missing': 1, 'asked': 0, 'risks': 0, 'activeNow': 3,
      },
      {
        'name': '未分配', 'assigned': 0, 'deliveries': 2, 'missing': 2,
        'asked': 0, 'risks': 0, 'activeNow': 0,
      },
    ];
    // the stall panel shares the home column; neutralize its default
    // rows so the exact-text finders below speak only about the team
    fake.stallsResult = [];
    await tester.pumpWidget(
        MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('未分配'), findsOneWidget);
    expect(find.textContaining('1 delivered (1 MISSING)'), findsOneWidget);
    expect(find.textContaining('2 delivered (2 MISSING)'), findsOneWidget);
    expect(find.textContaining('3 open now'), findsOneWidget);
    // door order preserved verbatim — the unattributed row renders LAST
    expect(tester.getTopLeft(find.text('Alice')).dy,
        lessThan(tester.getTopLeft(find.text('未分配')).dy));
  });

  testWidgets('an empty window says nobody moved — honestly', (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    fake.teamStatsResult = [];
    await tester.pumpWidget(
        MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();
    expect(find.text('Nobody moved in the last 24h.'), findsOneWidget);
  });

  testWidgets('an old core gets no-team-stats, NOT a quiet office',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    fake.teamStatsRefused = true;
    await tester.pumpWidget(
        MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();
    expect(find.text('No team stats from this core.'), findsOneWidget);
    expect(find.text('Nobody moved in the last 24h.'), findsNothing);
  });
}
