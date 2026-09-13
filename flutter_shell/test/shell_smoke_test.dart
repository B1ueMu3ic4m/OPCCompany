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
  });
}
