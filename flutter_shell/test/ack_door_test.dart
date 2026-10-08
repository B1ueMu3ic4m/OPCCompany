import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.21.0 the shell's ack door: a PENDING bus row offers its ack; the
// tap resolves the display name through the roster snapshot and sends
// the write; the verbatim refusal (or the ok) lands in the status line;
// an acked row offers nothing.

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

Map<String, dynamic> pendingRow({String status = 'pending'}) => {
      'id': 'm1',
      'kind': 'taskDispatched',
      'status': status,
      'from': 'CTO',
      'to': 'Eve',
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
  testWidgets('a pending row offers its ack and the tap resolves the name',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..messagesListResult = [pendingRow()];
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ack-m1')));
    await tester.pumpAndSettle();

    expect(fake.ackCalls, hasLength(1));
    expect(fake.ackCalls.single, ('m1', 'A1'),
        reason: 'the display name resolves through the roster — the bridge '
            'never sees a name');
    expect(find.textContaining('ack: ok'), findsOneWidget);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('a refusal lands verbatim; an acked row offers nothing',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..messagesListResult = [pendingRow()]
      ..messageAckRefusal =
          'message_ack refused — the message must be PENDING and addressed to this agent on the current product';
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ack-m1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('message_ack refused'), findsOneWidget);

    // an acked row carries no button — nothing to pretend
    fake.messageAckRefusal = null;
    fake.messagesListResult = [pendingRow(status: 'acknowledged')];
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ack-m1')), findsNothing);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('a name off the roster refuses before touching the bridge',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..messagesListResult = [
        pendingRow()..['to'] = 'Nobody',
      ];
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ack-m1')));
    await tester.pumpAndSettle();

    expect(fake.ackCalls, isEmpty,
        reason: 'a name the roster cannot vouch for never reaches the bridge');
    expect(find.textContaining('is not on this roster'), findsOneWidget);
    expect(fake.unfreed, isEmpty);
  });
}
