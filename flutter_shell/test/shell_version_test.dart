import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.41.0 the shell signs itself: the AppBar carries the shell version,
// and the constant is kept in lockstep with pubspec.yaml — the file the
// Windows build stamps into the exe version resource. A drifted string
// ships a shell that lies about itself; this test is the padlock.

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
  testWidgets('the AppBar signs the shell version next to the core schema',
      (tester) async {
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await tester
        .pumpWidget(MaterialApp(home: CompanyHome(bridge: fake.asBridge())));
    await tester.pumpAndSettle();

    expect(find.textContaining('shell v$kShellVersion'), findsOneWidget,
        reason: 'the version rides the title, verbatim from the constant');
    expect(find.textContaining('schema v14'), findsOneWidget,
        reason: 'the core schema stays beside it — both faces, one bar');
  });

  test('kShellVersion matches pubspec.yaml — the exe version resource',
      () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared =
        RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
    expect(declared, isNotNull, reason: 'pubspec.yaml declares a version');
    expect(declared!.group(1), kShellVersion,
        reason:
            'flutter build stamps pubspec version into the Windows exe '
            'resource — a drift here means the exe and the AppBar '
            'disagree about what build this is');
  });
}
