import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Clinical palette. Text colours meet WCAG AA (4.5:1) on paper, card and
/// the gray metric tile, in both themes (A11Y-04). [green] is also a fill:
/// white on it is 6.6:1, so buttons and the scan circle can use it in either
/// theme. [highlighter] is kept for the contrast audit; the UI no longer
/// paints a marker.
abstract final class LabColors {
  static const paper = Color(0xFFFFFFFF);
  static const paperDark = Color(0xFF111113);
  static const desk = Color(0xFFF6F6F7);
  static const deskDark = Color(0xFF0C0C0E);
  static const ink = Color(0xFF171717);
  static const inkDark = Color(0xFFF3F3F4);
  static const mutedInk = Color(0xFF5C5C66);
  static const mutedInkDark = Color(0xFFC8C8CC);
  static const card = Color(0xFFFFFFFF);
  static const cardDark = Color(0xFF1C1C1F);
  static const tile = Color(0xFFECECEE);
  static const tileDark = Color(0xFF2A2A2E);
  static const marginRed = Color(0xFFB42318);
  static const marginRedDark = Color(0xFFF0A098);
  static const amber = Color(0xFF8A5A08);
  static const amberDark = Color(0xFFE8B558);
  static const green = Color(0xFF0E6A43);
  static const greenDark = Color(0xFF8ED4AE);
  static const blue = Color(0xFF3E4F86);
  static const blueDark = Color(0xFFB7C4E6);
  static const ruled = Color(0xFFE4E4E7);
  static const ruledDark = Color(0xFF3A3A3E);
  static const marginLine = Color(0xFFE4E4E7);
  static const marginLineDark = Color(0xFF3A3A3E);
  static const highlighter = Color(0xFFF3D96B);

  static const tapePink = Color(0x8CE89FA8);
  static const tapeYellow = Color(0x8CF0D696);
  static const tapeBlue = Color(0x8C9FC5E0);
  static const tapeGreen = Color(0x8CB2D59E);
}

abstract final class AppTheme {
  static ThemeData light() => _theme(Brightness.light);
  static ThemeData dark() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final ink = dark ? LabColors.inkDark : LabColors.ink;
    final paper = dark ? LabColors.paperDark : LabColors.paper;
    final card = dark ? LabColors.cardDark : LabColors.card;
    final red = dark ? LabColors.marginRedDark : LabColors.marginRed;
    final green = dark ? LabColors.greenDark : LabColors.green;
    final muted = dark ? LabColors.mutedInkDark : LabColors.mutedInk;
    final tile = dark ? LabColors.tileDark : LabColors.tile;
    final line = dark ? LabColors.ruledDark : LabColors.ruled;
    final scheme = ColorScheme.fromSeed(
      seedColor: LabColors.green,
      brightness: brightness,
      surface: paper,
      primary: green,
      secondary: green,
      error: red,
    );
    const radius = BorderRadius.all(Radius.circular(12));

    final baseText = ThemeData(brightness: brightness).textTheme.apply(
      bodyColor: ink,
      displayColor: ink,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? LabColors.deskDark : LabColors.desk,
      textTheme: baseText.copyWith(
        bodyLarge: baseText.bodyLarge?.copyWith(fontSize: 16, height: 1.35),
        bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 15, height: 1.35),
        labelLarge: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        titleTextStyle: TextStyle(
          color: ink,
          fontWeight: FontWeight.w700,
          fontSize: 18,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: line),
          borderRadius: radius,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tile,
        labelStyle: TextStyle(
          color: muted,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        hintStyle: TextStyle(color: muted.withValues(alpha: .8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: LabColors.green, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: red, width: 1.5),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: ink),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: LabColors.green,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: line),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: green,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tile,
        selectedColor: tile,
        side: BorderSide(color: line),
        labelStyle: TextStyle(
          color: muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        shape: const StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: card,
        contentTextStyle: TextStyle(color: ink),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        // Sheets stay a readable column on tablets and in landscape
        // (A11Y-03); Material 3's default, made explicit.
        constraints: const BoxConstraints(maxWidth: 640),
        showDragHandle: true,
        dragHandleColor: muted,
        backgroundColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: const RoundedRectangleBorder(borderRadius: radius),
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}

extension LabThemeX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// [duration] unless the person asked the system to reduce motion, in
  /// which case animations complete at once (A11Y-05).
  Duration motion(Duration duration) =>
      MediaQuery.disableAnimationsOf(this) ? Duration.zero : duration;
  Color get paperColor => isDark ? LabColors.paperDark : LabColors.paper;
  Color get cardColor => isDark ? LabColors.cardDark : LabColors.card;
  Color get tileColor => isDark ? LabColors.tileDark : LabColors.tile;
  Color get inkColor => isDark ? LabColors.inkDark : LabColors.ink;
  Color get mutedInkColor =>
      isDark ? LabColors.mutedInkDark : LabColors.mutedInk;
  Color get ruledColor => isDark ? LabColors.ruledDark : LabColors.ruled;
  Color get marginLineColor =>
      isDark ? LabColors.marginLineDark : LabColors.marginLine;
  Color get marginRedColor =>
      isDark ? LabColors.marginRedDark : LabColors.marginRed;
  Color get healthyColor => isDark ? LabColors.greenDark : LabColors.green;
  Color get lowColor => isDark ? LabColors.amberDark : LabColors.amber;
  Color get blueColor => isDark ? LabColors.blueDark : LabColors.blue;
}

/// WCAG 2 contrast ratio between two opaque colours (1 to 21). Used by the
/// palette audit (A11Y-04); text needs 4.5:1, large text 3:1.
double contrastRatio(Color a, Color b) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color color) =>
      0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
  final light = math.max(luminance(a), luminance(b));
  final dark = math.min(luminance(a), luminance(b));
  return (light + 0.05) / (dark + 0.05);
}
