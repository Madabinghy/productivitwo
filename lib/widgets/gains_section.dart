import 'package:productivitwo_v1/gamification_flags.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/long_haul.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/badge_cards.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/widget_service.dart';
import 'package:productivitwo_v1/widgets/badge_card.dart' show BadgeCardView, rarityInk;
import 'package:productivitwo_v1/widgets/badge_gallery_screen.dart' show showBadgeSheet;

/// Les cartes qu'une activité ou une routine fait avancer (2026-11-02, retour
/// user : voir la progression vers le prochain gain hors de l'album) : sa
/// série, son compteur, ses heures, l'année et le chemin des 10 000 h.
List<BadgeState> gainsFor(BadgeDeck deck, String activityId, {bool time = true, AppState? state, Iterable<String> objectiveIds = const []}) {
  final ids = [
    'serie-$activityId',
    'fois-$activityId',
    'heures-$activityId',
    if (time) 'heures-annee',
    if (time) 'heures-total',
    for (final o in objectiveIds) 'temps-$o',
  ];
  // Compteurs recalculés EN DIRECT depuis les sessions et coches en mémoire
  // (retour user 2026-11-02 : « 152,4 » ne bougeait qu'à la relance de l'app,
  // le deck n'étant recalculé que de temps en temps). La série reste au deck.
  final live = state == null || !kCollectionMetaEnabled
      ? const <String, BadgeState>{}
      : {for (final b in longHaulBadges(activities: state.activities, habitHits: state.habitHits, sessions: state.sessions, now: DateTime.now())) b.def.id: b};
  return [for (final id in ids) if (live[id] ?? deck.byId(id) case final b?) b];
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

/// Une carte en mini (2026-11-03, retour user : voir les cartes de l'activité
/// dans sa fiche) : la carte elle-même, puis « 152,4 / 250 h » et la jauge
/// vers le prochain cadre, à sa couleur. Tap = fiche de la carte.
class GainCard extends StatelessWidget {
  final BadgeState b;
  final double width;
  const GainCard(this.b, {super.key, this.width = 92});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final next = b.nextTarget;
    final ladder = rarityLadder(b.def);
    final nextRarity = b.level < ladder.length ? ladder[b.level] : rarityOf(b);
    final color = rarityInk(nextRarity);
    final unit = b.def.unit.isEmpty ? '' : ' ${b.def.unit}';
    return Semantics(
      button: true,
      label: '${_label(b)}, ${next == null ? 'tout gagné' : '${_num(b.value)} sur ${fmtInt(next)}$unit'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showBadgeSheet(context, b, deck: WidgetService.badges?.deck),
        child: SizedBox(
          width: width,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            BadgeCardView(state: b, width: width),
            const SizedBox(height: 6),
            Text(_label(b), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            Text(
              next == null ? 'tout gagné' : '${_num(b.value)} / ${fmtInt(next)}$unit',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: .7)),
            ),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: b.progress ?? 1, minHeight: 4, backgroundColor: cs.onSurface.withValues(alpha: .1), color: color),
            ),
            if (next != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('vers ${rarityLabel(nextRarity).toLowerCase()}', maxLines: 1, style: TextStyle(fontSize: 10, color: color)),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Section « CE QUE ÇA FAIT AVANCER » des fiches (activité, routine) : les
/// cartes en mini, dans une rangée qui défile.
/// Rien tant que le deck n'est pas calculé ou qu'aucune carte n'existe.
class GainsSection extends StatelessWidget {
  final String activityId;
  final bool time;
  final Widget Function(BuildContext)? title;
  final AppState? state;
  /// Objectifs qui engagent l'activité : leur carte « temps investi ».
  final Iterable<String> objectiveIds;
  const GainsSection({super.key, required this.activityId, this.time = true, this.title, this.state, this.objectiveIds = const []});

  @override
  Widget build(BuildContext context) {
    final deck = WidgetService.badges?.deck;
    if (deck == null) return const SizedBox.shrink();
    final gains = gainsFor(deck, activityId, time: time, state: state, objectiveIds: objectiveIds);
    if (gains.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title != null) title!(context),
      const SizedBox(height: 4),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final b in gains) Padding(padding: const EdgeInsets.only(right: 12), child: GainCard(b)),
        ]),
      ),
    ]);
  }
}
