import 'package:ble_channel_kit/ble_channel_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BleDevice.fromMap', () {
    final device = BleDevice.fromMap({
      'id': 'AA:BB',
      'name': 'Sensör',
      'rssi': -60,
    });
    expect(device.id, 'AA:BB');
    expect(device.displayName, 'Sensör');
  });

  test('İsimsiz cihaz adı', () {
    final device = BleDevice.fromMap({'id': '11:22', 'name': null, 'rssi': -70});
    expect(device.displayName, contains('İsimsiz'));
  });

  test('BleConnectionEvent binary payload', () {
    final event = BleConnectionEvent.fromMap({
      'status': 'data',
      'message': 'Veri alındı (3 bayt)',
      'data': '01 02 FF  |  ASCII: ...',
      'hex': '01 02 FF',
      'ascii': '...',
      'utf8': null,
      'length': 3,
      'isText': false,
    });
    expect(event.hex, '01 02 FF');
    expect(event.isText, isFalse);
    expect(event.readablePayload, contains('Hex:'));
    expect(event.readablePayload, contains('binary'));
  });

  test('BleConnectionEvent text payload', () {
    final event = BleConnectionEvent.fromMap({
      'status': 'data',
      'message': 'Veri alındı (4 bayt)',
      'data': 'ping',
      'hex': '70 69 6E 67',
      'ascii': 'ping',
      'utf8': 'ping',
      'length': 4,
      'isText': true,
    });
    expect(event.isText, isTrue);
    expect(event.readablePayload, contains('Metin: ping'));
  });
}
