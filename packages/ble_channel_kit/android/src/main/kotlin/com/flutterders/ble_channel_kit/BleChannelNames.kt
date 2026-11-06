package com.flutterders.ble_channel_kit

/**
 * DERS 1 — Channel adları sabit / Neden böyle?
 * Flutter ve Kotlin aynı string'i kullanmalı; tek yerde tutmak yazım hatalarını önler.
 */
object BleChannelNames {
    const val METHOD = "com.flutterders.ble_channel_kit/methods"
    const val SCAN_EVENTS = "com.flutterders.ble_channel_kit/scan"
    const val CONNECTION_EVENTS = "com.flutterders.ble_channel_kit/connection"
}
