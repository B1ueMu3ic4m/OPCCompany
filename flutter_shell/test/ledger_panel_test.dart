import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v0.6.0 "every hand leaves a receipt" — the shell's ledger PANEL.
// historyList() plumbing already has a contract test (approvals_query);
// this pins what the boss SEES: verdict icon semantics, the attribution
// subtitle built from the roster the frame holds (ids in, names out),
// local clock text, and the honest empty state.
// ignore_for_file: lines_longer_than_80_chars

Map<String, dynamic> _snapWith({
  List<Map<String, dynamic>> agents = const [],
  List<Map<String, dynamic>> approvals = const [],
}) => {
      'schemaVersion': 14,
      'selectedProductID': 'P1',
      'products': [
        {'id': 'P1', 'name': 'Demo'}
      ],
      'tasks': <Map<String, dynamic>>[],
      'agents': agents,
      'approvals': approvals,
    };

void main() {
  testWidgets('ledger rows name the asker by roster name, the verdict, '
      'and a local timestamp', (tester) async {
    tester.view.physicalSize = const Size(2000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = FakeOpcBridge(initialSnapshot: _snapWith(agents: [
      {'id': 'aaa', 'displayName': 'Eve', 'status': 'idle'},
    ]));
    fake.approvalsListResult = [
      {
        'id': 'AP1', 'title': 'Ship v1', 'status': 'approved',
        'requesterID': 'AAA', // roster ids match case-insensitively
        'decidedAt': 1757000000, // 2025-09-04 ~ local wall-clock
      },
      {
        'id': 'AP2', 'title': 'Rebuild core', 'status': 'rejected',
        // no requester, no decidedAt: legacy row — the line says
        // "unassigned · rejected", never a fabricated owner or time.
      },
    ];
    await tester.pumpWidget(MaterialApp(
        home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.text('Recent decisions'), findsOneWidget);
    expect(find.text('Ship v1'), findsOneWidget);
    expect(find.text('Rebuild core'), findsOneWidget);
    // subtitle built from roster + verdict + local clock
    final sub = find.textContaining('Eve · approved · 202');
    expect(sub, findsOneWidget,
        reason: 'attributed row must show name, verdict, local time');
    expect(find.textContaining('unassigned · rejected'), findsOneWidget);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('pending queue rows attribute through the SAME door',
      (tester) async {
    tester.view.physicalSize = const Size(2000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // three hands: a known employee (case-insensitive id), a stale id,
    // and no requester at all — the door answers name / unknown / unassigned.
    final fake = FakeOpcBridge(initialSnapshot: _snapWith(
      agents: const [
        {'id': 'aaa', 'displayName': 'Eve', 'status': 'waitingApproval'},
      ],
      approvals: const [
        {'id': 'AP1', 'productID': 'P1', 'title': 'Raise cap',
            'reason': 'r1', 'status': 'pending', 'requesterID': 'AAA'},
        {'id': 'AP2', 'productID': 'P1', 'title': 'New hire',
            'status': 'pending', 'requesterID': 'zzz'},
        {'id': 'AP3', 'productID': 'P1', 'title': 'Buy GPU',
            'reason': 'r3', 'status': 'pending'},
      ],
    ));
    await tester.pumpWidget(MaterialApp(
        home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.text('r1 · from Eve'), findsOneWidget);
    expect(find.text('from unknown employee'), findsOneWidget);
    expect(find.text('r3 · from unassigned'), findsOneWidget);
  });

  testWidgets('empty ledger answers with the honest empty card',
      (tester) async {
    tester.view.physicalSize = const Size(2000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = FakeOpcBridge(initialSnapshot: _snapWith());
    fake.approvalsListResult = []; // bridge answered: genuinely nothing yet
    await tester.pumpWidget(MaterialApp(
        home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.text('No decisions logged yet.'), findsOneWidget);
    expect(find.text('Recent decisions'), findsOneWidget);
  });
}
