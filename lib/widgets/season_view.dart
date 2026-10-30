import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/embers.dart' show EmberEventKind;
import 'package:productivitwo_v1/utils/held_weeks.dart' show WeekState;
import 'package:productivitwo_v1/utils/seasons.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/badge_painter.dart' show kBadgeBrass, kEmberColor;
import 'package:productivitwo_v1/widgets/fiche.dart';

/// Saisons (lot 3, maquette validée « Saisons » 2026-10-30) : carte de
/// l'onglet Objectifs (saison en cours, bilan à voir, ou « Ouvrir une saison »),
/// feuille d'ouverture (trois chasses parmi les propositions) et bilan de fin.

const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
String _short(String ymd) {
  final d = DateTime.parse(ymd);
  return '${d.day} ${_months[d.month - 1]}';
}

TextStyle _eyebrow(Color c) => TextStyle(fontSize: 11, letterSpacing: .6, fontWeight: FontWeight.w700, color: c);

class SeasonCard extends StatefulWidget {
  final AppLogic logic;
  final BadgeCenter center;
  const SeasonCard({super.key, required this.logic, required this.center});

  @override
  State<SeasonCard> createState() => _SeasonCardState();
}

class _SeasonCardState extends State<SeasonCard> {
  /// Le bilan d'une saison close s'ouvre de lui-même une fois par lancement.
  static bool _autoShown = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.center,
      builder: (context, _) {
        final deck = widget.center.deck;
        if (deck == null) return const SizedBox.shrink();
        final today = widget.logic.livedTodayYmd;
        final unseen = unseenBilan(widget.logic.seasons, today);
        final s = widget.logic.season;
        if (unseen != null && s == null && !_autoShown) {
          _autoShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) showSeasonBilan(context, widget.logic, widget.center, unseen);
          });
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: s != null
              ? _running(context, s, deck, today)
              : unseen != null
                  ? _over(context, unseen, deck, today)
                  : _none(context),
        );
      },
    );
  }

  BoxDecoration get _box => BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBLine));

  Widget _none(BuildContext context) {
    final n = widget.logic.seasons.isEmpty ? 1 : widget.logic.seasons.last.n + 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: _box,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SAISON $n', style: _eyebrow(kBText3)),
            const SizedBox(height: 3),
            const Text('Trois chasses pour six semaines', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kBText)),
          ]),
        ),
        TextButton(onPressed: () => showSeasonOpenSheet(context, widget.logic, widget.center), child: const Text('Ouvrir')),
      ]),
    );
  }

  Widget _over(BuildContext context, Season s, BadgeDeck deck, String today) {
    final k = caughtCount(seasonViews(s, deck, today));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: _box.copyWith(border: Border.all(color: kBadgeBrass.withValues(alpha: .45))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SAISON ${s.n} · TERMINÉE', style: _eyebrow(kBadgeBrass)),
            const SizedBox(height: 3),
            Text('$k chasse${k > 1 ? 's' : ''} sur ${s.hunts.length}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kBText)),
          ]),
        ),
        TextButton(onPressed: () => showSeasonBilan(context, widget.logic, widget.center, s), child: const Text('Voir le bilan')),
      ]),
    );
  }

  Widget _running(BuildContext context, Season s, BadgeDeck deck, String today) {
    final views = seasonViews(s, deck, today);
    final live = views.where((v) => v.state != SeasonHuntState.dropped).toList();
    final good = live.where((v) => v.state == SeasonHuntState.caught || v.state == SeasonHuntState.onTrack).length;
    final caught = caughtCount(views);
    final week = s.weekOf(today);
    final left = s.daysLeft(today);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _box,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('SAISON ${s.n}', style: _eyebrow(kBText3))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: kBPrimary.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
            child: Text('semaine $week / ${s.weeks} · reste $left j', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kBPrimary)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('$good chasse${good > 1 ? 's' : ''} sur ${s.hunts.length} en bonne voie', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: kBText)),
        const SizedBox(height: 2),
        Text('${_short(s.start)} → ${_short(s.end)}${caught > 0 ? ' · déjà $caught attrapée${caught > 1 ? 's' : ''}' : ''}',
            style: const TextStyle(fontSize: 13, color: kBText3)),
        const SizedBox(height: 10),
        Row(children: [
          for (var i = 1; i <= s.weeks; i++) ...[
            if (i > 1) const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: i < week ? kBPrimary : (i == week ? kBPrimary.withValues(alpha: .35) : kBRaised),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ]),
        for (final v in views) _huntRow(v, s, today),
        if (live.isNotEmpty && live.any((v) => v.state != SeasonHuntState.caught))
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => _drop(context, s, live), child: const Text('Lâcher une chasse')),
          ),
      ]),
    );
  }

  Widget _huntRow(SeasonHuntView v, Season s, String today) {
    final (String chip, Color color) = switch (v.state) {
      SeasonHuntState.caught => ('attrapée ✓', kBadgeBrass),
      SeasonHuntState.onTrack => ('en bonne voie', kBPrimary),
      SeasonHuntState.push => ('à pousser', kBAttention),
      SeasonHuntState.dropped => ('lâchée', kBText4),
      SeasonHuntState.missed => ('manquée', kBText4),
    };
    final unit = v.badge?.def.unit ?? '';
    final right = v.state == SeasonHuntState.caught && v.caughtOn != null
        ? 'le ${v.caughtOn!.day} ${_months[v.caughtOn!.month - 1]}'
        : v.state == SeasonHuntState.dropped
            ? ''
            : 'encore ${fmtInt((v.target - v.value).clamp(0, v.target))}${unit.isEmpty ? '' : ' $unit'}';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(v.name, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: v.state == SeasonHuntState.dropped ? kBText4 : kBText))),
          Text(chip, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          return SizedBox(
            height: 10,
            child: Stack(children: [
              Positioned(left: 0, right: 0, top: 2, height: 6, child: Container(decoration: BoxDecoration(color: kBRaised, borderRadius: BorderRadius.circular(3)))),
              Positioned(
                left: 0,
                top: 2,
                height: 6,
                width: w * v.progress,
                child: Container(decoration: BoxDecoration(color: v.state == SeasonHuntState.caught ? kBadgeBrass : kBPrimary, borderRadius: BorderRadius.circular(3))),
              ),
              if (v.state == SeasonHuntState.onTrack || v.state == SeasonHuntState.push)
                Positioned(left: (w * s.elapsed(today)).clamp(0, w - 2), top: 0, width: 2, height: 10, child: Container(color: kBText2)),
            ]),
          );
        }),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
              child: Text(v.target > 0 ? '${fmtInt(v.value.clamp(0, v.target))} / ${fmtInt(v.target)}${unit.isEmpty ? '' : ' $unit'}' : '',
                  style: const TextStyle(fontSize: 12, color: kBText3))),
          Text(right, style: const TextStyle(fontSize: 12, color: kBText3)),
        ]),
      ]),
    );
  }

  Future<void> _drop(BuildContext context, Season s, List<SeasonHuntView> live) async {
    final open = live.where((v) => v.state != SeasonHuntState.caught).toList();
    final pick = await showModalBottomSheet<SeasonHuntView>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Lâcher une chasse ?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Elle comptera comme non réussie. Elle ne peut pas être remplacée.', style: TextStyle(fontSize: 13, color: kBText3)),
          ),
          for (final v in open) ListTile(title: Text(v.name), onTap: () => Navigator.pop(c, v)),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (pick == null) return;
    await widget.logic.dropSeasonHunt(pick.hunt.badgeId);
  }
}

