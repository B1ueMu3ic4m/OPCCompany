import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/opc_bridge_bindings.dart';
import 'fake_opc_bridge.dart';

// v1.3 approvals_list wrapper contract. The behavioral smoke (shell_smoke)
// proves the REAL ABI round-trip on macOS and Windows; this file pins the
// wrapper's discipline over the smuggled payload: rc decides, malformed
// payloads never surface as partial rows, returned buffers are freed.
void main() {
  test('carries scripted rows across the fake ABI', () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    fake.approvalsListResult = [
      {'id': 'a1', 'title': 'ship it?', 'reason': 'prod deploy'},
      {'id': 'a2', 'title': 'spend', 'reason': 'paid API', 'requesterID': 'r1'},
    ];
    final rows = bridge.approvalsList();
    expect(rows, isNotNull);
    expect(rows!.map((r) => r['id']).toList(), ['a1', 'a2']);
    // requesterID is optional — absent keys stay absent, no nulls invented
    expect(rows.first.containsKey('requesterID'), isFalse);
    expect(rows[1]['requesterID'], 'r1');
    expect(fake.unfreed, isEmpty);
    // the verb really went over the wire
    expect(fake.commands.map((c) => c.$1), contains('approvals_list'));
  });

  test('empty current product answers an empty list, not null', () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    fake.approvalsListResult = [];
    expect(bridge.approvalsList(), isEmpty);
    expect(fake.unfreed, isEmpty);
  });

  test('refusal (rc=-1) yields null regardless of payload text', () {
    final fake = FakeOpcBridge()
      ..nextCommandResult = OpcBridge.refused
      ..nextError = 'bridge not created';
    final bridge = fake.asBridge();
    expect(bridge.approvalsList(), isNull);
    expect(fake.unfreed, isEmpty);
  });

  test('malformed payloads yield null — never partial rows', () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    // array of non-objects, and mixed rows: BOTH refuse wholesale rather
    // than surface the good half.
    for (final bad in <List<dynamic>>[
      ['not-a-map'],
      [
        {'id': 'ok'},
        'junk',
      ],
    ]) {
      fake.approvalsListResult = bad;
      expect(bridge.approvalsList(), isNull);
    }
    // torn JSON across the C boundary also fails closed
    fake.approvalsListResult = [
      {'id': 'ok'}
    ];
    fake.rawCarryOverride = '[{"id": ';
    expect(bridge.approvalsList(), isNull);
    // and the same fake WITHOUT the override proves the loop only rejects
    // what it must — no over-refusal.
    fake.rawCarryOverride = null;
    expect(bridge.approvalsList()?.length, 1);
    expect(fake.unfreed, isEmpty);
  });
}
