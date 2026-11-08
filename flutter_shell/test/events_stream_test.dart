import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/main.dart';

import 'fake_opc_bridge.dart';

// v2.43.0 the event stream card (bridge v1.32): EVERY kind of event on
// the current product — the full stream the macOS event log renders,
// newest first, capped at 50. kind rides the raw enum value; an old
// core says so; a malformed row refuses the WHOLE stream; an empty
// stream says so.

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(2000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(FakeOpcBridge fake) =>
    MaterialApp(home: CompanyHome(bridge: fake.asBridge()));

void main() {
  testWidgets('the stream renders every kind with its raw vocabulary',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge();
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();

    expect(find.text('[taskAssigned] 分配任务：审计这封'), findsOneWidget);
    expect(find.text('[risk] 规模风险 3'), findsOneWidget,
        reason: 'the full stream — no boss filtering on this door');
    expect(find.text('[ctoSummary] 技术负责人摘要'), findsOneWidget);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('an old core says so — never a fabricated stream',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge()..eventsRefused = true;
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();

    expect(find.text('No event stream from this core.'), findsOneWidget);
    expect(find.textContaining('taskAssigned'), findsNothing);
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('a malformed row refuses the whole stream — never partial',
      (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge()
      ..eventsListResult = [
        {
          'id': 'e1',
          'kind': 'risk',
          'title': '风险',
          'detail': 'x',
          'createdAt': 1757001000,
        },
        'not-a-map',
      ];
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();

    expect(find.text('No event stream from this core.'), findsOneWidget,
        reason: 'wholesale refusal — a partial stream never renders');
    expect(fake.unfreed, isEmpty);
  });

  testWidgets('an empty stream says so', (tester) async {
    _wide(tester);
    final fake = FakeOpcBridge()..eventsListResult = <Map<String, dynamic>>[];
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();

    expect(find.text('No events yet — the office is quiet.'), findsOneWidget);
    expect(fake.unfreed, isEmpty);
  });
}
