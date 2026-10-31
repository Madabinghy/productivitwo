import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/claude_link.dart' show claudeNewUri, planDayPrompt;
import 'package:productivitwo_v1/utils/domain_colors.dart' show domainColor;
import 'package:productivitwo_v1/utils/duration_fmt.dart' show fmtMin;
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/interventions.dart' show interventionsOf;
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDayBlocks;
import 'package:productivitwo_v1/utils/planning.dart';
import 'package:productivitwo_v1/utils/project_moment.dart' show rankProjectMoments;
import 'package:productivitwo_v1/utils/reading_due.dart' show readingsDue;
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin;
import 'package:productivitwo_v1/utils/week_capacity.dart' show DayWindow;

/// Mode Planification (maquette validée 2026-10-31) : poser demain (ou la fin
/// d'aujourd'hui) en quelques minutes — ce qui se joue, le temps qui reste,
/// des blocs d'activité proposés, puis le récapitulatif. Écrit le programme
/// avec `generatedBy:"plan"` et `plannedAt` (badge Cap tenu, `capHeld`).
const kPlanAccent = Color(0xFF9DB8FF);
const _ink = Color(0xFF0B1430);
const _bg = Color(0xFF07100D);
const _card = Color(0xFF0C1C14);
const _line = Color(0xFF16281E);
const _text2 = Color(0xFFB9CFC4);
const _text3 = Color(0xFF9FB8AB);
const _gold = Color(0xFFFFD27A);
const _ember = Color(0xFFFFB27A);
const _green = Color(0xFF7FD3A0);

Future<void> showPlanScreen(BuildContext context, AppLogic logic, {BadgeCenter? badges}) {
  return Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => PlanScreen(logic: logic, badges: badges)));
}

enum _Step { cap, stakes, frame, fill, done }

class PlanScreen extends StatefulWidget {
  final AppLogic logic;
  final BadgeCenter? badges;
  const PlanScreen({super.key, required this.logic, this.badges});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => logic.sync ?? FirestoreSync();

  _Step _step = _Step.cap;
  bool _tomorrow = true;
  bool _chrono = true;
  PlanLoad _load = PlanLoad.normal;
  DateTime? _startedAt;

  DayWindow _window = const DayWindow(8 * 60, 22 * 60);
  DailySchedule? _doc; // programme du jour visé (doc calendaire)
  List<ScheduleBlock> _blocks = const []; // journée vécue visée, nuit comprise
  List<PlanStake> _stakes = const [];
  final Set<String> _kept = {};
  List<PlannedBlock> _plan = const [];
  final List<PlanWant> _extra = [];
  final Set<String> _dropped = {};
  bool _loading = false;
  int _capCount = 0;

  @override
  void initState() {
    super.initState();
    // Le matin, on pose plutôt la journée en cours ; l'après-midi et le soir, demain.
    _tomorrow = logic.livedNowMinNow >= 12 * 60;
  }

  DateTime get _day {
    final d = logic.livedToday;
    return _tomorrow ? DateTime(d.year, d.month, d.day + 1) : d;
  }

  String get _ymd => ymdOf(_day);

  // ── Données ─────────────────────────────────────────────────────────────────

  Future<void> _load2() async {
    setState(() => _loading = true);
    final day = _day;
    final next = DateTime(day.year, day.month, day.day + 1);
    final results = await Future.wait([
      sync.fetchDayWindow(),
      sync.fetchDailySchedule(ymdOf(day)),
      sync.fetchDailySchedule(ymdOf(next)),
    ]);
    _window = results[0] as DayWindow;
    _doc = results[1] as DailySchedule?;
    _blocks = livedDayBlocks(_doc, results[2] as DailySchedule?, logic.dayStartMin)
        .where((b) => b.status == 'pending' || b.status == 'done')
        .toList()
      ..sort((a, b) => blockStartMin(a).compareTo(blockStartMin(b)));
    _stakes = _buildStakes();
    _kept
      ..clear()
      ..addAll(_stakes.where((s) => s.keep).map((s) => s.id));
    if (mounted) setState(() => _loading = false);
  }

