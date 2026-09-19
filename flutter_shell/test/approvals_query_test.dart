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

  test('historyList shares the array door (v1.4): rc decides, same '
      'fail-closed rules, and it issues its OWN verb', () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    fake.approvalsListResult = [
      {'id': 'AP1', 'title': 'One', 'status': 'approved', 'decidedAt': 1700000000.0},
      {'id': 'AP2', 'title': 'Two', 'status': 'rejected'},
    ];
    final rows = bridge.historyList();
    expect(rows, isNotNull);
    expect(rows!.length, 2);
    expect(fake.commands.last.$1, 'history_list'); // not approvals_list
    // a torn ledger payload refuses wholesale, exactly like approvals_list
    fake.rawCarryOverride = '[{"id": ';
    expect(bridge.historyList(), isNull);
    expect(fake.unfreed, isEmpty);
  });

  test('deliverablesList shares the array door (v1.5): its own verb, its '
      'own default row, the same fail-closed rules', () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    // the default shelf row must be the SHELF's shape (existsNow present),
    // not a borrowed approvals row — the fake proves the two doors differ.
    final rows = bridge.deliverablesList();
    expect(rows, isNotNull);
    expect(rows!.single['existsNow'], true);
    expect(fake.commands.last.$1, 'deliverables_list');
    fake.deliverablesListResult = [
      {'id': 'S1', 'title': 'real', 'existsNow': true},
      {'id': 'S2', 'title': 'ghost', 'existsNow': false},
    ];
    final scripted = bridge.deliverablesList()!;
    expect(scripted.map((r) => r['existsNow']), [true, false]);
    // object-shaped and torn smuggles both refuse wholesale
    fake.rawCarryOverride = '[{"id": ';
    expect(bridge.deliverablesList(), isNull);
    fake.rawCarryOverride = '{"existsNow": true}';
    expect(bridge.deliverablesList(), isNull);
    expect(fake.unfreed, isEmpty);
  });
}
