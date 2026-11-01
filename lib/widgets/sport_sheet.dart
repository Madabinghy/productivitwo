import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/elan_bands.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/fiche_cache.dart';
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;
import 'package:productivitwo_v1/utils/objective_trajectory.dart';
import 'package:productivitwo_v1/utils/sleep_stats.dart' show sleepNightList, SleepNight, fmtNight;
import 'package:productivitwo_v1/utils/sport_stats.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/widgets/objective_readings_card.dart' show noteReadingQuick;
import 'package:productivitwo_v1/widgets/objective_trajectory_sheet.dart' show showObjectiveTrajectorySheet;

const kSportAccent = Color(0xFFF07C4C);
const _kGreen = Color(0xFF4CBF75);
const _kAmber = Color(0xFFF0B44C);
const _kReps = Color(0xFFC58BF0);
const _palette = [Color(0xFF5FC3E4), Color(0xFFF07C4C), Color(0xFF4CA8F0), Color(0xFF8BD17C), Color(0xFFE5C14C), Color(0xFFE57CB0)];
const _dayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

const kRuleSport = GameRule('Le suivi du sport', [
  RuleCard('🏃', 'Une séance', 'Un chrono de 10 min ou plus sur une activité de sport dans la journée (plusieurs chronos de la même activité = une séance), ou le +1 d’une routine de séance comme Footing.'),
  RuleCard('💪', 'Les répétitions', 'Pompes, Tractions : comptées à part. Elles ne font pas une séance à elles seules.'),
  RuleCard('😴', 'Le repos', 'Un jour sans séance. La feuille montre ton plus long repos sur 30 jours.'),
  RuleCard('⚙️', 'Tes activités', 'Par défaut, celles des domaines Sport et Musculation. « Mes activités de sport » pour en ajouter ou en retirer.'),
]);

String _dm(String ymd) {
  final p = ymd.split('-').map(int.parse).toList();
  return '${p[2]} ${_months[p[1] - 1]}';
}

String _plus(String ymd, int days) {
  final p = ymd.split('-').map(int.parse).toList();
  return ymdOf(DateTime(p[0], p[1], p[2] + days));
}

/// Feuille « Sport » (maquette validée 2026-11-01 « Suivi du sport ») : la
/// semaine, les engagements, les répétitions, 8 semaines, le poids, le
/// lendemain d'une séance, 8 semaines en cases ; ▶ lance une séance.
Future<void> showSportSheet(BuildContext context, {required AppLogic logic, required FirestoreSync sync}) {
  return showFiche<void>(context, builder: (ctx, scroll) => SportSheet(logic: logic, sync: sync, scroll: scroll));
}

class SportSheet extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final ScrollController? scroll;
  const SportSheet({super.key, required this.logic, required this.sync, this.scroll});

  @override
  State<SportSheet> createState() => _SportSheetState();
}

class _SportSheetState extends State<SportSheet> {
  AppLogic get logic => widget.logic;
  List<Session> _remote = const [];
  List<StrategicObjective> _objectives = FicheCache.objectives ?? const [];
  List<DailySchedule> _schedules = const [];

  @override
  void initState() {
    super.initState();
    logic.addListener(_onLogic);
    _load();
  }

  @override
  void dispose() {
    logic.removeListener(_onLogic);
    super.dispose();
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final sync = widget.sync;
    final now = DateTime.now();
    try {
      final o = await FicheCache.objectivesFast(sync);
      if (mounted && o != null) setState(() => _objectives = o);
    } catch (_) {}
    try {
      final s = await sync.fetchRecentSessions(66);
      if (mounted) setState(() => _remote = s);
    } catch (_) {}
    try {
      final sc = await sync.fetchDailySchedulesRange(ymdOf(now.subtract(const Duration(days: 32))), ymdOf(now));
      if (mounted) setState(() => _schedules = sc);
    } catch (_) {}
  }

  List<Session> get _sessions {
    final byId = {for (final s in _remote) s.id: s};
    for (final s in logic.state.sessions) {
      byId[s.id] = s;
    }
    return byId.values.toList();
  }

  SportPick get _pick => resolveSportPick(logic.state.activities, logic.state.domains, logic.sportOverrides);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final now = DateTime.now();
    final today = ymdOf(livedDate(now, logic.dayStartMin));
    final pick = _pick;
    final colors = {for (final (i, a) in pick.sessionActivities.indexed) a.id: _palette[i % _palette.length]};

