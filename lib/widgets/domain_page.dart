import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show routineSeries;
import 'package:productivitwo_v1/utils/budget_window.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/utils/mode_colors.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/week_stats.dart';
import 'package:productivitwo_v1/widgets/deep_work_sheet.dart';
import 'package:productivitwo_v1/widgets/fiche.dart';
import 'package:productivitwo_v1/widgets/moment_card.dart';
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart' show showRoutineSheet;
import 'package:productivitwo_v1/utils/routines_today.dart' show todayMark;
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show routinePlus, routineMinus, routineTodayCount;
import 'package:productivitwo_v1/widgets/status_row.dart';

/// Page d'un domaine (tap sur une ligne de Stats ; `domain` null = toutes les
/// activités), refonte 2026-10 « une carte, une fiche » : en-tête = la ligne de
/// Stats dépliée (minimum sur la fenêtre de budget, fait, attendu, routines
/// tenues), carte ACTIVITÉ DU MOMENT (la plus en retard sur son objectif, UN
/// geste selon le mode), lignes `StatusRow` par activité (moyenne / j, barre
/// fait / attendu avec repère, chip, ▶), sections À RATTRAPER · AU RYTHME ·
/// EN PAUSE ; segment Temps / Routines. La courbe 60 j et la heatmap vivent
/// dans la fiche d'activité. Renvoie `true` quand un chrono a été lancé (la
/// racine bascule sur Aujourd'hui).
Future<bool?> showDomainPage(
  BuildContext context, {
  required AppLogic logic,
  required FirestoreSync sync,
  Domain? domain,
  String focus = 'time',
  required Future<void> Function({String? domainId, required bool isHabit}) onCreate,
  required Future<bool> Function(Activity a) onOpenActivity,
  void Function(Activity a, int minutes)? onLaunchTimed,
  void Function(ScheduleBlock block)? onLaunchBlock,
}) {
  return showFiche<bool>(
    context,
    builder: (ctx, scroll) => _DomainPage(
      logic: logic,
      sync: sync,
      domain: domain,
      focus: focus,
      scroll: scroll,
      onCreate: onCreate,
      onOpenActivity: onOpenActivity,
      onLaunchTimed: onLaunchTimed,
      onLaunchBlock: onLaunchBlock,
    ),
  );
}

class _DomainPage extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final Domain? domain;
  final String focus;
  final ScrollController scroll;
  final Future<void> Function({String? domainId, required bool isHabit}) onCreate;
  final Future<bool> Function(Activity a) onOpenActivity;
  final void Function(Activity a, int minutes)? onLaunchTimed;
  final void Function(ScheduleBlock block)? onLaunchBlock;
  const _DomainPage({
    required this.logic,
    required this.sync,
    required this.domain,
    required this.focus,
    required this.scroll,
    required this.onCreate,
    required this.onOpenActivity,
    this.onLaunchTimed,
    this.onLaunchBlock,
  });

  @override
  State<_DomainPage> createState() => _DomainPageState();
}

/// Une activité-temps lue sur la fenêtre de budget.
class _TimeRow {
  final Activity a;
  final int goalMinDay;
  final int doneMin; // dans la fenêtre
  final int expectedMin; // minimum × jour de la fenêtre
  final int totalMin; // minimum × fenêtre
  final int avg7; // minutes / jour sur 7 jours glissants
  final bool paused;
  const _TimeRow(this.a, {required this.goalMinDay, required this.doneMin, required this.expectedMin, required this.totalMin, required this.avg7, required this.paused});
  bool get hasGoal => goalMinDay > 0;
  int get pctInt => !hasGoal ? 100 : (expectedMin <= 0 ? 100 : (doneMin / expectedMin * 100).round());
  /// « Au rythme » dès 95 % de l'attendu (même tolérance que l'ancienne page).
  bool get onTrack => !hasGoal || doneMin >= expectedMin * .95;
}

