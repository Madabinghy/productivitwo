
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/widgets/status_row.dart' show StateChip;

/// « Une carte, une fiche » (2026-10) : l'ossature commune des fiches —
/// feuille à 85 %, poignée, en-tête (titre + chip d'état + ligne repère), puis
/// des sections en capitales dans le même ordre partout : CETTE SEMAINE →
/// DEPUIS LE DÉBUT → RÉSULTAT / PROCHAINE ÉTAPE → gestes. La fiche objectif
/// (`objective_trajectory_sheet.dart`) est le modèle.
Future<T?> showFiche<T>(BuildContext context, {required Widget Function(BuildContext ctx, ScrollController scroll) builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: .85,
      minChildSize: .5,
      maxChildSize: .96,
      expand: false,
      builder: (ctx, scroll) {
        final cs = Theme.of(ctx).colorScheme;
        return Container(
          decoration: BoxDecoration(color: cs.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
          child: Column(children: [
            const SizedBox(height: 10),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .2), borderRadius: BorderRadius.circular(2))),
            Expanded(child: builder(ctx, scroll)),
          ]),
        );
      },
    ),
  );
}

/// Titre de section « CETTE SEMAINE · LES MOYENS » + élément à droite.
class FicheTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const FicheTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(children: [
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8, color: cs.onSurface.withValues(alpha: .5))),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), Flexible(child: trailing!)],
      ]),
    );
  }
}

/// Texte d'écart coloré à droite d'un titre : « −2 tâches », « 71 % du rythme ».
class FicheDelta extends StatelessWidget {
  final String text;
  final Color color;
  const FicheDelta(this.text, {super.key, required this.color});

  @override
  Widget build(BuildContext context) => Text(text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color, fontFeatures: const [FontFeature.tabularFigures()]));
}

/// En-tête : titre + chip d'état, puis la ligne repère (« Pour École · 12 tâches · séance ven. 30 oct. »).
class FicheHeader extends StatelessWidget {
  final String title;
  final String? chip;
  final Color? chipColor;
  final String? kpi;
  final Widget? leading;
  const FicheHeader({super.key, required this.title, this.chip, this.chipColor, this.kpi, this.leading});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (leading != null) ...[leading!, const SizedBox(width: 10)],
        Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.15))),
        if (chip != null) ...[
          const SizedBox(width: 10),
          Flexible(flex: 0, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: StateChip(chip!, color: chipColor ?? cs.primary))),
        ],
      ]),
      if (kpi != null) ...[
        const SizedBox(height: 6),
        Text(kpi!, style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .6))),
      ],
    ]);
  }
}

/// Encart de texte secondaire (détail, note, explication d'absence).
class FicheNote extends StatelessWidget {
  final String text;
  const FicheNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .05), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(fontSize: 13, height: 1.4, color: cs.onSurface.withValues(alpha: .8))),
    );
  }
}

/// Ligne d'étape / d'action dans une fiche : rond (fait / en cours / à faire), titre, détail, tap.
class FicheStep extends StatelessWidget {
  final String title;
  final String? detail;
  final bool done;
  final bool current;
  final VoidCallback? onTap;
  final Widget? trailing;
  const FicheStep({super.key, required this.title, this.detail, this.done = false, this.current = false, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: cs.onSurface.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: current ? Border.all(color: cs.primary.withValues(alpha: .45)) : null,
            ),
            child: Row(children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? cs.primary : null,
                  border: done ? null : Border.all(color: cs.onSurface.withValues(alpha: .4), width: 2),
                ),
                child: done ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          color: done ? cs.onSurface.withValues(alpha: .5) : cs.onSurface,
                          decoration: done ? TextDecoration.lineThrough : null)),
                  if (detail != null)
                    Text(detail!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .55))),
                ]),
              ),
              if (trailing != null) trailing!,
            ]),
          ),
        ),
      ),
    );
  }
}

/// Rangée de gestes en bas de fiche : un bouton plein + des contours.
class FicheActions extends StatelessWidget {
  final String primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;
  final List<({String label, VoidCallback? onTap})> secondary;
  const FicheActions({super.key, required this.primaryLabel, this.primaryIcon, this.onPrimary, this.secondary = const []});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
          height: 44,
          child: FilledButton.icon(
            onPressed: onPrimary,
            style: FilledButton.styleFrom(shape: const StadiumBorder(), textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            icon: Icon(primaryIcon ?? Icons.play_arrow_rounded, size: 20),
            label: Text(primaryLabel),
          ),
        ),
        for (final s in secondary)
          SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: s.onTap,
              style: OutlinedButton.styleFrom(
                  shape: const StadiumBorder(),
                  foregroundColor: cs.onSurface.withValues(alpha: .8),
                  side: BorderSide(color: cs.onSurface.withValues(alpha: .18)),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              child: Text(s.label),
            ),
          ),
      ]),
    );
  }
}
