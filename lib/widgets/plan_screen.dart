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
import 'package:productivitwo_v1/utils/fiche_cache.dart' show FicheCache;
import 'package:productivitwo_v1/utils/interventions.dart' show interventionsOf, linkMirrorsToSessions;
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDayBlocks;
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFolderProject, isOverdueAction, isUpcomingTask;
import 'package:productivitwo_v1/utils/parole.dart';
import 'package:productivitwo_v1/utils/planning.dart';
import 'package:productivitwo_v1/utils/project_health.dart' show nextAction;
import 'package:productivitwo_v1/utils/project_moment.dart' show rankProjectMoments;
import 'package:productivitwo_v1/utils/reading_due.dart' show readingsDue;
import 'package:productivitwo_v1/utils/recharge.dart' show isBasicNeedName;
import 'package:productivitwo_v1/utils/today_logic.dart' show blockEndMin, blockStartMin;
import 'package:productivitwo_v1/utils/week_capacity.dart' show DayWindow;
import 'package:productivitwo_v1/utils/week_place.dart';
import 'package:productivitwo_v1/utils/week_spread.dart';
import 'package:productivitwo_v1/widgets/activity_picker.dart' show showActivityPicker;
import 'package:productivitwo_v1/widgets/gcal_settings_sheet.dart' show gcalSyncDay;
import 'package:productivitwo_v1/utils/sport_stats.dart' show resolveSportPick, SportKind;
import 'dart:convert' show jsonDecode, jsonEncode;

/// Mode Planification (maquette validée 2026-10-31) : poser demain (ou la fin
/// d'aujourd'hui) en quelques minutes — ce qui se joue, le temps qui reste,
/// des blocs d'activité proposés, puis le récapitulatif. Écrit le programme
/// avec `generatedBy:"plan"` et `plannedAt` (badge Cap tenu, `capHeld`).
const kPlanAccent = Color(0xFF9DB8FF);

/// Planifier la semaine : retiré de l'interface le 2026-11-01 (retour user :
/// « pas exploitable »), le code reste en attendant une autre approche.
const kWeekPlanEnabled = false;
const _ink = Color(0xFF0B1430);
const _bg = Color(0xFF07100D);
const _card = Color(0xFF0C1C14);
const _line = Color(0xFF16281E);
const _text2 = Color(0xFFB9CFC4);
const _text3 = Color(0xFF9FB8AB);
const _gold = Color(0xFFFFD27A);
const _ember = Color(0xFFFFB27A);
const _green = Color(0xFF7FD3A0);

Future<void> showPlanScreen(BuildContext context, AppLogic logic, {BadgeCenter? badges, bool week = false}) {
  return Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => PlanScreen(logic: logic, badges: badges, startWeek: week)));
}

enum _Step { cap, stakes, frame, fill, parole, done, weekStakes, weekDays, weekTimes, weekSpread, weekDone }

class PlanScreen extends StatefulWidget {
  final AppLogic logic;
  final BadgeCenter? badges;
  /// Ouvre directement « La semaine » sur CE QUI SE JOUE (depuis la revue du dimanche).
  final bool startWeek;
  const PlanScreen({super.key, required this.logic, this.badges, this.startWeek = false});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => logic.sync ?? FirestoreSync();

