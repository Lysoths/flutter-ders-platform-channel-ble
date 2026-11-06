import 'dart:async';

import 'package:ble_channel_kit/ble_channel_kit.dart';
import 'package:ble_channel_kit/ble_channel_kit_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_uygulama2/app/views/ble_ders_view.dart';

class _FakeBlePlatform extends BleChannelKitPlatform {
  final scanController = StreamController<BleDevice>.broadcast();
  final connController = StreamController<BleConnectionEvent>.broadcast();

  @override
  Future<String?> getPlatformVersion() async => 'test';

  @override
  Future<bool> isBluetoothOn() async => true;

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<bool> ensurePermissions() async => true;

  @override
  Future<void> startScan() async {
    scanController.add(
      const BleDevice(id: 'AA:BB:CC:DD:EE:FF', name: 'Demo', rssi: -50),
    );
    connController.add(
      const BleConnectionEvent(status: 'scanning', message: 'Tarama'),
    );
  }

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
  Stream<BleDevice> get scanResults => scanController.stream;

  @override
  Stream<BleConnectionEvent> get connectionEvents => connController.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('BLE ders ekranı ve Tara tuşu', (tester) async {
    final fake = _FakeBlePlatform();
    BleChannelKitPlatform.instance = fake;

    await tester.pumpWidget(
      const MaterialApp(
        home: BleDersView(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Platform Channel Dersi'), findsOneWidget);
    expect(fake.scanController.hasListener, isTrue);

    final scan = find.byKey(const Key('bleView_scan'), skipOffstage: false);
    await tester.ensureVisible(scan);
    await tester.pumpAndSettle();
    await tester.tap(scan);
    await tester.pumpAndSettle();

    final demo = find.text('Demo', skipOffstage: false);
    await tester.ensureVisible(demo);
    await tester.pumpAndSettle();
    expect(demo, findsOneWidget);

    final filter = find.byKey(const Key('bleView_filter'), skipOffstage: false);
    await tester.ensureVisible(filter);
    await tester.enterText(filter, 'zz:zz');
    await tester.pumpAndSettle();
    expect(find.textContaining('Filtreye uyan cihaz yok'), findsOneWidget);

    await tester.enterText(filter, 'Demo');
    await tester.pumpAndSettle();
    expect(find.text('Demo'), findsWidgets);
  });
}
