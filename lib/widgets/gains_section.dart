import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/badge_cards.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/widget_service.dart';
import 'package:productivitwo_v1/widgets/badge_card.dart' show rarityInk;
import 'package:productivitwo_v1/widgets/badge_gallery_screen.dart' show showBadgeSheet;

/// Les cartes qu'une activité ou une routine fait avancer (2026-11-02, retour
/// user : voir la progression vers le prochain gain hors de l'album) : sa
/// série, son compteur, ses heures, l'année et le chemin des 10 000 h.
List<BadgeState> gainsFor(BadgeDeck deck, String activityId, {bool time = true}) {
  final ids = [
    'serie-$activityId',
    'fois-$activityId',
    'heures-$activityId',
    if (time) 'heures-annee',
    if (time) 'heures-total',
  ];
  return [for (final id in ids) if (deck.byId(id) case final b?) b];
}

String _label(BadgeState b) {
  final id = b.def.id;
  if (id.startsWith('serie-')) return 'Série';
  if (id.startsWith('fois-')) return 'Faite au total';
  if (id == 'heures-annee' || id == 'heures-total') return b.def.name;
  if (id.startsWith('heures-')) return 'Heures · ${b.def.name}';
  return b.def.name;
}

String _num(num v) => v is int || v == v.roundToDouble() ? fmtInt(v) : v.toStringAsFixed(1).replaceAll('.', ',');

/// Une ligne : libellé, « 152,4 / 250 h », jauge à la couleur du prochain cadre.
class GainRow extends StatelessWidget {
  final BadgeState b;
  final bool dense;
  const GainRow(this.b, {super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final next = b.nextTarget;
    final ladder = rarityLadder(b.def);
    final nextRarity = b.level < ladder.length ? ladder[b.level] : rarityOf(b);
    final color = rarityInk(nextRarity);
    final unit = b.def.unit.isEmpty ? '' : ' ${b.def.unit}';
    final right = next == null ? '${_num(b.value)}$unit · tout gagné' : '${_num(b.value)} / ${fmtInt(next)}$unit';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showBadgeSheet(context, b, deck: WidgetService.badges?.deck),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 3 : 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(_label(b),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: dense ? 12 : 13, fontWeight: FontWeight.w700)),
            ),
            Text(right, style: TextStyle(fontSize: dense ? 11.5 : 12.5, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: .7))),
            if (next != null && !dense) ...[
              const SizedBox(width: 6),
              Text(rarityLabel(nextRarity).toLowerCase(), style: TextStyle(fontSize: 11, color: color)),
            ],
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: b.progress ?? 1,
              minHeight: dense ? 4 : 5,
              backgroundColor: cs.onSurface.withValues(alpha: .1),
              color: color,
            ),
          ),
        ]),
      ),
    );
  }
}

/// Section « CE QUE ÇA FAIT AVANCER » des fiches (activité, routine).
/// Rien tant que le deck n'est pas calculé ou qu'aucune carte n'existe.
class GainsSection extends StatelessWidget {
  final String activityId;
  final bool time;
  final Widget Function(BuildContext)? title;
  const GainsSection({super.key, required this.activityId, this.time = true, this.title});

  @override
  Widget build(BuildContext context) {
    final deck = WidgetService.badges?.deck;
    if (deck == null) return const SizedBox.shrink();
    final gains = gainsFor(deck, activityId, time: time);
    if (gains.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title != null) title!(context),
      for (final b in gains) GainRow(b),
    ]);
  }
}
