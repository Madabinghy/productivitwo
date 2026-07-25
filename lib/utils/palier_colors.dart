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
