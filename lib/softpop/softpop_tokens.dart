import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens « Soft Pop » — source de vérité visuelle de la refonte.
///
/// Tout est centralisé ici (couleurs, dégradés, rayons, ombres, typo) pour que
/// les écrans n'écrivent jamais de valeur en dur. Ton calme, chaleureux, arrondi.
/// Réf : handoff design (§8 Design tokens).
class SoftPop {
  SoftPop._();

  // ── Couleurs de surface ────────────────────────────────────────────────────
  static const Color pageBg = Color(0xFFEFE9FB); // fond page (le plus foncé)
  static const Color screenBg = Color(0xFFFAF7FF); // fond d'écran
  static const Color card = Color(0xFFFFFFFF); // cartes

  // ── Texte ──────────────────────────────────────────────────────────────────
  static const Color ink = Color(0xFF2A2540); // texte principal
  static const Color inkSecondary = Color(0xFF6B6385); // texte secondaire
  static const Color inkMuted = Color(0xFF9B8FC4); // texte atténué

  // ── Accents ────────────────────────────────────────────────────────────────
  static const Color violet = Color(0xFF7C5CFF); // primaire
  static const Color coral = Color(0xFFFF6B5E);
  static const Color teal = Color(0xFF14C8B1); // succès / coché
  static const Color amber = Color(0xFFFFB020);
  static const Color pink = Color(0xFFFF5EA0);

  // Variantes foncées : texte d'accent lisible sur fond clair teinté.
  static const Color violetDark = Color(0xFF6A4CF0);
  static const Color coralDark = Color(0xFFE0493B);
  static const Color tealDark = Color(0xFF0E9E8C);
  static const Color amberDark = Color(0xFFCC8500);
  static const Color pinkDark = Color(0xFFE0357F);

  // Fonds teintés clairs : badges, pills, surfaces d'accent douces.
  static const Color violetSoft = Color(0xFFF0ECFF);
  static const Color coralSoft = Color(0xFFFDECEB);
  static const Color tealSoft = Color(0xFFEAFAF7);
  static const Color amberSoft = Color(0xFFFFF4DD);
  static const Color pinkSoft = Color(0xFFFFEAF3);

  // ── Dégradés ────────────────────────────────────────────────────────────────
  /// Dégradé héros : CTA principaux, en-têtes, accent fort.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, coral], // 135°
  );

  /// Dégradé série : flamme / streak.
  static const LinearGradient streakGradient = LinearGradient(
    begin: Alignment(-0.6, -1),
    end: Alignment(0.6, 1),
    colors: [amber, coral], // ~150°
  );

  // ── Rayons ──────────────────────────────────────────────────────────────────
  static const double rPill = 999;
  static const double rCardLg = 26;
  static const double rCard = 20;
  static const double rCardSm = 16;
  static const double rChip = 14;
  static const double rTiny = 10;

  // ── Espacements (échelle 4) ─────────────────────────────────────────────────
  static const double s4 = 4, s8 = 8, s12 = 12, s16 = 16, s20 = 20, s24 = 24,
      s32 = 32;

  // ── Ombres douces teintées violet ────────────────────────────────────────────
  /// Ombre de carte : portée, douce, légèrement violette.
  static List<BoxShadow> get cardShadow => const [
        BoxShadow(
          color: Color(0x267C5CFF), // rgba(124,92,255,.15)
          blurRadius: 40,
          offset: Offset(0, 18),
          spreadRadius: -20,
        ),
      ];

  /// Ombre colorée sous un élément actif (bouton héros, pill sélectionnée).
  static List<BoxShadow> coloredShadow(Color c) => [
        BoxShadow(
          color: c.withValues(alpha: .45),
          blurRadius: 24,
          offset: const Offset(0, 12),
          spreadRadius: -10,
        ),
      ];

  // ── Typographie ──────────────────────────────────────────────────────────────
  /// Police UI : Fredoka (titres, labels, corps).
  static TextStyle ui(
          {double size = 15,
          FontWeight weight = FontWeight.w500,
          Color color = ink,
          double? height,
          double? letterSpacing}) =>
      GoogleFonts.fredoka(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  /// Police « chiffres de jeu » : Space Mono (XP, ⚡, 💎, %, PV, timers).
  static TextStyle mono(
          {double size = 15,
          FontWeight weight = FontWeight.w700,
          Color color = ink,
          double? letterSpacing}) =>
      GoogleFonts.spaceMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  // ── Domaines de vie (couleur + accent) ───────────────────────────────────────
  /// Couleurs canoniques des domaines (alignées handoff §4.5).
  static const Map<String, Color> domainColors = {
    'sante': teal,
    'travail': violet,
    'apprentissage': amber,
    'maison': coral,
    'social': pink,
  };
}
