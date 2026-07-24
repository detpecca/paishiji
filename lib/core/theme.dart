import 'package:flutter/material.dart';

/// 拍食记 主题。Material 3，暖色调（食物联想）。
class AppTheme {
  AppTheme._();

  static const Color _seed = Color(0xFFE65100); // 深橙
  static const Color green = Color(0xFF2E7D32); // 🟢
  static const Color yellow = Color(0xFFF9A825); // 🟡
  static const Color red = Color(0xFFC62828); // 🔴

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: _seed);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
    );
  }
}
