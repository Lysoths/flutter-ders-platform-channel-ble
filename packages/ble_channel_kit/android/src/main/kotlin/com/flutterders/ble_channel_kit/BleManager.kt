package com.flutterders.ble_channel_kit

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanRecord
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * DERS 3 — BLE işi Kotlin'de / Neden böyle?
 * Platform Channel ince bir köprüdür; tarama, GATT, bildirim native tarafta kalır.
 * Dart sadece MethodChannel/EventChannel üzerinden çağırır ve dinler.
 */
class BleManager(
    private val context: Context,
    private val onScanResult: (Map<String, Any?>) -> Unit,
    private val onConnectionEvent: (Map<String, Any?>) -> Unit,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val bluetoothManager =
        context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? get() = bluetoothManager.adapter

    private var scannerCallback: ScanCallback? = null
    private var gatt: BluetoothGatt? = null
    private var writeCharacteristic: BluetoothGattCharacteristic? = null
    private var notifyCharacteristic: BluetoothGattCharacteristic? = null
    private var pendingGapNameRead = false
    private var connectedAddress: String? = null

    /** Aynı MAC için son bilinen isim — isimsiz paket önceki adı ezmesin. */
    private val knownNames = ConcurrentHashMap<String, String>()

    companion object {
        /** Generic Access servisi — standart cihaz adı burada. */
        private val UUID_GAP = UUID.fromString("00001800-0000-1000-8000-00805f9b34fb")
        private val UUID_DEVICE_NAME =
            UUID.fromString("00002a00-0000-1000-8000-00805f9b34fb")
    }

    fun isBluetoothOn(): Boolean = adapter?.isEnabled == true

    fun hasRequiredPermissions(): Boolean {
        return requiredPermissions().all { permission ->
            context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        }
    }

    fun requiredPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.ACCESS_FINE_LOCATION,
            )
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    /** Telefonda eşleşmiş cihazlar — tarama dışı ama MAC ile bağlanılabilir. */
    @SuppressLint("MissingPermission")
    fun bondedDevices(): List<Map<String, Any?>> {
        if (!hasRequiredPermissions()) return emptyList()
        val adapter = adapter ?: return emptyList()
        return adapter.bondedDevices.orEmpty().map { device ->
            val name = device.name?.takeIf { it.isNotBlank() }
            if (name != null) knownNames[device.address] = name
            mapOf(
                "id" to device.address,
                "name" to name,
                "rssi" to 0,
                "bonded" to true,
            )
        }
    }

    @SuppressLint("MissingPermission")
    fun startScan(): String? {
        if (!hasRequiredPermissions()) return "İzinler eksik. Önce ensurePermissions çağırın."
        val adapter = adapter ?: return "Bluetooth adaptörü yok."
        if (!adapter.isEnabled) return "Bluetooth kapalı."
        val scanner = adapter.bluetoothLeScanner
            ?: return "BLE tarayıcı yok (cihaz BLE desteklemiyor olabilir)."
        stopScan()
        knownNames.clear()

        // Önce eşleşmiş cihazları listeye bas (saat çoğu zaman burada; reklam yapmaz).
        for (bonded in bondedDevices()) {
            mainHandler.post { onScanResult(bonded) }
        }

        val callback =
            object : ScanCallback() {
                override fun onScanResult(
                    callbackType: Int,
                    result: ScanResult,
                ) {
                    publishScanResult(result.device, result.scanRecord, result.rssi, bonded = false)
                }

                override fun onBatchScanResults(results: MutableList<ScanResult>) {
                    for (result in results) {
                        publishScanResult(
                            result.device,
                            result.scanRecord,
                            result.rssi,
                            bonded = false,
                        )
                    }
                }

                override fun onScanFailed(errorCode: Int) {
                    emitConnection(
                        status = "error",
                        message = "Tarama başarısız: $errorCode",
                    )
                }
            }
        scannerCallback = callback
        val settings =
            ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
                .setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
                .setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
                .setReportDelay(0)
                .build()
        scanner.startScan(null, settings, callback)
        emitConnection(
            status = "scanning",
            message =
                "BLE tarama + eşleşmiş cihazlar. " +
                    "Saat listede yoksa reklam yapmıyor olabilir — MAC ile bağlan.",
        )
        return null
    }

    @SuppressLint("MissingPermission")
    private fun publishScanResult(
        device: BluetoothDevice,
        record: ScanRecord?,
        rssi: Int,
        bonded: Boolean,
    ) {
        val address = device.address
        val advertised = resolveAdvertisedName(record)
        val cachedDeviceName = device.name?.takeIf { it.isNotBlank() }
        val resolved =
            advertised
                ?: cachedDeviceName
                ?: knownNames[address]
        if (!advertised.isNullOrBlank()) {
            knownNames[address] = advertised
        } else if (!cachedDeviceName.isNullOrBlank()) {
            knownNames[address] = cachedDeviceName
        }
        val payload =
            mapOf(
                "id" to address,
                "name" to resolved,
                "rssi" to rssi,
                "bonded" to bonded,
            )
        mainHandler.post { onScanResult(payload) }
    }

    /**
     * Reklam verisinden yerel ad: ScanRecord.deviceName + AD type 0x08/0x09 yedek parse.
     */
    private fun resolveAdvertisedName(record: ScanRecord?): String? {
        if (record == null) return null
        record.deviceName?.takeIf { it.isNotBlank() }?.let { return it }
        return parseLocalNameFromBytes(record.bytes)
    }

    /** Complete (0x09) / Shortened (0x08) Local Name — bazı OEM'lerde deviceName boş kalır. */
    private fun parseLocalNameFromBytes(bytes: ByteArray?): String? {
        if (bytes == null || bytes.isEmpty()) return null
        var index = 0
        while (index < bytes.size) {
            val length = bytes[index].toInt() and 0xFF
            if (length == 0) break
            if (index + length >= bytes.size) break
            val type = bytes[index + 1].toInt() and 0xFF
            if (type == 0x08 || type == 0x09) {
                val start = index + 2
                val end = index + 1 + length
                val name = bytes.copyOfRange(start, end).toString(Charsets.UTF_8).trim()
                if (name.isNotEmpty()) return name
            }
            index += length + 1
        }
        return null
    }

    @SuppressLint("MissingPermission")
    fun stopScan() {
        scannerCallback?.let { callback ->
            adapter?.bluetoothLeScanner?.stopScan(callback)
        }
        scannerCallback = null
        emitConnection(status = "idle", message = "Tarama durdu")
    }

    @SuppressLint("MissingPermission")
    fun connect(deviceId: String): String? {
        if (!hasRequiredPermissions()) return "İzinler eksik."
        val adapter = adapter ?: return "Bluetooth adaptörü yok."
        if (!adapter.isEnabled) return "Bluetooth kapalı."

        val normalized = normalizeMac(deviceId)
            ?: return "Geçersiz MAC: $deviceId (örn. DC:33:3D:C3:13:4F)"

        stopScan()
        disconnect(emit = false)

        val device: BluetoothDevice =
            try {
                adapter.getRemoteDevice(normalized)
            } catch (_: IllegalArgumentException) {
                return "Geçersiz cihaz adresi: $normalized"
            }

        // Tarama listesinde olmasa da bilinen MAC ile GATT denenebilir.
        emitConnection(
            status = "connecting",
            message =
                "Bağlanıyor: $normalized (tarama şart değil). " +
                    "Saat yalnızca Classic BT ise BLE GATT başarısız olabilir.",
        )
        connectedAddress = normalized
        pendingGapNameRead = false
        gatt = device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        return null
    }

    /** DC:33:… / dc-33-… / dc33… → AA:BB:CC:DD:EE:FF */
    private fun normalizeMac(raw: String): String? {
        val hex = raw.trim().uppercase().replace(Regex("[^0-9A-F]"), "")
        if (hex.length != 12) return null
        return hex.chunked(2).joinToString(":")
    }

    /** Android/OEM GATT status → ders için okunur metin. */
    private fun explainGattStatus(status: Int): String {
        val meaning =
            when (status) {
                0 -> "SUCCESS"
                8, 22 -> "bağlantı zaman aşımı / peer kayboldu"
                19 -> "karşı taraf kapattı"
                133 -> "genel GATT_ERROR (cihaz yanıt vermedi)"
                147 -> "bağlantı kurulamadı/timeout (147) — çoğu saat Classic BT veya reklam kapalı"
                else -> "bilinmeyen kod"
            }
        return "$status ($meaning)"
    }

    @SuppressLint("MissingPermission")
    fun disconnect(emit: Boolean = true) {
        gatt?.close()
        gatt = null
        writeCharacteristic = null
        notifyCharacteristic = null
        pendingGapNameRead = false
        connectedAddress = null
        if (emit) {
            emitConnection(status = "disconnected", message = "Bağlantı kesildi")
        }
    }

    @SuppressLint("MissingPermission")
    fun write(
        text: String,
        serviceUuid: String?,
        characteristicUuid: String?,
    ): String? {
        val gatt = gatt ?: return "Bağlı cihaz yok."
        val characteristic =
            resolveWriteCharacteristic(serviceUuid, characteristicUuid)
                ?: return "Yazılabilir karakteristik bulunamadı."

        // "01 0A FF" veya "010AFF" → binary; aksi halde UTF-8 metin.
        val bytes = parseWritePayload(text)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val status =
                gatt.writeCharacteristic(
                    characteristic,
                    bytes,
                    BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
                )
            if (status == BluetoothStatusCodes.SUCCESS) null else "Yazma hatası: $status"
        } else {
            @Suppress("DEPRECATION")
            characteristic.value = bytes
            @Suppress("DEPRECATION")
            characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            @Suppress("DEPRECATION")
            val ok = gatt.writeCharacteristic(characteristic)
            if (ok) null else "Yazma başarısız."
        }
    }

    @SuppressLint("MissingPermission")
    fun read(
        serviceUuid: String?,
        characteristicUuid: String?,
    ): String? {
        val gatt = gatt ?: throw IllegalStateException("Bağlı cihaz yok.")
        val characteristic =
            resolveReadCharacteristic(serviceUuid, characteristicUuid)
                ?: throw IllegalStateException("Okunabilir karakteristik bulunamadı.")
        val ok = gatt.readCharacteristic(characteristic)
        if (!ok) throw IllegalStateException("Okuma isteği gönderilemedi.")
        // Asıl değer onCharacteristicRead içinde EventChannel ile gelir.
        return null
    }

    private fun resolveWriteCharacteristic(
        serviceUuid: String?,
        characteristicUuid: String?,
    ): BluetoothGattCharacteristic? {
        writeCharacteristic?.let { cached ->
            if (serviceUuid == null && characteristicUuid == null) return cached
        }
        return findCharacteristic(serviceUuid, characteristicUuid) { char ->
            val props = char.properties
            (props and BluetoothGattCharacteristic.PROPERTY_WRITE) != 0 ||
                (props and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0
        }.also { writeCharacteristic = it }
    }

    private fun resolveReadCharacteristic(
        serviceUuid: String?,
        characteristicUuid: String?,
    ): BluetoothGattCharacteristic? {
        return findCharacteristic(serviceUuid, characteristicUuid) { char ->
            (char.properties and BluetoothGattCharacteristic.PROPERTY_READ) != 0
        } ?: notifyCharacteristic
    }

    private fun findCharacteristic(
        serviceUuid: String?,
        characteristicUuid: String?,
        predicate: (BluetoothGattCharacteristic) -> Boolean,
    ): BluetoothGattCharacteristic? {
        val services = gatt?.services ?: return null
        if (serviceUuid != null && characteristicUuid != null) {
            val service = services.firstOrNull { it.uuid == UUID.fromString(serviceUuid) }
            return service?.getCharacteristic(UUID.fromString(characteristicUuid))
        }
        for (service in services) {
            for (characteristic in service.characteristics) {
                if (predicate(characteristic)) return characteristic
            }
        }
        return null
    }

    private val gattCallback =
        object : BluetoothGattCallback() {
            @SuppressLint("MissingPermission")
            override fun onConnectionStateChange(
                gatt: BluetoothGatt,
                status: Int,
                newState: Int,
            ) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    emitConnection(
                        status = "error",
                        message = "GATT bağlanamadı: ${explainGattStatus(status)}",
                    )
                    disconnect(emit = false)
                    return
                }
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        emitConnection(status = "connected", message = "Bağlandı, servisler keşfediliyor…")
                        gatt.discoverServices()
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        emitConnection(status = "disconnected", message = "Bağlantı koptu")
                        gatt.close()
                        this@BleManager.gatt = null
                    }
                }
            }

            @SuppressLint("MissingPermission")
            override fun onServicesDiscovered(
                gatt: BluetoothGatt,
                status: Int,
            ) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    emitConnection(status = "error", message = "Servis keşfi başarısız: $status")
                    return
                }
                writeCharacteristic =
                    findCharacteristic(null, null) { char ->
                        // GAP Device Name'i yazma hedefi sanma.
                        if (char.uuid == UUID_DEVICE_NAME) return@findCharacteristic false
                        val props = char.properties
                        (props and BluetoothGattCharacteristic.PROPERTY_WRITE) != 0 ||
                            (props and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0
                    }
                notifyCharacteristic =
                    findCharacteristic(null, null) { char ->
                        if (char.uuid == UUID_DEVICE_NAME) return@findCharacteristic false
                        (char.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0
                    }

                // GATT tek işlem: önce isim oku, bitince notify aç (aşağıda).
                val gapName =
                    gatt.getService(UUID_GAP)?.getCharacteristic(UUID_DEVICE_NAME)
                val canReadName =
                    gapName != null &&
                        (gapName.properties and BluetoothGattCharacteristic.PROPERTY_READ) != 0
                if (canReadName) {
                    pendingGapNameRead = true
                    gatt.readCharacteristic(gapName)
                    emitConnection(
                        status = "ready",
                        message =
                            "Hazır. GAP isim okunuyor… Yazma=${writeCharacteristic?.uuid}",
                    )
                } else {
                    notifyCharacteristic?.let { enableNotifications(gatt, it) }
                    emitConnection(
                        status = "ready",
                        message =
                            "Hazır (reklam/GAP isim yok). Yazma=${writeCharacteristic?.uuid}, " +
                                "Bildirim=${notifyCharacteristic?.uuid}",
                    )
                }
            }

            @Deprecated("Deprecated in Java")
            @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    val value = characteristic.value ?: ByteArray(0)
                    handleCharacteristicRead(characteristic.uuid, value)
                } else {
                    onGapNameReadFailed(characteristic.uuid)
                }
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
                status: Int,
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    handleCharacteristicRead(characteristic.uuid, value)
                } else {
                    onGapNameReadFailed(characteristic.uuid)
                }
            }

            @Deprecated("Deprecated in Java")
            @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
            ) {
                emitData(characteristic.value ?: ByteArray(0))
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
            ) {
                emitData(value)
            }
        }

    @SuppressLint("MissingPermission")
    private fun enableNotifications(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
    ) {
        gatt.setCharacteristicNotification(characteristic, true)
        val cccd = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        val descriptor = characteristic.getDescriptor(cccd) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
        } else {
            @Suppress("DEPRECATION")
            descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            @Suppress("DEPRECATION")
            gatt.writeDescriptor(descriptor)
        }
    }

    @SuppressLint("MissingPermission")
    private fun onGapNameReadFailed(uuid: UUID) {
        if (!pendingGapNameRead || uuid != UUID_DEVICE_NAME) return
        pendingGapNameRead = false
        gatt?.let { g -> notifyCharacteristic?.let { enableNotifications(g, it) } }
        emitConnection(
            status = "ready",
            message = "GAP isim okunamadı; bildirimler açıldı.",
        )
    }

    @SuppressLint("MissingPermission")
    private fun handleCharacteristicRead(
        uuid: UUID,
        value: ByteArray,
    ) {
        if (pendingGapNameRead && uuid == UUID_DEVICE_NAME) {
            pendingGapNameRead = false
            val name = value.toString(Charsets.UTF_8).trim()
            if (name.isNotEmpty()) {
                connectedAddress?.let { knownNames[it] = name }
                val payload =
                    mutableMapOf<String, Any?>(
                        "status" to "deviceName",
                        "message" to "GAP cihaz adı: $name",
                        "data" to name,
                        "deviceId" to connectedAddress,
                        "name" to name,
                    )
                mainHandler.post { onConnectionEvent(payload) }
            } else {
                emitConnection(
                    status = "ready",
                    message = "GAP Device Name boş — cihaz reklamda da isim vermiyor olabilir.",
                )
            }
            // İsim okuması bitti; şimdi notify (tek GATT işlemi kuralı).
            gatt?.let { g ->
                notifyCharacteristic?.let { enableNotifications(g, it) }
            }
            return
        }
        emitData(value)
    }

    /** Hex yazımını destekle: ders sırasında binary göndermek için. */
    private fun parseWritePayload(text: String): ByteArray {
        val compact = text.trim()
        val hexOnly = compact.replace(" ", "").replace(":", "").replace("-", "")
        val looksLikeHex =
            hexOnly.length >= 2 &&
                hexOnly.length % 2 == 0 &&
                hexOnly.matches(Regex("(?i)[0-9A-F]+")) &&
                // Saf kısa kelimeleri (örn. "cafe") yanlışlıkla hex sayma; boşluk/çift bayt ipucu.
                (compact.contains(' ') ||
                    compact.contains(':') ||
                    compact.contains('-') ||
                    hexOnly.length >= 4 && compact == hexOnly)
        if (looksLikeHex) {
            return ByteArray(hexOnly.length / 2) { i ->
                hexOnly.substring(i * 2, i * 2 + 2).toInt(16).toByte()
            }
        }
        return text.toByteArray(Charsets.UTF_8)
    }

    /**
     * DERS — Binary veri / Neden böyle?
     * Ham byte'ı kör UTF-8 yapmak anlamsız karakter üretir.
     * Hex + ASCII önizleme + (mümkünse) UTF-8 birlikte gider.
     */
    private fun emitData(bytes: ByteArray) {
        val hex = bytes.joinToString(" ") { b -> "%02X".format(b) }
        val ascii =
            bytes.joinToString("") { b ->
                val c = b.toInt() and 0xFF
                if (c in 32..126) c.toChar().toString() else "."
            }
        val utf8Candidate = bytes.toString(Charsets.UTF_8)
        val isText =
            bytes.isNotEmpty() &&
                utf8Candidate.isNotEmpty() &&
                !utf8Candidate.contains('\uFFFD') &&
                bytes.all { b ->
                    val c = b.toInt() and 0xFF
                    c == 9 || c == 10 || c == 13 || c in 32..126
                }
        val summary =
            if (isText) {
                utf8Candidate
            } else {
                "$hex  |  ASCII: $ascii"
            }
        val payload =
            mutableMapOf<String, Any?>(
                "status" to "data",
                "message" to "Veri alındı (${bytes.size} bayt)",
                "data" to summary,
                "hex" to hex,
                "ascii" to ascii,
                "utf8" to if (isText) utf8Candidate else null,
                "length" to bytes.size,
                "isText" to isText,
            )
        mainHandler.post { onConnectionEvent(payload) }
    }

    private fun emitConnection(
        status: String,
        message: String?,
        data: String? = null,
    ) {
        val payload =
            mutableMapOf<String, Any?>(
                "status" to status,
                "message" to message,
            )
        if (data != null) payload["data"] = data
        mainHandler.post { onConnectionEvent(payload) }
    }
}

/** API 33+ writeCharacteristic dönüş kodları için hafif sabit. */
private object BluetoothStatusCodes {
    const val SUCCESS = 0
}
