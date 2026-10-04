import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v1.15 the shell's autopilot button: ONE full dispatch per tap over
// the seat-write contract ('' = success, refusal verbatim), surfaced
// through the same _runWrite pipeline as every other write — refusal
// text lands in the status line, the snapshot reloads either way.

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
  test('wrapper: autopilot answers silence on success, refusal verbatim', () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    expect(bridge.autopilot(), '');
    expect(fake.autopilotCalls, 1);

    fake.autopilotRefusal = 'another writer is active';
    expect(bridge.autopilot(), contains('another writer'));
    expect(fake.autopilotCalls, 2);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('the button fires one dispatch per tap and reloads the doors',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await _pump(tester, fake);

    await tester.tap(find.byKey(const ValueKey('autopilot-button')));
    await tester.pumpAndSettle();

    expect(fake.autopilotCalls, 1);
    expect(find.text('autopilot: ok'), findsOneWidget);
    // the doors reloaded after the write: the refresh pipeline re-asked them
    expect(
        fake.commands.where((c) => c.$1 == 'standup_window').length,
        greaterThanOrEqualTo(1));

    // a refusal surfaces verbatim, never dressed up as an ack
    fake.autopilotRefusal = 'another writer is active';
    await tester.tap(find.byKey(const ValueKey('autopilot-button')));
    await tester.pumpAndSettle();
    expect(fake.autopilotCalls, 2);
    expect(find.text('autopilot: refused — another writer is active'),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
