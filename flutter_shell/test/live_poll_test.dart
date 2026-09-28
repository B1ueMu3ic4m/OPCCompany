import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v0.12.0 "the live office" — the production poll heartbeat. The shell
// used to move ONLY when a shell action fired; an employee typing in a
// real terminal changes no snapshot field, so the picture froze. The
// fix is a Timer that re-pulls every door — and the test seam is the
// constructor: CompanyHome WITHOUT a pollInterval (every widget test
// here and elsewhere) stays event-driven, because a periodic Timer
// would never let pumpAndSettle settle. THIS file uses pump() to walk
// the fake clock and prove the heartbeat actually re-pulls.
// ignore_for_file: lines_longer_than_80_chars

Map<String, dynamic> _snap() => {
      'schemaVersion': 14,
      'selectedProductID': 'P1',
      'products': [
        {'id': 'P1', 'name': 'Demo'}
      ],
      'tasks': <Map<String, dynamic>>[],
      'agents': <Map<String, dynamic>>[],
      'approvals': <Map<String, dynamic>>[],
    };

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(2000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('with a pollInterval the heartbeat re-pulls on the clock',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await tester.pumpWidget(
        MaterialApp(home: CompanyHome(bridge: fake.asBridge(),
            pollInterval: const Duration(seconds: 1))));
    await tester.pump(); // first frame + initState pull
    final afterBoot = fake.commands.length;

    await tester.pump(const Duration(seconds: 1));
    final afterOneTick = fake.commands.length;
    expect(afterOneTick, greaterThan(afterBoot),
        reason: 'one heartbeat must have re-pulled the bridge');
    // the heartbeat is a full refresh: doors ride along, not just a
    // snapshot re-read
    expect(fake.commands.map((c) => c.$1),
        containsAll(['standup_window', 'catchup_md', 'terminal_digest']));

    await tester.pump(const Duration(seconds: 1));
    expect(fake.commands.length, greaterThan(afterOneTick),
        reason: 'the heartbeat repeats every interval');

    await tester.pumpWidget(const SizedBox.shrink()); // dispose cancels
  });

  testWidgets('without a pollInterval nothing moves on the clock '
      '(event-driven only — the pumpAndSettle safety of every other test)',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pump();
    final afterBoot = fake.commands.length;

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(fake.commands.length, afterBoot,
        reason: 'no pollInterval => no heartbeat: the clock must move nothing');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