    Widget title(String t, [String? right]) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Row(children: [
            Expanded(child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute))),
            if (right != null) Text(right, style: TextStyle(fontSize: 11.5, color: mute)),
          ]),
        );

    final header = Row(children: [
      const Expanded(child: Text('Sport', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
      const InfoDot(kRuleSport),
    ]);

    if (pick.isEmpty) {
      return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        header,
        const SizedBox(height: 16),
        Text('Aucune activité de sport suivie. Choisis-les : un chrono, une routine de séance ou de répétitions.', style: TextStyle(color: mute)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _openPicker, child: const Text('Mes activités de sport')),
      ]);
    }

    final sessions = _sessions;
    final days = sportDays(
        pick: pick, sessions: sessions, hits: logic.state.habitHits, fromYmd: _plus(today, -70), toYmd: today, now: now, dayStartMin: logic.dayStartMin);
    final sum = sportSummary(days);
    final weeks9 = sportWeeks(days, weeks: 9);
    final weeks = weeks9.sublist(1);
    final decline = sportDecline(weeks9);
    final reps = repsStats(pick, days, logic.state.habitHits, logic.dayStartMin);
    final commitments = sportCommitments(pick, _objectives, sum.week);
    final objective = sportObjective(pick, _objectives);
    final impact = _impact(days, now, today);
    final routinesC = commitments.where((c) => !c.isTime && c.done < c.target).toList();
    final weeklyTarget = commitments.where((c) => c.isTime).fold(0, (s, c) => s + c.target);

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(children: [
          const Expanded(child: Text('Sport', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
          _chip('${sum.weekSessions} séance${sum.weekSessions > 1 ? 's' : ''} cette semaine', sum.weekSessions >= 3 ? _kGreen : _kAmber),
          const SizedBox(width: 6),
          const InfoDot(kRuleSport),
        ]),
        const SizedBox(height: 10),
        _weekCard(cs, sum, colors, pick, today, routinesC),
        const SizedBox(height: 10),
        Row(children: [
          _stat(cs, '${sum.sessions7}', 'séances / 7 j'),
          const SizedBox(width: 8),
          _stat(cs, '${sum.weeksWithThree} / $kSportWeeks', 'semaines à 3 séances'),
          const SizedBox(width: 8),
          _stat(cs, '${sum.longestRest} j', 'plus long repos', color: sum.longestRest >= 4 ? _kAmber : null),
        ]),
        if (commitments.isNotEmpty) ...[
          title('TES ENGAGEMENTS', 'cette semaine'),
          _card(cs, Column(children: [for (final c in commitments) _commitRow(cs, c, colors[c.activity.id] ?? kSportAccent)])),
        ],
        if (reps.isNotEmpty) ...[
          title('RÉPÉTITIONS', 'cette semaine · 8 semaines'),
          _card(cs, Column(children: [for (final r in reps) _repsRow(cs, r)])),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: kSportAccent, foregroundColor: const Color(0xFF1D0F08), minimumSize: const Size.fromHeight(50)),
          onPressed: () => _openLaunch(commitments, sum),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Lancer une séance', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _openPicker, child: const Text('Mes activités de sport ›')),
        ),
        title('8 SEMAINES', 'temps actif par semaine'),
        _card(cs, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: 120, child: _WeeksChart(weeks: weeks, colors: colors, target: weeklyTarget)),
          const SizedBox(height: 4),
          Row(children: [
            Text(_dm(weeks.first.monday), style: TextStyle(fontSize: 10.5, color: mute)),
            const Spacer(),
            Text('cette semaine', style: TextStyle(fontSize: 10.5, color: mute)),
          ]),
          if (weeklyTarget > 0) Text('Pointillés : ton engagement de ${fmtMin(weeklyTarget)} par semaine.', style: TextStyle(fontSize: 12, color: mute)),
          if (decline != null && pick.byId[decline.activityId] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text.rich(TextSpan(style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .8)), children: [
                TextSpan(text: '${pick.byId[decline.activityId]!.name} baisse depuis 4 semaines : '),
                TextSpan(text: '≈ ${fmtMin(decline.recentMin)} par semaine', style: const TextStyle(color: _kAmber, fontWeight: FontWeight.w700)),
                TextSpan(text: ', contre ${fmtMin(decline.priorMin)} avant.'),
              ])),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 4, children: [
            for (final a in pick.sessionActivities) _legend(cs, colors[a.id]!, a.name),
          ]),
        ])),
        if (objective != null) ..._weight(cs, title, objective, sessions, now),
        title('LE LENDEMAIN D\'UNE SÉANCE', '30 jours'),
        _card(cs, _impactView(cs, impact)),
        title('8 SEMAINES EN CASES', 'une case par jour'),
        _card(cs, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Grid(days: days.where((d) => d.ymd.compareTo(_plus(mondayOf(today), -49)) >= 0).toList(), today: today),
          const SizedBox(height: 8),
          Wrap(spacing: 10, children: [
            _legend(cs, _kGreen, 'séance'),
            _legend(cs, const Color(0xFF2F4A3C), 'répétitions seules'),
            _legend(cs, cs.onSurface.withValues(alpha: .08), 'repos'),
          ]),
        ])),
      ],
    );
  }

  SportImpact _impact(List<SportDay> days, DateTime now, String today) {
    final byYmd = {for (final s in _schedules) s.date: s};
    final marks = logic.elanMarksWithRecharge(byYmd);
    final low = <String, double>{};
    for (var i = 0; i <= 31; i++) {
      final y = _plus(today, -i);
      final share = modeShareOf([elanCellsOfDay(marks, y, now, logic.dayStartMin)]);
      if (share.said > 0) low[y] = share.low / share.said;
    }
    final nights = sleepNightList(sessions: _sessions, activities: logic.state.activities, now: now, dayStartMin: logic.dayStartMin, nights: 32);
    final nightAfter = <String, int>{for (final n in nights.whereType<SleepNight>()) _plus(n.nextYmd, -1): n.minutes};
    final last30 = days.sublist(days.length - 31, days.length);
    return sportImpact(last30, low, nightAfter, today);
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
      );

  Widget _card(ColorScheme cs, Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _stat(ColorScheme cs, String v, String l, {Color? color}) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            Text(l, style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: .55))),
          ]),
        ),
      );

  Widget _legend(ColorScheme cs, Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Flexible(child: Text(t, style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: .6)))),
      ]);

  Widget _weekCard(ColorScheme cs, SportSummary sum, Map<String, Color> colors, SportPick pick, String today, List<SportCommitment> routinesLate) {
    final mute = cs.onSurface.withValues(alpha: .55);
    final maxMin = sum.week.fold(60, (m, d) => d.activeMin > m ? d.activeMin : m);
    return _card(cs, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('CETTE SEMAINE · ${_dm(sum.week.first.ymd)} → ${_dm(sum.week.last.ymd)}', style: TextStyle(fontSize: 11, color: mute, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(sum.weekMin == 0 ? 'Rien encore' : '${fmtMin(sum.weekMin)} actives', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
      Text.rich(TextSpan(style: TextStyle(fontSize: 13, color: mute), children: [
        TextSpan(text: '${sum.weekSessions} séance${sum.weekSessions > 1 ? 's' : ''} · ${sum.weekRestDays} jour${sum.weekRestDays > 1 ? 's' : ''} de repos'),
        for (final c in routinesLate) TextSpan(text: ' · ${c.activity.name} ${c.done} / ${c.target}', style: const TextStyle(color: _kAmber)),
      ])),
      const SizedBox(height: 12),
      SizedBox(
        height: 140,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final (i, d) in sum.week.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: d.isRest && d.ymd.compareTo(today) < 0 ? .04 : .07),
                      borderRadius: BorderRadius.circular(8),
                      border: d.ymd == today ? Border.all(color: cs.onSurface.withValues(alpha: .8), width: 1.5) : null,
                    ),
                    child: LayoutBuilder(builder: (ctx, c) {
                      final h = c.maxHeight;
                      return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        for (final a in pick.sessionActivities)
                          if ((d.minutes[a.id] ?? 0) > 0)
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              height: (h * (d.minutes[a.id]! / maxMin)).clamp(4.0, h),
                              decoration: BoxDecoration(color: colors[a.id], borderRadius: BorderRadius.circular(4)),
                            ),
                      ]);
                    }),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 6,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var k = 0; k < d.reps.values.where((v) => v > 0).length.clamp(0, 4); k++)
                      Container(width: 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: const BoxDecoration(color: _kReps, shape: BoxShape.circle)),
                  ]),
                ),
                const SizedBox(height: 3),
                Text(_dayLetters[i], style: TextStyle(fontSize: 11, color: mute)),
              ]),
            ),
          ],
        ]),
      ),
      if (pick.repRoutines.isNotEmpty) ...[
        const SizedBox(height: 8),
        _legend(cs, _kReps, 'un point = une routine de répétitions faite ce jour'),
      ],
    ]));
  }

  Widget _commitRow(ColorScheme cs, SportCommitment c, Color color) {
    final ok = c.done >= c.target;
    final txt = c.isTime ? '${fmtMin(c.done)} / ${fmtMin(c.target)}' : '${c.done} / ${c.target}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.activity.name, style: const TextStyle(fontSize: 14.5)),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: c.ratio.clamp(0.0, 1.0), minHeight: 7, color: color, backgroundColor: cs.onSurface.withValues(alpha: .08)),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Text(ok ? '$txt ✓' : txt, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ok ? _kGreen : (c.ratio < .5 ? _kAmber : null))),
      ]),
    );
  }

  Widget _repsRow(ColorScheme cs, RepsStat r) {
    final maxW = r.weeks.fold(1, (m, v) => v > m ? v : m);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.activity.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            Text('${r.week} / ${r.weekTarget}${r.record > 0 ? ' · record ${r.record} en un jour' : ''}', style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .55))),
          ]),
        ),
        SizedBox(
          width: 84,
          height: 26,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final (i, v) in r.weeks.indexed) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                child: Container(
                  height: (26 * v / maxW).clamp(2.0, 26.0),
                  decoration: BoxDecoration(color: _kReps.withValues(alpha: i == r.weeks.length - 1 ? 1 : .7), borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  List<Widget> _weight(ColorScheme cs, Widget Function(String, [String?]) title, StrategicObjective o, List<Session> sessions, DateTime now) {
    final t = computeObjectiveTrajectory(o, sessions, now);
    final r = t.result;
    final m = o.metric!;
    if (r == null) return const [];
    final mute = cs.onSurface.withValues(alpha: .55);
    String v(double x) => '${x.toStringAsFixed(x == x.roundToDouble() ? 0 : 1).replaceAll('.', ',')} ${m.unit}';
    final delta = r.delta;
    return [
      title('TON ${m.label.toUpperCase()}', 'objectif ${v(m.targetValue)}${o.endDate != null ? ' · ${o.endDate!.day} ${_months[o.endDate!.month - 1]}' : ''}'),
      _card(cs, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: 110, child: CustomPaint(painter: _WeightPainter(o, t, cs.onSurface))),
        const SizedBox(height: 6),
        Text.rich(TextSpan(style: TextStyle(fontSize: 13, color: mute), children: [
          if (r.latestValue != null) TextSpan(text: v(r.latestValue!), style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
          if (r.latestDate != null) TextSpan(text: ' le ${_dm(r.latestDate!)}'),
          TextSpan(text: '${r.latestValue == null ? 'Aucun relevé' : ''} · attendu aujourd\'hui ${v(r.expectedValue)}'),
          if (r.latestValue != null && delta.abs() >= 0.05)
            TextSpan(
                text: delta < 0 ? ' · en retard de ${v(delta.abs())}' : ' · en avance de ${v(delta)}',
                style: TextStyle(color: delta < 0 ? _kAmber : _kGreen)),
        ])),
        Row(children: [
          TextButton(
            onPressed: () async {
              if (await noteReadingQuick(context, sync: widget.sync, objective: o)) {
                final all = await FicheCache.loadObjectives(widget.sync);
                if (mounted) setState(() => _objectives = all);
              }
            },
            child: const Text('Noter un relevé'),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => showObjectiveTrajectorySheet(context, logic: logic, sync: widget.sync, objective: o, projects: logic.currentProjects),
            child: const Text('Fiche de l\'objectif ›'),
          ),
        ]),
      ])),
    ];
  }

  Widget _impactView(ColorScheme cs, SportImpact i) {
    final mute = cs.onSurface.withValues(alpha: .55);
    String pct(double? x) => x == null ? '—' : '${(x * 100).round()} %';
    Widget side(String label, SportSide s, {bool worse = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .05), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$label · ${s.days} j', style: TextStyle(fontSize: 11.5, color: mute)),
              Text('Flemme ${pct(s.lowShare)}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: worse ? _kAmber : null)),
              if (s.sleepMin != null) Text('nuit ${fmtNight(s.sleepMin!)}', style: TextStyle(fontSize: 11.5, color: mute)),
            ]),
          ),
        );
    final worseWithout = (i.without.lowShare ?? 0) > (i.after.lowShare ?? 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('On compare les jours qui suivent une séance à ceux qui suivent un jour sans : la part de ton temps dit en Flemme, et la nuit entre les deux.',
          style: TextStyle(fontSize: 12.5, color: mute)),
      const SizedBox(height: 8),
      if (i.enough)
        Row(children: [side('après une séance', i.after), const SizedBox(width: 8), side('après un jour sans', i.without, worse: worseWithout)])
      else
        Text(
          'Pas encore assez de lendemains pour comparer : ${i.after.days} après une séance, ${i.without.days} après un jour sans. Il en faut $kSportImpactMinDays de chaque côté (et ton élan dit ces jours-là).',
          style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .75)),
        ),
    ]);
  }

  Future<void> _openLaunch(List<SportCommitment> commitments, SportSummary sum) async {
    final now = DateTime.now();
    final order = sportLaunchOrder(_pick, commitments, sum.week, paused: (a) => logic.isActivitySnoozed(a.id, now));
    final byId = {for (final c in commitments.where((c) => c.isTime)) c.activity.id: c};
    final running = logic.state.sessions.where((s) => !s.deleted && s.endAt == null).map((s) => s.activityId).toSet();
    final picked = await showModalBottomSheet<Activity>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
            const Text('Lancer une séance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Du plus en retard au plus avancé. Après 10 min, le +1 de la routine de séance liée se fait tout seul.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .55))),
            const SizedBox(height: 6),
            for (final a in order)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(() {
                  final c = byId[a.id];
                  final min = sum.week.fold(0, (s, d) => s + (d.minutes[a.id] ?? 0));
                  if (running.contains(a.id)) return 'en cours';
                  return c == null ? '${fmtMin(min)} cette semaine' : '${fmtMin(c.done)} / ${fmtMin(c.target)} cette semaine${c.done >= c.target ? ' ✓' : ''}';
                }()),
                trailing: Icon(running.contains(a.id) ? Icons.timer_outlined : Icons.play_arrow_rounded, color: kSportAccent),
                onTap: running.contains(a.id) ? null : () => Navigator.pop(ctx, a),
              ),
            if (order.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Aucune activité-temps de sport suivie.')),
          ]),
        );
      },
    );
    if (picked == null || !mounted) return;
    logic.start(picked.id);
    Navigator.of(context).pop();
  }

  Future<void> _openPicker() async {
    await showFiche<void>(context, builder: (ctx, scroll) => _SportPicker(logic: logic, scroll: scroll));
    if (mounted) setState(() {});
  }
}

