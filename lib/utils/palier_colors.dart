import 'package:flutter/material.dart';

/// Échelle de couleur des paliers — README du design Espace Coach, utilisée
/// PARTOUT où un % d'engagements tenus s'affiche (console coach 8a, tableau
/// de bord du coaché) : ≥ 85 vert · 60-84 ambre · < 60 corail.
const kPalierGreen = Color(0xFF27C48F);
const kPalierAmber = Color(0xFFF2A93B);
const kPalierCoral = Color(0xFFFF6B5E);
const kPalierMuted = Color(0xFF86A093);

Color palierColor(int pct) =>
    pct >= 85 ? kPalierGreen : (pct >= 60 ? kPalierAmber : kPalierCoral);


/// Ordre « par pourcentage » (2026-10, demandé pour Stats puis généralisé) :
/// d'abord ce qui est SOUS 100 %, le plus proche de 100 en tête (ce qu'un
/// petit effort fait basculer), puis 100 % et plus en ordre croissant.
int comparePct(int a, int b) {
  final aUnder = a < 100, bUnder = b < 100;
  if (aUnder != bUnder) return aUnder ? -1 : 1;
  return aUnder ? b.compareTo(a) : a.compareTo(b);
}