  List<PlanStake> _buildStakes() {
    final day = _day;
    final out = <PlanStake>[];
    // Daté : ce qui est déjà au programme ce jour-là, et les séances.
    for (final b in _blocks.where((b) => b.status == 'pending')) {
      if (b.gcalEventId == null && b.kind != 'session') continue;
      out.add(PlanStake(id: 'block:${b.id}', kind: PlanStakeKind.dated, title: b.title, detail: '${b.startTime} → ${hmOf(blockStartMin(b) + b.durationMin)}'));
    }
    final seen = <String>{};
    for (final p in logic.currentProjects) {
      if (p.status == 'archived' || p.status == 'done' || p.paused) continue;
      for (final i in interventionsOf(p)) {
        if (i.isDone) continue;
        final diff = i.date.difference(DateTime(day.year, day.month, day.day)).inDays;
        if (diff == 0) {
          out.add(PlanStake(id: 'session:${p.id}:${i.milestone.id}', kind: PlanStakeKind.dated, title: i.milestone.title, detail: p.title));
        } else if (diff > 0 && diff <= 3 && i.prep != null && i.prep!.status != 'done' && p.linkedActivityId != null && seen.add(p.id)) {
          out.add(PlanStake(
            id: 'prep:${p.id}',
            kind: PlanStakeKind.behind,
            title: 'Préparer · ${p.title}',
            detail: diff == 1 ? 'séance demain' : 'séance dans $diff j',
            activityId: p.linkedActivityId,
            minutes: 60,
          ));
        }
      }
    }
    // Se perd si rien : séries de routines, Montre suisse, relevés.
    for (final a in logic.state.activeActivities) {
      if (!a.isHabit || logic.effectiveHabitFreq(a) != HabitFreq.daily || logic.isAcquired(a.id) || logic.isActivitySnoozed(a.id, day)) continue;
      final s = logic.habitCurrentStreak(a.id);
      if (s <= 0) continue;
      out.add(PlanStake(id: 'routine:${a.id}', kind: PlanStakeKind.losing, title: '${a.name} · série $s j', detail: 'routine'));
    }
    final facts = widget.badges?.todayFacts();
    for (final p in facts?.pace ?? const []) {
      final need = _tomorrow ? p.tomorrowNeedMin : p.missingMin;
      if (need <= 0) continue;
      out.add(PlanStake(
        id: 'watch:${p.activity.id}',
        kind: PlanStakeKind.losing,
        title: '${p.activity.name} · Montre suisse',
        detail: 'il faut ${fmtMin(need)}',
        activityId: p.activity.id,
        minutes: need < 30 ? 30 : ((need + 14) ~/ 15) * 15,
      ));
    }
    for (final r in readingsDue(facts?.objectives ?? const [], day)) {
      if (!r.lastDay) continue;
      out.add(PlanStake(id: 'reading:${r.objective.id}', kind: PlanStakeKind.losing, title: 'Relevé · ${r.objective.title}', detail: 'dernier jour', keep: false));
    }
    // En retard sur le plan : projets avec une activité liée.
    for (final m in rankProjectMoments(logic.currentProjects, logic.state.sessions, day)) {
      if (!m.behind || m.upcoming || m.project.linkedActivityId == null || seen.contains(m.project.id)) continue;
      seen.add(m.project.id);
      out.add(PlanStake(
        id: 'plan:${m.project.id}',
        kind: PlanStakeKind.behind,
        title: m.project.title,
        detail: '${m.plan.expected - m.plan.done} tâche${m.plan.expected - m.plan.done > 1 ? 's' : ''} en retard sur le plan',
        activityId: m.project.linkedActivityId,
        minutes: 60,
        keep: out.where((s) => s.kind == PlanStakeKind.behind).length < 2,
      ));
    }
    return out;
  }

  DayWindow get _effectiveWindow {
    if (_tomorrow) return _window;
    final now = logic.livedNowMinNow;
    final start = ((now + 14) ~/ 15) * 15;
    return DayWindow(start > _window.startMin ? start : _window.startMin, _window.endMin);
  }

  List<PlanGap> get _gaps => freeGaps(_blocks, _effectiveWindow);

