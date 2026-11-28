import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class SpaceColors {
  static const bg = Color(0xFFF3F4F7);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF8F9FB);
  static const ink = Color(0xFF14161A);
  static const inkSecondary = Color(0xFF5E6470);
  static const inkMuted = Color(0xFF9298A3);
  static const line = Color(0xFFE8E9ED);
  static const accent = Color(0xFFFF5A3C);
  static const accentDark = Color(0xFFE84627);
  static const accentSoft = Color(0xFFFFEDE7);
  static const dark = Color(0xFF16181D);
  static const darkSoft = Color(0xFF23262E);
  static const success = Color(0xFF12B76A);
  static const successSoft = Color(0xFFE8F8F0);
  static const warning = Color(0xFFF79009);
  static const overlayInk = Color(0xF20B0C0F);
}

ThemeData buildSpaceTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'PingFang SC',
    scaffoldBackgroundColor: SpaceColors.bg,
  );
  return base.copyWith(
    colorScheme: const ColorScheme.light(
      primary: SpaceColors.accent,
      onPrimary: Colors.white,
      secondary: SpaceColors.dark,
      onSecondary: Colors.white,
      surface: SpaceColors.surface,
      onSurface: SpaceColors.ink,
      error: Color(0xFFE5484D),
      onError: Colors.white,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: SpaceColors.ink,
      displayColor: SpaceColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: SpaceColors.ink),
      titleTextStyle: TextStyle(
        color: SpaceColors.ink,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    dividerTheme: const DividerThemeData(
      color: SpaceColors.line,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SpaceColors.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: SpaceColors.ink,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SpaceColors.ink,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: SpaceColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SpaceColors.surfaceAlt,
      hintStyle: const TextStyle(color: SpaceColors.inkMuted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: SpaceColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: SpaceColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: SpaceColors.dark, width: 1.4),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: SpaceColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        color: SpaceColors.ink,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: const TextStyle(
        color: SpaceColors.inkSecondary,
        fontSize: 14,
        height: 1.55,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: SpaceColors.dark,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

String formatSpaceDate(DateTime value) {
  final now = DateTime.now();
  final local = value.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) {
    return '今天 ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  if (diff == 1) return '昨天';
  if (diff < 7) return '$diff 天前';
  if (local.year == now.year) return '${local.month}月${local.day}日';
  return '${local.year}/${local.month}/${local.day}';
}