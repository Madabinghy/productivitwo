import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coach_signals.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/elan_bands.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/held_weeks.dart' show WeekState;
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;
import 'package:productivitwo_v1/utils/project_health.dart' show nextAction;
import 'package:productivitwo_v1/utils/sleep_stats.dart' show clockOf, fmtNight;
import 'package:productivitwo_v1/utils/watch_minimums.dart';
import 'package:productivitwo_v1/utils/week_review.dart';
import 'package:productivitwo_v1/widgets/plan_screen.dart' show showPlanScreen, kWeekPlanEnabled;
import 'package:productivitwo_v1/widgets/watch_minimums_sheet.dart' show setActivityMinimum;
import 'package:productivitwo_v1/widgets/weekly_review_sheet.dart' show showWeeklyReviewSheet;

const kReviewAccent = Color(0xFFA98BF0);
const _kGreen = Color(0xFF4CBF75);
const _kAmber = Color(0xFFF0B44C);
const _kRed = Color(0xFFE5675B);
const _kNight = Color(0xFF7FB2E8);

const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

String _dayMonth(String ymd) {
  final p = ymd.split('-').map(int.parse).toList();
  return '${p[2]} ${_months[p[1] - 1]}';
}

/// Revue du dimanche (maquette validée 2026-11-01) : ce qui a tenu, ce qui a
/// avancé, ce qui a coûté (trancher), le cap — puis « Poser la semaine ».
Future<void> showWeekReviewScreen(BuildContext context, AppLogic logic, {BadgeCenter? badges}) {
  return Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => WeekReviewScreen(logic: logic, badges: badges)));
}

class WeekReviewScreen extends StatefulWidget {
  final AppLogic logic;
  final BadgeCenter? badges;
  const WeekReviewScreen({super.key, required this.logic, this.badges});

  @override
  State<WeekReviewScreen> createState() => _WeekReviewScreenState();
}

class _WeekReviewScreenState extends State<WeekReviewScreen> {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => logic.sync ?? FirestoreSync();

  int _step = 0;
  late final String _monday = reviewedMonday(DateTime.now(), logic.dayStartMin);
  late final List<String> _days = weekDays(_monday);
  List<DailySchedule> _schedules = const [];
  final _intention = TextEditingController();
  final Map<String, String> _decided = {}; // clé de la décision → texte retenu
  final Set<String> _kept = {};

  @override
  void initState() {
    super.initState();
    final prev = logic.weekReviews[_monday];
    if (prev != null) _intention.text = prev.intention;
    _load();
  }