  _Step _step = _Step.cap;
  bool _tomorrow = true;
  bool _week = false;
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
    if (widget.startWeek && kWeekPlanEnabled) {
      _week = true;
      _chrono = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _begin();
      });
    }
    SharedPreferences.getInstance().then((p) {
      final v = p.getBool(_kChronoPref);
      if (v != null && mounted && !widget.startWeek) setState(() => _chrono = v);
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
      out.add(PlanStake(id: 'routine:${a.id}', kind: PlanStakeKind.losing, title: '${a.name} · série $s j', detail: 'routine'));
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
      ..showSnackBar(SnackBar(content: Text('Plus de créneau libre de 30 min pour ${w.title} : raccourcis ou retire un bloc.')));
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
    if (_week) {
      setState(() => _step = _Step.weekStakes);
      _loadWeek();
      return;
    }
    setState(() => _step = _Step.stakes);
    _load2();
  }

  Future<void> _save() async {
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
                  _Step.weekStakes => _weekStakesView(),
                  _Step.weekDays => _weekDaysView(),
                  _Step.weekTimes => _weekTimesView(),
                  _Step.weekSpread => _weekSpreadView(),
                  _Step.weekDone => _weekDoneView(),
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
        selected: _tomorrow && !_week,
        onTap: () => setState(() {
          _tomorrow = true;
          _week = false;
        }),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Demain', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
          SizedBox(height: 3),
          Text('ce qui se joue, le temps libre, des blocs proposés', style: TextStyle(fontSize: 13, color: _text2)),
        ]),
      ),
      const SizedBox(height: 10),
      _choice(
        selected: !_tomorrow && !_week,
        onTap: () => setState(() {
          _tomorrow = false;
          _week = false;
        }),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('La fin d\'aujourd\'hui', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 3),
          Text('à partir de ${hmOf(((now + 14) ~/ 15) * 15)}', style: const TextStyle(fontSize: 13, color: _text2)),
        ]),
      ),
      if (kWeekPlanEnabled) const SizedBox(height: 10),
      if (kWeekPlanEnabled)
      _choice(
        selected: _week,
        onTap: () => setState(() => _week = true),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_weekLabel, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 3),
          const Text('les dates qui ne bougent pas, le contrat, un focus par jour', style: TextStyle(fontSize: 13, color: _text2)),
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
      _primary(_week ? 'Planifier la semaine' : (_tomorrow ? 'Planifier demain' : 'Planifier la fin de journée'), _begin),
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
    final others = logic.state.activeActivities.where((a) => !a.isHabit && a.goalMin > 0 && !isBasicNeedName(a.name) && !used.contains(a.id) && !logic.isActivitySnoozed(a.id, _day)).take(5).toList();
    final domains = logic.state.activeDomains;
    Color colorOf(String activityId) {
      final tk = timeKindOf(activityId);
      if (tk != null) return kTimeBlockColors[tk]!;
      final a = logic.state.activities.where((x) => x.id == activityId).firstOrNull;
      return domainColor(a?.domainId, domains) ?? kPlanAccent;
    }

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
              for (final k in const ['deep', 'small'])
                ActionChip(
                  label: Text('+ ${kTimeBlockLabels[k]}', style: TextStyle(fontWeight: FontWeight.w700, color: kTimeBlockColors[k])),
                  backgroundColor: Colors.transparent,
                  side: BorderSide(color: kTimeBlockColors[k]!),
                  onPressed: () => _addExtra(PlanWant(
                      activityId: timeWantId(k, 100 + _extra.length),
                      title: kTimeBlockLabels[k]!,
                      minutes: k == 'deep' ? 90 : 45,
                      reason: k == 'deep' ? 'Offensive · ${_deepPreview()}' : 'Guérilla · routines et petites actions')),
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
              : _primary('Poser la fin de journée', _save),
        ),
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

  // ── Semaine ─────────────────────────────────────────────────────────────────

  static const _dayShort = ['LUN', 'MAR', 'MER', 'JEU', 'VEN', 'SAM', 'DIM'];
  static const _months = ['janv', 'févr', 'mars', 'avr', 'mai', 'juin', 'juil', 'août', 'sept', 'oct', 'nov', 'déc'];

  List<DailySchedule?> _weekDocs = const [];
  List<List<ScheduleBlock>> _weekBlocks = const [];
  List<List<String>> _weekDated = const [];
  final List<WeekWant> _wants = [];
  final List<(int, String, int)> _prefill = []; // jour, activité, minutes (prépa la veille d'une séance)
  Map<String, PieceSpec> _spec = const {};
  Map<String, int> _datedMin = const {};
  final Set<String> _removed = {};
  int _weekUnfit = 0;
  Set<String> _on = {};
  List<List<WeekPiece>> _pieces = [for (var i = 0; i < 7; i++) <WeekPiece>[]];
  final Map<int, List<PlannedBlock>> _weekPosed = {};
  int _weekRoutines = 0;
  // Répartir par familles (2026-11-01, maquette « Répartir la semaine, autrement »).
  Map<String, PlanFamily> _families = const {};
  Map<String, PlanFamily> _famOverrides = const {};
  bool _workSaturday = false;
  static const _kFamiliesPref = 'plan_families';
  static const _kWorkSatPref = 'plan_work_saturday';
  static const _famColors = {
    PlanFamily.work: Color(0xFFF09A3C),
    PlanFamily.fond: Color(0xFFB06CDC),
    PlanFamily.body: Color(0xFFF2DC4C),
    PlanFamily.daily: Color(0xFF4CBF75),
    PlanFamily.base: Color(0xFF5F7268),
  };

  DateTime _plus(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

  /// Lundi prochain (demain le dimanche).
  DateTime get _weekStart {
    final d = logic.livedToday;
    return _plus(DateTime(d.year, d.month, d.day), 8 - d.weekday);
  }

  List<DateTime> get _weekDays => [for (var i = 0; i < 7; i++) _plus(_weekStart, i)];

  String get _weekLabel {
    final a = _weekStart, b = _plus(a, 6);
    return a.month == b.month
        ? 'La semaine du ${a.day} au ${b.day} ${_months[b.month - 1]}'
        : 'La semaine du ${a.day} ${_months[a.month - 1]} au ${b.day} ${_months[b.month - 1]}';
  }

  Future<void> _loadWeek() async {
    setState(() => _loading = true);
    final days = _weekDays;
    final window = await sync.fetchDayWindow();
    // L'agenda Google de la semaine, recopié dans le programme (même ⟳ que
    // l'onglet Aujourd'hui, un jour à la fois) : les rendez-vous sont posés
    // dans la grille avant qu'on place quoi que ce soit (retour user 2026-11-01).
    final synced = await Future.wait([for (final d in days) gcalSyncDay(sync, ymdOf(d))]);
    _gcalState = synced.any((r) => r?['ok'] == true) ? 'ok' : (synced.any((r) => r?['reason'] == 'not_connected') ? 'off' : 'unknown');
    List<DailySchedule> docs = const [];
    try {
      docs = await sync.fetchDailySchedulesRange(ymdOf(days.first), ymdOf(_plus(days.last, 1)));
    } catch (_) {}
    var objectives = FicheCache.objectives;
    if (objectives == null) {
      try {
        objectives = await sync.fetchStrategicObjectives();
      } catch (_) {}
    }
    final byYmd = {for (final d in docs) d.date: d};
    _window = window;
    _weekDocs = [for (final d in days) byYmd[ymdOf(d)]];
    _weekBlocks = [
      for (final d in days)
        livedDayBlocks(byYmd[ymdOf(d)], byYmd[ymdOf(_plus(d, 1))], logic.dayStartMin).where((b) => b.status == 'pending' || b.status == 'done').toList(),
    ];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kFamiliesPref);
      _famOverrides = raw == null ? const {} : parseFamilies(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      _workSaturday = prefs.getBool(_kWorkSatPref) ?? false;
    } catch (_) {}
    _buildWeek(objectives ?? const []);
    _classify();
    _initSpecs();
    if (mounted) setState(() => _loading = false);
  }

  void _buildWeek(List<StrategicObjective> objectives) {
    final days = _weekDays;
    final dated = [for (final _ in days) <String>[]];
    // Le temps des dates déjà prises, par activité : une séance d'Interventions
    // compte pour Interventions (retour user 2026-11-01 : pas de double emploi).
    final datedMin = <String, int>{};
    final countedTasks = <String>{};
    final projById = {for (final p in logic.currentProjects) p.id: p};
    for (var i = 0; i < 7; i++) {
      // Sur des copies : l'appariement miroir ↔ séance ne s'écrit jamais.
      final copies = [for (final b in _weekBlocks[i]) ScheduleBlock.from(b.toJson())];
      linkMirrorsToSessions(copies, logic.currentProjects, days[i]);
      for (final b in copies.where((b) => b.status == 'pending')) {
        if (b.gcalEventId == null && b.kind != 'session') continue;
        if (isBasicNeedName(b.title)) continue;
        dated[i].add('${b.title} · ${b.startTime}');
        final act = b.activityId ?? projById[b.projectId]?.linkedActivityId;
        if (act != null) datedMin[act] = (datedMin[act] ?? 0) + b.durationMin;
        if (b.taskId != null) countedTasks.add(b.taskId!);
      }
    }
    _wants.clear();
    _prefill.clear();
    void want(String activityId, int weekly, String reason) {
      final i = _wants.indexWhere((w) => w.activityId == activityId);
      if (i < 0) {
        _wants.add(WeekWant(activityId: activityId, title: _activityName(activityId), weeklyMin: weekly, reason: reason));
      } else if (weekly > _wants[i].weeklyMin) {
        _wants[i] = WeekWant(activityId: activityId, title: _wants[i].title, weeklyMin: weekly, reason: reason);
      }
    }

    // Dates qui ne bougent pas : séances de la semaine, et leur prépa la veille.
    for (final p in logic.currentProjects) {
      if (p.status == 'archived' || p.status == 'done' || p.paused) continue;
      for (final it in interventionsOf(p)) {
        if (it.isDone) continue;
        final i = DateTime(it.date.year, it.date.month, it.date.day).difference(days.first).inDays;
        if (i < 0 || i > 6) continue;
        final t = it.milestone.title;
        if (!dated[i].any((d) => d.startsWith(t))) dated[i].add(t);
        if (p.linkedActivityId != null && countedTasks.add(it.milestone.id)) {
          final n = it.native;
          int toMin(String hm) {
            final x = hm.split(':');
            return x.length == 2 ? (int.tryParse(x[0]) ?? 0) * 60 + (int.tryParse(x[1]) ?? 0) : 0;
          }
          final len = n == null ? 0 : toMin(n.endTime) - toMin(n.startTime);
          datedMin[p.linkedActivityId!] = (datedMin[p.linkedActivityId!] ?? 0) + (len > 0 ? len : 60);
        }
        if (it.prep != null && it.prep!.status != 'done' && p.linkedActivityId != null) {
          _prefill.add((i > 0 ? i - 1 : 0, p.linkedActivityId!, 60));
          if (!_wants.any((w) => w.activityId == p.linkedActivityId)) {
            _wants.add(WeekWant(activityId: p.linkedActivityId!, title: _activityName(p.linkedActivityId!), weeklyMin: 0, reason: 'prépa séance'));
          }
        }
      }
    }
    _weekDated = dated;
    _datedMin = datedMin;
    // Le contrat : minimums (Montre suisse), engagements des objectifs, plans en retard.
    for (final a in logic.state.activeActivities) {
      if (a.isHabit || a.goalMin <= 0 || isBasicNeedName(a.name) || logic.isActivitySnoozed(a.id, days.first) || logic.isDomainResting(a.domainId)) continue;
      want(a.id, a.goalMin * 7, 'Montre suisse');
    }
    for (final o in objectives.where((o) => o.status == 'active')) {
      for (final c in o.timeCommitments) {
        if (c.weeklyMin > 0 && logic.state.activities.any((a) => a.id == c.activityId && !a.deleted)) want(c.activityId, c.weeklyMin, 'objectif');
      }
    }
    var behind = 0;
    for (final m in rankProjectMoments(logic.currentProjects, logic.state.sessions, days.first)) {
      if (behind >= 3 || !m.behind || m.upcoming || m.project.linkedActivityId == null) continue;
      behind++;
      want(m.project.linkedActivityId!, 120, 'plan du projet');
    }
    _wants.sort((a, b) => b.weeklyMin.compareTo(a.weeklyMin));
    _weekRoutines = logic.state.activeActivities
        .where((a) => a.isHabit && logic.effectiveHabitFreq(a) == HabitFreq.daily && !logic.isAcquired(a.id) && !logic.isActivitySnoozed(a.id, days.first))
        .length;
  }

  int _freeOf(int i) => freeMinutes(freeGaps(_dayBlocks(i), _window));

  /// Les blocs déjà posés du jour, moins ceux qu'on retire ici.
  List<ScheduleBlock> _dayBlocks(int i) => _weekBlocks[i].where((b) => !_removed.contains(b.id)).toList();

  bool _removable(ScheduleBlock b) => b.docDate == null && b.gcalEventId == null && b.kind != 'session' && b.status == 'pending';

  /// « Ce qui prend ta journée » : les blocs déjà posés, la journée active ;
  /// retirer un bloc rend son temps (appliqué à la validation).
  Future<void> _showDay(int i) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final blocks = [..._weekBlocks[i]]..sort((a, b) => blockStartMin(a).compareTo(blockStartMin(b)));
        String hm(int m) => '${(m ~/ 60 % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
        final winLen = _window.endMin - _window.startMin;
        final free = _freeOf(i);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .8),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
              Text('${_dayLong[i][0].toUpperCase()}${_dayLong[i].substring(1)} ${_weekDays[i].day} · ta journée', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 4),
              Text('Journée active ${hm(_window.startMin)} → ${hm(_window.endMin)} (${_short(winLen)}) · déjà pris ${_short(winLen - free)} · libre ${_short(free)}',
                  style: const TextStyle(fontSize: 12.5, color: _text3)),
              const SizedBox(height: 10),
              if (blocks.isEmpty) const Text('Rien de posé ce jour-là.', style: TextStyle(color: _text2)),
              for (final b in blocks)
                Builder(builder: (_) {
                  final gone = _removed.contains(b.id);
                  final st = blockStartMin(b);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      SizedBox(width: 96, child: Text('${hm(st)} → ${hm(st + b.durationMin)}', style: const TextStyle(fontSize: 12.5, color: _text3))),
                      Expanded(
                        child: Text(
                          '${b.gcalEventId != null ? '📅 ' : ''}${b.title.isEmpty ? 'Bloc' : b.title}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: gone ? _text3 : Colors.white, decoration: gone ? TextDecoration.lineThrough : null),
                        ),
                      ),
                      Text(_short(b.durationMin), style: const TextStyle(fontSize: 12, color: _text3)),
                      SizedBox(
                        width: 40,
                        child: _removable(b)
                            ? IconButton(
                                tooltip: gone ? 'Garder' : 'Retirer',
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  setLocal(() => gone ? _removed.remove(b.id) : _removed.add(b.id));
                                  setState(() {});
                                },
                                icon: Icon(gone ? Icons.undo_rounded : Icons.close_rounded, size: 18, color: _text3),
                              )
                            : null,
                      ),
                    ]),
                  );
                }),
              const SizedBox(height: 10),
              const Text('« Libre » = la journée active moins ce qui est déjà posé. Les blocs retirés ici ne le sont qu\'à la validation.',
                  style: TextStyle(fontSize: 12, color: _text3, height: 1.4)),
            ]),
          ),
        );
      }),
    );
  }

  void _classify() {
    final st = logic.state;
    final byId = {for (final a in st.activities) a.id: a};
    final pick = resolveSportPick(st.activities, st.domains, logic.sportOverrides);
    _families = classifyWants(
      _wants.where((w) => w.weeklyMin > 0).toList(),
      domainOf: (id) => byId[id]?.domainId,
      isBase: (id) => isBasicNeedName(byId[id]?.name),
      isSport: (id) => pick.kinds[id] == SportKind.session,
      overrides: _famOverrides,
    );
  }

  PlanFamily _familyOf(String id) => _families[id] ?? PlanFamily.work;

  /// Le découpage par défaut d'une envie (famille), la prépa des séances en plus.
  PieceSpec _defaultSpec(WeekWant w) {
    final spec = pieceSpecOf(_familyOf(w.activityId), (w.weeklyMin - (_datedMin[w.activityId] ?? 0)).clamp(0, 1 << 20).toInt());
    final prep = _prefill.where((p) => p.$2 == w.activityId).length;
    if (spec.count == 0 && prep > 0 && _familyOf(w.activityId) != PlanFamily.base) return PieceSpec(prep, 60);
    return spec;
  }

  void _initSpecs() {
    _spec = {for (final w in _wants) w.activityId: _defaultSpec(w)};
    _on = {for (final e in _spec.entries) if (e.value.count > 0) e.key};
    _pieces = [for (var i = 0; i < 7; i++) <WeekPiece>[]];
  }

  Future<void> _setFamily(String id, PlanFamily f) async {
    _famOverrides = {..._famOverrides, id: f};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kFamiliesPref, jsonEncode(_famOverrides.map((k, v) => MapEntry(k, v.name))));
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _classify();
      final w = _wants.firstWhere((w) => w.activityId == id);
      _spec = {..._spec, id: _defaultSpec(w)};
      if (_spec[id]!.count > 0) {
        _on.add(id);
      } else {
        _on.remove(id);
      }
    });
  }

  Future<void> _pickFamily(WeekWant w) async {
    final cur = _familyOf(w.activityId);
    final f = await showModalBottomSheet<PlanFamily>(
      context: context,
      backgroundColor: _card,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('${w.title} · quelle famille ?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
          for (final f in PlanFamily.values)
            ListTile(
              leading: CircleAvatar(radius: 7, backgroundColor: _famColors[f]),
              title: Text(kFamilyLabels[f]!, style: const TextStyle(color: Colors.white)),
              subtitle: Text(kFamilyRules[f]!, style: const TextStyle(color: _text3, fontSize: 12)),
              trailing: f == cur ? const Icon(Icons.check_rounded, color: kPlanAccent) : null,
              onTap: () => Navigator.pop(ctx, f),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (f != null && f != cur) await _setFamily(w.activityId, f);
  }

  String _short(int m) => m < 60 ? '$m' : (m % 60 == 0 ? '${m ~/ 60}h' : '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}');

  static const _pieceSizes = [30, 45, 60, 90, 120];

  Future<void> _addWant() async {
    final id = await showActivityPicker(
      context,
      activities: logic.state.activeActivities.where((a) => !a.isHabit && !_wants.any((w) => w.activityId == a.id)).toList(),
      domains: logic.state.domains,
      title: 'Ajouter à ma semaine',
    );
    if (id == null || !mounted) return;
    setState(() {
      _wants.add(WeekWant(activityId: id, title: _activityName(id), weeklyMin: 0, reason: 'ajouté'));
      _spec = {..._spec, id: const PieceSpec(2, 60)};
      _on.add(id);
    });
  }

  /// Étape 1 : « Cette semaine, je veux… » — la liste de ce qu'on veut, en
  /// morceaux. Rien n'est placé.
  Widget _weekStakesView() {
    final winLen = (_window.endMin - _window.startMin).clamp(1, 24 * 60);
    final datedCount = _weekDated.fold(0, (s, d) => s + d.length);
    final placeable = _wants.where((w) => (_spec[w.activityId]?.count ?? 0) > 0 || w.reason == 'ajouté').toList();
    final daily = _wants.where((w) => w.weeklyMin > 0 && _familyOf(w.activityId) == PlanFamily.daily).toList();
    final base = _wants.where((w) => w.weeklyMin > 0 && _familyOf(w.activityId) == PlanFamily.base).toList();
    final covered = _wants
        .where((w) => w.weeklyMin > 0 && (_datedMin[w.activityId] ?? 0) > 0 && (_spec[w.activityId]?.count ?? 0) == 0 && _familyOf(w.activityId) != PlanFamily.base && _familyOf(w.activityId) != PlanFamily.daily)
        .toList();
    Widget noBlock(String label, List<WeekWant> ws) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(label, style: const TextStyle(fontSize: 12.5, color: _text2)),
            for (final w in ws)
              GestureDetector(
                onTap: () => _pickFamily(w),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF17291F), borderRadius: BorderRadius.circular(9)),
                  child: Text(w.title, style: const TextStyle(fontSize: 12, color: Colors.white)),
                ),
              ),
          ]),
        );
    Widget row(WeekWant w) {
      final id = w.activityId;
      final on = _on.contains(id);
      final s = _spec[id] ?? const PieceSpec(1, 60);
      final c = _famColors[_familyOf(id)]!;
      Widget round(IconData icon, VoidCallback? tap) => InkResponse(
            onTap: tap,
            radius: 20,
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFF17291F), borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 17, color: tap == null ? _text3.withValues(alpha: .4) : Colors.white),
            ),
          );
      return InkWell(
        onTap: () => setState(() => on ? _on.remove(id) : _on.add(id)),
        onLongPress: () => _pickFamily(w),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Icon(on ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, color: on ? kPlanAccent : _text3, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: on ? Colors.white : _text3)),
                Row(children: [
                  CircleAvatar(radius: 4, backgroundColor: c),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      [
                        if (w.weeklyMin > 0) fmtMin(w.weeklyMin),
                        if ((_datedMin[id] ?? 0) > 0) 'dont ${fmtMin(_datedMin[id]!)} déjà dans l\'agenda',
                        w.reason,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _text3),
                    ),
                  ),
                ]),
              ]),
            ),
            if (on) ...[
              round(Icons.remove_rounded, s.count > 1 ? () => setState(() => _spec = {..._spec, id: PieceSpec(s.count - 1, s.minutes)}) : null),
              GestureDetector(
                onTap: () => setState(() {
                  final k = _pieceSizes.indexOf(s.minutes);
                  _spec = {..._spec, id: PieceSpec(s.count, _pieceSizes[(k + 1) % _pieceSizes.length])};
                }),
                child: Container(
                  width: 70,
                  alignment: Alignment.center,
                  child: Text('${s.count} × ${_short(s.minutes)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
              round(Icons.add_rounded, s.count < 14 ? () => setState(() => _spec = {..._spec, id: PieceSpec(s.count + 1, s.minutes)}) : null),
            ],
          ]),
        ),
      );
    }

    final total = _on.fold(0, (s, id) => s + (_spec[id]?.total ?? 0));
    final free = [for (var i = 0; i < 7; i++) _freeOf(i)].fold(0, (s, m) => s + m);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _top(_weekLabel.replaceFirst('La semaine', 'SEMAINE').toUpperCase(), 1),
      _title('Cette semaine, je veux…'),
      const Text('Coche ce que tu veux faire et combien de fois. Rien n\'est placé pour l\'instant.', style: TextStyle(fontSize: 13.5, color: _text2)),
      const SizedBox(height: 8),
      Expanded(
        child: ListView(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Row(children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(children: [
                        Text(_dayShort[i], style: const TextStyle(fontSize: 10.5, color: _text3)),
                        const SizedBox(height: 3),
                        Container(
                          height: 34,
                          clipBehavior: Clip.antiAlias,
                          alignment: Alignment.bottomCenter,
                          decoration: BoxDecoration(color: const Color(0xFF27382D), borderRadius: BorderRadius.circular(6)),
                          child: FractionallySizedBox(
                            heightFactor: ((winLen - _freeOf(i)) / winLen).clamp(0.0, 1.0),
                            widthFactor: 1,
                            child: Container(color: const Color(0xFF2A3550)),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(_freeOf(i) == 0 ? 'plein' : _short(_freeOf(i)), maxLines: 1, style: TextStyle(fontSize: 10.5, color: _weekDated[i].isNotEmpty ? _gold : _green)),
                      ]),
                    ),
                  ),
              ]),
              const SizedBox(height: 6),
              Text(
                'Libre sur la semaine : ${fmtMin(free)}${datedCount > 0 ? ' · $datedCount date${datedCount > 1 ? 's' : ''} déjà prise${datedCount > 1 ? 's' : ''}' : ''}',
                style: const TextStyle(fontSize: 12, color: _text3),
              ),
            ]),
          ),
          _section('JE VEUX'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              if (placeable.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Aucun minimum ni engagement : ajoute ce que tu veux faire.', style: TextStyle(color: _text2))),
              for (var k = 0; k < placeable.length; k++) ...[
                if (k > 0) const Divider(height: 1, color: _line),
                row(placeable[k]),
              ],
              const Divider(height: 1, color: _line),
              TextButton.icon(
                onPressed: _addWant,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ajouter une activité'),
                style: TextButton.styleFrom(foregroundColor: kPlanAccent),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          const Text('Touche « 2 × 45 » pour changer la durée · appui long = la façon de la placer.', style: TextStyle(fontSize: 12, color: _text3)),
          if (covered.isNotEmpty || daily.isNotEmpty || base.isNotEmpty || _weekRoutines > 0)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('SANS BLOC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: _text3)),
                if (covered.isNotEmpty) noBlock('Couvert par tes dates :', covered),
                if (daily.isNotEmpty) noBlock('Au fil de la journée :', daily),
                if (base.isNotEmpty) noBlock('Déjà dans ta journée :', base),
                const SizedBox(height: 6),
                const Text('Touche une activité pour lui donner des blocs.', style: TextStyle(fontSize: 11.5, color: _text3)),
                if (_weekRoutines > 0) ...[
                  const SizedBox(height: 5),
                  Text('$_weekRoutines routines quotidiennes', style: const TextStyle(fontSize: 12.5, color: _text2)),
                ],
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      if (total > free)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('${fmtMin(total)} voulues pour ${fmtMin(free)} de libre : tu verras ce qui ne tient pas.', style: const TextStyle(fontSize: 12.5, color: _gold)),
        ),
      _primary('Placer · ${_on.length} activité${_on.length > 1 ? 's' : ''}', _startPlacing),
    ]);
  }

  List<WeekWant> get _onWants => _wants.where((w) => _on.contains(w.activityId) && (_spec[w.activityId]?.count ?? 0) > 0).toList();

  static const _dayLong = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

  // ── Placer une activité à la fois (maquette validée 2026-11-01 « Semaine
  // activité par activité ») : ses jours, puis ses heures sur la semaine.
  List<WeekWant> _order = const [];
  int _actIdx = 0;
  Set<int> _actDays = {};
  bool _sameTime = true;
  static const _kGridH = 420.0;
  static const _zooms = [1.0, 1.5, 2.0, 3.0];
  int _zoomIdx = 0;
  String _gcalState = 'unknown';
  double get _gridH => _kGridH * _zooms[_zoomIdx];

  WeekWant get _act => _order[_actIdx];

  void _startPlacing() {
    _order = _onWants;
    if (_order.isEmpty) {
      setState(() => _step = _Step.weekSpread);
      return;
    }
    _openAct(0);
  }

  void _openAct(int k) {
    setState(() {
      _actIdx = k;
      final id = _order[k].activityId;
      _actDays = {for (var d = 0; d < 7; d++) if (_pieces[d].any((p) => p.id == id)) d};
      _step = _Step.weekDays;
    });
  }

  /// Ce qui occupe un jour : blocs déjà posés, puis les morceaux placés
  /// (sauf [except]).
  List<(int, int)> _busyOf(int d, {WeekPiece? except}) => [
        for (final b in _dayBlocks(d))
          if (b.status == 'pending' || b.status == 'done') (blockStartMin(b), blockEndMin(b)),
        for (final p in _pieces[d])
          if (!identical(p, except) && p.start != null) (p.start!, p.end!),
      ];

  /// Le libre d'un jour sans compter l'activité en cours.
  int _freeFor(int d, String id) => _freeOf(d) - _pieces[d].where((p) => p.id != id).fold<int>(0, (s, p) => s + p.minutes);

  void _suggestDays() {
    final w = _act;
    final s = _spec[w.activityId]!;
    final free = [for (var d = 0; d < 7; d++) (_freeFor(d, w.activityId) * fillRatio(PlanLoad.normal)).round().clamp(0, 24 * 60).toInt()];
    var fam = _familyOf(w.activityId);
    if (fam == PlanFamily.daily || fam == PlanFamily.base) fam = PlanFamily.work;
    final spread = spreadByFamily([WeekWant(activityId: w.activityId, title: w.title, weeklyMin: s.total, reason: w.reason)], {w.activityId: fam}, free, workSaturday: _workSaturday);
    final days = {for (var d = 0; d < 7; d++) if ((spread.days[d][w.activityId] ?? 0) > 0) d};
    setState(() => _actDays = days.isEmpty ? {for (var d = 0; d < 7; d++) if (free[d] >= s.minutes) d}.take(s.count).toSet() : days);
  }

  /// Passe aux heures : les morceaux de l'activité sur les jours choisis,
  /// heures déjà réglées gardées, les autres proposées au premier créneau libre.
  void _toTimes() {
    final w = _act;
    final id = w.activityId;
    var s = _spec[id]!;
    final days = _actDays.toList()..sort();
    if (days.length > s.count) {
      s = PieceSpec(days.length, s.minutes);
      _spec = {..._spec, id: s};
    }
    final counts = perDay(s.count, days.length);
    for (var d = 0; d < 7; d++) {
      final k = days.indexOf(d);
      final want = k < 0 ? 0 : counts[k];
      final mine = _pieces[d].where((p) => p.id == id).toList();
      _pieces[d].removeWhere((p) => p.id == id);
      for (var j = 0; j < want; j++) {
        if (j < mine.length && mine[j].start != null && mine[j].minutes == s.minutes) {
          _pieces[d].add(mine[j]);
          continue;
        }
        final st = firstFreeStart(_busyOf(d), _window.startMin, _window.endMin, s.minutes);
        _pieces[d].add(WeekPiece(id, s.minutes, start: st, proposed: true));
      }
    }
    setState(() => _step = _Step.weekTimes);
  }

  void _setTime(int d, WeekPiece p, int m) {
    final st = (m ~/ 15 * 15).clamp(_window.startMin, (_window.endMin - p.minutes).clamp(_window.startMin, 24 * 60)).toInt();
    final idx = _pieces[d].indexOf(p);
    if (idx < 0) return;
    _pieces[d][idx] = p.at(st);
    if (!_sameTime) return;
    final rank = _pieces[d].where((x) => x.id == p.id).toList().indexOf(_pieces[d][idx]);
    for (var o = 0; o < 7; o++) {
      if (o == d) continue;
      final mine = _pieces[o].where((x) => x.id == p.id).toList();
      if (rank >= mine.length || !mine[rank].proposed) continue;
      final q = mine[rank];
      if (overlapsAny(_busyOf(o, except: q), st, q.minutes)) continue;
      _pieces[o][_pieces[o].indexOf(q)] = q.at(st);
    }
  }

  void _tapGrid(int d, double y) {
    final id = _act.activityId;
    final span = _window.endMin - _window.startMin;
    final m = _window.startMin + (y / _gridH * span).round();
    final s = _spec[id]!;
    final mine = _pieces[d].where((p) => p.id == id).toList();
    setState(() {
      if (mine.isEmpty) {
        final placed = placedCount(_pieces, id);
        if (placed >= s.count) _spec = {..._spec, id: PieceSpec(placed + 1, s.minutes)};
        final p = WeekPiece(id, s.minutes, start: m);
        _pieces[d].add(p);
        _actDays.add(d);
        _setTime(d, p, m - s.minutes ~/ 2);
        return;
      }
      final target = mine.firstWhere((p) => p.proposed || p.start == null, orElse: () {
        mine.sort((a, b) => ((a.start ?? 0) - m).abs().compareTo(((b.start ?? 0) - m).abs()));
        return mine.first;
      });
      _setTime(d, target, m - target.minutes ~/ 2);
    });
  }

  /// La semaine en colonnes, journée active de haut en bas : blocs déjà posés
  /// (bleu nuit), dates (contour or), morceaux placés (couleur de famille).
  /// [current] = l'activité qu'on place (ses blocs se touchent et se glissent).
  Widget _weekGrid({String? current, Set<int> sel = const {}, double? gridHeight, void Function(String id)? onPieceTap}) {
    final height = gridHeight ?? _gridH;
    final days = _weekDays;
    final span = (_window.endMin - _window.startMin).clamp(60, 24 * 60);
    double y(int m) => ((m - _window.startMin) / span * height).clamp(0.0, height);
    Widget box(double top, double h, Widget child, {Color? bg, Border? border}) => Positioned(
          top: top,
          left: 1,
          right: 1,
          height: h.clamp(6.0, height),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(color: bg, border: border, borderRadius: BorderRadius.circular(4)),
            child: child,
          ),
        );
    Text tiny(String t, Color c) => Text(t, maxLines: 2, overflow: TextOverflow.clip, style: TextStyle(fontSize: 8.5, height: 1.1, fontWeight: FontWeight.w800, color: c));
    final hours = [for (var h = (_window.startMin + 59) ~/ 60; h * 60 < _window.endMin; h += height >= 700 ? 1 : 2) h];
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 6, 8),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Row(children: [
          const SizedBox(width: 26),
          for (var d = 0; d < 7; d++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showDay(d),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('${_dayShort[d][0]} ${days[d].day}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: sel.contains(d) ? kPlanAccent : _text3, decoration: TextDecoration.underline, decorationColor: _text3.withValues(alpha: .5))),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        SizedBox(
          height: height,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 26,
              child: Stack(children: [
                for (final h in hours) Positioned(top: y(h * 60) - 5, left: 0, child: Text('${h}h', style: const TextStyle(fontSize: 9, color: _text3))),
              ]),
            ),
            for (var d = 0; d < 7; d++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: current == null ? null : (e) => _tapGrid(d, e.localPosition.dy),
                    child: Container(
                      decoration: BoxDecoration(color: sel.contains(d) ? const Color(0xFF13213A) : const Color(0xFF0F2219), borderRadius: BorderRadius.circular(5)),
                      child: Stack(clipBehavior: Clip.hardEdge, children: [
                        for (final b in _dayBlocks(d))
                          if (b.status == 'pending' || b.status == 'done')
                            (b.gcalEventId != null || b.kind == 'session')
                                ? box(y(blockStartMin(b)), y(blockEndMin(b)) - y(blockStartMin(b)), tiny(b.title, _gold),
                                    bg: _gold.withValues(alpha: .08), border: Border.all(color: _gold, width: 1.1))
                                : box(y(blockStartMin(b)), y(blockEndMin(b)) - y(blockStartMin(b)), tiny(b.title, const Color(0xFFC7D6FF)), bg: const Color(0xFF2A3550)),
                        for (final p in _pieces[d])
                          if (p.start != null)
                            Positioned(
                              top: y(p.start!),
                              left: 1,
                              right: 1,
                              height: (y(p.end!) - y(p.start!)).clamp(8.0, height),
                              child: _pieceBox(d, p, current: current, onTap: onPieceTap, span: span, height: height),
                            ),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  void _removePiece(int d, WeekPiece p) => setState(() {
        _pieces[d].remove(p);
        if (!_pieces[d].any((x) => x.id == p.id)) _actDays.remove(d);
      });

  Widget _zoomBar() => Row(children: [
        Expanded(
          child: Text(
            switch (_gcalState) {
              'ok' => '📅 agenda Google à jour',
              'off' => 'agenda Google non connecté (Paramètres)',
              _ => '',
            },
            style: const TextStyle(fontSize: 11.5, color: _text3),
          ),
        ),
        IconButton(
          tooltip: 'Dézoomer',
          visualDensity: VisualDensity.compact,
          onPressed: _zoomIdx == 0 ? null : () => setState(() => _zoomIdx--),
          icon: const Icon(Icons.zoom_out_rounded, color: Colors.white, size: 22),
        ),
        Text('×${_zooms[_zoomIdx].toString().replaceAll('.0', '').replaceAll('.', ',')}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _text2)),
        IconButton(
          tooltip: 'Zoomer',
          visualDensity: VisualDensity.compact,
          onPressed: _zoomIdx == _zooms.length - 1 ? null : () => setState(() => _zoomIdx++),
          icon: const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 22),
        ),
      ]);

  Widget _pieceBox(int d, WeekPiece p, {String? current, void Function(String id)? onTap, required int span, required double height}) {
    final c = _famColors[_familyOf(p.id)]!;
    final mine = current == p.id;
    final dim = current != null && !mine;
    final px = p.minutes / span * height;
    final ink = p.proposed && mine ? c : const Color(0xFF14100A);
    final label = Container(
      padding: EdgeInsets.fromLTRB(2, 1, mine && px >= 18 ? 14 : 2, 1),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: p.proposed && mine ? c.withValues(alpha: .14) : c.withValues(alpha: dim ? .55 : 1),
        borderRadius: BorderRadius.circular(4),
        border: mine ? Border.all(color: p.proposed ? c : Colors.white, width: p.proposed ? 1.4 : 1.2) : null,
      ),
      child: Text.rich(
        TextSpan(children: [
          if (px >= 34 && p.start != null) TextSpan(text: '${hmOf(p.start!)}\n', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: mine && p.proposed ? '${_activityName(p.id)} ?' : _activityName(p.id)),
        ]),
        maxLines: px >= 34 ? 3 : 2,
        overflow: TextOverflow.clip,
        style: TextStyle(fontSize: 8.5, height: 1.1, fontWeight: FontWeight.w900, color: ink),
      ),
    );
    final body = !mine || px < 18
        ? label
        : Stack(fit: StackFit.expand, children: [
            label,
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _removePiece(d, p),
                child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.close_rounded, size: 12, color: ink)),
              ),
            ),
          ]);
    if (!mine) return onTap == null ? body : GestureDetector(onTap: () => onTap(p.id), child: body);
    return GestureDetector(
      onTap: () => setState(() {
        final i = _pieces[d].indexOf(p);
        if (i >= 0) _pieces[d][i] = p.at(p.start);
      }),
      onLongPress: () => _removePiece(d, p),
      onVerticalDragUpdate: (e) => setState(() {
        final i = _pieces[d].indexOf(p);
        if (i < 0) return;
        final cur = _pieces[d][i];
        final dm = (e.delta.dy / height * span);
        final next = ((cur.start ?? _window.startMin) + dm).round().clamp(_window.startMin, _window.endMin - cur.minutes);
        _pieces[d][i] = cur.at(next);
        p = _pieces[d][i];
      }),
      onVerticalDragEnd: (_) => setState(() {
        final i = _pieces[d].indexOf(p);
        if (i >= 0) _setTime(d, _pieces[d][i], ((_pieces[d][i].start ?? 0) + 7) ~/ 15 * 15);
      }),
      child: body,
    );
  }

  Widget _actHeader(String hint) {
    final w = _act;
    final s = _spec[w.activityId]!;
    final c = _famColors[_familyOf(w.activityId)]!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (var k = 0; k < _order.length; k++)
          Expanded(
            child: Container(
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(color: k < _actIdx ? c : (k == _actIdx ? kPlanAccent : const Color(0xFF27382D)), borderRadius: BorderRadius.circular(3)),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(color: c, width: 4))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(w.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white)),
          Text('activité ${_actIdx + 1} sur ${_order.length} · ${s.count} × ${_short(s.minutes)}${(_datedMin[w.activityId] ?? 0) > 0 ? ' · + ${fmtMin(_datedMin[w.activityId]!)} de dates' : ''}',
              style: const TextStyle(fontSize: 12.5, color: _text3)),
        ]),
      ),
      const SizedBox(height: 8),
      Text(hint, style: const TextStyle(fontSize: 13.5, color: _text2)),
    ]);
  }

  /// Étape « Quels jours ? » d'une activité.
  Widget _weekDaysView() {
    final w = _act;
    final id = w.activityId;
    final s = _spec[id]!;
    final winLen = (_window.endMin - _window.startMin).clamp(1, 24 * 60);
    final days = _weekDays;
    final n = _actDays.length;
    final counts = perDay(s.count, n == 0 ? 1 : n);
    final sorted = _actDays.toList()..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _top('PLACER · ${w.title.toUpperCase()}', 2),
      _actHeader('Quels jours ? Touche ${s.count > 7 ? 'les jours' : '${s.count} jour${s.count > 1 ? 's' : ''}'}. Sous chaque jour : ce qui est déjà pris et le libre.'),
      const SizedBox(height: 10),
      Expanded(
        child: ListView(children: [
          Row(children: [
            for (var d = 0; d < 7; d++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: GestureDetector(
                    onTap: () => setState(() => _actDays.contains(d) ? _actDays.remove(d) : _actDays.add(d)),
                    child: Builder(builder: (_) {
                      final on = _actDays.contains(d);
                      final free = _freeFor(d, id);
                      final k = sorted.indexOf(d);
                      final per = on && k >= 0 && k < counts.length ? counts[k] : 0;
                      return Container(
                        padding: const EdgeInsets.fromLTRB(2, 7, 2, 7),
                        decoration: BoxDecoration(
                          color: on ? const Color(0xFF14223A) : _card,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: on ? kPlanAccent : Colors.transparent, width: 1.5),
                        ),
                        child: Column(children: [
                          Text(_dayShort[d], style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: on ? kPlanAccent : _text3)),
                          Text('${days[d].day}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white)),
                          const SizedBox(height: 4),
                          Container(
                            height: 34,
                            margin: const EdgeInsets.symmetric(horizontal: 5),
                            clipBehavior: Clip.antiAlias,
                            alignment: Alignment.bottomCenter,
                            decoration: BoxDecoration(color: const Color(0xFF27382D), borderRadius: BorderRadius.circular(4)),
                            child: FractionallySizedBox(heightFactor: ((winLen - free) / winLen).clamp(0.0, 1.0), widthFactor: 1, child: Container(color: const Color(0xFF2A3550))),
                          ),
                          const SizedBox(height: 4),
                          Text(free <= 0 ? 'plein' : _short(free), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: free < s.minutes ? _gold : _green)),
                          Text(per > 1 ? '× $per' : (on ? '✓' : ' '), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: kPlanAccent)),
                        ]),
                      );
                    }),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          const Text('bleu nuit = déjà pris · chiffre = libre · touche « voir » dans la semaine pour le détail', style: TextStyle(fontSize: 11.5, color: _text3)),
          const SizedBox(height: 12),
          InkWell(
            onTap: _suggestDays,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: kPlanAccent.withValues(alpha: .4))),
              child: Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: _text2, height: 1.4), children: [
                const TextSpan(text: '💡 Suggérer des jours', style: TextStyle(color: kPlanAccent, fontWeight: FontWeight.w800)),
                TextSpan(text: '\n${kFamilyRules[_familyOf(id)] ?? ''}'),
              ])),
            ),
          ),
          if (n > 0 && n < s.count)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('${s.count} blocs sur $n jour${n > 1 ? 's' : ''} : plusieurs le même jour.', style: const TextStyle(fontSize: 12.5, color: _gold)),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        SizedBox(
          height: 54,
          child: OutlinedButton(
            onPressed: () => _actIdx == 0 ? setState(() => _step = _Step.weekStakes) : _openTimesOf(_actIdx - 1),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withValues(alpha: .16)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Icon(Icons.chevron_left_rounded),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _primary(n == 0 ? 'Passer cette activité' : '$n jour${n > 1 ? 's' : ''} · choisir les heures', n == 0 ? _nextAct : _toTimes)),
      ]),
    ]);
  }

  void _openTimesOf(int k) {
    setState(() {
      _actIdx = k;
      final id = _order[k].activityId;
      _actDays = {for (var d = 0; d < 7; d++) if (_pieces[d].any((p) => p.id == id)) d};
      _step = _actDays.isEmpty ? _Step.weekDays : _Step.weekTimes;
    });
  }

  void _nextAct() {
    if (_actIdx + 1 < _order.length) {
      _openAct(_actIdx + 1);
    } else {
      setState(() => _step = _Step.weekSpread);
    }
  }

  /// Étape « À quelle heure ? » : la semaine entière, ce qui est déjà pris,
  /// l'activité en cours à placer.
  Widget _weekTimesView() {
    final id = _act.activityId;
    final next = _actIdx + 1 < _order.length ? _order[_actIdx + 1].title : null;
    final missing = [for (var d = 0; d < 7; d++) for (final p in _pieces[d]) if (p.id == id && p.start == null) d];
    final proposed = _pieces.fold<int>(0, (s, d) => s + d.where((p) => p.id == id && p.proposed).length);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _top('PLACER · ${_act.title.toUpperCase()}', 2),
      _actHeader('À quelle heure ? Touche un créneau dans une colonne bleue, ou glisse le bloc. ✕ = l\'enlever.'),
      const SizedBox(height: 8),
      Expanded(
        child: ListView(children: [
          _zoomBar(),
          _weekGrid(current: id, sel: _actDays),
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 4, children: [
            _legend(const Color(0xFF2A3550), 'déjà posé'),
            _legend(Colors.transparent, 'date fixe', border: _gold),
            _legend(_famColors[_familyOf(id)]!, 'placé'),
            _legend(Colors.transparent, 'heure proposée', border: _famColors[_familyOf(id)]!),
          ]),
          if (missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Pas de créneau libre ${missing.map((d) => _dayLong[d]).toSet().join(', ')} : touche la colonne pour le poser quand même.', style: const TextStyle(fontSize: 12.5, color: _gold)),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _sameTime,
            activeThumbColor: kPlanAccent,
            title: const Text('Même heure tous les jours', style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text('régler un jour cale les heures proposées des autres', style: TextStyle(color: _text3, fontSize: 12)),
            onChanged: (v) => setState(() => _sameTime = v),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      Row(children: [
        SizedBox(
          height: 54,
          child: OutlinedButton(
            onPressed: () => setState(() => _step = _Step.weekDays),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withValues(alpha: .16)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Text('‹ Jours', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _primary(
            next == null ? (proposed > 0 ? 'Garder ces heures · ta semaine' : 'Voir ta semaine') : (proposed > 0 ? 'Garder ces heures · $next ›' : 'Suivant · $next ›'),
            _nextAct,
          ),
        ),
      ]),
    ]);
  }

  Widget _legend(Color c, String t, {Color? border}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 11, height: 11, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3), border: border == null ? null : Border.all(color: border, width: 1.3))),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 11.5, color: _text3)),
      ]);

  /// La semaine complète : toutes les activités, placé / voulu, puis Valider.
  Widget _weekSpreadView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _top('SEMAINE · TA SEMAINE', 3),
      _title('Ta semaine'),
      const Text('Touche un bloc ou une activité pour revenir dessus.', style: TextStyle(fontSize: 13.5, color: _text2)),
      const SizedBox(height: 6),
      Expanded(
        child: ListView(children: [
          _zoomBar(),
          _weekGrid(gridHeight: 360 * _zooms[_zoomIdx], onPieceTap: (id) {
            final k = _order.indexWhere((w) => w.activityId == id);
            if (k >= 0) _openTimesOf(k);
          }),
          _section('OÙ J\'EN SUIS'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              if (_order.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Rien de coché à la première étape.', style: TextStyle(color: _text2))),
              for (var k = 0; k < _order.length; k++)
                Builder(builder: (_) {
                  final w = _order[k];
                  final s = _spec[w.activityId]!;
                  final done = placedCount(_pieces, w.activityId);
                  final ok = done >= s.count;
                  final dm = _datedMin[w.activityId] ?? 0;
                  return InkWell(
                    onTap: () => _openTimesOf(k),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        CircleAvatar(radius: 4, backgroundColor: _famColors[_familyOf(w.activityId)]),
                        const SizedBox(width: 8),
                        Expanded(child: Text(w.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Colors.white))),
                        Text('${fmtMin(done * s.minutes + dm)} / ${fmtMin(s.total + dm)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ok ? _green : _gold)),
                        SizedBox(width: 22, child: ok ? const Icon(Icons.check_rounded, size: 16, color: _green) : const Icon(Icons.chevron_right_rounded, size: 18, color: _text3)),
                      ]),
                    ),
                  );
                }),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        SizedBox(
          height: 54,
          child: OutlinedButton(
            onPressed: _order.isEmpty ? () => setState(() => _step = _Step.weekStakes) : () => _openTimesOf(_order.length - 1),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withValues(alpha: .16)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Icon(Icons.chevron_left_rounded),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _primary('Valider la semaine', _saveWeek)),
      ]),
    ]);
  }

  /// Pose chaque jour : les morceaux à leur heure choisie ; sans heure, au
  /// premier créneau libre (`proposeDay`). Les blocs retirés passent `deleted`.
  Future<void> _saveWeek() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final days = _weekDays;
    _weekPosed.clear();
    _weekUnfit = 0;
    for (var i = 0; i < 7; i++) {
      PlanWant wantOf(WeekPiece p) =>
          PlanWant(activityId: p.id, title: _activityName(p.id), minutes: p.minutes, reason: _wants.where((w) => w.activityId == p.id).map((w) => w.reason).firstOrNull ?? '');
      final timed = [for (final p in _pieces[i]) if (p.start != null) PlannedBlock(wantOf(p), p.start!, p.minutes)];
      final loose = [for (final p in _pieces[i]) if (p.start == null) wantOf(p)];
      final drop = _weekBlocks[i].where((b) => _removed.contains(b.id) && _removable(b)).map((b) => b.id).toSet();
      if (timed.isEmpty && loose.isEmpty && drop.isEmpty) continue;
      final extra = loose.isEmpty ? <PlannedBlock>[] : proposeDay(freeGaps([..._dayBlocks(i), ...timed.map(planBlockOf)], _window), loose, loose.fold(0, (s, w) => s + w.minutes));
      _weekUnfit += loose.length - extra.length;
      final planned = [...timed, ...extra]..sort((a, b) => a.startMin.compareTo(b.startMin));
      if (planned.isEmpty && drop.isEmpty) continue;
      final doc = _weekDocs[i] ?? DailySchedule(date: ymdOf(days[i]));
      for (final b in doc.blocks) {
        if (drop.contains(b.id)) b.status = 'deleted';
      }
      doc.blocks.addAll(planned.map(planBlockOf));
      doc
        ..generatedBy = 'plan'
        ..generatedAt = now
        ..plannedAt = now
        ..plannedSameDay = false;
      await sync.saveDailySchedule(doc);
      _weekPosed[i] = planned;
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _step = _Step.weekDone;
      });
    }
  }

  Widget _weekDoneView() {
    final total = _weekPosed.values.expand((l) => l).fold<int>(0, (s, p) => s + p.minutes);
    final dated = _weekDated.fold(0, (s, d) => s + d.length);
    final spent = _startedAt == null ? 0 : DateTime.now().difference(_startedAt!).inMinutes;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _top('LA SEMAINE EST POSÉE', 3),
      _title('${fmtMin(total)} réparties · $dated date${dated > 1 ? 's' : ''} tenue${dated > 1 ? 's' : ''}'),
      Text('Planifiée en ${spent < 1 ? 'moins d\'une' : spent} min${_chrono ? ' · chrono sur Planification' : ''}', style: const TextStyle(fontSize: 13.5, color: _text2)),
      if (_weekUnfit > 0)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('$_weekUnfit bloc${_weekUnfit > 1 ? 's' : ''} sans créneau libre dans la journée active : pas posé${_weekUnfit > 1 ? 's' : ''}.', style: const TextStyle(fontSize: 13, color: _gold)),
        ),
      const SizedBox(height: 10),
      Expanded(
        child: ListView(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const Divider(height: 1, color: _line),
                Builder(builder: (_) {
                  final posed = _weekPosed[i] ?? const <PlannedBlock>[];
                  final names = [
                    if (_weekDated[i].length == 1) _weekDated[i].first.split(' · ').first,
                    if (_weekDated[i].length > 1) '${_weekDated[i].length} dates',
                    ...posed.map((p) => p.want.title),
                  ];
                  final m = posed.fold<int>(0, (s, p) => s + p.minutes);
                  final full = m > _freeOf(i) * fillRatio(PlanLoad.full);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(children: [
                      SizedBox(width: 40, child: Text(_dayShort[i], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _text3))),
                      Expanded(
                        child: Text(names.isEmpty ? 'libre' : names.join(' · '),
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: names.isEmpty ? _text3 : Colors.white)),
                      ),
                      Text(m == 0 ? 'léger' : (full ? 'plein' : fmtMin(m)), style: TextStyle(fontSize: 12, color: m == 0 ? _green : (full ? _gold : _text3))),
                    ]),
                  );
                }),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kPlanAccent.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
            child: const Text('Chaque soir, « Planifier demain » partira de ce que tu as posé ici : tu n\'auras qu\'à ajuster.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFFC7D6FF), height: 1.4)),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
            child: const Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Semaine tenue en vue', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text('contrat tenu à 80 % · une braise à la clé', style: TextStyle(fontSize: 12, color: _text3)),
                ]),
              ),
              Text('+1', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _ember)),
            ]),
          ),
        ]),
      ),
      _primary('Terminer', _finish),
    ]);
  }
}
