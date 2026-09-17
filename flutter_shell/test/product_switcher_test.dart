import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opc_flutter_shell/main.dart';
import 'package:opc_flutter_shell/opc_bridge_bindings.dart';

import 'fake_opc_bridge.dart';

Widget _app(OpcBridge bridge) => MaterialApp(home: CompanyHome(bridge: bridge));

/// Product switcher (shell experience pass): the boss must be able to move
/// between product workspaces WITHOUT touching the macOS app. The switch
/// rides the bridge's product_select verb — the same store path the SwiftUI
/// sidebar uses — and the transcript surface must invalidate with it.
void main() {
  Map<String, dynamic> snapWithProducts(String selectedID) => {
        'schemaVersion': 14,
        'selectedProductID': selectedID,
        'products': [
          {'id': 'P1', 'name': 'Alpha'},
          {'id': 'P2', 'name': 'Beta'},
        ],
        'agents': [],
        'tasks': [],
        'pendingApprovals': [],
        'events': [],
      };

  testWidgets('appBar lists products and marks the selected one',
      (tester) async {
    final fake = FakeOpcBridge(
      initialSnapshot: snapWithProducts('P1'),
    );
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pump();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing); // only the current one shows

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget); // menu opened: both visible
  });

  testWidgets('choosing a product sends product_select with its raw ID',
      (tester) async {
    final fake = FakeOpcBridge(
      initialSnapshot: snapWithProducts('P1'),
    );
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pump();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    // The switch is followed by transcript sync (terminal_digest) — assert
    // product_select was sent with the tapped id, wherever it lands in the
    // pipeline. Field-wise: Dart Map equality is identity, so a record
    // comparison here can NEVER pass (that's a trap, not a test).
    final switchCmd = fake.commands.where((c) => c.$1 == 'product_select').last;
    expect(switchCmd.$1, 'product_select');
    expect(switchCmd.$2['productID'], 'P2');
  });

  testWidgets('refused switch surfaces the core reason, no crash',
      (tester) async {
    final fake = FakeOpcBridge(
      initialSnapshot: snapWithProducts('P1'),
    );
    await tester.pumpWidget(_app(fake.asBridge()));
    await tester.pump();

    fake.nextCommandResult = OpcBridge.refused;
    fake.nextError = 'product_select: no product with id P2';

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    expect(find.textContaining('refused'), findsWidgets);
    expect(find.textContaining('no product with id P2'), findsOneWidget);
  });
}
