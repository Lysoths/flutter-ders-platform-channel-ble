import 'package:flutter_test/flutter_test.dart';
import 'package:ble_channel_kit/ble_channel_kit.dart';
import 'package:ble_channel_kit/ble_channel_kit_platform_interface.dart';
import 'package:ble_channel_kit/ble_channel_kit_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockBleChannelKitPlatform
    with MockPlatformInterfaceMixin
    implements BleChannelKitPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<bool> isBluetoothOn() => Future.value(true);

  @override
  Future<bool> hasPermissions() => Future.value(true);

  @override
  Future<bool> ensurePermissions() => Future.value(true);

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<List<BleDevice>> getBondedDevices() async => const [];

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> write(
    String data, {
    String? serviceUuid,
    String? characteristicUuid,
  }) async {}

  @override
  Future<void> read({String? serviceUuid, String? characteristicUuid}) async {}

  @override
  Future<void> openAppSettings() async {}

  @override
  Stream<BleDevice> get scanResults => const Stream.empty();

  @override
  Stream<BleConnectionEvent> get connectionEvents => const Stream.empty();
}

void main() {
  final BleChannelKitPlatform initialPlatform = BleChannelKitPlatform.instance;

  test('$MethodChannelBleChannelKit varsayılan örnek', () {
    expect(initialPlatform, isInstanceOf<MethodChannelBleChannelKit>());
  });

  test('getPlatformVersion mock', () async {
    final plugin = BleChannelKit();
    final fakePlatform = MockBleChannelKitPlatform();
    BleChannelKitPlatform.instance = fakePlatform;

    expect(await plugin.getPlatformVersion(), '42');
  });

  test('isBluetoothOn mock', () async {
    BleChannelKitPlatform.instance = MockBleChannelKitPlatform();
    expect(await BleChannelKit().isBluetoothOn(), isTrue);
  });
}
