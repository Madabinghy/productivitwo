import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'dart:async';

import 'package:productivitwo_v1/utils/badge_hunt.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/embers.dart' show EmberSpend;
import 'package:productivitwo_v1/utils/mode.dart' show parseRestDomains;
import 'package:productivitwo_v1/utils/rest_periods.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/utils/objective_trajectory.dart' show isReadingDue;
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/badge_gallery_screen.dart' show showBadgeSheet;
import 'package:productivitwo_v1/widgets/badge_painter.dart';

/// Chasses sur le web : `data/meta.badgeHunts` suivi en temps réel, écrit par
/// `setBadgeHunts` (même règle que le mobile : trois au plus).
class WebHuntStore extends ChangeNotifier implements HuntStore {
  final FirestoreSync sync;
  StreamSubscription<Map<String, dynamic>>? _sub;
  List<BadgeHunt> _hunts = const [];
  /// Rallumages par les braises (`data/meta.emberSpends`) : les séries du web
  /// comptent les mêmes jours comblés que le mobile.
  List<EmberSpend> emberSpends = const [];
  /// Veilles (`restDomains`, `restPeriods`) : mêmes séries gelées que le mobile.
  List<RestPeriod> restPeriods = const [];
  Map<String, String> restDomains = const {};
  WebHuntStore(this.sync) {
    _sub = sync.streamMetaDoc().listen((m) {
      _hunts = parseBadgeHunts(m['badgeHunts']);
      emberSpends = EmberSpend.listFrom(m['emberSpends']);
      restPeriods = parseRestPeriods(m['restPeriods']);
      restDomains = parseRestDomains(m['restDomains']);
      notifyListeners();
    });
  }

  @override
  List<BadgeHunt> get hunts => _hunts;

  @override
  Future<void> hunt(BadgeHunt h) async {
    final list = [..._hunts.where((x) => x.badgeId != h.badgeId), h];
    if (list.length > kMaxBadgeHunts) return;
    _hunts = list;
    notifyListeners();
    await sync.setBadgeHunts(list.map((x) => x.toJson()).toList());
  }

