import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';

// Briques visuelles des tuiles de routine — extraites du lanceur (FAB
// « Lancer une routine », main.dart) pour être partagées avec « Le meilleur
// à faire » (Maintenant) : MÊME style partout.

/// Badge de série : 🔥 par jour, ⭐ par tranche de 5, pastille violette > 25 j.
Widget routineStreakBadge(int streak) {
  if (streak == 0) return const SizedBox.shrink();

  final Widget icons;
  if (streak > 25) {
    icons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 5; i++)
          Icon(Icons.star_rounded, size: 12, color: Colors.amber.shade500),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.deepPurple.shade400,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${streak}j',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  } else {
    final stars = streak ~/ 5;
    final flames = streak % 5;
    icons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < stars; i++)
          Icon(Icons.star_rounded, size: 12, color: Colors.amber.shade500),
        for (int i = 0; i < flames; i++)
          Icon(Icons.local_fire_department,
              size: 12, color: Colors.deepOrange.shade400),
      ],
    );
  }

  return Padding(
    padding: const EdgeInsets.only(top: 3),
    child: icons,
  );
}

/// Pastille de fréquence (Quotidien / Hebdo / Mensuel).
Widget freqPill(HabitFreq f, ColorScheme cs) {
  final label = switch (f) {
    HabitFreq.daily => 'Quotidien',
    HabitFreq.weekly => 'Hebdo',
    HabitFreq.monthly => 'Mensuel',
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest.withOpacity(.7),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label,
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withOpacity(.55))),
  );
}

/// Bouton rond d'action de tuile (▶ ⏱ − + ⏭…) — le style des boutons du
/// lanceur de routines.
Widget routineTileButton({
  required IconData icon,
  required String tooltip,
  required Color color,
  required Color background,
  VoidCallback? onTap,
  double size = 16,
}) {
  return Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: size, color: color),
      ),
    ),
  );
}
