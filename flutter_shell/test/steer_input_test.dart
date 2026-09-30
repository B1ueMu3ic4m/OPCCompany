import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v0.18.0 "the tell door" — the shell's seat-steering input. Pins the
// wrapper contract (a WRITE: '' = sent, refusal verbatim), the UI wiring
// (the typed line reaches the bridge with the SELECTED agent's id, the
// field clears on success) and the honest refusal surface (the reason
// shows inline, the line stays so the boss can retry).

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

void main() {
  test('wrapper returns silence on success and the verbatim refusal', () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    expect(bridge.terminalSend('A', 'echo hi'), '');
    expect(fake.terminalSends, hasLength(1));
    expect(fake.terminalSends.single.$1, 'A');
    expect(fake.terminalSends.single.$2, 'echo hi');

    fake.terminalSendRefusal =
        'terminal_send: no live tmux seat on this machine';
    expect(bridge.terminalSend('A', 'echo hi'), contains('no live tmux seat'));
    expect(fake.terminalSends, hasLength(2));
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('the typed line reaches the bridge and the field clears',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await tester.pumpWidget(
        MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ChoiceChip));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('steer-input')),
        'echo hello-seat');
    await tester.tap(find.byKey(const ValueKey('steer-send')));
    await tester.pumpAndSettle();

    expect(fake.terminalSends, hasLength(1));
    // the roster keys agents LOWERCASED — the send must carry the same
    // id the transcript cursors use
    expect(fake.terminalSends.single.$1,
        '11111111-1111-1111-1111-111111111111');
    expect(fake.terminalSends.single.$2, 'echo hello-seat');
    expect(find.byKey(const ValueKey('steer-status')), findsOneWidget);
    expect(find.text('✓ sent to seat'), findsOneWidget);
    final field = tester.widget<TextField>(
        find.byKey(const ValueKey('steer-input')));
    expect(field.controller!.text, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a refusal shows verbatim and keeps the line for a retry',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    fake.terminalSendRefusal =
        'terminal_send: agent Alice has no live tmux seat on this machine';
    await tester.pumpWidget(
        MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ChoiceChip));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('steer-input')), 'echo doomed');
    await tester.tap(find.byKey(const ValueKey('steer-send')));
    await tester.pumpAndSettle();

    expect(fake.terminalSends, hasLength(1));
    expect(find.textContaining('no live tmux seat'), findsOneWidget);
    final field = tester.widget<TextField>(
        find.byKey(const ValueKey('steer-input')));
    expect(field.controller!.text, 'echo doomed');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
