import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.17.0 the shell's goal ledger: the card renders the door's rows —
// goal text, completion score, step marks — and never invents a chain.
// A malformed payload (a non-Map row) renders the honest refusal state,
// not a partial ledger.

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
  testWidgets('the ledger card renders the door rows verbatim',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..goalsListResult = const [
        {
          'goalID': 'g1',
          'goal': 'ship the doctor door',
          'status': 'warning',
          'completionScore': 42,
          'steps': [
            {'id': 'task-graph', 'title': '任务图', 'status': 'passed',
             'detail': '4/4'},
            {'id': 'approval', 'title': '老板审批', 'status': 'warning',
             'detail': 'pending'},
          ],
          'counts': {'tasks': 4, 'messages': 2, 'approvals': 0,
                     'artifacts': 0, 'verifications': 0},
          'createdAt': 1757000000,
          'updatedAt': 1757000600,
        },
      ];
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.text('ship the doctor door — 42%'), findsOneWidget);
    expect(find.textContaining('[passed] 任务图'), findsOneWidget);
    expect(find.textContaining('[warning] 老板审批'), findsOneWidget);
    expect(fake.commands.any((c) => c.$1 == 'goals_list'), isTrue);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('an empty ledger says so; a malformed one never renders',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..goalsListResult = const <dynamic>[];
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();
    expect(find.text('No goals yet — send one from the command box.'),
        findsOneWidget);

    // a non-Map row is a malformed payload: the wrapper refuses wholesale
    fake.goalsListResult = const ['not-a-map'];
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.textContaining('ship the'), findsNothing,
        reason: 'a malformed ledger never renders as if it were facts');
    expect(fake.unfreed, isEmpty);
  });
}
