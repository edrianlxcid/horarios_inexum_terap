import 'package:flutter/material.dart';

/// Tema de la app: azul petróleo como color principal, claro y oscuro.
class TemaApp {
  const TemaApp._();

  static const _semilla = Color(0xFF1D5F8A);

  static ThemeData claro() => _base(ColorScheme.fromSeed(seedColor: _semilla));

  static ThemeData oscuro() =>
      _base(ColorScheme.fromSeed(seedColor: _semilla, brightness: Brightness.dark));

  static ThemeData _base(ColorScheme colores) {
    return ThemeData(
      colorScheme: colores,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colores.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: TextStyle(fontWeight: FontWeight.w600, color: colores.onSurfaceVariant, fontSize: 13),
        dataTextStyle: TextStyle(color: colores.onSurface, fontSize: 13.5),
      ),
    );
  }
}