  @override
  Future<void> stop(Iterable<String> badgeIds) async {
    final ids = badgeIds.toSet();
    if (!_hunts.any((x) => ids.contains(x.badgeId))) return;
    _hunts = _hunts.where((x) => !ids.contains(x.badgeId)).toList();
    notifyListeners();
    await sync.setBadgeHunts(_hunts.map((x) => x.toJson()).toList());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Le deck du web, partagé par la carte BADGES et les enjeux d'Aujourd'hui :
/// programmes des 400 derniers jours relus toutes les cinq minutes, deck
/// recalculé quand une entrée change.
class WebDeckSource extends ChangeNotifier {
  final FirestoreSync sync;
  WebDeckSource(this.sync);
  List<DailySchedule> schedules = const [];
  DateTime? _fetchedAt;
  BadgeDeck? _deck;
  String _key = '';

  Future<void> fetch() async {
    final now = DateTime.now();
    if (_fetchedAt != null && now.difference(_fetchedAt!) < const Duration(minutes: 5)) return;
    _fetchedAt = now;
    try {
      schedules = await sync.fetchDailySchedulesRange(ymdOf(now.subtract(const Duration(days: 400))), ymdOf(now));
      _key = '';
      notifyListeners();
    } catch (_) {}
  }

  BadgeDeck deck({
    required List<Activity> activities,
    required List<HabitHit> hits,
    required List<Project> projects,
    required List<StrategicObjective> objectives,
    required List<Session> sessions,
    required List<MoodMark> moodMarks,
    required List<ChainRun> chainRuns,
    required int dayStartMin,
    List<EmberSpend> emberSpends = const [],
    List<RestPeriod> restPeriods = const [],
    Map<String, String> restDomains = const {},
  }) {
    final key =
        '${hits.length}|${sessions.length}|${moodMarks.length}|${chainRuns.length}|${projects.length}|${objectives.length}|${schedules.length}|${ymdOf(DateTime.now())}|${emberSpends.length}|${restPeriods.length}|$restDomains';
    if (_deck != null && key == _key) return _deck!;
    _key = key;
    return _deck = computeBadges(
      activities: activities,
      habitHits: hits,
      schedules: schedules,
      projects: projects,
      objectives: objectives,
      sessions: sessions,
      moodMarks: moodMarks,
      chainRuns: chainRuns,
      now: DateTime.now(),
      dayStartMin: dayStartMin,
      emberSpends: emberSpends,
      restPeriods: restPeriods,
      restDomains: restDomains,
    );
  }
}

/// Badges sur le web (2026-10) : module « BADGES » de la colonne de droite
/// d'Aujourd'hui (compteur hors séries, séries en cours, bande de six badges,
/// « Voir le deck ») et le deck complet en dialog. Le deck se calcule ici
/// depuis les flux du web (hits, sessions, pointages, sessions d'Enchaîner) et
/// les programmes des 400 derniers jours, relus toutes les cinq minutes.
class WebBadgesCard extends StatefulWidget {
  final FirestoreSync sync;
  final List<Activity> activities;
  final List<Project> projects;
  final List<StrategicObjective> objectives;
  final List<HabitHit> hits;
  final List<Session> sessions;
  final List<MoodMark> moodMarks;
  final List<ChainRun> chainRuns;
  final int dayStartMin;
  final bool folded;
  final VoidCallback onToggleFold;
  final WebHuntStore? huntStore;
  final List<ScheduleBlock> todayBlocks;
  /// Source partagée du deck (Aujourd'hui) ; sans elle, la carte a la sienne.
  final WebDeckSource? source;
  const WebBadgesCard({
    super.key,
    required this.sync,
    required this.activities,
    required this.projects,
    required this.objectives,
    required this.hits,
    required this.sessions,
    required this.moodMarks,
    required this.chainRuns,
    required this.dayStartMin,
    required this.folded,
    required this.onToggleFold,
    this.huntStore,
    this.todayBlocks = const [],
    this.source,
  });

  @override
  State<WebBadgesCard> createState() => _WebBadgesCardState();
}

class _WebBadgesCardState extends State<WebBadgesCard> {
  late WebDeckSource _source;
  bool _own = false;

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? WebDeckSource(widget.sync);
    _own = widget.source == null;
    _source.addListener(_onHunts);
    widget.huntStore?.addListener(_onHunts);
    _source.fetch();
  }

  @override
  void dispose() {
    _source.removeListener(_onHunts);
    if (_own) _source.dispose();
    widget.huntStore?.removeListener(_onHunts);
    super.dispose();
  }

  void _onHunts() {
    if (mounted) setState(() {});
  }

  BadgeDeck _deckOf() => _source.deck(
        activities: widget.activities,
        hits: widget.hits,
        projects: widget.projects,
        objectives: widget.objectives,
        sessions: widget.sessions,
        moodMarks: widget.moodMarks,
        chainRuns: widget.chainRuns,
        dayStartMin: widget.dayStartMin,
        emberSpends: widget.huntStore?.emberSpends ?? const [],
        restPeriods: widget.huntStore?.restPeriods ?? const [],
        restDomains: widget.huntStore?.restDomains ?? const {},
      );

  @override
  Widget build(BuildContext context) {
    final deck = _deckOf();
    final all = deck.badges;
    final acquired = all.where((b) => b.acquired).toList()..sort((a, b) => (b.obtained ?? DateTime(2000)).compareTo(a.obtained ?? DateTime(2000)));
    final locked = all.where((b) => !b.acquired && b.showGauge && b.def.measured).toList();
    final strip = [...acquired, ...locked].take(6).toList();
    final store = widget.huntStore;
    final views = store == null ? const <HuntView>[] : huntViews(store.hunts, deck);
    // Chasses attrapées : sortent toutes seules (même règle que BadgeCenter).
    final caught = views.where((v) => v.caught).map((v) => v.badge.def.id).toList();
    if (caught.isNotEmpty) store!.stop(caught);
    final open = views.where((v) => !v.caught).toList();
    return Container(
      padding: widget.folded ? const EdgeInsets.fromLTRB(20, 14, 20, 14) : const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onToggleFold,
          child: Row(children: [
            const Icon(Icons.military_tech_outlined, size: 15, color: kBadgeBrass),
            const SizedBox(width: 6),
            const Text('BADGES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3)),
            const SizedBox(width: 8),
            Text('${deck.acquired} / ${deck.total}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kBadgeBrass)),
            if (deck.seriesRunning > 0) ...[
              const SizedBox(width: 8),
              Expanded(child: Text('· ${deck.seriesRunning} série${deck.seriesRunning > 1 ? 's' : ''} en cours', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kBText3))),
            ] else
              const Spacer(),
            Icon(widget.folded ? Icons.expand_more : Icons.expand_less, size: 18, color: kBText4),
          ]),
        ),
        if (!widget.folded) ...[
          const SizedBox(height: 12),
          Row(children: [
            for (final b in strip)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Tooltip(
                  message: b.def.name,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => showBadgeSheet(context, b, logic: widget.huntStore),
                    child: Opacity(opacity: b.acquired ? 1 : .55, child: BadgeView(state: b, size: 40)),
                  ),
                ),
              ),
          ]),
          if (open.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Row(children: [
              Icon(Icons.gps_fixed, size: 13, color: kBadgeBrass),
              SizedBox(width: 6),
              Text('BADGES VISÉS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBadgeBrass)),
            ]),
            for (final v in open) _huntRow(v),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: kBPrimary, padding: EdgeInsets.zero),
              onPressed: () => showWebBadgeDeck(context, deck, hunts: widget.huntStore),
              icon: const Icon(Icons.grid_view_rounded, size: 16),
              label: const Text('Voir le deck', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ]),
    );
  }

