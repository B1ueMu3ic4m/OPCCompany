import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.44.0 the honest hall pointer: the shell cannot probe the Mac's
// tmux — the parity gate documents that exemption — so instead of
// pretending the seats page doesn't exist, the shell SAYS SO and points
// at the door that can (`opc hall` on the Mac). The pointer is static:
// it renders with or without a snapshot, never calls the bridge, and
// never fabricates seat facts.

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(2000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Map<String, dynamic> _snap() => {
      'schemaVersion': 14,
      'selectedProductID': 'P1',
      'products': [
        {'id': 'P1', 'name': 'Alpha'},
      ],
      'agents': <Object>[],
      'tasks': <Object>[],
      'approvals': <Object>[],
    };

void main() {
  testWidgets('the pointer renders with a snapshot', (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.textContaining('run `opc hall` on the Mac'), findsOneWidget);
    expect(fake.commands.where((c) => c.$1 == 'hall'), isEmpty,
        reason: 'the pointer is honest — it never probes what it cannot');
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('the pointer renders without a snapshot too', (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge();
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();

    expect(find.textContaining('opc hall'), findsOneWidget);
    expect(fake.unfreed, isEmpty);
  });
}

Widget _app(FakeOpcBridge fake) =>
    MaterialApp(home: CompanyHome(bridge: fake.asBridge()));
