import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'ble_channel_kit_method_channel.dart';
import 'src/ble_models.dart';

/// DERS 4 — Platform arayüzü / Neden böyle?
/// Testlerde mock'lanabilir; gerçek kanal [MethodChannelBleChannelKit].
abstract class BleChannelKitPlatform extends PlatformInterface {
  /// Platform arayüzü token'ı.
  BleChannelKitPlatform() : super(token: _token);

  static final Object _token = Object();

  static BleChannelKitPlatform _instance = MethodChannelBleChannelKit();

  /// Aktif platform uygulaması.
  static BleChannelKitPlatform get instance => _instance;

  /// Test veya alternatif platform kaydı.
  static set instance(BleChannelKitPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Örnek MethodChannel çağrısı (şablon + birim test).
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() henüz yok.');
  }

  /// Adaptör açık mı?
  Future<bool> isBluetoothOn() {
    throw UnimplementedError('isBluetoothOn() henüz yok.');
  }

  /// Runtime izinleri var mı?
  Future<bool> hasPermissions() {
    throw UnimplementedError('hasPermissions() henüz yok.');
  }

  /// Gerekirse sistem izin diyaloğunu açar.
  Future<bool> ensurePermissions() {
    throw UnimplementedError('ensurePermissions() henüz yok.');
  }

  /// BLE taramayı başlatır; sonuçlar [scanResults] üzerinden akar.
  Future<void> startScan() {
    throw UnimplementedError('startScan() henüz yok.');
  }

  /// Taramayı durdurur.
  Future<void> stopScan() {
    throw UnimplementedError('stopScan() henüz yok.');
  }

  /// Telefonda eşleşmiş (bonded) cihazlar.
  Future<List<BleDevice>> getBondedDevices() {
    throw UnimplementedError('getBondedDevices() henüz yok.');
  }

  /// [deviceId] (MAC) ile GATT bağlantısı kurar — tarama şart değil.
  Future<void> connect(String deviceId) {
    throw UnimplementedError('connect() henüz yok.');
  }

  /// Bağlantıyı keser.
  Future<void> disconnect() {
    throw UnimplementedError('disconnect() henüz yok.');
  }

  /// Bağlı karakteristiğe UTF-8 yazar.
  Future<void> write(
    String data, {
    String? serviceUuid,
    String? characteristicUuid,
  }) {
    throw UnimplementedError('write() henüz yok.');
  }

  /// Okuma isteği; sonuç [connectionEvents] içinde `data` olarak gelir.
  Future<void> read({String? serviceUuid, String? characteristicUuid}) {
    throw UnimplementedError('read() henüz yok.');
  }

  /// Uygulama ayarları ekranını açar.
  Future<void> openAppSettings() {
    throw UnimplementedError('openAppSettings() henüz yok.');
  }

  /// Tarama EventChannel akışı.
  Stream<BleDevice> get scanResults {
    throw UnimplementedError('scanResults henüz yok.');
  }

  /// Bağlantı / veri EventChannel akışı.
  Stream<BleConnectionEvent> get connectionEvents {
    throw UnimplementedError('connectionEvents henüz yok.');
  }
}