class _DomainPageState extends State<_DomainPage> {
  late String _tab = widget.focus == 'habit' ? 'habit' : 'time';
  bool _showPaused = false;

  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    logic.addListener(_onLogic);
  }

  @override
  void dispose() {
    logic.removeListener(_onLogic);
    super.dispose();
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  // ── Lectures ────────────────────────────────────────────────────────────────

  List<Activity> _acts(bool habits) => logic.state.activities
      .where((a) => !a.deleted && a.isHabit == habits && (widget.domain == null || a.domainId == widget.domain!.id))
      .toList();

  List<_TimeRow> _timeRows(DateTime now) {
    final days = logic.budgetWindowDays;
    final start = budgetWindowStart(now, days);
    final idx = budgetDayIndex(now, days);
    final byAct = minutesByActivity(logic.state.sessions, start, now);
    final out = <_TimeRow>[];
    for (final a in _acts(false)) {
      final s7 = logic.timeSliding(a.id, 7);
      out.add(_TimeRow(
        a,
        goalMinDay: a.goalMin,
        doneMin: byAct[a.id] ?? 0,
        expectedMin: a.goalMin * idx,
        totalMin: a.goalMin * days,
        avg7: (s7.doneMin / 7).round(),
        paused: logic.isActivitySnoozed(a.id, now),
      ));
    }
    return out;
  }

  // ── Gestes ──────────────────────────────────────────────────────────────────

  void _start(Activity a) {
    logic.start(a.id);
    Navigator.of(context).pop(true);
  }

  Future<void> _deepWork(Activity a) async {
    final launch = widget.onLaunchBlock;
    if (launch == null) return _start(a);
    final ok = await showDeepWorkSheet(context,
        logic: logic, sync: widget.sync, date: logic.livedTodayYmd, onLaunch: launch, preferActivityId: a.id);
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _rowMenu(Activity a, DateTime now) async {
    final paused = logic.isActivitySnoozed(a.id, now);
    final running = logic.runningActivity()?.id == a.id;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text(a.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          ),
          if (paused)
            ListTile(leading: const Icon(Icons.play_circle_outline), title: const Text('Reprendre'), onTap: () => Navigator.pop(c, 'resume'))
          else ...[
            ListTile(
                leading: const Icon(Icons.redo_rounded),
                title: const Text('Reporter à demain'),
                subtitle: running ? const Text('Impossible : le chrono tourne dessus') : null,
                enabled: !running,
                onTap: () => Navigator.pop(c, 'tomorrow')),
            ListTile(leading: const Icon(Icons.pause_circle_outline), title: const Text('Mettre en pause jusqu\'à…'), onTap: () => Navigator.pop(c, 'pause')),
          ],
          ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(c).colorScheme.error),
              title: Text('Supprimer', style: TextStyle(color: Theme.of(c).colorScheme.error)),
              onTap: () => Navigator.pop(c, 'delete')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'resume':
        logic.clearSnooze(a.id);
      case 'tomorrow':
        logic.snoozeActivityUntil(a.id, DateTime(now.year, now.month, now.day, 23, 59, 59));
      case 'pause':
        final d = await showDatePicker(
            context: context, initialDate: now.add(const Duration(days: 1)), firstDate: now, lastDate: now.add(const Duration(days: 365)), locale: const Locale('fr', 'FR'));
        if (d != null) logic.snoozeActivityUntil(a.id, DateTime(d.year, d.month, d.day, 23, 59, 59));
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text('Supprimer « ${a.name} » ?'),
            content: Text(a.isHabit ? 'Cette routine sera supprimée et retirée des plans.' : 'Cette activité sera supprimée et retirée des plans.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Supprimer')),
            ],
          ),
        );
        if (ok == true) logic.deleteActivityCascade(a.id);
    }
    if (mounted) setState(() {});
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final d = widget.domain;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      children: [
        _header(now),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'time', icon: Icon(Icons.access_time_rounded, size: 18), label: Text('Temps')),
            ButtonSegment(value: 'habit', icon: Icon(Icons.repeat_rounded, size: 18), label: Text('Routines')),
          ],
          selected: {_tab},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        if (_tab == 'time') ..._timeBody(now, d) else ..._habitBody(now, d),
      ],
    );
  }

  Widget _header(DateTime now) {
    final cs = Theme.of(context).colorScheme;
    final d = widget.domain;
    final st = logic.state;
    if (d == null) {
      final n = _acts(_tab == 'habit').length;
      return FicheHeader(
        title: _tab == 'habit' ? 'Toutes les routines' : 'Toutes les activités',
        kpi: '$n ${_tab == 'habit' ? 'routine' : 'activité'}${n > 1 ? 's' : ''} · tous domaines',
      );
    }
    final rows = domainWeeks(
        domains: [d], activities: st.activeActivities, sessions: st.sessions, hits: st.habitHits, now: now, rest: logic.restDomains, windowDays: logic.budgetWindowDays);
    final r = rows.single;
    final color = domainColor(d.id, st.activeDomains) ?? cs.primary;
    final String chip;
    final Color chipColor;
    if (r.resting) {
      chip = 'en veille';
      chipColor = kPalierMuted;
    } else if (!r.hasGoal) {
      chip = 'sans minimum';
      chipColor = kPalierMuted;
    } else {
      chip = r.pctInt >= 85 ? 'au rythme' : (r.pctInt >= 60 ? 'à surveiller' : 'en retard');
      chipColor = palierColor(r.pctInt);
    }
    final win = r.windowDays == 14 ? 'sur 14 j' : 'cette semaine';
    final kpi = <String>[
      if (r.hasGoal) 'minimum ${fmtMin(r.goalMinDay)} / j',
      '${fmtMin(r.doneMin)} $win',
      if (r.hasGoal) 'attendu ${fmtMin(r.expectedMin)}',
      if (r.routinesTotal > 0) '${r.routinesReached} / ${r.routinesTotal} routine${r.routinesTotal > 1 ? 's' : ''} tenue${r.routinesReached > 1 ? 's' : ''}',
    ].join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FicheHeader(
        leading: Container(width: 12, height: 12, margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        title: d.name,
        chip: chip,
        chipColor: chipColor,
        kpi: kpi,
      ),
      if (r.hasGoal) ...[
        const SizedBox(height: 8),
        ExpectedBar(done: r.doneMin, total: r.weekMin, expected: r.expectedMin, color: palierColor(r.pctInt)),
      ],
    ]);
  }

  // ── Temps ───────────────────────────────────────────────────────────────────

  List<Widget> _timeBody(DateTime now, Domain? d) {
    final cs = Theme.of(context).colorScheme;
    final rows = _timeRows(now);
    final live = rows.where((r) => !r.paused).toList();
    final paused = rows.where((r) => r.paused).toList();
    // Même ordre que Stats : sous l'attendu, le plus proche en tête ; au rythme, en ordre croissant.
    final behind = live.where((r) => !r.onTrack).toList()..sort((a, b) => comparePct(a.pctInt, b.pctInt));
    final ok = live.where((r) => r.onTrack).toList()..sort((a, b) => comparePct(a.pctInt, b.pctInt));
    final moment = behind.isNotEmpty ? behind.first : (live.where((r) => r.hasGoal).firstOrNull ?? live.firstOrNull);
    return [
      if (moment != null) ...[const SizedBox(height: 14), _momentCard(moment, now, d)],
      ListSectionTitle('À RATTRAPER · ${behind.length}', action: '+ Nouvelle activité', onAction: () async {
        await widget.onCreate(domainId: d?.id, isHabit: false);
        if (mounted) setState(() {});
      }),
      if (behind.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(live.isEmpty ? 'Aucune activité-temps ici.' : 'Tout est au rythme de l\'attendu.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .5))),
        )
      else
        for (final r in behind) _timeRow(r, now),
      if (ok.isNotEmpty) ...[
        ListSectionTitle('AU RYTHME · ${ok.length}'),
        for (final r in ok) _timeRow(r, now),
      ],
      if (paused.isNotEmpty) ...[
        ListSectionTitle('EN PAUSE · ${paused.length}', onAction: () => setState(() => _showPaused = !_showPaused), expanded: _showPaused),
        if (_showPaused) for (final r in paused) _timeRow(r, now),
      ],
    ];
  }

  Widget _momentCard(_TimeRow r, DateTime now, Domain? d) {
    final a = r.a;
    final st = logic.state;
    final mode = logic.mode;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = modeAccentOverride(mode, dark: dark) ?? (domainColor(a.domainId, st.activeDomains) ?? Theme.of(context).colorScheme.primary);
    final running = logic.runningActivity()?.id == a.id;
    final pct = r.hasGoal ? (r.expectedMin <= 0 ? 1.0 : (r.doneMin / r.expectedMin).clamp(0.0, 1.0)) : 0.0;
    final domName = st.activeDomains.where((x) => x.id == a.domainId).firstOrNull?.name;
    final String primary;
    final IconData icon;
    final VoidCallback onPrimary;
    if (running) {
      primary = 'Arrêter';
      icon = Icons.stop_rounded;
      onPrimary = () => logic.stopActive();
    } else if (mode == DayMode.low && widget.onLaunchTimed != null) {
      primary = '10 min, malgré tout';
      icon = Icons.timer_outlined;
      onPrimary = () {
        widget.onLaunchTimed!(a, 10);
        Navigator.of(context).pop(true);
      };
    } else if (mode == DayMode.high) {
      primary = 'Deep work 90 min · sur quoi ?';
      icon = Icons.bolt_rounded;
      onPrimary = () => _deepWork(a);
    } else {
      primary = 'Chrono';
      icon = Icons.play_arrow_rounded;
      onPrimary = () => _start(a);
    }
    return MomentCard(
      accent: accent,
      eyebrow: 'ACTIVITÉ DU MOMENT',
      pill: r.onTrack ? (r.hasGoal ? 'au rythme' : 'sans objectif') : 'la plus en retard',
      ring: pct,
      ringColor: r.hasGoal ? palierColor(r.pctInt) : accent,
      ringBig: r.hasGoal ? '${r.pctInt} %' : fmtMin(r.doneMin),
      ringSmall: r.hasGoal ? 'DE L\'ATTENDU' : (logic.budgetWindowDays == 14 ? 'SUR 14 J' : 'CETTE SEM.'),
      context_: [if (d == null && domName != null) domName, if (r.hasGoal) 'objectif ${fmtMin(r.goalMinDay)} / j'].join(' · '),
      contextIcon: Icons.access_time_rounded,
      title: a.name,
      sub: _timeSub(r),
      subColor: r.hasGoal && !r.onTrack ? palierColor(r.pctInt) : null,
      primaryLabel: primary,
      primaryIcon: icon,
      primaryOutlined: running,
      onPrimary: onPrimary,
      onFiche: () async {
        final changed = await widget.onOpenActivity(a);
        if (changed && mounted) setState(() {});
      },
    );
  }

  String _timeSub(_TimeRow r) {
    final win = logic.budgetWindowDays == 14 ? 'sur 14 j' : 'cette semaine';
    return [
      '${fmtMin(r.avg7)} / j en moyenne',
      '${fmtMin(r.doneMin)} $win',
      if (r.hasGoal) 'attendu ${fmtMin(r.expectedMin)}',
    ].join(' · ');
  }

  Widget _timeRow(_TimeRow r, DateTime now) {
    final cs = Theme.of(context).colorScheme;
    final a = r.a;
    final running = logic.runningActivity()?.id == a.id;
    final until = r.paused ? logic.snoozedUntilOf(a.id) : null;
    final sub = r.paused
        ? 'en pause${until == null ? '' : ' jusqu\'au ${until.day}/${until.month.toString().padLeft(2, '0')}'}'
        : [
            '${fmtMin(r.avg7)} / j en moy.',
            if (r.hasGoal) 'objectif ${fmtMin(r.goalMinDay)} / j' else 'pas d\'objectif',
          ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StatusRow(
        leading: GestureDetector(
          onTap: r.paused ? null : () => running ? logic.stopActive() : _start(a),
          child: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded, color: running ? cs.primary : null),
        ),
        title: a.name,
        sub: sub,
        bar: r.hasGoal && !r.paused ? (done: r.doneMin, total: r.totalMin, expected: r.expectedMin) : null,
        pct: r.pctInt,
        chip: r.paused ? null : (r.hasGoal ? '${r.pctInt} %' : null),
        muted: r.paused,
        trailing: r.paused || !r.hasGoal ? Icon(Icons.chevron_right, color: cs.onSurface.withValues(alpha: .4)) : null,
        onTap: () async {
          final changed = await widget.onOpenActivity(a);
          if (changed && mounted) setState(() {});
        },
        onLongPress: () => _rowMenu(a, now),
      ),
    );
  }

  // ── Routines ────────────────────────────────────────────────────────────────

  List<Widget> _habitBody(DateTime now, Domain? d) {
    final cs = Theme.of(context).colorScheme;
    final all = _acts(true);
    double ratio(Activity a) {
      final t = logic.activeHabitTarget(a);
      return t <= 0 ? 0 : (logic.activeHabitDone(a) / t).clamp(0.0, 1.0);
    }
    int pctOf(Activity a) => (ratio(a) * 100).round();
    final todo = all.where((a) => !logic.habitReached(a)).toList()..sort((x, y) => comparePct(pctOf(x), pctOf(y)));
    final done = all.where(logic.habitReached).toList()..sort((x, y) => comparePct(pctOf(x), pctOf(y)));
    return [
      ListSectionTitle('À FAIRE · ${todo.length}', action: '+ Nouvelle routine', onAction: () async {
        await widget.onCreate(domainId: d?.id, isHabit: true);
        if (mounted) setState(() {});
      }),
      if (todo.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(all.isEmpty ? 'Aucune routine ici.' : 'Toutes les routines de la période sont atteintes.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .5))),
        )
      else
        for (final a in todo) _habitRow(a, now),
      if (done.isNotEmpty && d != null) ...[
        ListSectionTitle('ATTEINTES · ${done.length}'),
        for (final a in done) _habitRow(a, now),
      ],
    ];
  }

  Widget _habitRow(Activity a, DateTime now) {
    final cs = Theme.of(context).colorScheme;
    final target = logic.activeHabitTarget(a);
    final done = logic.activeHabitDone(a);
    final reached = logic.habitReached(a);
    final period = switch (a.habitFreq) { HabitFreq.weekly => '7 j', HabitFreq.monthly => '30 j', _ => 'aujourd\'hui' };
    final series = routineSeries(a, logic.state.habitHits, now, dayStartMin: logic.dayStartMin, bridged: logic.bridgedOf(a.id));
    final pct = target <= 0 ? 100 : (done / target * 100).round().clamp(0, 100);
    final todayN = routineTodayCount(logic, a);
    final mark = todayMark(a.habitFreq, todayN);
    final sub = [
      '$period : $done / $target',
      if (mark != null) mark,
      if (series.current > 0) '🔥 ${series.current} j',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StatusRow(
        leading: Icon(reached || mark != null ? Icons.check_rounded : Icons.repeat_rounded,
            color: reached ? cs.primary : (mark != null ? cs.primary.withValues(alpha: .6) : null)),
        title: a.name,
        sub: sub,
        bar: target > 0 ? (done: done, total: target, expected: target) : null,
        pct: reached ? 100 : (pct >= 60 ? 60 : 0),
        muted: reached,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          _round('−', done > 0 ? () => routineMinus(logic, a) : null),
          const SizedBox(width: 6),
          _round('+', () => routinePlus(logic, a), primary: true),
        ]),
        onTap: () => showRoutineSheet(context, logic: logic, habitId: a.id, day: now, onSaved: () => setState(() {})),
        onLongPress: () => _rowMenu(a, now),
      ),
    );
  }

  Widget _round(String label, VoidCallback? onTap, {bool primary = false}) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 34,
      height: 34,
      child: Material(
        color: primary ? cs.primary.withValues(alpha: .16) : cs.onSurface.withValues(alpha: .06),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: onTap == null ? cs.onSurface.withValues(alpha: .3) : (primary ? cs.primary : cs.onSurface))),
          ),
        ),
      ),
    );
  }
}
