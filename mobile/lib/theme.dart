import 'package:flutter/material.dart';

class FolioColors {
  static const bg = Color(0xFF181A19);
  static const card = Color(0xFF262624);
  static const cardHigh = Color(0xFF2E2E2C);
  static const line = Color(0xFF343432);
  static const accent = Color(0xFFC5D7F6);
  static const accentInk = Color(0xFF1E2430);
  static const green = Color(0xFF8ED4B0);
  static const greenInk = Color(0xFF143024);
  static const red = Color(0xFFF0A0A0);
  static const muted = Color(0xFF9B9BA6);
  static const text = Color(0xFFF4F4F5);
}

ThemeData buildFolioTheme() {
  const scheme = ColorScheme.dark(
    primary: FolioColors.green,
    onPrimary: FolioColors.greenInk,
    surface: FolioColors.card,
    error: FolioColors.red,
  );
  final base = ThemeData.dark(useMaterial3: true);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: FolioColors.bg,
    colorScheme: scheme,
    textTheme: base.textTheme.apply(
      bodyColor: FolioColors.text,
      displayColor: FolioColors.text,
    ),
    iconTheme: const IconThemeData(color: FolioColors.text),
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
    dialogTheme: const DialogThemeData(backgroundColor: FolioColors.card),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: FolioColors.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
  );
}
