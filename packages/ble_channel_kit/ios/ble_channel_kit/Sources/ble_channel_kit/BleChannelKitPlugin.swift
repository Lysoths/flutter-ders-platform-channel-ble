import Flutter
import UIKit

/// DERS — iOS stub / Neden böyle?
/// Bu ders Android BLE odaklıdır. iOS tarafı no-op: MethodChannel cevap verir,
/// EventChannel boş kalır; gerçek CoreBluetooth ileride eklenebilir.
public class BleChannelKitPlugin: NSObject, FlutterPlugin {
  private static let methodName = "com.flutterders.ble_channel_kit/methods"
  private static let scanName = "com.flutterders.ble_channel_kit/scan"
  private static let connectionName = "com.flutterders.ble_channel_kit/connection"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: methodName, binaryMessenger: registrar.messenger())
    let instance = BleChannelKitPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    let scan = FlutterEventChannel(name: scanName, binaryMessenger: registrar.messenger())
    scan.setStreamHandler(EmptyStreamHandler())
    let connection = FlutterEventChannel(name: connectionName, binaryMessenger: registrar.messenger())
    connection.setStreamHandler(EmptyStreamHandler())
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "isBluetoothOn", "hasPermissions", "ensurePermissions":
      result(false)
    case "startScan", "stopScan", "connect", "disconnect", "write", "read", "openAppSettings":
      result(
        FlutterError(
          code: "UNSUPPORTED",
          message: "ble_channel_kit bu derste yalnızca Android'i destekler.",
          details: nil
        )
      )
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private class EmptyStreamHandler: NSObject, FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    return nil
  }
}
