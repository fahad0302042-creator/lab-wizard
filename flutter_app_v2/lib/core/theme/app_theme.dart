import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Direction C — "The Store Room".
///
/// Warm bone paper, hairline rules, one sage accent that only becomes clay or
/// berry when a row actually needs attention. Colours are exposed through a
/// [LabPalette] theme extension so light and dark can lerp instead of being
/// switched with booleans.
@immutable
class LabPalette extends ThemeExtension<LabPalette> {
  const LabPalette({
    required this.bone,
    required this.card,
    required this.ink,
    required this.soft,
    required this.hair,
    required this.sage,
    required this.clay,
    required this.berry,
  });

  /// Page background.
  final Color bone;

  /// Row and sheet surface.
  final Color card;

  /// Primary text.
  final Color ink;

  /// Secondary text and quiet labels.
  final Color soft;

  /// Hairline dividers.
  final Color hair;

  /// Healthy stock.
  final Color sage;

  /// Below the order level.
  final Color clay;

  /// Empty.
  final Color berry;

  /// The colour a stock state is drawn in — the single source of truth so the
  /// jar, the flag word and the summary can never disagree.
  Color forState(StockSignal signal) => switch (signal) {
    StockSignal.fine => sage,
    StockSignal.order => clay,
    StockSignal.empty => berry,
  };

  static const light = LabPalette(
    bone: Color(0xFFF0EEE7),
    card: Color(0xFFFBFAF6),
    ink: Color(0xFF2C2B26),
    soft: Color(0xFF8C887C),
    hair: Color(0xFFDCD8CB),
    sage: Color(0xFF5C7A5E),
    clay: Color(0xFFB4703F),
    berry: Color(0xFF9C3F4A),
  );

  static const dark = LabPalette(
    bone: Color(0xFF171613),
    card: Color(0xFF201F1B),
    ink: Color(0xFFEDE9DF),
    soft: Color(0xFF9A9486),
    hair: Color(0xFF33312B),
    sage: Color(0xFF8BA98C),
    clay: Color(0xFFD08F5B),
    berry: Color(0xFFD07A85),
  );

  @override
  LabPalette copyWith({
    Color? bone,
    Color? card,
    Color? ink,
    Color? soft,
    Color? hair,
    Color? sage,
    Color? clay,
    Color? berry,
  }) => LabPalette(
    bone: bone ?? this.bone,
    card: card ?? this.card,
    ink: ink ?? this.ink,
    soft: soft ?? this.soft,
    hair: hair ?? this.hair,
    sage: sage ?? this.sage,
    clay: clay ?? this.clay,
    berry: berry ?? this.berry,
  );

  @override
  LabPalette lerp(covariant LabPalette? other, double t) {
    if (other == null) return this;
    return LabPalette(
      bone: Color.lerp(bone, other.bone, t)!,
      card: Color.lerp(card, other.card, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
      hair: Color.lerp(hair, other.hair, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      clay: Color.lerp(clay, other.clay, t)!,
      berry: Color.lerp(berry, other.berry, t)!,
    );
  }
}

/// What a row is signalling. Three values, not four: "healthy" and "no limit
/// set" both mean *nothing is wrong*, so they share an appearance and the
/// difference lives in the caption instead.
enum StockSignal { fine, order, empty }

extension LabThemeX on BuildContext {
  LabPalette get lab => Theme.of(this).extension<LabPalette>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Handwritten asides — dates, hints, empty states.
  TextStyle get aside => TextStyle(
    fontFamily: 'Caveat',
    fontSize: 17,
    height: 1.1,
    color: lab.soft,
  );

  /// Item names. Hand-set rather than geometric, so a shelf of them reads as
  /// written labels rather than rows in a spreadsheet.
  TextStyle get itemName => TextStyle(
    fontFamily: 'ArchitectsDaughter',
    fontSize: 16.5,
    height: 1.12,
    letterSpacing: -.1,
    color: lab.ink,
  );

  /// Chemical formulas.
  TextStyle get formula => TextStyle(
    fontFamily: 'Kalam',
    fontSize: 12.5,
    height: 1.15,
    color: lab.soft,
  );

  /// Small spaced capitals used for eyebrows, units and flag words.
  TextStyle get label => TextStyle(
    fontSize: 10,
    height: 1.1,
    letterSpacing: 1.1,
    fontWeight: FontWeight.w600,
    color: lab.soft,
  );

  /// Quantities. Tabular figures so a column of numbers lines up and never
  /// reflows while animating.
  TextStyle get figure => TextStyle(
    fontSize: 17,
    height: 1.05,
    letterSpacing: -.4,
    fontWeight: FontWeight.w600,
    color: lab.ink,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

abstract final class LabTheme {
  static ThemeData light() => _build(Brightness.light, LabPalette.light);
  static ThemeData dark() => _build(Brightness.dark, LabPalette.dark);

  static ThemeData _build(Brightness brightness, LabPalette lab) {
    final scheme = ColorScheme.fromSeed(
      seedColor: lab.sage,
      brightness: brightness,
    ).copyWith(
      surface: lab.bone,
      primary: lab.ink,
      secondary: lab.sage,
      error: lab.berry,
      onSurface: lab.ink,
    );

    final base = ThemeData(brightness: brightness, useMaterial3: true);

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: lab.bone,
      canvasColor: lab.bone,
      extensions: [lab],
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.apply(
        bodyColor: lab.ink,
        displayColor: lab.ink,
      ),
      dividerTheme: DividerThemeData(color: lab.hair, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: lab.ink, size: 21),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        hintStyle: TextStyle(color: lab.soft.withValues(alpha: .8)),
        labelStyle: TextStyle(color: lab.soft, fontSize: 13),
        floatingLabelStyle: TextStyle(color: lab.sage, fontSize: 13),
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: lab.hair, width: 1.2),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: lab.hair, width: 1.2),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: lab.sage, width: 1.6),
        ),
        errorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: lab.berry, width: 1.2),
        ),
        focusedErrorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: lab.berry, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: lab.ink,
          foregroundColor: lab.bone,
          elevation: 0,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            letterSpacing: .2,
          ),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: lab.ink,
          minimumSize: const Size(0, 44),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lab.ink,
          minimumSize: const Size(0, 46),
          side: BorderSide(color: lab.hair, width: 1.2),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: lab.ink,
        contentTextStyle: TextStyle(color: lab.bone, fontSize: 13),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: lab.bone,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lab.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titleTextStyle: TextStyle(
          color: lab.ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -.3,
        ),
        contentTextStyle: TextStyle(color: lab.soft, fontSize: 13.5),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}
