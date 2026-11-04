import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0B1020);
  static const bgTop = Color(0xFF111A33);
  static const card = Color(0xFF151D35);
  static const cardBorder = Color(0xFF243055);
  static const text = Color(0xFFE8ECF8);
  static const muted = Color(0xFF8A94B3);
  static const accent = Color(0xFF3DDC97); // grön
  static const accent2 = Color(0xFF4F8CFF); // blå
  static const win = Color(0xFF3DDC97);
  static const draw = Color(0xFFF5C451);
  static const loss = Color(0xFFFF5D6C);
  static const value = Color(0xFF3DDC97);
  static const fair = Color(0xFF4F8CFF);
  static const weak = Color(0xFFFF8A5B);
  static const model = Color(0xFF8A94B3);
}

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.accent,
      secondary: AppColors.accent2,
      surface: AppColors.card,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
  );
}
