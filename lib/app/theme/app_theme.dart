import 'package:flutter/material.dart';

/// DERS 5 — Tema / Neden böyle?
/// Material 3 ile tutarlı renk; ders UI'sı sade kalsın.
ThemeData buildAppTheme() {
  const seed = Color(0xFF0B6E4F);
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ),
    appBarTheme: const AppBarTheme(centerTitle: false),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
  );
}
