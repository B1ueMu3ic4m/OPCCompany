import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.7.0 the transcript door's visible face. Pins the wrapper contract
// (object-or-null, wholesale refusal on a malformed payload, the tail
// knob riding the payload) and the pane wiring: the visible/raw toggle
// swaps the transcript pane between the door's sanitized visible log —
// headed by its honest "N of T lines" count — and the raw seat stream.

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
  test('transcript wrapper: the ask rides the payload, refusal is null',
      () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    final t = bridge.transcript('A', tail: 7);
    expect(t, isNotNull);
    expect(t!['lines'], ['visible-line-one', 'visible-line-two']);
    expect(fake.transcriptCalls, [('A', 7)]);

    // a refused verb answers null — never a guess
    fake.transcriptRefusal = 'transcript: no agent with id A';
    expect(bridge.transcript('A'), isNull);

    // a malformed payload refuses WHOLESALE — never half a log
    fake.transcriptRefusal = null;
    fake.transcriptResult = {
      'agentID': 'A',
      'displayName': 'Fake',
      'totalLines': 2,
      'tail': 7,
      'lines': ['good line', 42],
    };
    expect(bridge.transcript('A'), isNull);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('the visible/raw toggle swaps the pane honestly',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge(initialSnapshot: _snap());
    await _pump(tester, fake);

    // raw by default: the pane shows the (empty) seat stream
    expect(find.textContaining('Transcript ·'), findsOneWidget);

    // toggle to visible: the door's lines render under the honest count
    await tester.tap(find.byKey(const ValueKey('visible-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('visible · 2 of 2 lines'), findsOneWidget);
    expect(find.textContaining('visible-line-one'), findsOneWidget);
    expect(fake.transcriptCalls, hasLength(1));
    expect(fake.transcriptCalls.single.$2, 200);

    // toggle back to raw: the seat stream returns, the count header too
    await tester.tap(find.byKey(const ValueKey('visible-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Transcript ·'), findsOneWidget);
    expect(find.textContaining('visible-line-one'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