/// Feuille « Saison n · trois chasses pour six semaines ».
Future<void> showSeasonOpenSheet(BuildContext context, AppLogic logic, BadgeCenter center) async {
  final deck = center.deck ?? await center.load();
  final picks = seasonPicks(deck, engagedRoutineIds: deck.weeks.engagedNow);
  final today = logic.livedTodayYmd;
  final n = logic.seasons.isEmpty ? 1 : logic.seasons.last.n + 1;
  final end = seasonEndFor(today);
  final hadHunts = logic.badgeHunts.isNotEmpty;
  if (!context.mounted) return;
  // Chasse choisie → palier visé (une série peut viser plus haut que son prochain palier).
  final chosen = <String, int>{};
  final expanded = <SeasonPickGroup>{};
  const shown = 4;
  final ok = await showFiche<bool>(
    context,
    builder: (ctx, scroll) => StatefulBuilder(builder: (ctx, setSt) {
      Widget row(SeasonPick p) {
        final id = p.badge.def.id;
        final on = chosen.containsKey(id);
        final t = chosen[id] ?? p.tier;
        final full = !on && chosen.length >= kSeasonHunts;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Opacity(
            opacity: full ? .5 : 1,
            child: Material(
              color: on ? kBActive : Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: on ? kBPrimary : kBLine)),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: full
                    ? null
                    : () => setSt(() {
                          if (on) {
                            chosen.remove(id);
                          } else {
                            chosen[id] = p.tier;
                          }
                        }),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(children: [
                    Icon(on ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: on ? kBPrimary : kBText4, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.labelOf(t), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kBText)),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                              value: (p.badge.value / p.targetOf(t)).clamp(0.0, 1.0).toDouble(), minHeight: 4, backgroundColor: kBRaised, color: kBPrimary),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    // Palier visé : touche pour viser plus haut (paliers tenables en six semaines).
                    if (on && p.tiers.length > 1)
                      OutlinedButton(
                        onPressed: () => setSt(() => chosen[id] = p.nextTier(t)),
                        style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            foregroundColor: kBPrimary,
                            side: const BorderSide(color: kBPrimary)),
                        child: Text('${fmtInt(p.targetOf(t))}${p.badge.def.unit.isEmpty ? '' : ' ${p.badge.def.unit}'} ▾', style: const TextStyle(fontSize: 12.5)),
                      )
                    else
                      Text(p.remainingOf(t), style: const TextStyle(fontSize: 12, color: kBText2)),
                  ]),
                ),
              ),
            ),
          ),
        );
      }

      Widget group(SeasonPickGroup g, String title) {
        final items = picks.where((p) => p.group == g).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        final open = expanded.contains(g) || items.length <= shown + 1;
        // Les choisies restent visibles même repliées.
        final visible = open ? items : [...items.take(shown), ...items.skip(shown).where((p) => chosen.containsKey(p.badge.def.id))];
        final hidden = items.length - visible.length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text('$title · ${items.length}', style: _eyebrow(kBText3))),
          for (final p in visible) row(p),
          if (hidden > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => setSt(() => expanded.add(g)), child: Text('Afficher les $hidden autres')),
            ),
        ]);
      }

      return Column(children: [
        Expanded(
          child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
            Text('SAISON $n', style: _eyebrow(kBText3)),
            const SizedBox(height: 4),
            const Text('Trois chasses pour six semaines', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: kBText)),
            const SizedBox(height: 2),
            Text('${_short(today)} → ${_short(end)} · ${chosen.length} / $kSeasonHunts choisie${chosen.length > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 13, color: kBText3)),
            const SizedBox(height: 2),
            const Text('Une fois choisie, le bouton du palier (« 7 j ▾ ») vise plus haut.', style: TextStyle(fontSize: 12, color: kBText4)),
            if (picks.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text('Aucun palier à portée pour l’instant : tiens quelques routines ou pose un objectif, puis reviens.',
                    style: TextStyle(fontSize: 13, color: kBText3)),
              ),
            group(SeasonPickGroup.objectives, 'DE TES OBJECTIFS'),
            group(SeasonPickGroup.reachable, 'À PORTÉE EN SIX SEMAINES'),
            group(SeasonPickGroup.restart, 'POUR REPARTIR'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kBRaised, borderRadius: BorderRadius.circular(12)),
              child: Text(
                'Figées pour six semaines : tu peux en lâcher une, pas la remplacer.${hadHunts ? ' Elles remplacent tes chasses en cours.' : ''} Le bilan arrive le ${_short(end)} au soir.',
                style: const TextStyle(fontSize: 13, height: 1.35, color: kBText2),
              ),
            ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: chosen.isEmpty ? null : () => Navigator.pop(ctx, true),
                child: Text(chosen.isEmpty ? 'Choisis jusqu’à trois chasses' : 'Ouvrir la saison $n'),
              ),
            ),
          ),
        ),
      ]);
    }),
  );
  if (ok != true) return;
  await logic.openSeason([
    for (final p in picks)
      if (chosen[p.badge.def.id] case final t?) SeasonHunt(badgeId: p.badge.def.id, tier: t, name: p.labelOf(t))
  ]);
  center.load(refresh: true);
}

