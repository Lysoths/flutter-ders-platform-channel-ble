import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ble_channel_kit_platform_interface.dart';
import 'src/ble_models.dart';

/// DERS 1 — Channel adları (Dart) / Neden böyle?
/// Kotlin [BleChannelNames] ile birebir aynı olmalı.
class BleChannelKitChannels {
  /// MethodChannel adı.
  static const methods = 'com.flutterders.ble_channel_kit/methods';

  /// Tarama EventChannel adı.
  static const scan = 'com.flutterders.ble_channel_kit/scan';

  /// Bağlantı EventChannel adı.
  static const connection = 'com.flutterders.ble_channel_kit/connection';
}

/// MethodChannel + EventChannel uygulaması.
class MethodChannelBleChannelKit extends BleChannelKitPlatform {
  /// Testlerde mock'lanabilir MethodChannel.
  @visibleForTesting
  final methodChannel = const MethodChannel(BleChannelKitChannels.methods);

  final EventChannel _scanChannel =
      const EventChannel(BleChannelKitChannels.scan);
  final EventChannel _connectionChannel =
      const EventChannel(BleChannelKitChannels.connection);

  @override
  Future<String?> getPlatformVersion() async {
    return methodChannel.invokeMethod<String>('getPlatformVersion');
  }

  @override
  Future<bool> isBluetoothOn() async {
    return await methodChannel.invokeMethod<bool>('isBluetoothOn') ?? false;
  }

  @override
  Future<bool> hasPermissions() async {
    return await methodChannel.invokeMethod<bool>('hasPermissions') ?? false;
  }

  @override
  Future<bool> ensurePermissions() async {
    return await methodChannel.invokeMethod<bool>('ensurePermissions') ?? false;
  }

  @override
  Future<void> startScan() async {
    await methodChannel.invokeMethod<void>('startScan');
  }

  @override
  Future<void> stopScan() async {
    await methodChannel.invokeMethod<void>('stopScan');
  }

  @override
  Future<List<BleDevice>> getBondedDevices() async {
    final raw = await methodChannel.invokeMethod<List<dynamic>>(
      'getBondedDevices',
    );
    if (raw == null) return const [];
    return raw
        .map((e) => BleDevice.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<void> connect(String deviceId) async {
    await methodChannel.invokeMethod<void>('connect', {'deviceId': deviceId});
  }

  @override
  Future<void> disconnect() async {
    await methodChannel.invokeMethod<void>('disconnect');
  }

  @override
  Future<void> write(
    String data, {
    String? serviceUuid,
    String? characteristicUuid,
  }) async {
    await methodChannel.invokeMethod<void>('write', {
      'data': data,
      'serviceUuid': serviceUuid,
      'characteristicUuid': characteristicUuid,
    });
  }

  @override
  Future<void> read({String? serviceUuid, String? characteristicUuid}) async {
    await methodChannel.invokeMethod<void>('read', {
      'serviceUuid': serviceUuid,
      'characteristicUuid': characteristicUuid,
    });
  }

  @override
  Future<void> openAppSettings() async {
    await methodChannel.invokeMethod<void>('openAppSettings');
  }

  @override
  Stream<BleDevice> get scanResults {
    return _scanChannel.receiveBroadcastStream().map((event) {
      return BleDevice.fromMap(Map<dynamic, dynamic>.from(event as Map));
    });
  }

  @override
  Stream<BleConnectionEvent> get connectionEvents {
    return _connectionChannel.receiveBroadcastStream().map((event) {
      return BleConnectionEvent.fromMap(
        Map<dynamic, dynamic>.from(event as Map),
      );
    });
  }
}
