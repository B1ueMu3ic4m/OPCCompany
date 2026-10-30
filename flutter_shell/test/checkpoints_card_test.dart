import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.28.0 the shell's checkpoint archive: the card renders the door's
// rows and never invents a filing. A malformed payload (a non-Map row)
// renders the honest refusal state, not a partial archive.

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
  testWidgets('the archive card renders the door rows verbatim',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..checkpointsListResult = const [
        {
          'file': 'checkpoint-2026-10-31T00-30-00-abc12345.json',
          'bytes': 8192,
          'modifiedAt': 1757001200,
        },
      ];
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.textContaining('checkpoint-2026-10-31'), findsOneWidget);
    expect(find.textContaining('8 KB'), findsOneWidget);
    expect(fake.commands.any((c) => c.$1 == 'checkpoints_list'), isTrue);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('an empty archive says so; a malformed one never renders',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..checkpointsListResult = const <dynamic>[];
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();
    expect(find.textContaining('No filings yet'), findsOneWidget);

    fake.checkpointsListResult = const ['not-a-map'];
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.textContaining('checkpoint-'), findsNothing,
        reason: 'a malformed archive never renders as if it were facts');
    expect(fake.unfreed, isEmpty);
  });
}