/// Bilan d'une saison close : les chasses, ce que la saison a donné, la suite.
Future<void> showSeasonBilan(BuildContext context, AppLogic logic, BadgeCenter center, Season s) async {
  final deck = center.deck ?? await center.load();
  final today = logic.livedTodayYmd;
  final views = seasonViews(s, deck, today);
  final k = caughtCount(views);
  final won = wonSeasons(logic.seasons, deck, today).length;
  final heldWeeks = deck.weeks.weeks.where((w) => w.monday.compareTo(s.start) >= 0 && w.sunday.compareTo(s.end) <= 0);
  final held = heldWeeks.where((w) => w.state == WeekState.held).length;
  final closedWeeks = heldWeeks.where((w) => w.state == WeekState.held || w.state == WeekState.missed).length;
  final ev = deck.embers.history.where((e) => e.ymd.compareTo(s.start) >= 0 && e.ymd.compareTo(s.end) <= 0);
  final forged = ev.where((e) => e.kind == EmberEventKind.earned).length;
  final spent = ev.where((e) => e.kind == EmberEventKind.spent).length;
  final tiers = tiersDuring(s, deck);
  if (!context.mounted) return;
  await logic.markSeasonBilanSeen(s);
  if (!context.mounted) return;
  final next = await showFiche<bool>(
    context,
    builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Text('${_short(s.start)} → ${_short(s.end)} · ${s.weeks} semaines', style: const TextStyle(fontSize: 13, color: kBText3)),
      const SizedBox(height: 6),
      Text('SAISON ${s.n} · TERMINÉE', style: _eyebrow(kBadgeBrass)),
      const SizedBox(height: 4),
      Text('$k chasse${k > 1 ? 's' : ''} sur ${s.hunts.length}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: kBText)),
      Text(
          k >= kSeasonWinHunts
              ? 'La saison compte pour le badge Saisons ($won réussie${won > 1 ? 's' : ''}).'
              : 'Il en fallait $kSeasonWinHunts pour le badge Saisons.',
          style: const TextStyle(fontSize: 14, color: kBText2)),
      const FicheTitle('LES CHASSES'),
      for (final v in views)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: kBLine)),
            child: Row(children: [
              Icon(v.state == SeasonHuntState.caught ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: v.state == SeasonHuntState.caught ? kBadgeBrass : kBText4, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kBText)),
                  Text(
                    switch (v.state) {
                      SeasonHuntState.caught when v.caughtOn != null => 'attrapée le ${v.caughtOn!.day} ${_months[v.caughtOn!.month - 1]}',
                      SeasonHuntState.dropped => 'lâchée en route',
                      _ => v.target > 0 ? 'arrêtée à ${fmtInt(v.value.clamp(0, v.target))} / ${fmtInt(v.target)} · elle peut revenir' : 'pas attrapée',
                    },
                    style: const TextStyle(fontSize: 12.5, color: kBText3),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      const FicheTitle('CE QUE LA SAISON A DONNÉ'),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.4,
        children: [
          _stat(closedWeeks == 0 ? '—' : '$held / $closedWeeks', 'semaines tenues', kBadgeBrass),
          _stat('+$forged · −$spent', 'braises forgées · dépensées', kEmberColor),
          _stat('${tiers.length}', 'palier${tiers.length > 1 ? 's' : ''} obtenu${tiers.length > 1 ? 's' : ''}', kBText),
          _stat('$k / ${s.hunts.length}', 'chasses attrapées', kBPrimary),
        ],
      ),
      if (tiers.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Paliers obtenus : ${tiers.join(', ')}.', style: const TextStyle(fontSize: 13, color: kBText2)),
        ),
      const SizedBox(height: 20),
      SizedBox(
        height: 50,
        child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Préparer la saison ${s.n + 1}')),
      ),
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Plus tard')),
    ]),
  );
  if (next == true && context.mounted) await showSeasonOpenSheet(context, logic, center);
}

Widget _stat(String v, String k, Color color) => Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        Text(k, style: const TextStyle(fontSize: 12, color: kBText3), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
