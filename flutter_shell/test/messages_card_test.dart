import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.19.0 the shell's message bus: the card renders the door's rows —
// kind, route, subject — and never invents a message. A malformed
// payload (a non-Map row) renders the honest refusal state, not a
// partial bus.

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

void main() {
  testWidgets('the bus card renders kind, route and subject',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..messagesListResult = const [
        {
          'id': 'm1',
          'kind': 'taskDispatched',
          'status': 'pending',
          'from': 'CTO',
          'to': 'Eve',
          'subject': '派发：实现 goals 门',
          'createdAt': 1757001000,
        },
      ];
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.text('[taskDispatched] CTO → Eve'), findsOneWidget);
    expect(find.text('派发：实现 goals 门'), findsOneWidget);
    expect(fake.commands.any((c) => c.$1 == 'messages_list'), isTrue);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('a quiet bus says so; a malformed one never renders',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..messagesListResult = const <dynamic>[];
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();
    expect(find.text('The bus is quiet.'), findsOneWidget);

    fake.messagesListResult = const ['not-a-map'];
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.textContaining('派发'), findsNothing,
        reason: 'a malformed bus never renders as if it were facts');
    expect(fake.unfreed, isEmpty);
  });
}
