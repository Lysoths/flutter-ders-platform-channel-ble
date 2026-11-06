// DERS 0 — Giriş / Neden böyle?
// Bu uygulama Platform Channel mantığını BLE üzerinden öğretir.
// Native iş: packages/ble_channel_kit (Kotlin). Dart API ince kalır.

import 'package:flutter/material.dart';
import 'package:flutter_uygulama2/app/theme/app_theme.dart';
import 'package:flutter_uygulama2/app/views/ble_ders_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FlutterUygulama2App());
}

/// Uygulama kökü — basit Navigator, Material 3.
class FlutterUygulama2App extends StatelessWidget {
  /// Kök widget.
  const FlutterUygulama2App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Uygulama 2 — BLE Channel',
      theme: buildAppTheme(),
      home: const BleDersView(),
      debugShowCheckedModeBanner: false,
    );
  }
}
