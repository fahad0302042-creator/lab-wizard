import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared notebook palette. These values intentionally mirror the web app so
/// both clients feel like the same physical lab notebook.
abstract final class LabColors {
  static const paper = Color(0xFFFBF7EC);
  static const paperDark = Color(0xFF221E18);
  static const desk = Color(0xFFD9D2BE);
  static const deskDark = Color(0xFF15120E);
  static const ink = Color(0xFF2B2A28);
  static const inkDark = Color(0xFFEDE6D6);
  static const mutedInk = Color(0xFF6B6559);
  static const mutedInkDark = Color(0xFFA89E89);
  static const card = Color(0xFFFEFCF5);
  static const cardDark = Color(0xFF2B2621);
  static const marginRed = Color(0xFFB23A2E);
  // Status colours double as text colours, so they meet WCAG AA (4.5:1)
  // on paper and card in their own theme (A11Y-04): amber 5.2:1, green
  // 5.5:1, red 5.6:1 light; red 5.1:1 on the dark card.
  static const marginRedDark = Color(0xFFE07A6C);
  static const amber = Color(0xFF8F5E0E);
  static const amberDark = Color(0xFFE8B558);
  static const green = Color(0xFF3F6F3B);
  static const greenDark = Color(0xFF7BAE74);
  static const blue = Color(0xFF4A5C8A);
  static const ruled = Color(0xFFD8D2C0);
  static const ruledDark = Color(0xFF3D362E);
  static const marginLine = Color(0xFFE6B8AE);
  static const marginLineDark = Color(0xFF6B4A44);
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
    final scheme = ColorScheme.fromSeed(
      seedColor: red,
      brightness: brightness,
      surface: paper,
      primary: ink,
      secondary: red,
      error: red,
    );

    final baseText = ThemeData(brightness: brightness).textTheme
        .apply(bodyColor: ink, displayColor: ink, fontFamily: 'Kalam');

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? LabColors.deskDark : LabColors.desk,
      fontFamily: 'Kalam',
      textTheme: baseText.copyWith(
        bodyLarge: baseText.bodyLarge?.copyWith(fontSize: 16, height: 1.35),
        bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 15, height: 1.35),
        labelLarge: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        titleTextStyle: TextStyle(
          color: ink,
          fontFamily: 'Caveat',
          fontWeight: FontWeight.w700,
          fontSize: 28,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: dark ? const Color(0xFF5A5247) : const Color(0xFF3A362E),
            width: 1.4,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.elliptical(3, 9),
            topRight: Radius.elliptical(9, 3),
            bottomLeft: Radius.elliptical(8, 3),
            bottomRight: Radius.elliptical(3, 9),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        labelStyle: TextStyle(
          color: dark ? LabColors.mutedInkDark : LabColors.mutedInk,
          fontFamily: 'Caveat',
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
        hintStyle: TextStyle(
          color: (dark ? LabColors.mutedInkDark : LabColors.mutedInk)
              .withValues(alpha: .65),
          fontFamily: 'Kalam',
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
        border: UnderlineInputBorder(
          borderSide: BorderSide(
            color: dark ? LabColors.ruledDark : LabColors.ruled,
            width: 1.5,
          ),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(
            color: dark ? LabColors.ruledDark : LabColors.ruled,
            width: 1.5,
          ),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: red, width: 2),
        ),
        errorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: red, width: 1.5),
        ),
        focusedErrorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: red, width: 2),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: ink),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: card,
          textStyle: const TextStyle(
            fontFamily: 'Caveat',
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: ink, width: 1.8),
          textStyle: const TextStyle(
            fontFamily: 'Caveat',
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: red,
          textStyle: const TextStyle(
            fontFamily: 'Caveat',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: Colors.transparent,
        side: BorderSide.none,
        labelStyle: TextStyle(
          color: dark ? LabColors.mutedInkDark : LabColors.mutedInk,
          fontFamily: 'Caveat',
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        padding: EdgeInsets.zero,
        shape: const StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: card,
        contentTextStyle: TextStyle(color: ink, fontFamily: 'Kalam'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(3),
            topRight: Radius.circular(10),
            bottomLeft: Radius.circular(9),
            bottomRight: Radius.circular(3),
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        // Sheets stay a readable column on tablets and in landscape
        // (A11Y-03); Material 3's default, made explicit.
        constraints: const BoxConstraints(maxWidth: 640),
        showDragHandle: true,
        dragHandleColor: dark ? LabColors.mutedInkDark : LabColors.mutedInk,
        backgroundColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: ink, width: 1.4),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(3),
            topRight: Radius.circular(12),
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(4),
          ),
        ),
        titleTextStyle: TextStyle(
          color: ink,
          fontFamily: 'Caveat',
          fontSize: 26,
          fontWeight: FontWeight.w700,
        ),
      ),
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
}

/// WCAG 2 contrast ratio between two opaque colours (1 to 21). Used by the
/// palette audit (A11Y-04); text needs 4.5:1, large text 3:1.
double contrastRatio(Color a, Color b) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color color) =>
      0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
  final light = math.max(luminance(a), luminance(b));
  final dark = math.min(luminance(a), luminance(b));
  return (light + 0.05) / (dark + 0.05);
}
