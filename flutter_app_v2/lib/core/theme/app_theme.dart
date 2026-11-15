import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Instrument panel — the design language for Lab Wizard 2.
///
/// Three rules hold the whole thing together:
///
/// 1. **Colour is data.** Cyan is the only "this is live / this is selected"
///    colour. Stock state is the only thing allowed to be green, amber or red,
///    and those three are the only colours that may ever appear on a vessel.
///    Nothing is tinted for decoration, so a coloured pixel on a shelf row is a
///    fact about a chemical, not a mood.
/// 2. **One type ladder.** IBM Plex Sans reads names and figures; IBM Plex Mono
///    reads anything the app *measures* — quantities, units, dates, formulas,
///    states. Formulas are mono because `HCl` must never be mistaken for `HCI`.
///    Five fixed steps, ten pixels at the floor, so nothing is unreadable at
///    arm's length with goggles on.
/// 3. **The vessel is the object.** Glass, liquid and a hairline order-level
///    notch. The liquid's colour *is* the stock signal, and the notch is drawn
///    in the liquid's own frame so tilting the phone cannot make the line lie.
@immutable
class LabPalette extends ThemeExtension<LabPalette> {
  const LabPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.hair,
    required this.hairStrong,
    required this.accent,
    required this.accentWash,
    required this.sage,
    required this.clay,
    required this.berry,
    required this.glass,
    required this.glassEdge,
    required this.vignette,
  });

  /// Page background: near-black with a cold cast, not a neutral grey.
  final Color canvas;

  /// Cards, rows, sheets.
  final Color surface;

  /// Anything that sits on top of [surface] and needs to separate from it.
  final Color surfaceRaised;

  /// Primary text.
  final Color ink;

  /// Secondary text, captions, units.
  final Color inkSoft;

  /// Disabled, decorative rules, the quietest tier that is still allowed to be
  /// read as text.
  final Color inkFaint;

  /// Hairline dividers.
  final Color hair;

  /// A divider that must be visible at a glance.
  final Color hairStrong;

  /// Live / selected / interactive. One colour, one job.
  final Color accent;

  /// [accent] at background strength, for selected chips and live pills.
  final Color accentWash;

  /// Healthy stock.
  final Color sage;

  /// Below the order level.
  final Color clay;

  /// Empty.
  final Color berry;

  /// Liquid body, before the state colour is applied.
  final Color glass;

  /// The vessel's outline and its glass highlights.
  final Color glassEdge;

  /// Radial wash painted behind the header so the canvas is not dead flat.
  final Color vignette;

  /// A state colour at wash strength, for tinting a whole row so a problem can
  /// be found by sweeping a thumb down the list without reading a word.
  Color wash(Color color, [double alpha = .06]) =>
      color.withValues(alpha: alpha);

  /// The colour a stock state is drawn in — the single source of truth, so the
  /// vessel, the flag word and the summary can never disagree.
  Color forState(StockSignal signal) => switch (signal) {
    StockSignal.fine => sage,
    StockSignal.order => clay,
    StockSignal.empty => berry,
  };

  static const dark = LabPalette(
    canvas: Color(0xFF080C14),
    surface: Color(0xFF111827),
    surfaceRaised: Color(0xFF1B2740),
    ink: Color(0xFFF1F5F9),
    inkSoft: Color(0xFF94A3B8),
    inkFaint: Color(0xFF64748B),
    hair: Color(0x17FFFFFF),
    hairStrong: Color(0x2EFFFFFF),
    accent: Color(0xFF38BDF8),
    accentWash: Color(0x2938BDF8),
    sage: Color(0xFF4ADE80),
    clay: Color(0xFFFBBF24),
    berry: Color(0xFFF87171),
    glass: Color(0xFF7DD3FC),
    glassEdge: Color(0xB3FFFFFF),
    vignette: Color(0xFF16243D),
  );

  @override
  LabPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    Color? hair,
    Color? hairStrong,
    Color? accent,
    Color? accentWash,
    Color? sage,
    Color? clay,
    Color? berry,
    Color? glass,
    Color? glassEdge,
    Color? vignette,
  }) => LabPalette(
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    ink: ink ?? this.ink,
    inkSoft: inkSoft ?? this.inkSoft,
    inkFaint: inkFaint ?? this.inkFaint,
    hair: hair ?? this.hair,
    hairStrong: hairStrong ?? this.hairStrong,
    accent: accent ?? this.accent,
    accentWash: accentWash ?? this.accentWash,
    sage: sage ?? this.sage,
    clay: clay ?? this.clay,
    berry: berry ?? this.berry,
    glass: glass ?? this.glass,
    glassEdge: glassEdge ?? this.glassEdge,
    vignette: vignette ?? this.vignette,
  );

  /// Dark is the only mode, but the extension still has to support lerp so the
  /// platform's own light/dark transition can never leave the app half-lit.
  @override
  LabPalette lerp(covariant LabPalette? other, double t) {
    if (other == null) return this;
    return LabPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      hair: Color.lerp(hair, other.hair, t)!,
      hairStrong: Color.lerp(hairStrong, other.hairStrong, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentWash: Color.lerp(accentWash, other.accentWash, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      clay: Color.lerp(clay, other.clay, t)!,
      berry: Color.lerp(berry, other.berry, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      glassEdge: Color.lerp(glassEdge, other.glassEdge, t)!,
      vignette: Color.lerp(vignette, other.vignette, t)!,
    );
  }
}

/// The size ladder. Five steps, fixed. Anything on screen picks one of these
/// rather than inventing a number — that is what makes a screen read as loud,
/// quiet and in between instead of uniformly medium.
abstract final class LabType {
  /// Eyebrows, units, flag words. Ten is the floor: anything smaller is
  /// unreadable on a phone held at arm's length on a bench.
  static const micro = 10.0;

  /// Body copy and secondary lines.
  static const small = 13.0;

  /// The primary reading size: quantities, list values.
  static const body = 17.0;

  /// Section and sheet titles.
  static const title = 24.0;

  /// One per screen: the headline that answers "what do I need to know".
  static const display = 31.0;
}

/// Tabular figures everywhere a number lives, so a column of quantities lines
/// up and a count-up never reflows mid-animation.
const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

const String kSans = 'PlexSans';
const String kMono = 'PlexMono';

/// What a row is signalling. Three values, not four: "healthy" and "no limit
/// set" both mean *nothing is wrong*, so they share an appearance and the
/// difference lives in the caption instead.
enum StockSignal { fine, order, empty }

extension LabThemeX on BuildContext {
  LabPalette get lab => Theme.of(this).extension<LabPalette>()!;

  /// Dark is the only mode; kept so call sites stay readable.
  bool get isDark => true;

  /// The one headline per screen. Sans, tight, heavy.
  TextStyle get display => TextStyle(
    fontFamily: kSans,
    fontSize: LabType.display,
    height: 1.06,
    letterSpacing: -1.1,
    fontWeight: FontWeight.w700,
    color: lab.ink,
  );

  /// Sheet and section titles.
  TextStyle get title => TextStyle(
    fontFamily: kSans,
    fontSize: LabType.title,
    height: 1.1,
    letterSpacing: -.7,
    fontWeight: FontWeight.w600,
    color: lab.ink,
  );

  /// Item names: a clean sans at reading weight. Forty chemical names in a
  /// scrawl would be tiring, and a name has to survive being read across a
  /// bench.
  TextStyle get itemName => TextStyle(
    fontFamily: kSans,
    fontSize: LabType.body,
    height: 1.15,
    letterSpacing: -.2,
    fontWeight: FontWeight.w500,
    color: lab.ink,
  );

  /// Formulas and categories. Mono, because `HCl` must not become `HCI`.
  TextStyle get formula => TextStyle(
    fontFamily: kMono,
    fontSize: 12.5,
    height: 1.25,
    letterSpacing: .1,
    color: lab.inkSoft,
    fontFeatures: _tabular,
  );

  /// Small spaced capitals for eyebrows, units and flag words.
  TextStyle get label => TextStyle(
    fontFamily: kMono,
    fontSize: LabType.micro,
    height: 1.1,
    letterSpacing: 1.2,
    fontWeight: FontWeight.w600,
    color: lab.inkSoft,
  );

  /// Quantities: mono, tabular, the loudest number on a row.
  TextStyle get figure => TextStyle(
    fontFamily: kMono,
    fontSize: LabType.body,
    height: 1.05,
    letterSpacing: -.4,
    fontWeight: FontWeight.w600,
    color: lab.ink,
    fontFeatures: _tabular,
  );

  /// Prose: hints, empty states, one-off explanations. Sans rather than the old
  /// handwriting — an instrument panel does not have a margin to doodle in.
  TextStyle get aside => TextStyle(
    fontFamily: kSans,
    fontSize: LabType.small,
    height: 1.45,
    color: lab.inkSoft,
  );
}

abstract final class LabTheme {
  /// Dark only. The instrument panel was designed for a dim lab bench and a
  /// phone propped against a reagent bottle; a paper-white version of it would
  /// be a different design, not a second theme.
  static ThemeData dark() => _build(LabPalette.dark);

  static ThemeData _build(LabPalette lab) {
    final scheme = ColorScheme.fromSeed(
      seedColor: lab.accent,
      brightness: Brightness.dark,
    ).copyWith(
      surface: lab.canvas,
      primary: lab.accent,
      onPrimary: const Color(0xFF020617),
      secondary: lab.accent,
      error: lab.berry,
      onSurface: lab.ink,
      outline: lab.hair,
    );

    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: lab.canvas,
      canvasColor: lab.canvas,
      extensions: [lab],
      splashFactory: InkSparkle.splashFactory,
      fontFamily: kSans,
      textTheme: base.textTheme
          .apply(bodyColor: lab.ink, displayColor: lab.ink, fontFamily: kSans),
      dividerTheme: DividerThemeData(color: lab.hair, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: lab.ink, size: 21),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lab.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        hintStyle: TextStyle(color: lab.inkSoft.withValues(alpha: .8), fontSize: 13),
        labelStyle: TextStyle(color: lab.inkSoft, fontSize: 13),
        floatingLabelStyle: TextStyle(color: lab.accent, fontSize: 13),
        border: _field(lab.hair),
        enabledBorder: _field(lab.hair),
        focusedBorder: _field(lab.accent, width: 1.4),
        errorBorder: _field(lab.berry),
        focusedErrorBorder: _field(lab.berry, width: 1.4),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: lab.accent,
          foregroundColor: const Color(0xFF020617),
          elevation: 0,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: const TextStyle(
            fontFamily: kSans,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .2,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: lab.accent,
          minimumSize: const Size(0, 44),
          textStyle: const TextStyle(
            fontFamily: kSans,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lab.ink,
          minimumSize: const Size(0, 46),
          side: BorderSide(color: lab.hairStrong, width: 1.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          textStyle: const TextStyle(
            fontFamily: kSans,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: lab.surface,
        side: BorderSide(color: lab.hair),
        labelStyle: TextStyle(
          fontFamily: kMono,
          fontSize: LabType.micro,
          letterSpacing: .6,
          color: lab.inkSoft,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: lab.surfaceRaised,
        contentTextStyle: TextStyle(
          fontFamily: kSans,
          color: lab.ink,
          fontSize: 13,
        ),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: lab.canvas,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lab.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titleTextStyle: TextStyle(
          fontFamily: kSans,
          color: lab.ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -.3,
        ),
        contentTextStyle: TextStyle(
          fontFamily: kSans,
          color: lab.inkSoft,
          fontSize: 13.5,
        ),
      ),
      // The activity indicator is used for syncing: draw it in the accent so a
      // spinner is the only moving thing on an otherwise still screen.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: lab.accent,
        linearTrackColor: lab.hair,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _field(Color color, {double width = 1.1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
}
