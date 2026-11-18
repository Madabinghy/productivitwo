import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDayBlocks, livedYmd;
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show routineTodayCount;
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFolderProject, isOverdueAction, isUpcomingTask;
import 'package:productivitwo_v1/utils/parole.dart';
import 'package:productivitwo_v1/utils/planning.dart';
import 'package:productivitwo_v1/utils/project_health.dart' show nextAction;
import 'package:productivitwo_v1/utils/project_moment.dart' show rankProjectMoments;
import 'package:productivitwo_v1/utils/reading_due.dart' show readingsDue;
import 'package:productivitwo_v1/utils/recharge.dart' show isBasicNeedName;
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

Future<void> showPlanScreen(BuildContext context, AppLogic logic, {BadgeCenter? badges, VoidCallback? onOpenProgram}) {
  return Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true, builder: (_) => PlanScreen(logic: logic, badges: badges, onOpenProgram: onOpenProgram)));
}

enum _Step { cap, stakes, frame, fill, parole, done }

class PlanScreen extends StatefulWidget {
  final AppLogic logic;
  final BadgeCenter? badges;
  /// « Voir mon programme » de l'écran final (feuille Programme d'Aujourd'hui).
  final VoidCallback? onOpenProgram;
  const PlanScreen({super.key, required this.logic, this.badges, this.onOpenProgram});

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
  /// Routines écartées au moment de poser (« pas ce soir » / « pas demain ») : écrites dans `nowDoneByYmd`.
  final Set<String> _excused = {};
  bool _routinesOpen = false;
  List<PlannedBlock> _plan = const [];
  final List<PlanWant> _extra = [];
  final Set<String> _dropped = {};
  /// Heure et durée choisies à la main (activité → (début, minutes)) : gardées telles quelles à chaque nouvelle proposition.
  final Map<String, (int, int)> _manual = {};
  bool _loading = false;
  int _capCount = 0;
  /// Blocs de temps (Deep work · Petites choses · Tampon) plutôt que blocs
  /// d'activité : on choisit quoi faire au moment de lancer le bloc.
  bool _timeMode = true;
  static const _kTimeModePref = 'plan_time_mode';
  /// Parole tenue : les actions choisies pour demain (ids), dans l'ordre.
  final List<String> _parole = [];
  Set<String> _paroleBefore = {};
  bool _paroleGiven = false;

