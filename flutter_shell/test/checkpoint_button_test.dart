import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v1.16 the shell's checkpoint door: the reason IS the record. The
// wrapper answers '' on success and the verbatim refusal otherwise;
// an empty field refuses LOCALLY — zero bridge traffic, nothing
// pretended — and the verbatim refusal (or the ok) lands in the
// status line through the same _runWrite pipeline as every write.

Map<String, dynamic> _snap() => {
      'schemaVersion': 14,
      'selectedProductID': 'P1',
      'products': [
        {'id': 'P1', 'name': 'Demo'}
      ],
      'tasks': <Map<String, dynamic>>[],
      'agents': [
        {
          'id': '11111111-1111-1111-1111-111111111111',
          'displayName': 'Alice',
          'status': 'coding',
        },
      ],
      'approvals': <Map<String, dynamic>>[],
    };

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(2000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester, FakeOpcBridge fake) async {
  await tester.pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
  await tester.pumpAndSettle();
}

void main() {
  test('wrapper: checkpoint answers silence on success, refusal verbatim',
      () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    expect(bridge.checkpoint('before the jump'), '');
    expect(fake.checkpointReasons, ['before the jump']);

    fake.checkpointRefusal = 'checkpoint failed to land';
    expect(bridge.checkpoint('again'), contains('failed to land'));
    expect(fake.checkpointReasons, hasLength(2));
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('empty reason refuses locally with zero bridge traffic',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await _pump(tester, fake);

    await tester.tap(find.byKey(const ValueKey('checkpoint-button')));
    await tester.pumpAndSettle();

    expect(fake.commands.where((c) => c.$1 == 'checkpoint'), isEmpty,
        reason: 'an empty reason must never reach the bridge');
    expect(find.text('checkpoint: empty — a checkpoint needs its reason'),
        findsOneWidget);
  });

  testWidgets('the button files the reason verbatim and reloads the doors',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await _pump(tester, fake);

    await tester.enterText(
        find.byKey(const ValueKey('checkpoint-field')), 'before the jump');
    await tester.tap(find.byKey(const ValueKey('checkpoint-button')));
    await tester.pumpAndSettle();

    expect(fake.checkpointReasons, ['before the jump']);
    expect(find.text('checkpoint: ok'), findsOneWidget);
    expect(
        fake.commands.where((c) => c.$1 == 'standup_window').length,
        greaterThanOrEqualTo(1));

    // a refusal surfaces verbatim, never dressed up as an ack
    fake.checkpointRefusal = 'checkpoint failed to land';
    await tester.enterText(
        find.byKey(const ValueKey('checkpoint-field')), 'second try');
    await tester.tap(find.byKey(const ValueKey('checkpoint-button')));
    await tester.pumpAndSettle();
    expect(find.text('checkpoint: refused — checkpoint failed to land'),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