/// « Mes activités de sport » : une ligne par activité ou routine vivante,
/// rangées par rôle ; les domaines de sport sont cochés par défaut.
class _SportPicker extends StatefulWidget {
  final AppLogic logic;
  final ScrollController scroll;
  const _SportPicker({required this.logic, required this.scroll});

  @override
  State<_SportPicker> createState() => _SportPickerState();
}

class _SportPickerState extends State<_SportPicker> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final logic = widget.logic;
    final st = logic.state;
    final defaults = defaultSportIds(st.activities, st.domains);
    final o = logic.sportOverrides;
    final pick = resolveSportPick(st.activities, st.domains, o);
    final domains = {for (final d in st.domains) d.id: d.name};
    final live = st.activities.where((a) => !a.deleted).toList()..sort((a, b) => a.name.compareTo(b.name));
    final shown = _showAll ? live : live.where((a) => pick.contains(a.id) || defaults.contains(a.id)).toList();

    Widget section(String t, String hint, SportKind k) {
      final items = shown.where((a) => sportKindOf(a) == k).toList();
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 4),
          child: Row(children: [
            Expanded(child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute))),
            Text(hint, style: TextStyle(fontSize: 11.5, color: mute)),
          ]),
        ),
        for (final a in items)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(a.name),
            subtitle: Text(domains[a.domainId] ?? '', style: TextStyle(fontSize: 12, color: mute)),
            value: pick.contains(a.id),
            onChanged: (on) {
              logic.saveSportOverrides(logic.sportOverrides.toggled(a.id, byDefault: defaults.contains(a.id), on: on));
              setState(() {});
            },
          ),
      ]);
    }

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      const Text('Mes activités de sport', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      Text('Par défaut : les domaines de sport (Sport, Musculation…). Ajoute ou retire ce que tu veux.', style: TextStyle(fontSize: 13, color: mute)),
      section('SÉANCES · CHRONO', 'une séance = 10 min ou plus', SportKind.session),
      section('ROUTINES DE SÉANCE', 'un +1 = une séance', SportKind.sessionRoutine),
      section('RÉPÉTITIONS', 'cible ≥ 5 par jour', SportKind.reps),
      const SizedBox(height: 10),
      TextButton(
        onPressed: () => setState(() => _showAll = !_showAll),
        child: Text(_showAll ? 'Seulement le sport' : 'Voir toutes les activités'),
      ),
    ]);
  }
}

