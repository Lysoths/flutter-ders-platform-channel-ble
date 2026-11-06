import 'ble_channel_kit_platform_interface.dart';
import 'src/ble_models.dart';

export 'src/ble_models.dart';
export 'ble_channel_kit_method_channel.dart' show BleChannelKitChannels;

/// İnce Dart API — asıl BLE işi Android/Kotlin tarafında.
///
/// Örnek:
/// ```dart
/// final ble = BleChannelKit();
/// await ble.ensurePermissions();
/// ble.scanResults.listen(print);
/// await ble.startScan();
/// ```
class BleChannelKit {
  /// Platform sürümü (şablon / teşhis).
  Future<String?> getPlatformVersion() {
    return BleChannelKitPlatform.instance.getPlatformVersion();
  }

  /// Bluetooth adaptörü açık mı?
  Future<bool> isBluetoothOn() {
    return BleChannelKitPlatform.instance.isBluetoothOn();
  }

  /// Runtime BLE izinleri verilmiş mi?
  Future<bool> hasPermissions() {
    return BleChannelKitPlatform.instance.hasPermissions();
  }

  /// Eksikse sistem izin diyaloğunu gösterir; sonuç true/false.
  Future<bool> ensurePermissions() {
    return BleChannelKitPlatform.instance.ensurePermissions();
  }

  /// BLE taramayı başlatır.
  Future<void> startScan() {
    return BleChannelKitPlatform.instance.startScan();
  }

  /// Taramayı durdurur.
  Future<void> stopScan() {
    return BleChannelKitPlatform.instance.stopScan();
  }

  /// Telefonda eşleşmiş cihazlar (saat vb. tarama dışı kalabilir).
  Future<List<BleDevice>> getBondedDevices() {
    return BleChannelKitPlatform.instance.getBondedDevices();
  }

  /// [deviceId] (Android MAC) ile bağlanır — listede olmasa da olur.
  Future<void> connect(String deviceId) {
    return BleChannelKitPlatform.instance.connect(deviceId);
  }

  /// GATT bağlantısını keser.
  Future<void> disconnect() {
    return BleChannelKitPlatform.instance.disconnect();
  }

  /// Yazılabilir karakteristiğe UTF-8 metin yazar.
  Future<void> write(
    String data, {
    String? serviceUuid,
    String? characteristicUuid,
  }) {
    return BleChannelKitPlatform.instance.write(
      data,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );
  }

  /// Okuma isteği gönderir; veri [connectionEvents] ile gelir.
  Future<void> read({String? serviceUuid, String? characteristicUuid}) {
    return BleChannelKitPlatform.instance.read(
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );
  }

  /// Uygulama ayarlarına gider (izin reddedilirse).
  Future<void> openAppSettings() {
    return BleChannelKitPlatform.instance.openAppSettings();
  }

  /// Tarama sonuçları (EventChannel).
  Stream<BleDevice> get scanResults =>
      BleChannelKitPlatform.instance.scanResults;

  /// Bağlantı durumu ve gelen veri (EventChannel).
  Stream<BleConnectionEvent> get connectionEvents =>
      BleChannelKitPlatform.instance.connectionEvents;
}
