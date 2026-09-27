import 'package:flutter/material.dart';

// Tokens de la refonte web (docs/specs/refonte-web-2026-09/README.md § 0) —
// même thème que l'Espace coach. Préfixe kB = « brand » ; utilisés par le
// shell, la vue Aujourd'hui et la Bibliothèque, puis par chaque vue reprise.

const kBBg = Color(0xFF07100D);
const kBBar = Color(0xFF0A1611);
const kBSurface = Color(0xFF0C1C14);
const kBRaised = Color(0xFF152B1E);
const kBActive = Color(0xFF12241B);
const kBPrimary = Color(0xFF27C48F);
const kBPrimaryDark = Color(0xFF1D9E75);
const kBText = Color(0xFFE8F3ED);
const kBText2 = Color(0xFFB9CFC4);
const kBText3 = Color(0xFF86A093);
const kBText4 = Color(0xFF6E8A7B);
const kBAlert = Color(0xFFFF6B5E);
const kBAttention = Color(0xFFF2A93B);
const kBLine = Color(0x12FFFFFF);

/// Couleur d'un bloc de programme selon sa catégorie.
const kBCategoryColor = {
  'project': Color(0xFF1D9E75),
  'routine': Color(0xFFE07B39),
  'personal': Color(0xFF5B8DEF),
  'break': Color(0xFF8E9AAF),
};