class _WeeksChart extends StatelessWidget {
  final List<SportWeekVolume> weeks;
  final Map<String, Color> colors;
  final int target;
  const _WeeksChart({required this.weeks, required this.colors, required this.target});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxV = [target, ...weeks.map((w) => w.total)].fold(60, (m, v) => v > m ? v : m) * 1.1;
    return LayoutBuilder(builder: (ctx, c) {
      final h = c.maxHeight;
      return Stack(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final (i, w) in weeks.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Container(
                decoration: i == weeks.length - 1 ? BoxDecoration(border: Border.all(color: cs.onSurface.withValues(alpha: .7), width: 1.2), borderRadius: BorderRadius.circular(4)) : null,
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  for (final e in w.minutes.entries.where((e) => e.value > 0 && colors[e.key] != null))
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      height: (h * e.value / maxV).clamp(2.0, h),
                      decoration: BoxDecoration(color: colors[e.key], borderRadius: BorderRadius.circular(3)),
                    ),
                ]),
              ),
            ),
          ],
        ]),
        if (target > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: h * target / maxV,
            child: CustomPaint(size: const Size(double.infinity, 2), painter: _DashPainter(cs.onSurface.withValues(alpha: .45))),
          ),
      ]);
    });
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 0), Offset(x + 4, 0), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter o) => o.color != color;
}

