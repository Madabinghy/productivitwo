import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/mode.dart';

/// Ambiance par mode (lot 1 Modes et coups, 2026-10) : Flemme = ambre doux,
/// Normal = vert actuel (rien ne change), En forme = teal électrique. Discret :
/// l'accent, jamais un fond plein écran.
Color modeSeed(DayMode m) => switch (m) {
      DayMode.low => const Color(0xFFC98A1C),
      DayMode.normal => Colors.teal,
      DayMode.high => const Color(0xFF00BCD4),
    };

/// Accent du mode ; null en Normal (on garde la couleur primaire du thème).
Color? modeAccentOverride(DayMode m, {required bool dark}) => switch (m) {
      DayMode.low => dark ? const Color(0xFFF2A93B) : const Color(0xFFB7791F),
      DayMode.normal => null,
      DayMode.high => dark ? const Color(0xFF22D3EE) : const Color(0xFF0097A7),
    };

/// Couleur des chips « malgré tout » (ambre) et « à fond » (teal).
Color modeChipColor(DayMode m, {required bool dark}) => modeAccentOverride(m, dark: dark) ?? (dark ? const Color(0xFF27C48F) : Colors.teal);

String modeEyebrow(DayMode m) => switch (m) { DayMode.low => 'MODE FLEMME', DayMode.normal => '', DayMode.high => 'MODE EN FORME' };

IconData modeIcon(DayMode m) => switch (m) {
      DayMode.low => Icons.bedtime_outlined,
      DayMode.normal => Icons.wb_cloudy_outlined,
      DayMode.high => Icons.bolt_rounded,
    };

String modeDescription(DayMode m) => switch (m) {
      DayMode.low => 'Le minimum qui compte · 10 min malgré tout',
      DayMode.normal => 'La journée telle que prévue',
      DayMode.high => 'Pousser fort sur une chose · deep work',
    };
