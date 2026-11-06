import 'dart:async';

import 'package:ble_channel_kit/ble_channel_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// DERS 5 — Ana ekran / Neden böyle?
/// Amaç: Platform Channel’ı GÖREREK anlamak.
/// MethodChannel = istek/cevap (Flutter → Kotlin → cevap).
/// EventChannel = sürekli akış (Kotlin → Flutter).
class BleDersView extends StatefulWidget {
  /// Ana BLE ders ekranı.
  const BleDersView({super.key, this.ble});

  /// Testlerde enjekte edilebilir API.
  final BleChannelKit? ble;

  @override
  State<BleDersView> createState() => _BleDersViewState();
}

enum _ChannelKind { method, event }

class _ChannelLogEntry {
  _ChannelLogEntry({
    required this.kind,
    required this.direction,
    required this.label,
    required this.detail,
  }) : time = TimeOfDay.now();

  final _ChannelKind kind;
  /// "→" Flutter→native, "←" native→Flutter, "↔" gidiş-dönüş.
  final String direction;
  final String label;
  final String detail;
  final TimeOfDay time;
}

class _BleDersViewState extends State<BleDersView> {
  late final BleChannelKit _ble = widget.ble ?? BleChannelKit();

  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _filterController = TextEditingController();
  final Map<String, BleDevice> _devices = {};
  final List<_ChannelLogEntry> _log = [];
  String _filterQuery = '';

  StreamSubscription<BleDevice>? _scanSub;
  StreamSubscription<BleConnectionEvent>? _connSub;

  bool? _bluetoothOn;
  bool _scanning = false;
  String _connectionStatus = 'idle';
  String _statusMessage = 'Adım 1: İzinleri iste.';
  String _receivedData = '—';
  BleConnectionEvent? _lastPayload;
  String? _selectedDeviceId;
  String? _lastError;
  _ChannelKind? _lastKind;
  int _scanEventCount = 0;

  static const _methodChannelName =
      'com.flutterders.ble_channel_kit/methods';
  static const _scanChannelName = 'com.flutterders.ble_channel_kit/scan';
  static const _connChannelName =
      'com.flutterders.ble_channel_kit/connection';

  @override
  void initState() {
    super.initState();
    _scanSub = _ble.scanResults.listen(_onScanDevice, onError: _onStreamError);
    _connSub = _ble.connectionEvents.listen(
      _onConnectionEvent,
      onError: _onStreamError,
    );
    _logChannel(
      kind: _ChannelKind.event,
      direction: '←',
      label: 'EventChannel dinleniyor',
      detail: 'scan + connection stream açıldı (initState)',
    );
    unawaited(_refreshBluetoothState());
  }