class _Grid extends StatelessWidget {
  final List<SportDay> days; // commence un lundi
  final String today;
  const _Grid({required this.days, required this.today});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: [
        for (final d in days)
          Container(
            decoration: BoxDecoration(
              color: !d.isRest ? _kGreen : (d.repsOnly ? const Color(0xFF2F4A3C) : cs.onSurface.withValues(alpha: .08)),
              borderRadius: BorderRadius.circular(4),
              border: d.ymd == today ? Border.all(color: cs.onSurface, width: 1.5) : null,
            ),
          ),
      ],
    );
  }
}

class _WeightPainter extends CustomPainter {
  final StrategicObjective o;
  final ObjectiveTrajectory t;
  final Color ink;
  _WeightPainter(this.o, this.t, this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    final m = o.metric!;
    final start = t.start;
    final readings = [for (final r in o.readings) (DateTime.tryParse(r.date), r.value)].where((x) => x.$1 != null).toList();
    final lastReading = readings.isEmpty ? start : readings.last.$1!;
    final end = t.end ?? (lastReading.isAfter(DateTime.now()) ? lastReading : DateTime.now()).add(const Duration(days: 14));
    final span = end.difference(start).inHours.clamp(1, 1 << 30).toDouble();
    final vals = [m.startValue, m.targetValue, for (final r in readings) r.$2];
    final lo = vals.reduce((a, b) => a < b ? a : b), hi = vals.reduce((a, b) => a > b ? a : b);
    final pad = (hi - lo).abs() < 0.01 ? 1.0 : (hi - lo) * .12;
    double x(DateTime d) => (d.difference(start).inHours / span).clamp(0.0, 1.0) * size.width;
    double y(double v) => size.height - ((v - (lo - pad)) / ((hi + pad) - (lo - pad))) * size.height;

    final dash = Paint()
      ..color = ink.withValues(alpha: .4)
      ..strokeWidth = 1.5;
    final a = Offset(0, y(m.startValue)), b = Offset(x(end), y(m.targetValue));
    const n = 40;
    for (var i = 0; i < n; i += 2) {
      canvas.drawLine(Offset.lerp(a, b, i / n)!, Offset.lerp(a, b, (i + 1) / n)!, dash);
    }
    final nowX = x(DateTime.now());
    canvas.drawLine(Offset(nowX, 0), Offset(nowX, size.height), Paint()
      ..color = ink.withValues(alpha: .5)
      ..strokeWidth = 1);
    if (readings.isNotEmpty) {
      final line = Paint()
        ..color = _kGreen
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(0, y(m.startValue));
      for (final r in readings) {
        path.lineTo(x(r.$1!), y(r.$2));
      }
      canvas.drawPath(path, line);
      for (final r in readings) {
        canvas.drawCircle(Offset(x(r.$1!), y(r.$2)), 3.5, Paint()..color = _kGreen);
      }
    }
  }

  @override
  bool shouldRepaint(_WeightPainter old) => true;
}
