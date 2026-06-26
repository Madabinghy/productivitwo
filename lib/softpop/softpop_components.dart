import 'package:flutter/material.dart';
import 'softpop_tokens.dart';

/// Bibliothèque de composants « Soft Pop » réutilisables.
///
/// Chaque composant est autonome et ne dépend que de [SoftPop] (tokens). Ils
/// servent de briques pour reconstruire les écrans du handoff.

/// Carte arrondie blanche à ombre douce — conteneur de base.
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final VoidCallback? onTap;
  final Gradient? gradient;

  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SoftPop.s16),
    this.radius = SoftPop.rCard,
    this.color,
    this.onTap,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? SoftPop.card) : null,
        gradient: gradient,
        borderRadius: r,
        boxShadow: SoftPop.cardShadow,
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: r,
      child: InkWell(borderRadius: r, onTap: onTap, child: content),
    );
  }
}

/// Pill / badge arrondi. Sélectionnable (fond accent) ou neutre (fond teinté).
class SoftPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color accent;
  final bool selected;
  final VoidCallback? onTap;

  const SoftPill({
    super.key,
    required this.label,
    this.icon,
    this.accent = SoftPop.violet,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : accent;
    final bg = selected ? accent : accent.withValues(alpha: .12);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(SoftPop.rPill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: SoftPop.s16, vertical: SoftPop.s8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(SoftPop.rPill),
            boxShadow: selected ? SoftPop.coloredShadow(accent) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: SoftPop.s8),
              ],
              Text(label, style: SoftPop.ui(size: 13, weight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bouton héros à dégradé violet→corail, ombre colorée — CTA principal.
class SoftHeroButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expand;

  const SoftHeroButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(SoftPop.rPill);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: r,
        onTap: onPressed,
        child: Ink(
          decoration: BoxDecoration(
            gradient: SoftPop.heroGradient,
            borderRadius: r,
            boxShadow: SoftPop.coloredShadow(SoftPop.violet),
          ),
          child: Container(
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(
                horizontal: SoftPop.s24, vertical: SoftPop.s16),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: Colors.white),
                  const SizedBox(width: SoftPop.s8),
                ],
                Text(label,
                    style: SoftPop.ui(
                        size: 16, weight: FontWeight.w600, color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barre d'XP / progression arrondie, avec dégradé et valeur optionnelle.
class SoftXpBar extends StatelessWidget {
  final double value; // 0..1
  final Gradient gradient;
  final double height;
  final Color? track;

  const SoftXpBar({
    super.key,
    required this.value,
    this.gradient = SoftPop.heroGradient,
    this.height = 12,
    this.track,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(SoftPop.rPill),
      child: Stack(
        children: [
          Container(height: height, color: track ?? SoftPop.violetSoft),
          FractionallySizedBox(
            widthFactor: v == 0 ? 0.001 : v,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: height,
              decoration: BoxDecoration(gradient: gradient),
            ),
          ),
        ],
      ),
    );
  }
}

/// Statistique « jeu » : grand chiffre Space Mono + label + icône/emoji d'accent.
class SoftStat extends StatelessWidget {
  final String value;
  final String label;
  final Color accent;
  final String? emoji;

  const SoftStat({
    super.key,
    required this.value,
    required this.label,
    this.accent = SoftPop.violet,
    this.emoji,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null) ...[
              Text(emoji!, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: SoftPop.s4),
            ],
            Text(value,
                style: SoftPop.mono(size: 22, weight: FontWeight.w700, color: accent)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: SoftPop.ui(size: 12, color: SoftPop.inkSecondary)),
      ],
    );
  }
}

/// Mascotte « Pomo » — placeholder géométrique (cercle corail + feuille teal +
/// 2 yeux). À remplacer par l'asset illustré final.
class PomoMascot extends StatelessWidget {
  final double size;
  const PomoMascot({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PomoPainter()),
    );
  }
}

class _PomoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.58);
    final r = size.width * 0.40;
    // Corps : dégradé violet→corail.
    final body = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [SoftPop.violet, SoftPop.coral],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, body);
    // Feuille teal au sommet.
    final leaf = Paint()..color = SoftPop.teal;
    final stem = size.width * 0.10;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx + stem * 0.4, c.dy - r - stem * 0.2),
        width: stem * 1.6,
        height: stem * 0.9,
      ),
      leaf,
    );
    // Yeux.
    final eye = Paint()..color = Colors.white;
    final eyeR = r * 0.18;
    canvas.drawCircle(Offset(c.dx - r * 0.32, c.dy - r * 0.1), eyeR, eye);
    canvas.drawCircle(Offset(c.dx + r * 0.32, c.dy - r * 0.1), eyeR, eye);
    final pupil = Paint()..color = SoftPop.ink;
    canvas.drawCircle(Offset(c.dx - r * 0.32, c.dy - r * 0.1), eyeR * 0.5, pupil);
    canvas.drawCircle(Offset(c.dx + r * 0.32, c.dy - r * 0.1), eyeR * 0.5, pupil);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
