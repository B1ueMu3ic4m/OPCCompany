import 'package:flutter_test/flutter_test.dart';
import 'package:opc_flutter_shell/opc_bridge_bindings.dart';
import 'fake_opc_bridge.dart';

void main() {
  test('digest rejects malformed lengths without casting exceptions', () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    for (final value in [null, true, '3', -1, 1.5, [], {}]) {
      fake.digestResult = {'a1': value};
      expect(bridge.terminalDigest(), isNull);
      expect(fake.unfreed, isEmpty);
    }
    fake.digestResult = {'a1': 3};
    expect(bridge.terminalDigest(), {'a1': 3});
  });

  test('tail rejects malformed shape and impossible cursor', () {
    final fake = FakeOpcBridge();
    final bridge = fake.asBridge();
    for (final payload in <Map<String, dynamic>>[
      {},
      {'text': 5, 'nextOffset': 1, 'length': 1},
      {'text': 'x', 'nextOffset': '1', 'length': 1},
      {'text': 'x', 'nextOffset': -1, 'length': 1},
      {'text': 'x', 'nextOffset': 2, 'length': 1},
      {'text': 'x', 'nextOffset': 1.5, 'length': 2},
    ]) {
      fake.tailResult = payload;
      expect(bridge.terminalTail('a1'), isNull);
      expect(fake.unfreed, isEmpty);
    }
    fake.tailResult = {'text': 'x', 'nextOffset': 1, 'length': 1};
    expect(bridge.terminalTail('a1')?.text, 'x');
  });

  test('query refusals preserve reason and free returned buffers', () {
    final fake = FakeOpcBridge()
      ..nextCommandResult = OpcBridge.refused
      ..nextError = 'query refused';
    final bridge = fake.asBridge();
    expect(bridge.terminalDigest(), isNull);
    expect(bridge.lastError(), 'query refused');
    expect(fake.unfreed, isEmpty);
    expect(bridge.snapshot(), isNotNull);
    expect(fake.unfreed, isEmpty);
  });
}