  int get _budget => (freeMinutes(_gaps) * fillRatio(_load)).round();

  String _activityName(String id) => logic.state.activities.where((a) => a.id == id).map((a) => a.name).firstOrNull ?? 'Activité';

  void _propose() {
    final wants = <PlanWant>[];
    final ids = <String>{};
    for (final kind in [PlanStakeKind.dated, PlanStakeKind.losing, PlanStakeKind.behind]) {
      for (final s in _stakes.where((s) => s.kind == kind && _kept.contains(s.id) && s.activityId != null)) {
        if (!ids.add(s.activityId!)) continue;
        wants.add(PlanWant(activityId: s.activityId!, title: _activityName(s.activityId!), minutes: s.minutes, reason: _reasonOf(s)));
      }
    }
    for (final w in _extra) {
      if (ids.add(w.activityId)) wants.add(w);
    }
    _plan = proposeDay(_gaps, wants.where((w) => !_dropped.contains(w.activityId)).toList(), _budget);
  }

  String _reasonOf(PlanStake s) => switch (s.id.split(':').first) {
        'watch' => 'Montre suisse',
        'prep' => 'séance',
        'plan' => 'plan du projet',
        _ => s.detail,
      };

  Activity? _planningActivity() => logic.state.activities.where((a) => !a.deleted && !a.isHabit && a.name.trim().toLowerCase() == 'planification').firstOrNull;

  void _begin() {
    _startedAt = DateTime.now();
    if (_chrono) {
      var a = _planningActivity();
      if (a == null) {
        final domains = logic.state.activeDomains;
        final d = domains.where((d) => d.name.toLowerCase().contains('organis')).firstOrNull ?? domains.firstOrNull;
        if (d != null) {
          a = Activity(domainId: d.id, name: 'Planification', goalMin: 0);
          logic.state.activities.add(a);
          logic.onChange();
        }
      }
      if (a != null) logic.start(a.id);
    }
    setState(() => _step = _Step.stakes);
    _load2();
  }

  Future<void> _save() async {
    final doc = _doc ?? DailySchedule(date: _ymd);
    for (final p in _plan) {
      doc.blocks.add(planBlockOf(p));
    }
    doc
      ..generatedBy = 'plan'
      ..generatedAt = DateTime.now()
      ..plannedAt = DateTime.now()
      ..plannedSameDay = !_tomorrow;
    await sync.saveDailySchedule(doc);
    final today = ymdOf(logic.livedToday);
    final from = ymdOf(logic.livedToday.subtract(const Duration(days: 60)));
    try {
      final past = await sync.fetchDailySchedulesRange(from, today);
      _capCount = capHeldCount(past, today);
    } catch (_) {}
    if (mounted) setState(() => _step = _Step.done);
  }

