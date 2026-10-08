import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.22.0 the shell's task picker: the snapshot's own list SELECTS, the
// task door RENDERS. A tap pulls the file through task_show; a refusal
// (or an old core) lands verbatim in the status line; the view counts
// edges and judges artifacts (OK/MISSING at read time).

Map<String, dynamic> snapshot(String product) => {
      'schemaVersion': 14,
      'selectedProductID': product,
      'products': [
        {'id': product, 'name': product},
      ],
      'agents': [
        {'id': 'A1', 'displayName': 'Eve', 'status': 'coding'},
      ],
      'tasks': [
        {
          'id': '11111111-1111-1111-1111-111111111111',
          'productID': product,
          'title': '实现 goals 门',
          'status': 'running',
        },
        {
          'id': '22222222-2222-2222-2222-222222222222',
          'productID': product,
          'title': '已完成任务',
          'status': 'done',
        },
      ],
      'approvals': <Object>[],
    };

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(2000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('the list selects; the tap renders the file from the door',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'));
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-file')), findsNothing);

    await tester.tap(find.text('实现 goals 门'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task-file')), findsOneWidget);
    expect(find.textContaining('实现 goals 门 — running'), findsOneWidget);
    expect(find.textContaining('work items: 1'), findsOneWidget);
    expect(find.textContaining('[OK] 实现报告'), findsOneWidget);
    expect(fake.commands.any((c) => c.$1 == 'task_show'), isTrue);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('a refusal lands verbatim; a MISSING artifact is judged',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..taskShowResult = const {
        'taskID': '11111111-1111-1111-1111-111111111111',
        'title': '实现 goals 门',
        'status': 'running',
        'owner': null,
        'successCriteria': 'opc goals 能读出链',
        'artifactPath': null,
        'workItems': 'not-a-list', // malformed for the v1.22 contract
        'artifacts': <dynamic>[],
        'approvals': <dynamic>[],
        'messages': <dynamic>[],
      };
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('实现 goals 门'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-file')), findsNothing,
        reason: 'a malformed file never renders as if it were facts');
    expect(find.textContaining('task: refused'), findsOneWidget);

    // a real file with a dead claim: the door judges it MISSING
    fake.taskShowResult = const {
      'taskID': '11111111-1111-1111-1111-111111111111',
      'title': '实现 goals 门',
      'status': 'running',
      'owner': 'Alice',
      'successCriteria': 'opc goals 能读出链',
      'artifactPath': null,
      'workItems': <dynamic>[],
      'artifacts': [
        {'id': 'a1', 'title': '幽灵报告', 'kind': 'report',
         'path': '/tmp/gone.md', 'existsNow': false},
      ],
      'approvals': <dynamic>[],
      'messages': <dynamic>[],
    };
    await tester.tap(find.text('实现 goals 门'));
    await tester.pumpAndSettle();
    expect(find.textContaining('[MISSING] 幽灵报告'), findsOneWidget);
    expect(fake.unfreed, isEmpty);
  });
}