  @override
  void initState() {
    super.initState();
    // Le matin, on pose plutôt la journée en cours ; l'après-midi et le soir, demain.
    _tomorrow = logic.livedNowMinNow >= 12 * 60;
    // Chrono : activé d'office si une activité « Planification » existe ; ensuite le dernier choix.
    _chrono = _planningActivity() != null;
    SharedPreferences.getInstance().then((p) {
      final v = p.getBool(_kChronoPref);
      if (v != null && mounted) setState(() => _chrono = v);
      final t = p.getBool(_kTimeModePref);
      if (t != null && mounted) setState(() => _timeMode = t);
    }).catchError((_) {});
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _runningSession != null) setState(() {});
    });
  }

  static const _kChronoPref = 'plan_chrono';
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Session? get _runningSession {
    final a = _planningActivity();
    if (a == null) return null;
    return logic.state.sessions.where((s) => s.endAt == null && !s.deleted && s.activityId == a.id).firstOrNull;
  }

  void _setChrono(bool v) {
    setState(() => _chrono = v);
    SharedPreferences.getInstance().then((p) => p.setBool(_kChronoPref, v)).catchError((_) => false);
  }

  /// Lance le chrono sur « Planification » (activité créée au besoin dans Organisation).
  void _startPlanningChrono() {
    var a = _planningActivity();
    if (a == null) {
      final domains = logic.state.activeDomains;
      final d = domains.where((d) => d.name.toLowerCase().contains('organis')).firstOrNull ?? domains.firstOrNull;
      if (d == null) return;
      a = Activity(domainId: d.id, name: 'Planification', goalMin: 0);
      logic.state.activities.add(a);
      logic.onChange();
    }
    logic.start(a.id);
  }

  /// Pastille du chrono dans la barre : temps qui défile, tap = arrêter / relancer.
  Widget _chronoPill() {
    final s = _runningSession;
    if (s == null && _step == _Step.cap) return const SizedBox.shrink();
    final running = s != null;
    String label = 'Chrono';
    if (running) {
      final d = DateTime.now().difference(s.startAt);
      final m = d.inMinutes, sec = d.inSeconds % 60;
      label = '$m:${sec.toString().padLeft(2, '0')}';
    }
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: running ? kPlanAccent.withValues(alpha: .16) : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: running ? kPlanAccent : Colors.white.withValues(alpha: .2))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => setState(() {
            if (running) {
              logic.stopActive();
            } else {
              _startPlanningChrono();
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(running ? Icons.timer : Icons.play_arrow_rounded, size: 15, color: running ? kPlanAccent : _text3),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: running ? const Color(0xFFC7D6FF) : _text3, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        ),
      ),
    );
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
    final already = logic.nowDoneSet(_excuseYmd);
    _kept.removeWhere((id) => id.startsWith('routine:') && already.contains(id.substring(8)));
    if (_tomorrow) {
      final ids = [
        for (final e in _paroleIndex.entries)
          if (!e.value.action.done && e.value.action.focusDate != null && ymdOf(e.value.action.focusDate!) == _ymd) e.key,
      ];
      _parole
        ..clear()
        ..addAll(ids);
      _paroleBefore = ids.toSet();
    }
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
      // Fin de journée : une routine déjà atteinte ne se joue plus.
      if (!_tomorrow && routineTodayCount(logic, a) >= logic.effectiveHabitTarget(a).clamp(1, 999999)) continue;
      out.add(PlanStake(id: 'routine:${a.id}', kind: PlanStakeKind.losing, title: a.name, detail: 'série $s j'));
    }
    final facts = widget.badges?.todayFacts();
    for (final p in facts?.pace ?? const []) {
      final need = _tomorrow ? p.tomorrowNeedMin : p.missingMin;
      // Sommeil, sieste, repas : jamais un bloc proposé (un « Sommeil » à 15:15 n'a pas de sens).
      if (need <= 0 || isBasicNeedName(p.activity.name)) continue;
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

  /// Clé de la journée vécue visée (`YYYYMMDD`, celle de `nowDoneByYmd`).
  String get _excuseYmd => livedYmd(DateTime.now().add(Duration(days: _tomorrow ? 1 : 0)), logic.dayStartMin);

  Color colorOf(String activityId) {
    final tk = timeKindOf(activityId);
    if (tk != null) return kTimeBlockColors[tk]!;
    final a = logic.state.activities.where((x) => x.id == activityId).firstOrNull;
    return domainColor(a?.domainId, logic.state.activeDomains) ?? kPlanAccent;
  }

  bool _isRoutine(PlanStake s) => s.id.startsWith('routine:');

  /// Ce qu'un bloc proposé couvre : les enjeux cochés qui visent son activité.
  List<String> _coveredBy(String activityId) => [
        for (final s in _stakes)
          if (s.activityId == activityId && _kept.contains(s.id)) s.title.startsWith('Préparer · ') ? s.title.substring(11) : s.title,
      ];

  String _evening(String tonight, String tomorrow) => _tomorrow ? tomorrow : tonight;

  /// Écrit le choix des routines : décochée = écartée pour la journée visée, cochée = remise.
  void _applyExcuses() {
    final ids = logic.nowDoneSet(_excuseYmd);
    _excused.clear();
    for (final s in _stakes.where(_isRoutine)) {
      final id = s.id.substring(8);
      if (_kept.contains(s.id)) {
        ids.remove(id);
      } else {
        ids.add(id);
        _excused.add(id);
      }
    }
    logic.setNowDone(_excuseYmd, ids);
  }

  void _restoreExcused() {
    final ids = logic.nowDoneSet(_excuseYmd)..removeAll(_excused);
    logic.setNowDone(_excuseYmd, ids);
    setState(() {
      for (final id in _excused) {
        _kept.add('routine:$id');
      }
      _excused.clear();
    });
  }

  String _activityName(String id) => logic.state.activities.where((a) => a.id == id).map((a) => a.name).firstOrNull ?? 'Activité';

  /// « pour : … » sous un bloc Deep work : un aperçu de ce qui sera en tête
  /// au moment de le lancer (rien n'est attribué au bloc).
  String _deepPreview() {
    final names = <String>[
      for (final id in _parole)
        if (_paroleIndex[id] != null) _paroleIndex[id]!.action.title,
      for (final st in _stakes.where((x) => x.kind == PlanStakeKind.behind && _kept.contains(x.id))) st.title,
    ];
    if (names.isEmpty) return 'ce qui sera le plus utile à ce moment-là';
    return 'pour : ${names.take(3).join(' · ')}';
  }

  void _propose() {
    final wants = <PlanWant>[];
    final ids = <String>{};
    if (_timeMode) {
      wants.addAll(timeBlockWants(_budget, reasons: {'deep': 'Offensive · ${_deepPreview()}', 'small': 'Guérilla · routines et petites actions'}));
      ids.addAll(wants.map((w) => w.activityId));
    }
    for (final kind in _timeMode ? const <PlanStakeKind>[] : [PlanStakeKind.dated, PlanStakeKind.losing, PlanStakeKind.behind]) {
      for (final s in _stakes.where((s) => s.kind == kind && _kept.contains(s.id) && s.activityId != null)) {
        if (!ids.add(s.activityId!)) continue;
        wants.add(PlanWant(activityId: s.activityId!, title: _activityName(s.activityId!), minutes: s.minutes, reason: _reasonOf(s)));
      }
    }
    for (final w in _extra) {
      if ((timeKindOf(w.activityId) != null) != _timeMode) continue;
      if (ids.add(w.activityId)) wants.add(w);
    }
    final fixed = <PlannedBlock>[];
    final rest = <PlanWant>[];
    for (final w in wants.where((w) => !_dropped.contains(w.activityId))) {
      final m = _manual[w.activityId];
      m == null ? rest.add(w) : fixed.add(PlannedBlock(w, m.$1, m.$2));
    }
    // Les blocs réglés à la main occupent leur créneau ; le reste se pose autour.
    final busy = [
      ..._blocks,
      for (final f in fixed) ScheduleBlock(startTime: hmOf(f.startMin), durationMin: f.minutes, title: f.want.title, category: 'project'),
    ];
    final used = fixed.fold<int>(0, (s, f) => s + f.minutes);
    // Ajoutés à la main (« + … ») : posés APRÈS le reste, sur le temps libre
    // réel — le plafond de l'état (Léger / Normal / À fond) ne vaut que pour
    // la proposition, pas pour un ajout explicite.
    final extraIds = _extra.map((w) => w.activityId).toSet();
    final core = rest.where((w) => !extraIds.contains(w.activityId)).toList();
    final added = rest.where((w) => extraIds.contains(w.activityId)).toList();
    final first = proposeDay(freeGaps(busy, _effectiveWindow), core, _budget - used < 0 ? 0 : _budget - used);
    final busy2 = [
      ...busy,
      for (final f in first) ScheduleBlock(startTime: hmOf(f.startMin), durationMin: f.minutes, title: f.want.title, category: 'project'),
    ];
    final gaps2 = freeGaps(busy2, _effectiveWindow);
    final second = proposeDay(gaps2, added, freeMinutes(gaps2));
    _plan = [...fixed, ...first, ...second]..sort((a, b) => a.startMin.compareTo(b.startMin));
  }

  /// « + … » : ajoute un bloc ; s'il ne tient nulle part, on le dit (avant,
  /// l'ajout était ignoré sans un mot).
  void _addExtra(PlanWant w) {
    setState(() {
      _dropped.remove(w.activityId);
      _extra.add(w);
      _propose();
    });
    if (_plan.any((p) => p.want.activityId == w.activityId)) return;
    setState(() {
      _extra.removeWhere((x) => x.activityId == w.activityId);
      _propose();
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showClosingSnackBar(SnackBar(content: Text('Plus de créneau libre de 30 min pour ${w.title} : raccourcis ou retire un bloc.')));
  }

  /// Les blocs DÉJÀ posés de la journée visée (fin de journée : ceux qui ne
  /// sont pas finis), affichés dans la liste à leur heure.
  List<ScheduleBlock> get _shownPosed {
    final from = _tomorrow ? 0 : _effectiveWindow.startMin;
    return _blocks.where((b) => b.status == 'pending' && blockStartMin(b) + b.durationMin > from).toList();
  }

  List<({ScheduleBlock? posed, PlannedBlock? planned})> _timeline() {
    final out = <(int, ({ScheduleBlock? posed, PlannedBlock? planned}))>[
      for (final b in _shownPosed) (blockStartMin(b), (posed: b, planned: null)),
      for (final p in _plan) (p.startMin, (posed: null, planned: p)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final e in out) e.$2];
  }

  Widget _posedRow(ScheduleBlock b) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF3A5A4A))),
        child: Row(children: [
          const Icon(Icons.lock_outline, size: 16, color: _text3),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${b.title} · ${fmtMin(b.durationMin)}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _text2)),
              Text('${b.startTime} → ${hmOf(blockStartMin(b) + b.durationMin)} · déjà posé', style: const TextStyle(fontSize: 12, color: _text3)),
            ]),
          ),
        ]),
      );

  /// Régler un bloc proposé : heure de début (pas de 15 min) et durée.
  Future<void> _editPlanned(PlannedBlock p) async {
    var start = p.startMin, minutes = p.minutes;
    final res = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final clash = _blocks
            .where((b) => blockStartMin(b) < start + minutes && blockStartMin(b) + b.durationMin > start)
            .map((b) => '${b.startTime} ${b.title}')
            .firstOrNull;
        Widget stepper(String label, String value, VoidCallback minus, VoidCallback plus, {VoidCallback? onValue}) => Row(children: [
              SizedBox(width: 72, child: Text(label, style: const TextStyle(fontSize: 13, color: _text3))),
              IconButton(onPressed: minus, icon: const Icon(Icons.remove_circle_outline, color: _text2)),
              Expanded(
                child: InkWell(
                  onTap: onValue,
                  child: Center(child: Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white))),
                ),
              ),
              IconButton(onPressed: plus, icon: const Icon(Icons.add_circle_outline, color: _text2)),
            ]);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(p.want.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              Text('${hmOf(start)} → ${hmOf(start + minutes)} · ${p.want.reason}', style: const TextStyle(fontSize: 13, color: _text3)),
              const SizedBox(height: 12),
              stepper('Début', hmOf(start), () => set(() => start = (start - 15).clamp(0, 24 * 60 - 15)), () => set(() => start = (start + 15).clamp(0, 24 * 60 - 15)),
                  onValue: () async {
                final t = await showTimePicker(context: ctx, initialTime: TimeOfDay(hour: start ~/ 60, minute: start % 60));
                if (t != null) set(() => start = t.hour * 60 + (t.minute ~/ 5) * 5);
              }),
              stepper('Durée', fmtMin(minutes), () => set(() => minutes = (minutes - 15).clamp(15, 6 * 60)), () => set(() => minutes = (minutes + 15).clamp(15, 6 * 60))),
              Wrap(spacing: 6, children: [
                for (final m in const [30, 45, 60, 90, 120])
                  ChoiceChip(
                    label: Text(fmtMin(m)),
                    selected: minutes == m,
                    selectedColor: kPlanAccent,
                    labelStyle: TextStyle(color: minutes == m ? _ink : _text2, fontWeight: FontWeight.w700),
                    backgroundColor: Colors.transparent,
                    onSelected: (_) => set(() => minutes = m),
                  ),
              ]),
              if (clash != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Chevauche « $clash » déjà au programme.', style: const TextStyle(fontSize: 12.5, color: _gold)),
                ),
              const SizedBox(height: 14),
              Row(children: [
                TextButton(onPressed: () => Navigator.pop(ctx, 'drop'), child: const Text('Retirer', style: TextStyle(color: _ember))),
                const Spacer(),
                SizedBox(width: 160, child: _primary('Garder', () => Navigator.pop(ctx, 'ok'))),
              ]),
            ]),
          ),
        );
      }),
    );
    if (!mounted || res == null) return;
    setState(() {
      if (res == 'drop') {
        _manual.remove(p.want.activityId);
        _dropped.add(p.want.activityId);
        _extra.removeWhere((w) => w.activityId == p.want.activityId);
      } else {
        _manual[p.want.activityId] = (start, minutes);
      }
      _propose();
    });
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
    if (_chrono && _runningSession == null) _startPlanningChrono();
    setState(() => _step = _Step.stakes);
    _load2();
  }

  Future<void> _save() async {
    _applyExcuses();
    final doc = _doc ?? DailySchedule(date: _ymd);
    for (final p in _plan) {
      doc.blocks.add(planOrTimeBlockOf(p));
    }
    doc
      ..generatedBy = 'plan'
      ..generatedAt = DateTime.now()
      ..plannedAt = DateTime.now()
      ..plannedSameDay = !_tomorrow;
    await sync.saveDailySchedule(doc);
    // Journée posée : la routine « Planifier ma journée » prend son +1 (2026-11-04).
    logic.countPlannedDay();
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
    if (a != null && _runningSession != null) {
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
                  _Step.parole => _paroleView(),
                  _Step.done => _doneView(),
                },
        ),
      ),
    );
  }

  Widget _top(String label, int stepIdx) => SizedBox(
        height: 48,
        child: Row(children: [
          Expanded(child: Text(label, maxLines: 2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1, color: kPlanAccent))),
          _chronoPill(),
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
          Switch(value: _chrono, activeColor: kPlanAccent, onChanged: _setChrono),
        ]),
      ),
      const Spacer(),
      _primary(_tomorrow ? 'Planifier demain' : 'Planifier la fin de journée', _begin),
    ]);
  }

  Widget _stakesView() {
    Widget box(List<PlanStake> list, {bool locked = false, bool routines = false}) => Container(
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: _line),
              Builder(builder: (_) {
                final st = list[i];
                final on = _kept.contains(st.id);
                final detail = routines && !on ? '${st.detail} s\'arrête' : st.detail;
                return CheckboxListTile(
                  key: ValueKey('stake-${st.id}'),
                  value: on,
                  onChanged: locked ? null : (v) => setState(() => v == true ? _kept.add(st.id) : _kept.remove(st.id)),
                  activeColor: kPlanAccent,
                  checkColor: _ink,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text(st.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: routines && !on ? _text3 : Colors.white)),
                  secondary: Text(detail,
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 12, color: routines ? _ember : (st.kind == PlanStakeKind.behind ? _gold : (st.kind == PlanStakeKind.losing ? _ember : _text3)))),
                );
              }),
            ],
          ]),
        );

    final dated = _stakes.where((x) => x.kind == PlanStakeKind.dated).toList();
    final timed = _stakes.where((x) => x.kind != PlanStakeKind.dated && x.activityId != null).toList();
    final routines = _stakes.where(_isRoutine).toList();
    final notes = _stakes.where((x) => x.kind != PlanStakeKind.dated && x.activityId == null && !_isRoutine(x)).toList();
    final timedCount = timed.where((x) => _kept.contains(x.id)).length;
    final off = routines.where((x) => !_kept.contains(x.id)).toList();
    final when = _evening('ce soir', 'demain');
    final cta = [
      timedCount == 0 ? 'Voir le temps' : 'Placer $timedCount chose${timedCount > 1 ? 's' : ''}',
      if (off.isNotEmpty) 'écarter ${off.length}',
    ].join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _top(_tomorrow ? 'DEMAIN · CE QUI SE JOUE' : 'CE SOIR · CE QUI SE JOUE', 1),
      _title(_evening('Qu\'est-ce que tu veux placer ce soir ?', 'Qu\'est-ce que tu veux placer demain ?')),
      const Text('Ce qui demande du temps devient un bloc dans ton programme.', style: TextStyle(fontSize: 13.5, color: _text2)),
      Expanded(
        child: ListView(children: [
          if (_stakes.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('Rien de daté ni d\'urgent : journée libre à remplir.', style: TextStyle(color: _text2))),
          if (dated.isNotEmpty) ...[_section('DÉJÀ POSÉ · NE BOUGE PAS'), box(dated, locked: true)],
          if (timed.isNotEmpty) ...[_section('À PLACER DANS LE TEMPS'), box(timed)],
          if (notes.isNotEmpty) ...[_section('À NOTER · PAS DE BLOC'), box(notes)],
          if (routines.isNotEmpty) ...[
            _section('ROUTINES · PAS DE BLOC · DÉCOCHE = PAS ${when.toUpperCase()}'),
            InkWell(
              key: const ValueKey('plan-routines-fold'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _routinesOpen = !_routinesOpen),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        off.isEmpty ? '${routines.length} routine${routines.length > 1 ? 's' : ''} à tenir · toutes cochées' : '${routines.length - off.length} tenue${routines.length - off.length > 1 ? 's' : ''} · ${off.length} écartée${off.length > 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                  Text(_routinesOpen ? 'replier' : 'voir', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _ember)),
                  Icon(_routinesOpen ? Icons.expand_less : Icons.expand_more, color: _ember, size: 20),
                ]),
              ),
            ),
            if (_routinesOpen) ...[const SizedBox(height: 6), box(routines, routines: true)],
            if (off.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    '${off.length} écartée${off.length > 1 ? 's' : ''} pour $when : Journée parfaite reste possible sans elle${off.length > 1 ? 's' : ''} et ${off.length > 1 ? 'leurs séries s\'arrêtent' : 'sa série s\'arrête'}.',
                    style: const TextStyle(fontSize: 12.5, color: _gold, height: 1.35)),
              ),
          ],
        ]),
      ),
      const SizedBox(height: 10),
      _primary(cta, () => setState(() => _step = _Step.frame)),
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
    final others = logic.state.activeActivities.where((a) => !a.isHabit && a.goalMin > 0 && !isBasicNeedName(a.name) && !used.contains(a.id) && !logic.isActivitySnoozed(a.id, _day)).take(5).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _top(_tomorrow ? 'DEMAIN · REMPLIR' : 'CE SOIR · REMPLIR', 3),
      Row(children: [
        Expanded(child: _title(_tomorrow ? 'Ta journée de demain' : 'Ta fin de journée')),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${fmtMin(total)} proposées', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _text2)),
          Text('sur ${fmtMin(_budget)} · ${kPlanLoadLabels[_load]}', style: const TextStyle(fontSize: 11.5, color: _text3)),
        ]),
      ]),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
            value: _budget == 0 ? 0 : (total / _budget).clamp(0.0, 1.0), minHeight: 8, color: kPlanAccent, backgroundColor: const Color(0xFF27382D)),
      ),
      const SizedBox(height: 10),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('Blocs de temps')),
          ButtonSegment(value: false, label: Text('Détailler par activité')),
        ],
        selected: {_timeMode},
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: kPlanAccent,
          selectedForegroundColor: _ink,
          foregroundColor: _text2,
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
        onSelectionChanged: (v) {
          setState(() {
            _timeMode = v.first;
            _manual.clear();
            _dropped.clear();
            _propose();
          });
          SharedPreferences.getInstance().then((p) => p.setBool(_kTimeModePref, v.first)).catchError((_) => false);
        },
      ),
      if (_timeMode)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Du temps réservé à un mode : Deep work lance une Offensive, Petites choses une Guérilla. Tu choisis sur quoi au moment venu.', style: TextStyle(fontSize: 12.5, color: _text2)),
        ),
      Expanded(
        child: ListView(children: [
          _section(_tomorrow ? 'TA JOURNÉE · TOUCHE UN BLOC PROPOSÉ POUR LE RÉGLER, GLISSE POUR LE RETIRER' : 'TA FIN DE JOURNÉE · TOUCHE UN BLOC PROPOSÉ POUR LE RÉGLER, GLISSE POUR LE RETIRER'),
          if (_plan.isEmpty && _shownPosed.isEmpty)
            const Padding(padding: EdgeInsets.all(12), child: Text('Rien à poser : ajoute un bloc ci-dessous, ou garde ta journée libre.', style: TextStyle(color: _text2))),
          for (final e in _timeline())
            if (e.posed case final b?) _posedRow(b) else Builder(builder: (_) { final p = e.planned!; return Dismissible(
              key: ValueKey('plan-${p.want.activityId}'),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => setState(() {
                _manual.remove(p.want.activityId);
                _dropped.add(p.want.activityId);
                _extra.removeWhere((w) => w.activityId == p.want.activityId);
                _propose();
              }),
              child: GestureDetector(
                onTap: () => _editPlanned(p),
                child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                  border: _manual.containsKey(p.want.activityId) ? Border.all(color: kPlanAccent.withValues(alpha: .5)) : null,
                ),
                child: Row(children: [
                  Container(width: 4, height: 34, decoration: BoxDecoration(color: colorOf(p.want.activityId), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${p.want.title} · ${fmtMin(p.minutes)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                      Text('${hmOf(p.startMin)} → ${hmOf(p.endMin)}', style: const TextStyle(fontSize: 12, color: _text3)),
                      if (timeKindOf(p.want.activityId) != null && p.want.reason.isNotEmpty)
                        Text(p.want.reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colorOf(p.want.activityId))),
                      if (_coveredBy(p.want.activityId) case final c when c.isNotEmpty)
                        Text('pour : ${c.join(' · ')}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Color(0xFFDFE6E1))),
                      if (_coveredBy(p.want.activityId).length > 1)
                        Text('${_coveredBy(p.want.activityId).length} choses en ${fmtMin(p.minutes)} : ≈ ${fmtMin(p.minutes ~/ _coveredBy(p.want.activityId).length)} chacune · touche pour allonger',
                            style: const TextStyle(fontSize: 12, color: _gold)),
                    ]),
                  ),
                  if (timeKindOf(p.want.activityId) == null) Text(p.want.reason, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _gold)),
                  const SizedBox(width: 6),
                  const Icon(Icons.tune, size: 18, color: _text3),
                ]),
              ),
              ),
            ); }),
          if (_timeMode) ...[
            _section('AJOUTER'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in const ['deep', 'small', 'morning', 'leisure'])
                ActionChip(
                  label: Text('+ ${kTimeBlockLabels[k]}', style: TextStyle(fontWeight: FontWeight.w700, color: kTimeBlockColors[k])),
                  backgroundColor: Colors.transparent,
                  side: BorderSide(color: kTimeBlockColors[k]!),
                  onPressed: () => _addExtra(PlanWant(
                      activityId: timeWantId(k, 100 + _extra.length),
                      title: kTimeBlockLabels[k]!,
                      minutes: timeBlockDefaultMin(k),
                      reason: switch (k) {
                        'deep' => 'Offensive · ${_deepPreview()}',
                        'morning' => 'Tes étapes du matin, dans ton ordre',
                        'leisure' => 'Du temps pour souffler · ne pèse sur rien',
                        _ => 'Guérilla · routines et petites actions',
                      })),
                ),
            ]),
          ] else if (others.isNotEmpty) ...[
            _section('AJOUTER · 45 MIN SUR TON TEMPS LIBRE'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final a in others)
                ActionChip(
                  label: Text('+ ${a.name} · 45 min', style: const TextStyle(fontWeight: FontWeight.w600, color: _text2)),
                  backgroundColor: Colors.transparent,
                  side: const BorderSide(color: Color(0xFF5F7A6C)),
                  onPressed: () => _addExtra(PlanWant(activityId: a.id, title: a.name, minutes: 45, reason: 'à ton choix')),
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
        Expanded(
          flex: 2,
          child: _tomorrow
              ? _primary('Suivant · ta parole', () => setState(() => _step = _Step.parole))
              : _primary(_plan.isEmpty ? 'Poser la fin de journée' : 'Ajouter au programme · ${_plan.length} bloc${_plan.length > 1 ? 's' : ''}', _save),
        ),
      ]),
    ]);
  }

  Widget _doneView() {
    final spent = _startedAt == null ? 0 : DateTime.now().difference(_startedAt!).inMinutes;
    final left = _stakes.where((s) => !_kept.contains(s.id) && !_isRoutine(s) && s.kind != PlanStakeKind.dated).toList();
    final held = _stakes.where((s) => _isRoutine(s) && _kept.contains(s.id)).length;
    final excusedNames = [for (final s in _stakes) if (_isRoutine(s) && _excused.contains(s.id.substring(8))) s.title];
    final next = kCapTiers.firstWhere((t) => t > _capCount, orElse: () => kCapTiers.last);
    final when = _evening('ce soir', 'demain');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _top(_tomorrow ? 'DEMAIN EST POSÉ' : 'LA FIN DE JOURNÉE EST POSÉE', 4),
      _title(_plan.isEmpty ? 'Rien d\'ajouté au programme' : 'Ajouté à ton programme'),
      Text('Planifié en ${spent < 1 ? 'moins d\'une' : spent} min${_chrono ? ' · chrono sur Planification' : ''}', style: const TextStyle(fontSize: 13.5, color: _text2)),
      Expanded(
        child: ListView(children: [
          const SizedBox(height: 8),
          for (final p in _plan)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Container(width: 4, height: 34, decoration: BoxDecoration(color: colorOf(p.want.activityId), borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${p.want.title} · ${hmOf(p.startMin)} → ${hmOf(p.endMin)}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.white)),
                    if (_coveredBy(p.want.activityId) case final c when c.isNotEmpty)
                      Text('pour : ${c.join(' · ')}', style: const TextStyle(fontSize: 12.5, color: Color(0xFFDFE6E1))),
                  ]),
                ),
              ]),
            ),
          if (_plan.isNotEmpty && widget.onOpenProgram != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton(
                key: const ValueKey('plan-open-program'),
                onPressed: () {
                  _finish();
                  widget.onOpenProgram!();
                },
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFC8D4FF),
                    minimumSize: const Size.fromHeight(46),
                    side: BorderSide(color: kPlanAccent.withValues(alpha: .5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23))),
                child: const Text('Voir mon programme', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          if (held > 0 || excusedNames.isNotEmpty) ...[
            _section('ROUTINES'),
            if (held > 0) Text('$held à tenir au fil de ${_evening('la soirée', 'la journée')}', style: const TextStyle(fontSize: 14, color: Colors.white)),
            if (excusedNames.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('Écartée${excusedNames.length > 1 ? 's' : ''} $when : ', style: const TextStyle(fontSize: 13, color: _ember)),
                  Text('${excusedNames.join(', ')} · série${excusedNames.length > 1 ? 's' : ''} arrêtée${excusedNames.length > 1 ? 's' : ''} · ',
                      style: const TextStyle(fontSize: 13, color: _text3)),
                  GestureDetector(
                    key: const ValueKey('plan-restore-excused'),
                    onTap: _restoreExcused,
                    child: const Text('annuler', style: TextStyle(fontSize: 13, color: _text2, decoration: TextDecoration.underline)),
                  ),
                ]),
              ),
          ],
          if (left.isNotEmpty) ...[
            _section('LAISSÉ POUR PLUS TARD'),
            Text(left.map((s) => s.title).join(' · '), style: const TextStyle(fontSize: 13, color: _text3)),
          ],
          if (_paroleGiven) ...[
            _section('TA PAROLE POUR DEMAIN · ${_parole.length}'),
            for (final id in _parole)
              if (_paroleIndex[id] != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('· ${_paroleIndex[id]!.action.title}', style: const TextStyle(fontSize: 14, color: Colors.white)),
                ),
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

  // ── Parole tenue (2026-10-31) ───────────────────────────────────────────────

  Map<String, ParoleAction>? _paroleIndexCache;
  Map<String, ParoleAction> get _paroleIndex =>
      _paroleIndexCache ??= paroleIndex(logic.currentProjects.where(_liveProject).toList(), logic.state.activities);

  bool _liveProject(Project p) =>
      p.status != 'archived' && p.status != 'done' && !p.paused && !isFolderProject(p, logic.currentProjects);

  List<ParoleProposal> get _proposals {
    final today = logic.livedToday;
    return paroleProposals(
      index: _paroleIndex,
      projects: logic.currentProjects,
      today: today,
      chosen: _parole.toSet(),
      nextActionOf: (p) {
        final n = nextAction(p);
        if (n == null || isUpcomingTask(n.task, _day)) return null;
        return n;
      },
      isLive: _liveProject,
      isOverdue: (a, t) => isOverdueAction(a, t, today),
    );
  }

  int _estOf(TaskAction a) => a.estimatedMin ?? 45;

  Widget _paroleView() {
    final chosen = [for (final id in _parole) if (_paroleIndex[id] != null) _paroleIndex[id]!];
    final total = chosen.fold<int>(0, (s, x) => s + _estOf(x.action));
    final planned = _plan.fold<int>(0, (s, p) => s + p.minutes);
    final free = freeMinutes(_gaps);
    final props = _proposals;
    final enough = chosen.length >= kParoleMin;
    Widget row(ParoleAction x, {int? rank, String? reason, bool warn = false}) {
      final selected = rank != null;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: selected ? _card : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: selected ? kPlanAccent.withValues(alpha: .45) : const Color(0xFF2C4436)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => selected ? _parole.remove(x.action.id) : _parole.add(x.action.id)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              child: Row(children: [
                if (selected)
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: kPlanAccent, shape: BoxShape.circle),
                    child: Text('$rank', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _ink)),
                  )
                else
                  const SizedBox(width: 26, child: Icon(Icons.add, color: kPlanAccent)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(x.action.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.white)),
                    Text(
                      [x.context, if (reason != null) reason, '≈ ${fmtMin(_estOf(x.action))}'].where((t) => t.isNotEmpty).join(' · '),
                      style: TextStyle(fontSize: 12, color: warn ? const Color(0xFFFFB27A) : _text3),
                    ),
                  ]),
                ),
                if (selected) const Icon(Icons.close, size: 18, color: _text3),
              ]),
            ),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _top('DEMAIN · TA PAROLE', 4),
      _title('Ta parole pour demain'),
      Text('Au moins $kParoleMin actions que tu t\'engages à finir demain. Toutes faites demain soir = une journée de Parole tenue.',
          style: const TextStyle(fontSize: 13.5, color: _text2, height: 1.4)),
      Expanded(
        child: ListView(children: [
          _section('TA PAROLE · ${chosen.length}'),
          if (chosen.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Touche une proposition pour l\'ajouter.', style: TextStyle(fontSize: 13, color: _text3, fontStyle: FontStyle.italic)),
            ),
          for (var i = 0; i < chosen.length; i++) row(chosen[i], rank: i + 1),
          if (chosen.isNotEmpty)
            Text(
              '≈ ${fmtMin(total)} au total · ${fmtMin((free - planned).clamp(0, 24 * 60))} libres demain après tes blocs${total > (free - planned) ? ' : ça déborde' : ' : ça tient'}',
              style: TextStyle(fontSize: 12.5, color: total > (free - planned) ? const Color(0xFFFFB27A) : _text3),
            ),
          if (props.isNotEmpty) ...[
            _section('PROPOSÉES · TAP POUR AJOUTER'),
            for (final p in props) row(p.item, reason: p.reason, warn: p.warn),
          ],
        ]),
      ),
      Text(
        enough ? 'Tu pourras en ajouter demain, mais seule la parole donnée ce soir compte pour le badge.' : 'Encore ${kParoleMin - chosen.length} pour donner ta parole.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: _text3),
      ),
      const SizedBox(height: 8),
      _primary(enough ? 'Donner ma parole · ${chosen.length} actions' : 'Poser demain sans parole', () => _giveParoleAndSave(enough)),
    ]);
  }

  Future<void> _giveParoleAndSave(bool give) async {
    final day = _day;
    final projects = <String, Project>{};
    final activities = <String, Activity>{};
    void touch(ParoleAction x) {
      if (x.project != null) projects[x.project!.id] = x.project!;
      if (x.activity != null) activities[x.activity!.id] = x.activity!;
    }
    // Retirées de la liste : elles ne sont plus visées demain.
    for (final id in _paroleBefore.difference(_parole.toSet())) {
      final x = _paroleIndex[id];
      if (x == null) continue;
      x.action.focusDate = null;
      touch(x);
    }
    for (final id in _parole) {
      final x = _paroleIndex[id];
      if (x == null) continue;
      final f = x.action.focusDate;
      if (f == null || ymdOf(f) != _ymd) {
        x.action.focusDate = DateTime(day.year, day.month, day.day);
        touch(x);
      }
    }
    for (final p in projects.values) {
      unawaited(sync.saveProjectTasks(p.id, p.tasks));
    }
    for (final a in activities.values) {
      unawaited(sync.updateOwnActions(a.id, a.ownActions));
    }
    if (give) {
      await logic.giveParole(_ymd, List.of(_parole));
      _paroleGiven = true;
    }
    logic.onChange();
    await _save();
  }
}