  @override
  void dispose() {
    unawaited(_ble.stopScan());
    _scanSub?.cancel();
    _connSub?.cancel();
    _messageController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  /// MAC/isim filtresi — iki nokta ve tire yok sayılır, büyük/küçük harf duyarsız.
  List<BleDevice> _filteredDevices(List<BleDevice> all) {
    final q = _filterQuery.trim();
    if (q.isEmpty) return all;
    final qLower = q.toLowerCase();
    final qMac = qLower.replaceAll(RegExp(r'[:\-\s]'), '');
    return all.where((d) {
      final name = (d.name ?? '').toLowerCase();
      final mac = d.id.toLowerCase();
      final macCompact = mac.replaceAll(RegExp(r'[:\-\s]'), '');
      return name.contains(qLower) ||
          mac.contains(qLower) ||
          (qMac.isNotEmpty && macCompact.contains(qMac));
    }).toList();
  }

  void _logChannel({
    required _ChannelKind kind,
    required String direction,
    required String label,
    required String detail,
  }) {
    setState(() {
      _lastKind = kind;
      _log.insert(
        0,
        _ChannelLogEntry(
          kind: kind,
          direction: direction,
          label: label,
          detail: detail,
        ),
      );
      if (_log.length > 40) {
        _log.removeRange(40, _log.length);
      }
    });
  }

  Future<T?> _invokeMethod<T>(
    String method,
    Future<T> Function() call, {
    String? detail,
  }) async {
    _logChannel(
      kind: _ChannelKind.method,
      direction: '→',
      label: method,
      detail: detail ?? 'MethodChannel isteği gönderildi',
    );
    try {
      final result = await call();
      _logChannel(
        kind: _ChannelKind.method,
        direction: '←',
        label: '$method sonucu',
        detail: result == null ? 'void / null (başarılı)' : '$result',
      );
      setState(() => _lastError = null);
      return result;
    } on PlatformException catch (e) {
      _logChannel(
        kind: _ChannelKind.method,
        direction: '←',
        label: '$method hata',
        detail: '${e.code}: ${e.message}',
      );
      setState(() => _lastError = e.message ?? e.code);
      return null;
    }
  }

  void _onScanDevice(BleDevice device) {
    setState(() {
      final existing = _devices[device.id];
      final hasNewName =
          device.name != null && device.name!.trim().isNotEmpty;
      _devices[device.id] = BleDevice(
        id: device.id,
        name: hasNewName ? device.name : existing?.name,
        rssi: device.rssi != 0 ? device.rssi : (existing?.rssi ?? 0),
        bonded: device.bonded || (existing?.bonded ?? false),
      );
      _scanEventCount++;
      _lastKind = _ChannelKind.event;
      if (_scanEventCount == 1 || _scanEventCount % 5 == 0) {
        _log.insert(
          0,
          _ChannelLogEntry(
            kind: _ChannelKind.event,
            direction: '←',
            label: 'scan event #$_scanEventCount',
            detail:
                '${device.displayName}  rssi=${device.rssi}'
                '${device.bonded ? '  [eşleşmiş]' : ''}',
          ),
        );
        if (_log.length > 40) {
          _log.removeRange(40, _log.length);
        }
      }
    });
  }

  void _onConnectionEvent(BleConnectionEvent event) {
    setState(() {
      _connectionStatus = event.status;
      if (event.message != null) _statusMessage = event.message!;
      if (event.status == 'data') {
        _lastPayload = event;
        _receivedData = event.readablePayload;
      } else if (event.status == 'deviceName') {
        final id = event.deviceId;
        final name = event.name ?? event.data;
        if (id != null && name != null && name.trim().isNotEmpty) {
          final existing = _devices[id];
          _devices[id] = BleDevice(
            id: id,
            name: name,
            rssi: existing?.rssi ?? 0,
            bonded: existing?.bonded ?? false,
          );
        }
      } else if (event.data != null && event.status != 'data') {
        // status mesajları — hex paneliyle karıştırma
      }
      _scanning = event.status == 'scanning';
      _lastKind = _ChannelKind.event;
      _log.insert(
        0,
        _ChannelLogEntry(
          kind: _ChannelKind.event,
          direction: '←',
          label: 'connection: ${event.status}',
          detail: switch (event.status) {
            'data' => event.hex ?? event.data ?? '—',
            'deviceName' => 'İsim: ${event.name ?? event.data}',
            _ => event.data ?? event.message ?? '—',
          },
        ),
      );
      if (_log.length > 40) {
        _log.removeRange(40, _log.length);
      }
    });
  }

  void _onStreamError(Object error) {
    setState(() => _lastError = error.toString());
    _logChannel(
      kind: _ChannelKind.event,
      direction: '←',
      label: 'stream hata',
      detail: '$error',
    );
  }

  Future<void> _refreshBluetoothState() async {
    final on = await _invokeMethod<bool>(
      'isBluetoothOn',
      () => _ble.isBluetoothOn(),
      detail: 'Adaptör açık mı? (bool cevap)',
    );
    if (on != null) {
      setState(() {
        _bluetoothOn = on;
        _statusMessage = on
            ? 'Bluetooth açık. Adım 1 veya 2’ye geç.'
            : 'Bluetooth kapalı — önce sistemden aç.';
      });
    }
  }

  Future<void> _ensurePermissions() async {
    final ok = await _invokeMethod<bool>(
      'ensurePermissions',
      () => _ble.ensurePermissions(),
      detail: 'Runtime izin diyaloğu (Activity)',
    );
    if (ok != null) {
      setState(() {
        _statusMessage = ok
            ? 'İzin OK. Adım 2: Tara.'
            : 'İzin reddedildi — Ayarlar gerekebilir.';
      });
    }
  }

  Future<void> _startScan() async {
    setState(() {
      _devices.clear();
      _scanEventCount = 0;
      _lastError = null;
      _statusMessage = 'Tarama… sonuçlar EventChannel/scan ile gelecek.';
    });
    await _invokeMethod<void>(
      'startScan',
      () => _ble.startScan(),
      detail: 'Kotlin BLE scanner başlar; cevap void, liste EVENT ile gelir',
    );
    setState(() => _scanning = true);
  }

  Future<void> _stopScan() async {
    await _invokeMethod<void>(
      'stopScan',
      () => _ble.stopScan(),
      detail: 'Taramayı durdur',
    );
    setState(() {
      _scanning = false;
      _statusMessage = 'Tarama durdu. Cihaz seç → Bağlan.';
    });
  }

  String? _normalizeMacInput(String raw) {
    final hex = raw.trim().toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    if (hex.length != 12) return null;
    final parts = <String>[];
    for (var i = 0; i < 12; i += 2) {
      parts.add(hex.substring(i, i + 2));
    }
    return parts.join(':');
  }

  Future<void> _connect() async {
    final id = _selectedDeviceId;
    if (id == null) {
      setState(() => _statusMessage = 'Önce listeden cihaz seç veya MAC ile bağlan.');
      return;
    }
    await _invokeMethod<void>(
      'connect',
      () => _ble.connect(id),
      detail: 'deviceId=$id — durum EventChannel/connection ile gelir',
    );
  }

  /// Listede olmasa bile bilinen MAC ile GATT dene (saat senaryosu).
  Future<void> _connectByMac() async {
    final mac = _normalizeMacInput(_filterQuery);
    if (mac == null) {
      setState(() {
        _statusMessage =
            'Filtreye geçerli MAC yaz: DC:33:3D:C3:13:4F (veya dc333dc3134f)';
      });
      return;
    }
    setState(() {
      _selectedDeviceId = mac;
      _devices.putIfAbsent(
        mac,
        () => BleDevice(id: mac, name: 'MAC ile hedef', rssi: 0),
      );
      _statusMessage = 'MAC ile bağlanılıyor: $mac';
    });
    await _invokeMethod<void>(
      'connect',
      () => _ble.connect(mac),
      detail: 'Doğrudan MAC=$mac (tarama şart değil)',
    );
  }

  Future<void> _disconnect() async {
    await _invokeMethod<void>(
      'disconnect',
      () => _ble.disconnect(),
      detail: 'GATT kapat',
    );
  }

  Future<void> _write() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      setState(() => _statusMessage = 'Mesaj yaz, sonra Gönder.');
      return;
    }
    await _invokeMethod<void>(
      'write',
      () => _ble.write(text),
      detail: 'UTF-8: "$text"',
    );
  }

  Future<void> _read() async {
    await _invokeMethod<void>(
      'read',
      () => _ble.read(),
      detail: 'İstek MethodChannel; değer EVENT status=data ile gelir',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allDevices = _devices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    final devices = _filteredDevices(allDevices);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Platform Channel Dersi'),
            Text(
              'MethodChannel + EventChannel + BLE',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _BridgeBanner(
            methodActive: _lastKind == _ChannelKind.method,
            eventActive: _lastKind == _ChannelKind.event,
            methodName: _methodChannelName,
            scanName: _scanChannelName,
            connName: _connChannelName,
          ),
          const SizedBox(height: 12),
          _IdeaCard(
            title: 'Ne farkı var?',
            bullets: const [
              'MethodChannel = soru-cevap. Butona bas → Kotlin çalışır → tek cevap.',
              'EventChannel = canlı yayın. Kotlin istediği kadar veri yollar; Dart dinler.',
              'MAC (AA:BB:…) = adres. Hex panel = mesaj baytları. İkisi de “isim” değil.',
              'Cihaz adı: reklam Local Name veya bağlanınca GAP 0x2A00.',
            ],
          ),
          const SizedBox(height: 16),
          _SectionHeader(
            step: '1',
            title: 'Hazırlık',
            subtitle: 'Hepsi MethodChannel (→ istek, ← cevap)',
            tint: scheme.primary,
          ),
          const SizedBox(height: 8),
          _StatusChips(
            bluetoothOn: _bluetoothOn,
            connectionStatus: _connectionStatus,
            scanning: _scanning,
            deviceCount: devices.length,
          ),
          const SizedBox(height: 8),
          Text(_statusMessage, style: Theme.of(context).textTheme.bodyMedium),
          if (_lastError != null) ...[
            const SizedBox(height: 4),
            Text(
              'Hata: $_lastError',
              style: TextStyle(color: scheme.error),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChannelButton(
                key: const Key('bleView_permissions'),
                kind: _ChannelKind.method,
                methodLabel: 'ensurePermissions',
                onPressed: _ensurePermissions,
                child: const Text('1 · İzinleri iste'),
              ),
              _ChannelButton(
                key: const Key('bleView_refreshBt'),
                kind: _ChannelKind.method,
                methodLabel: 'isBluetoothOn',
                outlined: true,
                onPressed: _refreshBluetoothState,
                child: const Text('BT durumu?'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionHeader(
            step: '2',
            title: 'Tara',
            subtitle:
                'startScan = Method · cihaz listesi = EventChannel/scan (←)',
            tint: scheme.tertiary,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChannelButton(
                key: const Key('bleView_scan'),
                kind: _ChannelKind.method,
                methodLabel: 'startScan',
                onPressed: _scanning ? null : _startScan,
                child: const Text('2 · Tara'),
              ),
              _ChannelButton(
                key: const Key('bleView_stopScan'),
                kind: _ChannelKind.method,
                methodLabel: 'stopScan',
                outlined: true,
                onPressed: _scanning ? _stopScan : null,
                child: const Text('Durdur'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'EventChannel/scan → $_scanEventCount olay  ·  '
            '${allDevices.length} cihaz'
            '${_filterQuery.trim().isEmpty ? '' : ' · filtre: ${devices.length}'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'Liste satırındaki AA:BB:… cihaz ADI değil, MAC adresidir. '
            'İsim yoksa cihaz reklamda Local Name göndermiyordur. '
            'Bağlanınca GAP Device Name (0x2A00) okumayı deneriz. '
            'Alttaki Hex ise isim değil, gelen paket baytlarıdır.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('bleView_filter'),
            controller: _filterController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Filtre / bilinen MAC',
              hintText: 'DC:33:3D:C3:13:4F',
              helperText:
                  'Saat listede yoksa normal: bağlıyken reklam yapmaz. '
                  'MAC yaz → “MAC ile bağlan”. İzinleri yeniden iste (konum).',
              prefixIcon: const Icon(Icons.filter_alt_outlined),
              suffixIcon: _filterQuery.isEmpty
                  ? null
                  : IconButton(
                      key: const Key('bleView_filterClear'),
                      tooltip: 'Filtreyi temizle',
                      onPressed: () {
                        _filterController.clear();
                        setState(() => _filterQuery = '');
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onChanged: (value) => setState(() => _filterQuery = value),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChannelButton(
                key: const Key('bleView_connectMac'),
                kind: _ChannelKind.method,
                methodLabel: 'connect(mac)',
                onPressed: _connectByMac,
                child: const Text('MAC ile bağlan'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (allDevices.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Henüz cihaz yok.\n'
                'Tara’ya bas; gelen her cihaz aslında bir EventChannel olayı.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            )
          else if (devices.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Filtreye uyan cihaz yok (“$_filterQuery”).\n'
                'İsim parçası veya MAC (AA:BB / aabb) dene.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            )
          else
            ...devices.map((device) {
              final selected = device.id == _selectedDeviceId;
              final named =
                  device.name != null && device.name!.trim().isNotEmpty;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: selected
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    key: Key('bleView_device_${device.id}'),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: Icon(
                      selected
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth_searching,
                    ),
                    title: Text(
                      named
                          ? '${device.bonded ? '🔗 ' : ''}${device.name!}'
                          : '${device.bonded ? '🔗 ' : ''}İsimsiz cihaz',
                    ),
                    subtitle: Text(
                      [
                        'MAC ${device.id}',
                        if (device.bonded) 'eşleşmiş',
                        if (device.rssi != 0) 'RSSI ${device.rssi}',
                        if (!named) 'isim yok',
                      ].join('  ·  '),
                    ),
                    trailing: selected
                        ? const Icon(Icons.check_circle)
                        : const Icon(Icons.touch_app_outlined),
                    onTap: () => setState(() {
                      _selectedDeviceId = device.id;
                      _statusMessage =
                          'Seçildi: ${named ? device.name! : device.id}. Adım 3: Bağlan.';
                    }),
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),
          _SectionHeader(
            step: '3',
            title: 'Bağlan',
            subtitle:
                'connect/disconnect = Method · durum = EventChannel/connection',
            tint: scheme.secondary,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChannelButton(
                key: const Key('bleView_connect'),
                kind: _ChannelKind.method,
                methodLabel: 'connect',
                onPressed: _connect,
                child: const Text('3 · Bağlan'),
              ),
              _ChannelButton(
                key: const Key('bleView_disconnect'),
                kind: _ChannelKind.method,
                methodLabel: 'disconnect',
                outlined: true,
                onPressed: _disconnect,
                child: const Text('Kes'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionHeader(
            step: '4',
            title: 'Mesaj yaz / oku',
            subtitle:
                'write/read = Method · gelen veri = Event (status=data)',
            tint: scheme.primary,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('bleView_messageField'),
            controller: _messageController,
            decoration: const InputDecoration(
              labelText: 'Gönder (metin veya hex)',
              hintText: 'merhaba  veya  01 0A FF',
              helperText: 'Hex: "01 0A FF" / "010AFF" → binary yazılır',
              prefixIcon: Icon(Icons.outgoing_mail),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChannelButton(
                key: const Key('bleView_write'),
                kind: _ChannelKind.method,
                methodLabel: 'write',
                onPressed: _write,
                child: const Text('4 · Gönder'),
              ),
              _ChannelButton(
                key: const Key('bleView_read'),
                kind: _ChannelKind.method,
                methodLabel: 'read',
                outlined: true,
                onPressed: _read,
                child: const Text('Oku'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _DataPanel(
            label: 'Alınan veri (EventChannel)',
            value: _receivedData,
            payload: _lastPayload,
          ),
          const SizedBox(height: 20),
          _SectionHeader(
            step: '●',
            title: 'Canlı channel günlüğü',
            subtitle: 'Her dokunuşta köprüde ne olduğunu burada gör',
            tint: scheme.outline,
          ),
          const SizedBox(height: 8),
          _ChannelLogPanel(entries: _log),
        ],
      ),
    );
  }
}

// ——— Öğretici UI parçaları ———

class _BridgeBanner extends StatelessWidget {
  const _BridgeBanner({
    required this.methodActive,
    required this.eventActive,
    required this.methodName,
    required this.scanName,
    required this.connName,
  });

  final bool methodActive;
  final bool eventActive;
  final String methodName;
  final String scanName;
  final String connName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.9),
            scheme.tertiaryContainer.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _BridgePill(
                  title: 'Flutter\n(Dart)',
                  emphasize: methodActive || eventActive,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  children: [
                    Text('→ Method', style: TextStyle(fontSize: 11)),
                    Icon(Icons.compare_arrows, size: 28),
                    Text('← Event', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
              Expanded(
                child: _BridgePill(
                  title: 'Android\n(Kotlin)',
                  emphasize: methodActive || eventActive,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ChannelNameChip(
            active: methodActive,
            color: scheme.primary,
            title: 'MethodChannel',
            name: methodName,
          ),
          const SizedBox(height: 6),
          _ChannelNameChip(
            active: eventActive,
            color: scheme.tertiary,
            title: 'EventChannel',
            name: '$scanName\n$connName',
          ),
        ],
      ),
    );
  }
}

class _BridgePill extends StatelessWidget {
  const _BridgePill({required this.title, required this.emphasize});

  final String title;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(
              alpha: emphasize ? 1 : 0.7,
            ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: emphasize
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
          width: emphasize ? 2 : 1,
        ),
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

class _ChannelNameChip extends StatelessWidget {
  const _ChannelNameChip({
    required this.active,
    required this.color,
    required this.title,
    required this.name,
  });

  final bool active;
  final Color color;
  final String title;
  final String name;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? 0.22 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: active ? 0.8 : 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            active ? '● $title (şimdi aktif)' : title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          Text(
            name,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
          ),
        ],
      ),
    );
  }
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({required this.title, required this.bullets});

  final String title;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: Theme.of(context).textTheme.bodyMedium),
                  Expanded(child: Text(b)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.tint,
  });

  final String step;
  final String title;
  final String subtitle;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: tint,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          child: Text(
            step,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({
    required this.bluetoothOn,
    required this.connectionStatus,
    required this.scanning,
    required this.deviceCount,
  });

  final bool? bluetoothOn;
  final String connectionStatus;
  final bool scanning;
  final int deviceCount;

  @override
  Widget build(BuildContext context) {
    final bt = switch (bluetoothOn) {
      true => 'BT: açık',
      false => 'BT: kapalı',
      null => 'BT: ?',
    };
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        Chip(label: Text(bt), visualDensity: VisualDensity.compact),
        Chip(
          label: Text('durum: $connectionStatus'),
          visualDensity: VisualDensity.compact,
        ),
        Chip(
          label: Text(scanning ? 'taranıyor' : 'tarama kapalı'),
          visualDensity: VisualDensity.compact,
        ),
        Chip(
          label: Text('cihaz: $deviceCount'),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _ChannelButton extends StatelessWidget {
  const _ChannelButton({
    super.key,
    required this.kind,
    required this.methodLabel,
    required this.onPressed,
    required this.child,
    this.outlined = false,
  });

  final _ChannelKind kind;
  final String methodLabel;
  final VoidCallback? onPressed;
  final Widget child;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color =
        kind == _ChannelKind.method ? scheme.primary : scheme.tertiary;
    final button = outlined
        ? OutlinedButton(
            onPressed: onPressed,
            child: child,
          )
        : FilledButton(
            onPressed: onPressed,
            child: child,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        button,
        const SizedBox(height: 2),
        Text(
          'MethodChannel · $methodLabel()',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontFamily: 'monospace',
                fontSize: 10,
              ),
        ),
      ],
    );
  }
}

class _DataPanel extends StatelessWidget {
  const _DataPanel({
    required this.label,
    required this.value,
    this.payload,
  });

  final String label;
  final String value;
  final BleConnectionEvent? payload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = payload;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: scheme.tertiary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          Text(
            'Bu panel cihaz adı değil; karakteristikten gelen veri paketidir.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 6),
          if (p?.hex != null) ...[
            _PayloadRow(
              title: 'Hex (paket içeriği)',
              body: p!.hex!,
              hint: 'Ham bayt — MAC/isim değil',
            ),
            const SizedBox(height: 8),
            _PayloadRow(
              title: 'ASCII',
              body: p.ascii ?? '—',
              hint: 'Yazdırılamayanlar "."',
            ),
            if (p.isText && p.utf8 != null) ...[
              const SizedBox(height: 8),
              _PayloadRow(
                title: 'Metin (UTF-8)',
                body: p.utf8!,
                hint: 'Sadece güvenli metinse gösterilir',
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'Bu paket binary. Kör UTF-8 yerine hex/ASCII kullanıyoruz.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (p.length != null) ...[
              const SizedBox(height: 6),
              Text(
                '${p.length} bayt',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ] else
            Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _PayloadRow extends StatelessWidget {
  const _PayloadRow({
    required this.title,
    required this.body,
    required this.hint,
  });

  final String title;
  final String body;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        SelectableText(
          body,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontFamily: 'monospace',
              ),
        ),
        Text(
          hint,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _ChannelLogPanel extends StatelessWidget {
  const _ChannelLogPanel({required this.entries});

  final List<_ChannelLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (entries.isEmpty) {
      return Text(
        'Henüz log yok — bir butona bas.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        shrinkWrap: true,
        itemCount: entries.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: scheme.outlineVariant,
        ),
        itemBuilder: (context, index) {
          final e = entries[index];
          final color = e.kind == _ChannelKind.method
              ? scheme.primary
              : scheme.tertiary;
          final kindTag =
              e.kind == _ChannelKind.method ? 'METHOD' : 'EVENT';
          final clock =
              '${e.time.hour.toString().padLeft(2, '0')}:${e.time.minute.toString().padLeft(2, '0')}';
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    '$clock\n${e.direction}',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '[$kindTag] ${e.label}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: color,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        e.detail,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
