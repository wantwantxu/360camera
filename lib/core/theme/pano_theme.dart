import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pano_colors.dart';

ThemeData buildPanoTheme() {
  const scheme = ColorScheme.dark(
    surface: PanoColors.bgBase,
    primary: PanoColors.amber,
    secondary: PanoColors.cyan,
    tertiary: PanoColors.emerald,
    error: PanoColors.rose,
    onPrimary: PanoColors.bgBase,
    onSecondary: PanoColors.bgBase,
    onSurface: PanoColors.textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: PanoColors.bgBase,
    fontFamily: 'PingFang SC',
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: PanoColors.textPrimary, fontSize: 14, height: 1.4),
      labelLarge: TextStyle(color: PanoColors.textPrimary, fontWeight: FontWeight.w600),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: PanoColors.bgCard,
      contentTextStyle: const TextStyle(color: PanoColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
