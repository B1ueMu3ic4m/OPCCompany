import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.16.0 the shell's doctor door: the button pulls a point-in-time
// diagnosis and renders the FACTS; a malformed payload (a pre-v1.18
// core) never renders as if it were facts — the refusal lands verbatim
// in the status line. Same wide-viewport discipline as the checkpoint
// tests: the actions panel outgrew the default test window long ago.

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
  testWidgets('doctor button pulls the report and renders the facts',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..doctorResult = const {
        'contractVersion': 'v1.18',
        'supportDir': '/tmp/office',
        'stateFileExists': true,
        'stateFileBytes': 8192,
        'tmuxAvailable': false,
        'seatsRunning': 2,
        'seatsAliveButExited': 1,
        'appRunning': false,
        'overrideSet': true,
        'warnings': [
          'OPC_ALLOW_CONCURRENT_WRITE=1 — the cross-process writer guard is OFF',
        ],
      };
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('doctor-report')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('doctor-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('doctor-report')), findsOneWidget);
    expect(find.text('doctor — contract v1.18'), findsOneWidget);
    expect(find.textContaining('8192 bytes'), findsOneWidget);
    expect(find.textContaining('tmux: not found'), findsOneWidget);
    expect(find.textContaining('seats running: 2'), findsOneWidget);
    expect(find.textContaining('OVERRIDDEN'), findsOneWidget);
    expect(find.textContaining('writer guard is OFF'), findsOneWidget);
    expect(fake.commands.any((c) => c.$1 == 'doctor'), isTrue);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('a pre-v1.18 core refuses and the shell says so verbatim',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: snapshot('P1'))
      ..doctorResult = const {
        'legacy': true, // malformed for the v1.18 contract
      };
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('doctor-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('doctor-report')), findsNothing,
        reason: 'a malformed report never renders as if it were facts');
    expect(find.textContaining('doctor: refused'), findsOneWidget);
    expect(fake.unfreed, isEmpty);
  });
}
