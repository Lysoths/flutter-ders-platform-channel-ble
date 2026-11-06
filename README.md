# Flutter Ders — Platform Channel + BLE (Android)

Öğretici Flutter uygulaması: **MethodChannel** ve **EventChannel** mantığını Android BLE üzerinden gösterir.

- Uygulama: `flutter_uygulama2` (`com.flutterders.flutter_uygulama2`)
- Yerel plugin: `packages/ble_channel_kit` (Kotlin, Android-only; iOS stub)
- UI: Türkçe, Material 3, StatefulWidget (flutter_bloc yok — bilinçli sade tutum)

## Ne öğrenilir?

| Kanal | Yön | Örnek |
|---|---|---|
| **MethodChannel** | Flutter → Kotlin → cevap | `ensurePermissions`, `startScan`, `connect`, `write`, `read` |
| **EventChannel** | Kotlin → Flutter (akış) | tarama sonuçları, bağlantı durumu, gelen veri |

Channel adları:

- `com.flutterders.ble_channel_kit/methods`
- `com.flutterders.ble_channel_kit/scan`
- `com.flutterders.ble_channel_kit/connection`

## Çalıştırma

```bash
cd flutter-ders-platform-channel-ble   # veya bu klasör
flutter pub get
flutter run -d <android-cihaz>
```

Akış: **İzinleri iste → Tara → cihaz seç (veya MAC ile bağlan) → Bağlan → mesaj gönder/oku**

> **Not:** Birçok saat Classic Bluetooth kullanır; BLE GATT bağlanmayabilir (`status=147`). Ders için BLE reklamı yapan cihaz (ESP32, beacon, eşleştirme modundaki BLE kulaklık) daha uygundur. MAC bilmek adres bilmektir; BLE kapısı açık olmadan bağlanılmaz.

## Klasör yapısı

```
lib/
  main.dart
  app/theme/
  app/views/ble_ders_view.dart   # öğretici UI + canlı channel günlüğü
packages/ble_channel_kit/
  lib/                           # ince Dart API
  android/.../BleManager.kt      # tarama, GATT, hex/ASCII veri
```

## Test

```bash
flutter analyze
flutter test
cd packages/ble_channel_kit && flutter test
```

## Lisans

Öğretici / ders amaçlı örnek kod.