  /// Une chasse : badge, palier, rythme, levier du jour (règle du mobile).
  Widget _huntRow(HuntView v) {
    final now = DateTime.now();
    final b = v.badge;
    final today = livedDate(now, widget.dayStartMin);
    final todayYmd = ymdOf(today);
    final reachedByRoutine = {
      for (final a in widget.activities)
        if (!a.deleted && a.isHabit && a.habitFreq == HabitFreq.daily) a.id: routineReachedDays(a, widget.hits, dayStartMin: widget.dayStartMin),
    };
    final score = scoreDay(today, activities: widget.activities, reachedDaysByRoutine: reachedByRoutine,
        schedule: DailySchedule(date: todayYmd, generatedBy: 'web', generatedAt: now, blocks: widget.todayBlocks));
    final todayReached = b.def.subjectId != null && (reachedByRoutine[b.def.subjectId]?.contains(todayYmd) ?? false);
    final readingDue = b.def.id == 'releve-fidele' && widget.objectives.any((o) => isReadingDue(o, now));
    final lever = v.lever(todayReached: todayReached, readingDue: readingDue, todayRoutinesDue: score.routinesDue, todayRoutinesReached: score.routinesReached, todayBlocks: score.blocks, todayBlocksDone: score.blocksDone);
    return InkWell(
      onTap: () => showBadgeSheet(context, b, logic: widget.huntStore),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          BadgeView(state: b, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${b.def.name} · ${fmtInt(v.tierValue)}${b.def.unit.isEmpty ? '' : ' ${b.def.unit}'} · ${v.paceLabel(now)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kBText)),
              if (lever.text.isNotEmpty) Text(lever.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: todayReached ? kBPrimary : kBText3)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Le deck complet en dialog (familles, badges à 72 px, fiche au clic).
Future<void> showWebBadgeDeck(BuildContext context, BadgeDeck deck, {HuntStore? hunts}) {
  final last = deck.lastObtained;
  final views = hunts == null ? const <HuntView>[] : huntViews(hunts.hunts, deck).where((v) => !v.caught).toList();
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: kBBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 640,
        height: 720,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(children: [
              const Text('Badges', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kBText)),
              const SizedBox(width: 12),
              Text.rich(TextSpan(children: [
                TextSpan(text: '${deck.acquired}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kBadgeBrass)),
                TextSpan(text: ' sur ${deck.total}', style: const TextStyle(fontSize: 14, color: kBText3)),
              ])),
              const Spacer(),
              if (last != null)
                Row(children: [
                  BadgeView(state: last, size: 32),
                  const SizedBox(width: 8),
                  Text('Dernier obtenu · ${last.def.name}', style: const TextStyle(fontSize: 12.5, color: kBText2)),
                  const SizedBox(width: 12),
                ]),
              IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close, color: kBText3)),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                if (views.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 6),
                    child: Row(children: [
                      Icon(Icons.gps_fixed, size: 13, color: kBadgeBrass),
                      SizedBox(width: 6),
                      Text('EN CHASSE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: kBadgeBrass)),
                    ]),
                  ),
                  for (final v in views)
                    InkWell(
                      onTap: () => showBadgeSheet(ctx, v.badge, logic: hunts),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          BadgeView(state: v.badge, size: 40),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${v.badge.def.name} · palier ${fmtInt(v.tierValue)}${v.badge.def.unit.isEmpty ? '' : ' ${v.badge.def.unit}'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kBText)),
                              Text(v.paceLabel(DateTime.now()), style: const TextStyle(fontSize: 12, color: kBText3)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                ],
                for (final f in BadgeFamily.values)
                  if (deck.ofFamily(f).isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Row(children: [
                        Text(badgeFamilyLabel(f).toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: kBText3)),
                        const Spacer(),
                        Text(
                          f == BadgeFamily.routines
                              ? '${deck.seriesRunning} en cours'
                              : '${deck.ofFamily(f).fold(0, (s, b) => s + b.paliersDone)} / ${deck.ofFamily(f).fold(0, (s, b) => s + b.paliersTotal)}',
                          style: const TextStyle(fontSize: 12, color: kBText4),
                        ),
                      ]),
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 14,
                      children: [
                        for (final b in deck.ofFamily(f))
                          SizedBox(
                            width: 104,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => showBadgeSheet(ctx, b, logic: hunts),
                              child: Column(children: [
                                Opacity(opacity: b.acquired ? 1 : .55, child: BadgeView(state: b, size: 72)),
                                const SizedBox(height: 4),
                                Text(b.def.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12, height: 1.25, fontWeight: b.acquired ? FontWeight.w600 : FontWeight.w400, color: b.acquired ? kBText : kBText3)),
                                Text(_sub(b), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: kBText3)),
                              ]),
                            ),
                          ),
                      ],
                    ),
                  ],
              ],
            ),
          ),
        ]),
      ),
    ),
  );
}

String _sub(BadgeState b) {
  if (!b.def.measured) return 'bientôt';
  if (b.complete) return '${fmtInt(b.def.tiers.last)} ${b.def.unit} · complet';
  if (b.showGauge) return '${b.value == b.value.roundToDouble() ? fmtInt(b.value) : b.value.toStringAsFixed(1).replaceAll('.', ',')} / ${fmtInt(b.nextTarget!)} ${b.def.unit}';
  if (b.acquired && b.obtained != null) return 'le ${b.obtained!.day} ${const ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'][b.obtained!.month - 1]}';
  return 'pas encore';
}