  @override
  void dispose() {
    _intention.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = _days.first.split('-').map(int.parse).toList();
      final from = ymdOf(DateTime(p[0], p[1], p[2] - 3));
      final s = await sync.fetchDailySchedulesRange(from, _days.last);
      if (mounted) setState(() => _schedules = s);
    } catch (_) {}
  }

  Map<String, dynamic> _signals() => coachSignals(
        now: DateTime.now(),
        dayStartMin: logic.dayStartMin,
        activities: logic.state.activities,
        sessions: logic.state.sessions,
        hits: logic.state.habitHits,
        schedules: _schedules,
        paroles: logic.paroles,
        projects: logic.currentProjects,
        marks: logic.state.moodMarks,
        frozenOf: (a) => logic.frozenOf(a.id),
        acquired: logic.acquired,
        days: _days,
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final steps = [_held, _advanced, _costs, _cap];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(_step == 0 ? Icons.close_rounded : Icons.chevron_left_rounded),
          onPressed: () => _step == 0 ? Navigator.of(context).pop() : setState(() => _step--),
        ),
        title: Row(children: [
          for (var i = 0; i < 4; i++)
            Expanded(
              child: Container(
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(color: i <= _step ? kReviewAccent : cs.onSurface.withValues(alpha: .12), borderRadius: BorderRadius.circular(2)),
              ),
            ),
          const SizedBox(width: 10),
          Text('${_step + 1}/4', style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .55))),
        ]),
      ),
      body: SafeArea(child: steps[_step](cs)),
    );
  }

  Widget _page(ColorScheme cs, List<Widget> children, {required String button, required VoidCallback onButton, Widget? footer}) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          ...children,
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kReviewAccent, foregroundColor: const Color(0xFF14101F), minimumSize: const Size.fromHeight(50)),
            onPressed: onButton,
            child: Text(button, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          if (footer != null) footer,
        ],
      );

  Widget _title(String t) => Padding(padding: const EdgeInsets.only(top: 4, bottom: 4), child: Text(t, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1.2)));

  Widget _sub(ColorScheme cs, String t) => Text(t, style: TextStyle(fontSize: 13.5, color: cs.onSurface.withValues(alpha: .6)));

  Widget _sec(ColorScheme cs, String t, [String? right]) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: Row(children: [
          Expanded(child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: cs.onSurface.withValues(alpha: .55)))),
          if (right != null) Text(right, style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: .5))),
        ]),
      );

  Widget _row(ColorScheme cs, String k, String v, {List<Color?>? dots, Color? color}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.onSurface.withValues(alpha: .07)))),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(fontSize: 14.5))),
          if (dots != null)
            SizedBox(
              width: 96,
              child: Row(children: [
                for (final c in dots)
                  Expanded(
                    child: Container(
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(color: c ?? cs.onSurface.withValues(alpha: .08), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
              ]),
            ),
          const SizedBox(width: 10),
          Text(v, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: color)),
        ]),
      );

  // ── 1 · Ce qui a tenu ─────────────────────────────────────────────────────

  Widget _held(ColorScheme cs) {
    final sig = _signals();
    List<bool?> bools(Object? v) => [for (final x in (v as List? ?? const [])) x is bool ? x : null];
    Color? tri(bool? b) => b == null ? null : (b ? _kGreen : _kRed);
    String ratio(List<bool?> d) => '${d.where((x) => x == true).length}/${d.where((x) => x != null).length}';
    final metro = bools((sig['metronome'] as Map)['days']);
    final watch = bools((sig['watch'] as Map)['days']);
    final parole = bools((sig['parole'] as Map)['days']);
    final cap = [for (final x in ((sig['cap'] as Map)['days'] as List)) x as String?];
    final today = ymdOf(livedDate(DateTime.now(), logic.dayStartMin));
    final perfect = logic.embers.perfectYmds.where(_days.contains).length;
    final week = widget.badges?.deck?.weeks.weeks.where((w) => w.monday == _monday).firstOrNull;
    final streak = widget.badges?.deck?.weeks.current ?? 0;
    String verdict;
    String detail;
    if (week == null || week.pct == null) {
      verdict = 'La semaine du ${_dayMonth(_days.first)} au ${_dayMonth(_days.last)}';
      detail = 'Pas de contrat de routines mesurable cette semaine.';
    } else {
      final pct = (week.pct! * 100).round();
      final held = week.state == WeekState.held || (week.state == WeekState.current && pct >= 80);
      verdict = held ? 'Semaine tenue · contrat à $pct %' : 'Contrat à $pct % · semaine pas tenue';
      detail = held
          ? (streak > 0 ? '${streak + (week.state == WeekState.current ? 1 : 0)}ᵉ semaine tenue d’affilée' : 'Une semaine tenue forge une braise')
          : 'Il faut 80 % pour tenir la semaine.';
    }
    final sleep = sig['sleep'] as Map;
    final nights = [for (final n in (sleep['nights'] as List? ?? const [])) (n as num?)?.toInt()];
    final target = (sleep['targetMin'] as num?)?.toInt() ?? 450;
    final shortN = nights.whereType<int>().where((n) => n < target - 30).length;
    final avg = (sleep['avgMin'] as num?)?.toInt();
    final byYmd = {for (final s in _schedules) s.date: s};
    final marks = logic.elanMarksWithRecharge(byYmd);
    final share = modeShareOf([for (final d in _days) elanCellsOfDay(marks, d, DateTime.now(), logic.dayStartMin)]);
    return _page(cs, [
      _sub(cs, 'Semaine du ${_dayMonth(_days.first)} au ${_dayMonth(_days.last)}${_days.contains(today) ? ' · aujourd’hui compris' : ''}'),
      _title(verdict),
      _sub(cs, detail),
      _sec(cs, 'TES JEUX', 'une case par jour'),
      _row(cs, '🎵 Métronome', ratio(metro), dots: [for (final d in metro) tri(d)]),
      _row(cs, '⌚ Montre suisse', ratio(watch), dots: [for (final d in watch) tri(d)]),
      _row(cs, '🤝 Parole tenue', ratio(parole), dots: [for (final d in parole) tri(d)]),
      _row(cs, '🧭 Posé la veille', '${cap.where((x) => x != null).length}/7',
          dots: [for (final x in cap) x == null ? null : (x == 'held' ? _kGreen : _kAmber)]),
      _row(cs, '☀ Journées parfaites', '$perfect'),
      _sec(cs, 'TON CORPS ET TON ÉLAN'),
      _row(cs, '🌙 Sommeil', avg == null ? 'pas de nuit chronométrée' : '${fmtNight(avg)} · $shortN nuit${shortN > 1 ? 's' : ''} courte${shortN > 1 ? 's' : ''}',
          color: avg != null && avg < target - 30 ? _kAmber : null,
          dots: [for (final n in nights) n == null ? null : (n < target - 30 ? _kAmber : _kNight)]),
      _row(cs, 'Ton temps dit',
          share.said == 0 ? 'rien de dit' : 'Normal ${share.pct(BandMode.normal)} % · Flemme ${share.pct(BandMode.low)} % · En forme ${share.pct(BandMode.high)} %'),
    ], button: 'Suivant', onButton: () => setState(() => _step = 1));
  }

  // ── 2 · Ce qui a avancé ───────────────────────────────────────────────────

  Widget _advanced(ColorScheme cs) {
    final weeks = projectWeeks(logic.currentProjects, _days, logic.dayStartMin).where((w) => !w.project.paused).toList();
    final actions = weeks.fold<int>(0, (s, w) => s + w.actions);
    final tasks = weeks.fold<int>(0, (s, w) => s + w.tasks);
    final own = logic.state.activities
        .expand((a) => a.ownActions)
        .where((a) => a.done && a.doneAt != null && _days.contains(ymdOf(livedDate(a.doneAt!, logic.dayStartMin))))
        .length;
    final minutes = minutesByDomainOf(logic.state.sessions, logic.state.activities, _days, DateTime.now());
    final domains = logic.state.activeDomains;
    final byDomain = [
      for (final d in domains)
        if ((minutes[d.id] ?? 0) > 0) (d, minutes[d.id]!),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final maxMin = byDomain.isEmpty ? 1 : byDomain.first.$2;
    final gained = <String>[];
    for (final b in widget.badges?.deck?.badges ?? const []) {
      for (var i = 0; i < b.tierDates.length; i++) {
        final t = b.tierDates[i];
        if (t != null && _days.contains(ymdOf(t))) gained.add(i < b.def.tiers.length && b.def.tiers.length > 1 ? '${b.def.name} ${b.def.tiers[i]}' : b.def.name);
      }
    }
    final shown = [...weeks.where((w) => w.actions > 0), ...weeks.where((w) => w.actions == 0).take(3)];
    return _page(cs, [
      _title('${actions + own} action${actions + own > 1 ? 's' : ''} faite${actions + own > 1 ? 's' : ''}, $tasks tâche${tasks > 1 ? 's' : ''} finie${tasks > 1 ? 's' : ''}'),
      if (own > 0) _sub(cs, 'dont $own action${own > 1 ? 's' : ''} hors projet'),
      _sec(cs, 'TES PROJETS', 'actions cette semaine'),
      if (shown.isEmpty) _sub(cs, 'Aucun projet actif.'),
      for (final w in shown)
        _row(
          cs,
          w.project.title,
          '${w.actions}',
          color: w.actions == 0 ? _kAmber : null,
        ),
      if (weeks.any((w) => w.actions == 0)) Padding(padding: const EdgeInsets.only(top: 4), child: _sub(cs, 'En ambre : rien coché cette semaine.')),
      _sec(cs, 'TON TEMPS', 'par domaine'),
      if (byDomain.isEmpty) _sub(cs, 'Aucun chrono cette semaine.'),
      for (final (d, m) in byDomain)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(width: 110, child: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: m / maxMin, minHeight: 8, color: domainColor(d.id, domains) ?? kReviewAccent, backgroundColor: cs.onSurface.withValues(alpha: .07)),
              ),
            ),
            SizedBox(width: 64, child: Text(fmtMin(m), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
          ]),
        ),
      _sec(cs, 'BADGES', 'gagnés cette semaine'),
      _sub(cs, gained.isEmpty ? 'Aucun palier cette semaine.' : gained.join(' · ')),
    ], button: 'Suivant', onButton: () => setState(() => _step = 2));
  }

  // ── 3 · Ce qui a coûté · décider ──────────────────────────────────────────

  List<ReviewDecision> _decisions() {
    final out = <ReviewDecision>[];
    final blockers = watchBlockers(
        activities: logic.state.activities, sessions: logic.state.sessions, now: DateTime.now(), frozenOf: (a) => logic.frozenOf(a.id));
    if (blockers.isNotEmpty) {
      final b = blockers.first;
      out.add(ReviewDecision(ReviewDecisionKind.minimum, '${b.activity.name} t’a coûté la Montre suisse ${b.lostDays} soirs',
          'minimum ${fmtMin(b.activity.goalMin)} · tu fais ${fmtMin(b.avgMin)} / j', activityId: b.activity.id, suggestedMin: b.suggestedMin));
    }
    final stalled = stalledProjects(logic.currentProjects, DateTime.now());
    if (stalled.isNotEmpty) {
      final (p, idle) = stalled.first;
      final next = nextAction(p);
      out.add(ReviewDecision(ReviewDecisionKind.stalledProject, '${p.title} : rien depuis $idle jours',
          next == null ? 'aucune action ouverte' : 'prochaine action : ${next.action.title}', project: p));
    }
    final sleep = _signals()['sleep'] as Map;
    final nights = [for (final n in (sleep['nights'] as List? ?? const [])) (n as num?)?.toInt()].whereType<int>().toList();
    final target = (sleep['targetMin'] as num?)?.toInt() ?? 450;
    final shortN = nights.where((n) => n < target - 30).length;
    final avgBed = (sleep['avgBed'] as num?)?.toInt();
    final planned = (sleep['plannedBed'] as num?)?.toInt();
    if (shortN >= 3 && avgBed != null) {
      out.add(ReviewDecision(ReviewDecisionKind.sleep, 'Nuits courtes $shortN sur ${nights.length}, couché·e vers ${clockOf(avgBed)}',
          planned == null ? 'pas de bloc Sommeil au programme' : 'bloc Sommeil à ${clockOf(planned)}', plannedBed: planned ?? avgBed - 30));
    }
    return out.take(3).toList();
  }

  String _key(ReviewDecision d) => '${d.kind.name}:${d.activityId ?? d.project?.id ?? ''}';

  Widget _costs(ColorScheme cs) {
    final ds = _decisions();
    Widget choice(String label, VoidCallback onTap, {bool primary = false, bool chosen = false}) => Padding(
          padding: const EdgeInsets.only(right: 6, top: 6),
          child: chosen
              ? FilledButton.tonal(onPressed: null, child: Text('✓ $label'))
              : OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: primary ? kReviewAccent : null, side: BorderSide(color: primary ? kReviewAccent : cs.outlineVariant)),
                  onPressed: onTap,
                  child: Text(label),
                ),
        );
    Widget card(ReviewDecision d, List<Widget> choices) {
      final k = _key(d);
      final done = _decided[k] ?? (_kept.contains(k) ? 'Garder' : null);
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .05), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          _sub(cs, d.detail),
          if (done != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('✓ $done', style: const TextStyle(color: _kGreen, fontWeight: FontWeight.w700)))
          else
            Wrap(children: choices),
        ]),
      );
    }

    final cards = <Widget>[];
    for (final d in ds) {
      final k = _key(d);
      void keep() => setState(() => _kept.add(k));
      switch (d.kind) {
        case ReviewDecisionKind.minimum:
          final a = logic.state.activities.where((x) => x.id == d.activityId).firstOrNull;
          if (a == null) continue;
          cards.add(card(d, [
            if (d.suggestedMin != null)
              choice('Baisser à ${fmtMin(d.suggestedMin!)}', () {
                setActivityMinimum(context, logic, a, d.suggestedMin!);
                setState(() => _decided[k] = '${a.name} : minimum ${fmtMin(d.suggestedMin!)}');
              }, primary: true),
            choice('Pas de minimum', () {
              setActivityMinimum(context, logic, a, 0);
              setState(() => _decided[k] = '${a.name} : plus de minimum');
            }),
            choice('Garder', keep),
          ]));
        case ReviewDecisionKind.stalledProject:
          final p = d.project!;
          final next = nextAction(p);
          cards.add(card(d, [
            if (next != null)
              choice('Viser lundi', () async {
                final now = livedDate(DateTime.now(), logic.dayStartMin);
                final monday = DateTime(now.year, now.month, now.day + (8 - now.weekday) % 7 + (now.weekday == DateTime.monday ? 7 : 0));
                next.action.focusDate = monday;
                await sync.patchActionOf(p, next.action);
                if (mounted) setState(() => _decided[k] = '${p.title} : « ${next.action.title} » visée lundi');
              }, primary: true),
            choice('Mettre en pause', () async {
              p.paused = true;
              await sync.saveProject(p);
              logic.onChange();
              if (mounted) setState(() => _decided[k] = '${p.title} : en pause');
            }),
            choice('Garder', keep),
          ]));
        case ReviewDecisionKind.sleep:
          final bed = d.plannedBed!;
          cards.add(card(d, [
            choice('Me coucher à ${clockOf(bed)} cette semaine', () => setState(() => _decided[k] = 'Me coucher à ${clockOf(bed)}'), primary: true),
            choice('Garder', keep),
          ]));
      }
    }
    return _page(cs, [
      _title(cards.isEmpty ? 'Rien à trancher cette semaine' : '${cards.length} chose${cards.length > 1 ? 's' : ''} à trancher'),
      _sub(cs, cards.isEmpty ? 'Ni activité qui coûte la Montre suisse, ni projet endormi, ni nuits courtes.' : 'Une décision par ligne, ou « Garder ». Rien ne bouge sans toi.'),
      ...cards,
      _sec(cs, 'MISE AU CLAIR', 'idées, projets en sommeil, tâches à classer'),
      OutlinedButton.icon(
        onPressed: () => showWeeklyReviewSheet(context, sync),
        icon: const Icon(Icons.cleaning_services_outlined, size: 18),
        label: const Text('Ouvrir la mise au clair'),
      ),
    ], button: 'Suivant', onButton: () => setState(() => _step = 3));
  }

  // ── 4 · Le cap ────────────────────────────────────────────────────────────

  Widget _cap(ColorScheme cs) {
    final decisions = _decided.values.toList();
    return _page(cs, [
      _title('Et la semaine prochaine ?'),
      _sub(cs, 'Une phrase, si tu veux. Elle revient la semaine prochaine en tête d’Aujourd’hui.'),
      const SizedBox(height: 10),
      TextField(
        controller: _intention,
        maxLines: 2,
        maxLength: 140,
        decoration: InputDecoration(
          hintText: 'Me coucher avant minuit, finir la maquette…',
          filled: true,
          fillColor: cs.onSurface.withValues(alpha: .05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
      if (decisions.isNotEmpty) ...[
        _sec(cs, 'CE QUE TU AS DÉCIDÉ'),
        for (final d in decisions) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('✓ $d', style: const TextStyle(fontSize: 14))),
      ],
    ],
        button: kWeekPlanEnabled ? 'Poser la semaine →' : 'Terminer la revue',
        onButton: () => _finish(plan: kWeekPlanEnabled),
        footer: kWeekPlanEnabled ? TextButton(onPressed: () => _finish(plan: false), child: const Text('Terminer sans poser la semaine')) : null);
  }

  Future<void> _finish({required bool plan}) async {
    await logic.saveWeekReview(_monday, WeekReview(DateTime.now(), intention: _intention.text, decisions: _decided.values.toList()));
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
    if (plan) await showPlanScreen(nav.context, logic, badges: widget.badges, week: true);
  }
}

/// Carte d'entrée en tête d'Aujourd'hui, du samedi 18 h au lundi midi, tant
/// que la revue de la semaine n'est pas faite.
class WeekReviewCard extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback onLater;
  const WeekReviewCard({super.key, required this.onOpen, required this.onLater});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kReviewAccent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kReviewAccent.withValues(alpha: .45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('LA SEMAINE EST FINIE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: kReviewAccent)),
        const SizedBox(height: 4),
        const Text('Revue du dimanche · 10 min', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        Text('Ce qui a tenu, ce qui a coûté, et la semaine prochaine posée.', style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .6))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kReviewAccent, foregroundColor: const Color(0xFF14101F)),
              onPressed: onOpen,
              child: const Text('Faire la revue', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          TextButton(onPressed: onLater, child: const Text('Plus tard')),
        ]),
      ]),
    );
  }
}

/// Rappel de la phrase de la semaine (posée le dimanche d'avant).
class WeekIntentionCard extends StatelessWidget {
  final String intention;
  final VoidCallback onDismiss;
  const WeekIntentionCard({super.key, required this.intention, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(color: kReviewAccent.withValues(alpha: .08), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        const Icon(Icons.flag_outlined, size: 18, color: kReviewAccent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TON CAP DE LA SEMAINE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: cs.onSurface.withValues(alpha: .5))),
            Text('« $intention »', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          ]),
        ),
        IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: onDismiss),
      ]),
    );
  }
}
