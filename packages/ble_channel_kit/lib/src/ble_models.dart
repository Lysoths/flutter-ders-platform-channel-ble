// DERS 4 — Dart modelleri / Neden böyle?
// Native Map payload'unu tip güvenli sınıflara çeviririz; UI temiz kalır.

/// Tarama sırasında bulunan BLE cihazı.
class BleDevice {
  /// MAC adresi (Android'de cihaz kimliği).
  final String id;

  /// Reklam adı; yoksa null olabilir.
  final String? name;

  /// Sinyal gücü (dBm). Eşleşmiş (bonded) için 0 olabilir.
  final int rssi;

  /// Telefonda önceden eşleşmiş mi? (saat çoğu zaman burada)
  final bool bonded;

  const BleDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.bonded = false,
  });

  /// EventChannel Map → model.
  factory BleDevice.fromMap(Map<dynamic, dynamic> map) {
    return BleDevice(
      id: map['id'] as String,
      name: map['name'] as String?,
      rssi: (map['rssi'] as num?)?.toInt() ?? 0,
      bonded: map['bonded'] as bool? ?? false,
    );
  }

  /// Liste satırında gösterim.
  String get displayName =>
      (name == null || name!.trim().isEmpty) ? 'İsimsiz ($id)' : name!;

  @override
  String toString() => 'BleDevice(id: $id, name: $name, rssi: $rssi)';
}

/// Bağlantı / bildirim EventChannel olayları.
class BleConnectionEvent {
  /// scanning | idle | connecting | connected | ready | disconnected | data | deviceName | error
  final String status;

  /// İnsan okunur Türkçe mesaj (öğretici).
  final String? message;

  /// Kısa özet (metinse UTF-8, değilse hex + ASCII).
  final String? data;

  /// Boşlukla ayrılmış hex: `48 65 6C 6C 6F` — bu CİHAZ ADI değil, paket içeriği.
  final String? hex;

  /// Yazdırılamayan baytlar `.` olan ASCII önizleme.
  final String? ascii;

  /// Sadece gerçekten metinse dolu.
  final String? utf8;

  /// Bayt uzunluğu.
  final int? length;

  /// İçerik güvenli metin mi?
  final bool isText;

  /// GAP/deviceName olayında MAC.
  final String? deviceId;

  /// GAP Device Name karakteristikinden okunan ad.
  final String? name;

  const BleConnectionEvent({
    required this.status,
    this.message,
    this.data,
    this.hex,
    this.ascii,
    this.utf8,
    this.length,
    this.isText = false,
    this.deviceId,
    this.name,
  });

  factory BleConnectionEvent.fromMap(Map<dynamic, dynamic> map) {
    return BleConnectionEvent(
      status: map['status'] as String? ?? 'unknown',
      message: map['message'] as String?,
      data: map['data'] as String?,
      hex: map['hex'] as String?,
      ascii: map['ascii'] as String?,
      utf8: map['utf8'] as String?,
      length: (map['length'] as num?)?.toInt(),
      isText: map['isText'] as bool? ?? false,
      deviceId: map['deviceId'] as String?,
      name: map['name'] as String?,
    );
  }

  /// UI için çok satırlı okunabilir özet.
  String get readablePayload {
    if (status != 'data' && hex == null && data == null) {
      return message ?? '—';
    }
    final parts = <String>[];
    if (length != null) parts.add('Uzunluk: $length bayt');
    if (hex != null && hex!.isNotEmpty) parts.add('Hex: $hex');
    if (ascii != null && ascii!.isNotEmpty) parts.add('ASCII: $ascii');
    if (isText && utf8 != null && utf8!.isNotEmpty) {
      parts.add('Metin: $utf8');
    } else if (!isText) {
      parts.add('Tür: binary (kör UTF-8 gösterilmedi)');
    }
    if (parts.isEmpty) return data ?? message ?? '—';
    return parts.join('\n');
  }

  @override
  String toString() =>
      'BleConnectionEvent(status: $status, message: $message, data: $data, hex: $hex)';
}
