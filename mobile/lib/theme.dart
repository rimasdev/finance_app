import 'package:flutter/material.dart';

class FolioColors {
  static const bg = Color(0xFF0C0C0E);
  static const card = Color(0xFF17171B);
  static const cardHigh = Color(0xFF212126);
  static const line = Color(0xFF2C2C32);
  static const green = Color(0xFF2FCB6E);
  static const greenInk = Color(0xFF07140C);
  static const red = Color(0xFFFF5C5C);
  static const muted = Color(0xFF9B9BA6);
  static const text = Color(0xFFF4F4F5);
}

ThemeData buildFolioTheme() {
  const scheme = ColorScheme.dark(
    primary: FolioColors.green,
    onPrimary: FolioColors.greenInk,
    surface: FolioColors.bg,
    error: FolioColors.red,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: FolioColors.bg,
    colorScheme: scheme,
    dividerColor: FolioColors.line,
    appBarTheme: const AppBarTheme(
      backgroundColor: FolioColors.bg,
      foregroundColor: FolioColors.text,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(color: FolioColors.text, fontSize: 17, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: FolioColors.card,
      hintStyle: const TextStyle(color: FolioColors.muted),
      labelStyle: const TextStyle(color: FolioColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: FolioColors.green),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
