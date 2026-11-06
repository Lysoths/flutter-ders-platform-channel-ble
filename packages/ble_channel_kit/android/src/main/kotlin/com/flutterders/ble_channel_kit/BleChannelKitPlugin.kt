package com.flutterders.ble_channel_kit

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * DERS 1 — Platform Channel köprüsü / Neden böyle?
 * MethodChannel: Flutter → native (istek/cevap).
 * EventChannel: native → Flutter (sürekli akış: tarama + bağlantı).
 */
class BleChannelKitPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var methodChannel: MethodChannel
    private lateinit var scanEventChannel: EventChannel
    private lateinit var connectionEventChannel: EventChannel

    private var activity: Activity? = null
    private var bleManager: BleManager? = null
    private var pendingPermissionResult: Result? = null

    private var scanEvents: EventChannel.EventSink? = null
    private var connectionEvents: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, BleChannelNames.METHOD)
        methodChannel.setMethodCallHandler(this)

        scanEventChannel = EventChannel(binding.binaryMessenger, BleChannelNames.SCAN_EVENTS)
        scanEventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?,
                ) {
                    scanEvents = events
                }

                override fun onCancel(arguments: Any?) {
                    scanEvents = null
                }
            },
        )

        connectionEventChannel =
            EventChannel(binding.binaryMessenger, BleChannelNames.CONNECTION_EVENTS)
        connectionEventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?,
                ) {
                    connectionEvents = events
                }

                override fun onCancel(arguments: Any?) {
                    connectionEvents = null
                }
            },
        )

        bleManager =
            BleManager(
                context = binding.applicationContext,
                onScanResult = { payload -> scanEvents?.success(payload) },
                onConnectionEvent = { payload -> connectionEvents?.success(payload) },
            )
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        // Basit sürüm sorgusu motor bağlaması olmadan da çalışsın (birim testi).
        if (call.method == "getPlatformVersion") {
            result.success("Android ${android.os.Build.VERSION.RELEASE}")
            return
        }

        val manager = bleManager
        if (manager == null) {
            result.error("NO_ENGINE", "Plugin henüz bağlı değil.", null)
            return
        }

        when (call.method) {
            "isBluetoothOn" -> {
                result.success(manager.isBluetoothOn())
            }
            "ensurePermissions" -> {
                ensurePermissions(manager, result)
            }
            "hasPermissions" -> {
                result.success(manager.hasRequiredPermissions())
            }
            "startScan" -> {
                val error = manager.startScan()
                if (error == null) result.success(null) else result.error("SCAN", error, null)
            }
            "stopScan" -> {
                manager.stopScan()
                result.success(null)
            }
            "getBondedDevices" -> {
                result.success(manager.bondedDevices())
            }
            "connect" -> {
                val deviceId = call.argument<String>("deviceId")
                if (deviceId.isNullOrBlank()) {
                    result.error("ARG", "deviceId gerekli.", null)
                    return
                }
                val error = manager.connect(deviceId)
                if (error == null) result.success(null) else result.error("CONNECT", error, null)
            }
            "disconnect" -> {
                manager.disconnect()
                result.success(null)
            }
            "write" -> {
                val data = call.argument<String>("data")
                if (data == null) {
                    result.error("ARG", "data gerekli.", null)
                    return
                }
                val error =
                    manager.write(
                        text = data,
                        serviceUuid = call.argument("serviceUuid"),
                        characteristicUuid = call.argument("characteristicUuid"),
                    )
                if (error == null) result.success(null) else result.error("WRITE", error, null)
            }
            "read" -> {
                try {
                    manager.read(
                        serviceUuid = call.argument("serviceUuid"),
                        characteristicUuid = call.argument("characteristicUuid"),
                    )
                    result.success(null)
                } catch (e: IllegalStateException) {
                    result.error("READ", e.message, null)
                }
            }
            "openAppSettings" -> {
                val act = activity
                if (act == null) {
                    result.error("NO_ACTIVITY", "Activity yok.", null)
                    return
                }
                val intent =
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", act.packageName, null),
                    )
                act.startActivity(intent)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun ensurePermissions(
        manager: BleManager,
        result: Result,
    ) {
        if (manager.hasRequiredPermissions()) {
            result.success(true)
            return
        }
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "İzin istemek için Activity gerekli.", null)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("BUSY", "İzin isteği zaten sürüyor.", null)
            return
        }
        pendingPermissionResult = result
        act.requestPermissions(manager.requiredPermissions(), REQUEST_BLE_PERMISSIONS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_BLE_PERMISSIONS) return false
        val pending = pendingPermissionResult ?: return false
        pendingPermissionResult = null
        val granted =
            grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pending.success(granted)
        return true
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        scanEventChannel.setStreamHandler(null)
        connectionEventChannel.setStreamHandler(null)
        bleManager?.disconnect(emit = false)
        bleManager?.stopScan()
        bleManager = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    companion object {
        private const val REQUEST_BLE_PERMISSIONS = 2401
    }
}
