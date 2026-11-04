import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.34.0 the shell's batch ack door (bridge v1.25): every pending
// RECIPIENT on the bus offers one mark-all-read row; the tap resolves
// the display name through the roster snapshot and sends the write; the
// receipt {"acked":N} lands verbatim in the status line; a refusal lands
// verbatim; a name off the roster never reaches the bridge.

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

Map<String, dynamic> pendingRow(
        {String id = 'm1', String to = 'Eve', String status = 'pending'}) =>
    {
      'id': id,
      'kind': 'taskDispatched',
      'status': status,
      'from': 'CTO',
      'to': to,
      'subject': '派发：确认这封',
      'createdAt': 1757001000,
    };

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(2000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('a pending recipient offers one mark-all row and the receipt '
      'lands verbatim', (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..messagesListResult = [pendingRow()];
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ack-all-Eve')));
    await tester.pumpAndSettle();

    expect(fake.ackAllCalls, ['A1'],
        reason: 'the display name resolves through the roster — the bridge '
            'never sees a name');
    expect(find.textContaining('ack-all: ok'), findsOneWidget);
    expect(find.textContaining('{"acked":2}'), findsOneWidget,
        reason: 'the receipt rides verbatim — the whole-inbox count, '
            'not the top-5 card');
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('two rows for one recipient collapse to ONE mark-all row',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..messagesListResult = [
        pendingRow(id: 'm1'),
        pendingRow(id: 'm2'),
      ];
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ack-all-Eve')), findsOneWidget,
        reason: 'the verb is per-agent — one recipient, one row');
    expect(find.byKey(const ValueKey('ack-m1')), findsOneWidget);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('a refusal lands verbatim', (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..messagesListResult = [pendingRow()]
      ..messageAckAllRefusal =
          'message_ack_all requires a UUID agentID';
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ack-all-Eve')));
    await tester.pumpAndSettle();
    expect(find.textContaining('message_ack_all requires'), findsOneWidget);
    expect(fake.ackAllCalls, ['A1'],
        reason: 'the ask is recorded even when refused');
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('a name off the roster refuses before touching the bridge',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..messagesListResult = [pendingRow()..['to'] = 'Nobody'];
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ack-all-Nobody')));
    await tester.pumpAndSettle();

    expect(fake.ackAllCalls, isEmpty,
        reason: 'a name the roster cannot vouch for never reaches the bridge');
    expect(find.textContaining('is not on this roster'), findsOneWidget);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('a quiet bus offers no mark-all row', (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..messagesListResult = [pendingRow(status: 'acknowledged')];
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ack-all-Eve')), findsNothing,
        reason: 'nothing pending — nothing to pretend');
    expect(fake.unfreed, isEmpty);
  });
}
