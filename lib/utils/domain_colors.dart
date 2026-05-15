import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';

const kDomainPalette = [
  Color(0xFF4CAF50), // vert
  Color(0xFF2196F3), // bleu
  Color(0xFFFF9800), // orange
  Color(0xFF9C27B0), // violet
  Color(0xFFE91E63), // rose
  Color(0xFF00BCD4), // cyan
  Color(0xFFFF5722), // orange profond
  Color(0xFF3F51B5), // indigo
];

/// Retourne la couleur associée au domaine.
/// Priorité : colorValue choisi par l'utilisateur, sinon palette par index.
Color? domainColor(String? domainId, List<Domain> domains) {
  if (domainId == null || domainId.isEmpty) return null;
  final idx = domains.indexWhere((d) => d.id == domainId);
  if (idx < 0) return null;
  final domain = domains[idx];
  if (domain.colorValue != null) return Color(domain.colorValue!);
  return kDomainPalette[idx % kDomainPalette.length];
}

// Palette proposée dans le color picker
const kColorPickerOptions = [
  Color(0xFF4CAF50), Color(0xFF8BC34A), Color(0xFF009688), Color(0xFF00BCD4),
  Color(0xFF2196F3), Color(0xFF3F51B5), Color(0xFF9C27B0), Color(0xFFE91E63),
  Color(0xFFF44336), Color(0xFFFF5722), Color(0xFFFF9800), Color(0xFFFFEB3B),
  Color(0xFF795548), Color(0xFF607D8B), Color(0xFF9E9E9E), Color(0xFFFFFFFF),
];
