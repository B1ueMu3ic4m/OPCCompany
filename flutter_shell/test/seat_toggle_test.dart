import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.0.0 the seat lifecycle — the shell starts its own employees. Pins
// the wrapper contract (seat_spawn/seat_stop: '' = success, refusal
// verbatim), the toggle wiring (what THIS shell spawned this session —
// never a guessed liveness), and the honest refusal surface.

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

Future<CompanyHome> _pump(WidgetTester tester, FakeOpcBridge fake) async {
  final home = CompanyHome(bridge: fake.asBridge());
  await tester.pumpWidget(MaterialApp(home: home));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ChoiceChip));
  await tester.pumpAndSettle();
  return home;
}

void main() {
  test('wrapper returns silence on success and the verbatim refusal', () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    expect(bridge.seatSpawn('A'), '');
    expect(bridge.seatStop('A'), '');
    expect(fake.seatCommands,
        [('seat_spawn', 'A'), ('seat_stop', 'A')]);

    fake.seatSpawnRefusal = 'seat_spawn: codex runs one-shot';
    fake.seatStopRefusal = 'seat_stop: no local seat for A';
    expect(bridge.seatSpawn('A'), contains('one-shot'));
    expect(bridge.seatStop('A'), contains('no local seat'));
    expect(fake.seatCommands, hasLength(4));
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('start seat records the spawn and flips the toggle',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await _pump(tester, fake);

    await tester.tap(find.byKey(const ValueKey('seat-toggle')));
    await tester.pumpAndSettle();

    expect(fake.seatCommands, hasLength(1));
    // the roster keys agents LOWERCASED — the spawn must carry the same
    // id the transcript cursors use
    expect(fake.seatCommands.single,
        ('seat_spawn', '11111111-1111-1111-1111-111111111111'));
    expect(find.text('stop seat'), findsOneWidget);
    expect(find.text('✓ seat started'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a stop refusal shows verbatim and keeps the seat tracked',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    fake.seatStopRefusal =
        'seat_stop: bridge refused — seat process did not exit';
    await _pump(tester, fake);

    await tester.tap(find.byKey(const ValueKey('seat-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('stop seat'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('seat-toggle')));
    await tester.pumpAndSettle();

    expect(fake.seatCommands, hasLength(2));
    expect(fake.seatCommands.last.$1, 'seat_stop');
    expect(find.textContaining('did not exit'), findsOneWidget);
    // the failed stop keeps the seat tracked — the shell never guesses
    expect(find.text('stop seat'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
