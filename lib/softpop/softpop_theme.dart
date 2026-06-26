import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'softpop_tokens.dart';

/// ThemeData de la refonte « Soft Pop ».
///
/// ISOLÉ de l'app actuelle : on ne touche pas à `_buildTheme` dans main.dart.
/// On applique ce thème localement (Theme(...) au-dessus d'un écran refondu) le
/// temps de construire la nouvelle UI en parallèle de l'existante.
ThemeData softPopTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: SoftPop.violet,
    brightness: Brightness.light,
    primary: SoftPop.violet,
    secondary: SoftPop.coral,
    tertiary: SoftPop.teal,
    surface: SoftPop.card,
  );

  final textTheme = GoogleFonts.fredokaTextTheme().apply(
    bodyColor: SoftPop.ink,
    displayColor: SoftPop.ink,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: SoftPop.screenBg,
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    cardTheme: CardThemeData(
      color: SoftPop.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SoftPop.rCard),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      backgroundColor: SoftPop.violetSoft,
      labelStyle: SoftPop.ui(size: 13, weight: FontWeight.w600),
      side: BorderSide.none,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: SoftPop.screenBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: SoftPop.ui(size: 20, weight: FontWeight.w700),
      iconTheme: const IconThemeData(color: SoftPop.ink),
    ),
    dividerTheme: DividerThemeData(
      color: SoftPop.inkMuted.withValues(alpha: .18),
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SoftPop.violet,
        foregroundColor: Colors.white,
        textStyle: SoftPop.ui(size: 15, weight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SoftPop.rPill),
        ),
      ),
    ),
  );
}
