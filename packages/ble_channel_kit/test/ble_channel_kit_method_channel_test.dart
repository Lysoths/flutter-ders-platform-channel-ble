import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ble_channel_kit/ble_channel_kit_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelBleChannelKit();
  const channel = MethodChannel(BleChannelKitChannels.methods);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'getPlatformVersion':
          return '42';
        case 'isBluetoothOn':
          return true;
        case 'hasPermissions':
          return true;
        case 'ensurePermissions':
          return true;
        case 'startScan':
        case 'stopScan':
        case 'connect':
        case 'disconnect':
        case 'write':
        case 'read':
        case 'openAppSettings':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('isBluetoothOn', () async {
    expect(await platform.isBluetoothOn(), isTrue);
  });

  test('startScan / connect / write', () async {
    await platform.startScan();
    await platform.connect('AA:BB:CC:DD:EE:FF');
    await platform.write('merhaba');
  });
}
