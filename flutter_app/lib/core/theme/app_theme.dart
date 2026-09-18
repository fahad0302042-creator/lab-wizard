import 'package:flutter/material.dart';

abstract final class LabColors {
  static const paper = Color(0xFFFFFBF1);
  static const paperDark = Color(0xFF181714);
  static const desk = Color(0xFFE8E0CF);
  static const deskDark = Color(0xFF0D0D0C);
  static const ink = Color(0xFF20201E);
  static const inkDark = Color(0xFFF6F0E2);
  static const mutedInk = Color(0xFF6F6A60);
  static const mutedInkDark = Color(0xFFBDB5A6);
  static const marginRed = Color(0xFFC8453D);
  static const amber = Color(0xFFD58A23);
  static const green = Color(0xFF277A55);
  static const blue = Color(0xFF3478A8);
  static const ruled = Color(0x293B78A4);
  static const ruledDark = Color(0x245E91B4);
}

abstract final class AppTheme {
  static ThemeData light() => _theme(Brightness.light);
  static ThemeData dark() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: LabColors.marginRed,
      brightness: brightness,
      surface: dark ? LabColors.paperDark : LabColors.paper,
      primary: LabColors.marginRed,
      secondary: LabColors.blue,
      error: const Color(0xFFB3261E),
    );
    final bodyColor = dark ? LabColors.inkDark : LabColors.ink;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: dark ? LabColors.deskDark : LabColors.desk,
      fontFamily: 'Roboto',
      textTheme: ThemeData(brightness: brightness).textTheme
          .apply(bodyColor: bodyColor, displayColor: bodyColor),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: bodyColor,
      ),
      cardTheme: CardThemeData(
        color: dark ? const Color(0xFF24221E) : const Color(0xFFFFFEFA),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: bodyColor.withValues(alpha: .16)),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? const Color(0xFF24221E)
            : Colors.white.withValues(alpha: .8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: bodyColor.withValues(alpha: .12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: LabColors.marginRed, width: 1.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: dark
            ? const Color(0xFF201F1B)
            : const Color(0xFFFFFEF8),
        indicatorColor: LabColors.marginRed.withValues(alpha: .14),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            fontSize: 11,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: Colors.transparent,
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
  Color get paperColor => isDark ? LabColors.paperDark : LabColors.paper;
  Color get inkColor => isDark ? LabColors.inkDark : LabColors.ink;
  Color get mutedInkColor =>
      isDark ? LabColors.mutedInkDark : LabColors.mutedInk;
  Color get ruledColor => isDark ? LabColors.ruledDark : LabColors.ruled;
}