  void _finish() {
    final a = _planningActivity();
    if (_chrono && a != null && logic.state.sessions.any((s) => s.endAt == null && !s.deleted && s.activityId == a.id)) {
      logic.stopActive();
    }
    Navigator.of(context).pop();
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: kPlanAccent))
              : switch (_step) {
                  _Step.cap => _capView(),
                  _Step.stakes => _stakesView(),
                  _Step.frame => _frameView(),
                  _Step.fill => _fillView(),
                  _Step.done => _doneView(),
                },
        ),
      ),
    );
  }

  Widget _top(String label, int stepIdx) => SizedBox(
        height: 48,
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1, color: kPlanAccent))),
          if (stepIdx > 0)
            for (var i = 1; i <= 4; i++)
              Container(
                width: 18,
                height: 4,
                margin: const EdgeInsets.only(left: 3),
                decoration: BoxDecoration(color: i <= stepIdx ? kPlanAccent : const Color(0xFF27382D), borderRadius: BorderRadius.circular(2)),
              ),
          IconButton(tooltip: 'Fermer', icon: const Icon(Icons.close, color: _text2), onPressed: _finish),
        ]),
      );

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2, color: Colors.white)),
      );

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
        child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: _text3)),
      );

  Widget _primary(String label, VoidCallback? onTap) => SizedBox(
        height: 54,
        width: double.infinity,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(backgroundColor: kPlanAccent, foregroundColor: _ink, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _choice({required bool selected, required VoidCallback onTap, required Widget child}) => Material(
        color: selected ? kPlanAccent.withValues(alpha: .12) : const Color(0xFF12241B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? kPlanAccent : Colors.white.withValues(alpha: .12), width: selected ? 1.5 : 1),
        ),
        child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: Padding(padding: const EdgeInsets.all(14), child: child)),
      );

  Widget _capView() {
    final now = logic.livedNowMinNow;
    final a = _planningActivity();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _top('PLANIFIER · PRENDRE LE CAP', 0),
      _title('Qu\'est-ce qu\'on pose ?'),
      const SizedBox(height: 8),
      _choice(
        selected: _tomorrow,
        onTap: () => setState(() => _tomorrow = true),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Demain', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
          SizedBox(height: 3),
          Text('ce qui se joue, le temps libre, des blocs proposés', style: TextStyle(fontSize: 13, color: _text2)),
        ]),
      ),
      const SizedBox(height: 10),
      _choice(
        selected: !_tomorrow,
        onTap: () => setState(() => _tomorrow = false),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('La fin d\'aujourd\'hui', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 3),
          Text('à partir de ${hmOf(((now + 14) ~/ 15) * 15)}', style: const TextStyle(fontSize: 13, color: _text2)),
        ]),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.timer_outlined, color: kPlanAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Chrono sur « Planification »', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              Text(a == null ? 'l\'activité sera créée' : 'ce temps compte, comme le reste', style: const TextStyle(fontSize: 12, color: _text3)),
            ]),
          ),
          Switch(value: _chrono, activeColor: kPlanAccent, onChanged: (v) => setState(() => _chrono = v)),
        ]),
      ),
      const Spacer(),
      _primary(_tomorrow ? 'Planifier demain' : 'Planifier la fin de journée', _begin),
    ]);
  }

  Widget _stakesView() {
    Widget group(String label, PlanStakeKind k) {
      final list = _stakes.where((s) => s.kind == k).toList();
      if (list.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _section(label),
        Container(
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: _line),
              CheckboxListTile(
                value: _kept.contains(list[i].id),
                onChanged: k == PlanStakeKind.dated ? null : (v) => setState(() => v == true ? _kept.add(list[i].id) : _kept.remove(list[i].id)),
                activeColor: kPlanAccent,
                checkColor: _ink,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: Text(list[i].title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                secondary: Text(list[i].detail,
                    style: TextStyle(fontSize: 12, color: k == PlanStakeKind.losing ? _ember : (k == PlanStakeKind.behind ? _gold : _text3))),
              ),
            ],
          ]),
        ),
      ]);
    }

    final keptCount = _stakes.where((s) => _kept.contains(s.id)).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _top(_tomorrow ? 'DEMAIN · CE QUI SE JOUE' : 'CE SOIR · CE QUI SE JOUE', 1),
      _title(_tomorrow ? 'Ce qui se joue demain' : 'Ce qui se joue encore'),
      const Text('Coche ce que tu veux tenir. Le reste attendra, sans culpabilité.', style: TextStyle(fontSize: 13.5, color: _text2)),
      Expanded(
        child: ListView(children: [
          if (_stakes.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('Rien de daté ni d\'urgent : journée libre à remplir.', style: TextStyle(color: _text2))),
          group('DATÉ · NE BOUGE PAS', PlanStakeKind.dated),
          group('SE PERD SI RIEN', PlanStakeKind.losing),
          group('EN RETARD SUR LE RYTHME', PlanStakeKind.behind),
        ]),
      ),
      const SizedBox(height: 10),
      _primary('Tenir ces $keptCount · voir le temps', () => setState(() => _step = _Step.frame)),
    ]);
  }

  Widget _frameView() {
    final gaps = _gaps;
    final free = freeMinutes(gaps);
    final w = _effectiveWindow;
    final items = <(int, Widget)>[];
    for (final b in _blocks.where((b) => blockStartMin(b) + b.durationMin > w.startMin && blockStartMin(b) < w.endMin)) {
      final mirror = b.gcalEventId != null;
      items.add((
        blockStartMin(b),
        _slot('${b.startTime} · ${b.title}${mirror ? ' · agenda' : ''}', mirror ? const Color(0xFF2A3550) : const Color(0xFF1D2B23), mirror ? const Color(0xFFC9D4F3) : _text2)
      ));
    }
    for (final g in gaps) {
      items.add((g.startMin, _slot('${hmOf(g.startMin)} · libre · ${fmtMin(g.minutes)}', const Color(0xFF16281E), _green, dashed: true)));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _top(_tomorrow ? 'DEMAIN · LE CADRE' : 'CE SOIR · LE CADRE', 2),
      _title('Le temps qui reste'),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text(fmtMin(free), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: kPlanAccent)),
        const SizedBox(width: 8),
        Expanded(child: Text('libres entre ${hmOf(w.startMin)} et ${hmOf(w.endMin)}', style: const TextStyle(fontSize: 13.5, color: _text2))),
      ]),
      const SizedBox(height: 10),
      Expanded(child: ListView(children: [for (final i in items) i.$2])),
      _section(_tomorrow ? 'COMMENT TU TE SENS POUR DEMAIN' : 'ET LÀ, TU TE SENS'),
      Row(children: [
        for (final l in PlanLoad.values) ...[
          if (l != PlanLoad.light) const SizedBox(width: 8),
          Expanded(
            child: _choice(
              selected: _load == l,
              onTap: () => setState(() => _load = l),
              child: Center(child: Text(kPlanLoadLabels[l]!, style: TextStyle(fontWeight: FontWeight.w800, color: _load == l ? const Color(0xFFC7D6FF) : _text2))),
            ),
          ),
        ],
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
        child: Text('${kPlanLoadLabels[_load]} = on remplit ${(fillRatio(_load) * 100).round()} % du libre · ${fmtMin(free - _budget)} de marge',
            style: const TextStyle(fontSize: 12.5, color: _text3)),
      ),
      _primary('Remplir ${fmtMin(_budget)}', () {
        _propose();
        setState(() => _step = _Step.fill);
      }),
    ]);
  }

  Widget _slot(String text, Color bg, Color fg, {bool dashed = false}) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: dashed ? Border.all(color: const Color(0xFF3A5A4A)) : null,
        ),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
      );

  Widget _fillView() {
    final total = _plan.fold<int>(0, (s, p) => s + p.minutes);
    final used = {for (final p in _plan) p.want.activityId};
    final others = logic.state.activeActivities.where((a) => !a.isHabit && a.goalMin > 0 && !used.contains(a.id) && !logic.isActivitySnoozed(a.id, _day)).take(5).toList();
    final domains = logic.state.activeDomains;
    Color colorOf(String activityId) {
      final a = logic.state.activities.where((x) => x.id == activityId).firstOrNull;
      return domainColor(a?.domainId, domains) ?? kPlanAccent;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _top(_tomorrow ? 'DEMAIN · REMPLIR' : 'CE SOIR · REMPLIR', 3),
      Row(children: [
        Expanded(child: _title(_tomorrow ? 'Ta journée de demain' : 'Ta fin de journée')),
        Text('${fmtMin(total)} / ${fmtMin(_budget)}', style: const TextStyle(fontSize: 13, color: _text2)),
      ]),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
            value: _budget == 0 ? 0 : (total / _budget).clamp(0.0, 1.0), minHeight: 8, color: kPlanAccent, backgroundColor: const Color(0xFF27382D)),
      ),
      Expanded(
        child: ListView(children: [
          _section('PROPOSÉ · GLISSE POUR RETIRER'),
          if (_plan.isEmpty)
            const Padding(padding: EdgeInsets.all(12), child: Text('Rien à poser : ajoute une activité ci-dessous, ou garde ta journée libre.', style: TextStyle(color: _text2))),
          for (final p in _plan)
            Dismissible(
              key: ValueKey('plan-${p.want.activityId}'),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => setState(() {
                _dropped.add(p.want.activityId);
                _extra.removeWhere((w) => w.activityId == p.want.activityId);
                _propose();
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Container(width: 4, height: 34, decoration: BoxDecoration(color: colorOf(p.want.activityId), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${p.want.title} · ${fmtMin(p.minutes)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                      Text('${hmOf(p.startMin)} → ${hmOf(p.endMin)}', style: const TextStyle(fontSize: 12, color: _text3)),
                    ]),
                  ),
                  Text(p.want.reason, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _gold)),
                ]),
              ),
            ),
          if (others.isNotEmpty) ...[
            _section('À CASER SI TU VEUX'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final a in others)
                ActionChip(
                  label: Text('+ ${a.name} · 45 min', style: const TextStyle(fontWeight: FontWeight.w600, color: _text2)),
                  backgroundColor: Colors.transparent,
                  side: const BorderSide(color: Color(0xFF5F7A6C)),
                  onPressed: () => setState(() {
                    _dropped.remove(a.id);
                    _extra.add(PlanWant(activityId: a.id, title: a.name, minutes: 45, reason: 'à ton choix'));
                    _propose();
                  }),
                ),
            ]),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kPlanAccent.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
            child: const Text('Blocs d\'activité, pas un bloc par action : le moment venu, la page focus enchaîne la prochaine action de chaque projet lié.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFFC7D6FF), height: 1.4)),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: SizedBox(
            height: 54,
            child: OutlinedButton(
              onPressed: () => launchUrl(claudeNewUri(planDayPrompt(date: _ymd, blocks: _blocks)), mode: LaunchMode.externalApplication),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withValues(alpha: .16)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: const Text('Avec Claude', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: _primary(_tomorrow ? 'Poser demain' : 'Poser la fin de journée', _save)),
      ]),
    ]);
  }

  Widget _doneView() {
    final total = _plan.fold<int>(0, (s, p) => s + p.minutes);
    final spent = _startedAt == null ? 0 : DateTime.now().difference(_startedAt!).inMinutes;
    final kept = _stakes.where((s) => _kept.contains(s.id)).toList();
    final left = _stakes.where((s) => !_kept.contains(s.id)).toList();
    final next = kCapTiers.firstWhere((t) => t > _capCount, orElse: () => kCapTiers.last);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _top(_tomorrow ? 'DEMAIN EST POSÉ' : 'LA FIN DE JOURNÉE EST POSÉE', 4),
      _title('${_plan.length} bloc${_plan.length > 1 ? 's' : ''} · ${fmtMin(total)}'),
      Text('Planifié en ${spent < 1 ? 'moins d\'une' : spent} min${_chrono ? ' · chrono sur Planification' : ''}', style: const TextStyle(fontSize: 13.5, color: _text2)),
      Expanded(
        child: ListView(children: [
          _section('CE QUE TU TIENS'),
          for (final s in kept.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(s.title, style: const TextStyle(fontSize: 14, color: Colors.white))),
                Text(s.detail, style: const TextStyle(fontSize: 12.5, color: _text3)),
              ]),
            ),
          if (left.isNotEmpty) ...[
            _section('LAISSÉ POUR PLUS TARD'),
            Text(left.map((s) => s.title).join(' · '), style: const TextStyle(fontSize: 13, color: _text3)),
          ],
          const SizedBox(height: 16),
          if (_tomorrow)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: kPlanAccent.withValues(alpha: .45))),
              child: Row(children: [
                const Icon(Icons.explore_outlined, size: 40, color: Color(0xFFC7D6FF)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Cap tenu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFFC7D6FF))),
                    Text('$_capCount / $next journées · palier $next', style: const TextStyle(fontSize: 13, color: _text2)),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(value: (_capCount / next).clamp(0.0, 1.0), minHeight: 6, color: kPlanAccent, backgroundColor: const Color(0xFF27382D)),
                    ),
                    const SizedBox(height: 4),
                    const Text('Planifiée la veille et tenue à 70 % : la journée compte.', style: TextStyle(fontSize: 11.5, color: _text3)),
                  ]),
                ),
              ]),
            ),
        ]),
      ),
      _primary(_tomorrow ? 'Terminer · bonne nuit' : 'Terminer', _finish),
    ]);
  }
}
