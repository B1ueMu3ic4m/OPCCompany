import 'package:flutter_test/flutter_test.dart';

import 'package:opc_flutter_shell/opc_bridge_bindings.dart';
import 'package:opc_flutter_shell/shell_smoke.dart';

void main() {
  test('SmokeResult serializes for the machine-readable verdict', () {
    final r = SmokeResult('probe', true, 'detail-x');
    expect(r.toJson(), {'name': 'probe', 'pass': true, 'detail': 'detail-x'});
  });

  test('OpcSnapshot exposes documented accessors on a realistic payload', () {
    final snap = OpcSnapshot({
      'schemaVersion': 14,
      'tasks': [
        {'id': 'a'},
        {'id': 'b'},
      ],
      'approvals': [
        {'status': 'pending'},
        {'status': 'approved'},
      ],
    });
    expect(snap.schemaVersion, 14);
    expect(snap.tasks.length, 2);
    expect(
        snap.approvals
            .whereType<Map<String, dynamic>>()
            .where((a) => a['status'] == 'pending')
            .length,
        1);
  });

  test('OpcSnapshot degrades gracefully on a sparse payload', () {
    final snap = OpcSnapshot(const {});
    expect(snap.schemaVersion, 0);
    expect(snap.tasks, isEmpty);
    expect(snap.approvals, isEmpty);
    expect(snap.selectedProductID, isNull);
    // accessors must survive nulls, wrong types, junk entries
    final junk = OpcSnapshot({
      'selectedProductID': 'P1',
      'tasks': [
        null,
        {'productID': 'P1', 'status': 'running'},
        {'status': 'done'}, // wrong product → excluded
        'not-a-map',
      ],
      'approvals': [
        {'status': 'pending', 'productID': 'P1', 'id': 'a'},
        {'status': 'pending', 'productID': 'other'},
        {'status': 'approved', 'productID': 'P1'},
      ],
      'agents': [
        {'displayName': 'Eve', 'status': 'coding'},
        {'displayName': null, 'status': null},
        42,
      ],
    });
    expect(junk.pendingApprovals.length, 1);
    expect(junk.tasksByStatus['running']?.length, 1);
    expect(junk.tasksByStatus['done'], isNull); // wrong-product excluded
    final names = junk.roster.map((r) => r.$2).toList();
    expect(names, ['Eve', '?']); // null displayName maps to '?'
  });

  test('pendingApprovals groups by product and pending status', () {
    final snap = OpcSnapshot({
      'selectedProductID': 'X',
      'approvals': [
        {'id': '1', 'status': 'pending', 'productID': 'X'},
        {'id': '2', 'status': 'approved', 'productID': 'X'},
        {'id': '3', 'status': 'pending', 'productID': 'Y'},
      ],
    });
    final ids = snap.pendingApprovals.map((a) => a['id']).toList();
    expect(ids, ['1']);
  });

  test('tasksByStatus aggregates per status for the selected product', () {
    final snap = OpcSnapshot({
      'selectedProductID': 'X',
      'tasks': [
        {'productID': 'X', 'status': 'running'},
        {'productID': 'X', 'status': 'running'},
        {'productID': 'X', 'status': 'done'},
        {'productID': 'other', 'status': 'running'},
      ],
    });
    final grouped = snap.tasksByStatus;
    expect(grouped['running']?.length, 2);
    expect(grouped['done']?.length, 1);
  });
}
