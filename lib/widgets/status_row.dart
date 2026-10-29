
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

/// « Une carte, une fiche » (2026-10) : la *ligne* commune — icône · titre ·
/// sous-ligne chiffrée · barre fait / attendu avec le repère « attendu
/// aujourd'hui » · état à droite (chip ou écart). Même ligne pour un objectif,
/// un projet, une action, un domaine. Tap = la fiche.
class StatusRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? sub;
  /// (fait, total, attendu) ; null = pas de barre.
  final ({num done, num total, num expected})? bar;
  /// Pourcentage qui colore la barre et l'état (paliers : ≥ 85 vert, ≥ 60 ambre).
  final int pct;
  final String? chip;
  final String? delta;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool muted;

  const StatusRow({
    super.key,
    required this.leading,
    required this.title,
    this.sub,
    this.bar,
    this.pct = 100,
    this.chip,
    this.delta,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final text3 = dark ? kBText3 : cs.onSurface.withValues(alpha: .55);
    final st = palierColor(pct);
    final b = bar;
    final inlineChip = trailing == null && delta == null && chip != null;
    return Material(
      color: dark ? kBSurface : cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: dark ? kBLine : cs.outlineVariant.withValues(alpha: .4)),
          ),
          child: Row(children: [
            SizedBox(
              width: 26,
              height: 26,
              child: Container(
                decoration: BoxDecoration(color: dark ? kBRaised : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.center,
                child: IconTheme(data: IconThemeData(size: 15, color: muted ? text3 : cs.onSurface.withValues(alpha: .8)), child: leading),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Le titre a toute la largeur (retour user 2026-10-30 : la chip à
                // droite mangeait un tiers de la ligne) ; la chip d'état passe en
                // tête de la sous-ligne.
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: muted ? text3 : cs.onSurface,
                        decoration: muted ? TextDecoration.lineThrough : null)),
                if (inlineChip || sub != null) ...[
                  const SizedBox(height: 3),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (inlineChip) ...[
                      Padding(padding: const EdgeInsets.only(top: 1), child: StateChip(chip!, color: st, compact: true)),
                      if (sub != null) const SizedBox(width: 6),
                    ],
                    if (sub != null)
                      Expanded(
                        child: Text(sub!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, height: 1.3, color: text3, fontFeatures: const [FontFeature.tabularFigures()])),
                      ),
                  ]),
                ],
                if (b != null) ...[
                  const SizedBox(height: 6),
                  ExpectedBar(done: b.done, total: b.total, expected: b.expected, color: st, height: 6),
                ],
              ]),
            ),
            if (!inlineChip) ...[
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: trailing ??
                    (delta != null
                        ? Text(delta!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: st, fontFeatures: const [FontFeature.tabularFigures()]))
                        : Icon(Icons.chevron_right, color: text3)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Chip d'état : « au rythme », « en retard », « fait »…
class StateChip extends StatelessWidget {
  final String label;
  final Color color;
  /// En ligne dans une sous-ligne : plus petit, moins de marge.
  final bool compact;
  const StateChip(this.label, {super.key, required this.color, this.compact = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 1.5 : 3),
        decoration: BoxDecoration(color: color.withValues(alpha: .16), borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: compact ? 10.5 : 11, fontWeight: FontWeight.w800, color: color)),
      );
}

/// Barre fait / total avec le repère vertical « attendu aujourd'hui » (même
/// geste que la barre « temps investi » de la fiche objectif).
class ExpectedBar extends StatelessWidget {
  final num done;
  final num total;
  final num expected;
  final Color color;
  final double height;
  const ExpectedBar({super.key, required this.done, required this.total, required this.expected, required this.color, this.height = 10});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final donePct = total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0).toDouble();
    final expPct = total <= 0 ? 0.0 : (expected / total).clamp(0.0, 1.0).toDouble();
    return LayoutBuilder(builder: (_, box) {
      final w = box.maxWidth;
      return SizedBox(
        height: height + 6,
        child: Stack(children: [
          Positioned.fill(
            top: 3,
            bottom: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(height / 2),
              child: LinearProgressIndicator(
                  value: donePct, minHeight: height, backgroundColor: cs.onSurface.withValues(alpha: .08), valueColor: AlwaysStoppedAnimation<Color>(color)),
            ),
          ),
          Positioned(
            left: (w * expPct - 1).clamp(0.0, w - 2),
            top: 0,
            bottom: 0,
            child: Container(width: 2, decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .55), borderRadius: BorderRadius.circular(1))),
          ),
        ]),
      );
    });
  }
}

/// En-tête de section d'une liste : « TOUS LES PROJETS » + action à droite.
class ListSectionTitle extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final bool expanded;
  const ListSectionTitle(this.text, {super.key, this.action, this.onAction, this.expanded = true});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final text3 = dark ? kBText3 : cs.onSurface.withValues(alpha: .55);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: InkWell(
        onTap: onAction,
        borderRadius: BorderRadius.circular(8),
        child: Row(children: [
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: text3))),
          if (action != null)
            Text(action!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: dark ? kBText2 : cs.onSurface.withValues(alpha: .7)))
          else if (onAction != null)
            Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: text3),
        ]),
      ),
    );
  }
}
