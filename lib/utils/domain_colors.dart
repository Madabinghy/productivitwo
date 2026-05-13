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

/// Retourne la couleur associée au domaine d'après son index, ou null.
Color? domainColor(String? domainId, List<Domain> domains) {
  if (domainId == null || domainId.isEmpty) return null;
  final idx = domains.indexWhere((d) => d.id == domainId);
  if (idx < 0) return null;
  return kDomainPalette[idx % kDomainPalette.length];
}
