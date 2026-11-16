import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/coup_alarm.dart';
import 'package:productivitwo_v1/run_session_store.dart';
import 'package:productivitwo_v1/utils/run_session.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart' show fmtMin, pickDurationMin;
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;
import 'package:productivitwo_v1/utils/miracle_morning.dart';
import 'package:productivitwo_v1/utils/mode.dart' show DayMode, kModeLabels;
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin;
import 'package:productivitwo_v1/widgets/activity_picker.dart' show showActivityPicker;
import 'package:productivitwo_v1/widgets/fiche.dart';
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show routinePlus, routineTodayCount;

/// Miracle Morning (maquette validée 2026-11-16) : ta matinée, tes étapes dans ton ordre ;
/// l'heure ne compte pas. Accent chaud du lever.
const kMiracleAccent = Color(0xFFFFB86B);
const _ink = Color(0xFF1D1205);
const _bg = Color(0xFF1A120A);
const _card = Color(0xFF2A1D10);
const _text2 = Color(0xFFE8C9A4);
const _text3 = Color(0xFFB89A78);

// ── Réglage : Mon Miracle Morning ──────────────────────────────────────────

Future<void> showMiracleSetup(BuildContext context, {required AppLogic logic}) =>
    showFiche<void>(context, builder: (ctx, scroll) => _MiracleSetup(logic: logic, scroll: scroll));

class _MiracleSetup extends StatefulWidget {
  final AppLogic logic;
  final ScrollController scroll;
  const _MiracleSetup({required this.logic, required this.scroll});

  @override
  State<_MiracleSetup> createState() => _MiracleSetupState();
}

class _MiracleSetupState extends State<_MiracleSetup> {
  late List<MiracleStep> _steps = [...widget.logic.miracleNow.steps];

  AppLogic get logic => widget.logic;

  void _save(List<MiracleStep> next) {
    setState(() => _steps = next);
    logic.saveMiracleMorning(MiracleMorning(next));
  }

  String _id() => 's${DateTime.now().microsecondsSinceEpoch}';

  Activity? _routine(String? id) => id == null ? null : logic.state.activeActivities.where((a) => a.id == id).firstOrNull;

  String _subOf(MiracleStep s) {
    final r = _routine(s.routineId);
    if (r == null) return s.routineId == null ? 'étape libre' : 'routine retirée';
    final linked = (r.linkedActivityId ?? '').isEmpty ? null : logic.state.activities.where((a) => a.id == r.linkedActivityId).firstOrNull;
    return ['routine ${r.name}', if ((r.habitTarget ?? 1) > 1) '${r.habitTarget} ${r.unit ?? 'fois'}', if (linked != null) 'chrono sur ${linked.name}'].join(' · ');
  }

  Future<void> _editMinutes(int i) async {
    final v = await pickDurationMin(context, initial: _steps[i].minutes, title: _steps[i].name);
    if (v == null || v <= 0) return;
    _save([for (var k = 0; k < _steps.length; k++) k == i ? _steps[k].copyWith(minutes: v) : _steps[k]]);
  }

  Future<void> _addFree({String? name, int minutes = 5, String? note}) async {
    final ctrl = TextEditingController(text: name ?? '');
    final ok = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle étape'),
        content: TextField(controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Visualisation, gratitude…')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Ajouter')),
        ],
      ),
    );
    if (ok == null || ok.isEmpty) return;
    _save([..._steps, MiracleStep(id: _id(), name: ok, minutes: minutes, note: note)]);
  }

  Future<void> _addRoutine() async {
    final routines = logic.state.activeActivities.where((a) => a.isHabit && !_steps.any((s) => s.routineId == a.id)).toList();
    final id = await showActivityPicker(context, activities: routines, domains: logic.state.domains, title: 'Une de mes routines');
    final r = _routine(id);
    if (r == null) return;
    _save([..._steps, MiracleStep(id: _id(), name: r.name, routineId: r.id, minutes: (r.timerMin ?? 5).clamp(1, 120))]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = _steps.fold<int>(0, (s, x) => s + x.minutes);
    final ideas = [for (final i in kMiracleIdeas) if (!_steps.any((s) => s.name.toLowerCase() == i.$1.toLowerCase())) i];
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 14, 20, 32), children: [
      FicheHeader(title: 'Mon Miracle Morning', chip: '${_steps.length} étape${_steps.length > 1 ? 's' : ''} · ${fmtMin(total)}', chipColor: kMiracleAccent),
      const SizedBox(height: 6),
      Text("Tes étapes, dans ton ordre. L'heure ne compte pas : tu le fais quand tu te lèves.",
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.4)),
      if (logic.miracleMorning == null && _steps.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text('Au départ : tes routines du matin, rien d’imposé.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ],
      const FicheTitle('LES ÉTAPES · maintenir pour réordonner'),
      if (_steps.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('Aucune étape pour l’instant. Ajoute une routine ou une idée ci-dessous.', style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorder: (a, b) {
          final next = [..._steps];
          final s = next.removeAt(a);
          next.insert(b > a ? b - 1 : b, s);
          _save(next);
        },
        children: [
          for (var i = 0; i < _steps.length; i++)
            ReorderableDelayedDragStartListener(
              key: ValueKey('miracle-step-${_steps[i].id}'),
              index: i,
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  CircleAvatar(radius: 13, backgroundColor: kMiracleAccent.withValues(alpha: .2), child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kMiracleAccent))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_steps[i].name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(_subOf(_steps[i]), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  TextButton(onPressed: () => _editMinutes(i), child: Text(fmtMin(_steps[i].minutes))),
                  IconButton(
                    tooltip: 'Retirer',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => _save([for (var k = 0; k < _steps.length; k++) if (k != i) _steps[k]]),
                  ),
                ]),
              ),
            ),
        ],
      ),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: OutlinedButton.icon(key: const ValueKey('miracle-add-routine'), onPressed: _addRoutine, icon: const Icon(Icons.repeat_rounded, size: 18), label: const Text('Une de mes routines'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(key: const ValueKey('miracle-add-free'), onPressed: () => _addFree(), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Une étape'))),
      ]),
      if (ideas.isNotEmpty) ...[
        const FicheTitle('IDÉES SI TU VEUX · LE CLASSIQUE S.A.V.E.R.S.'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final i in ideas)
            ActionChip(
              label: Text('+ ${i.$1}'),
              tooltip: i.$3,
              onPressed: () => _save([..._steps, MiracleStep(id: _id(), name: i.$1, minutes: i.$2, note: i.$3)]),
            ),
        ]),
      ],
      const SizedBox(height: 16),
      const FicheNote('Une étape peut être une de tes routines : faite pendant le Miracle Morning, elle prend son +1, et lance le chrono de son activité liée (Lecture, Sport).'),
    ]);
  }
}

// ── Le dérouler : une étape à la fois ──────────────────────────────────────

/// Lance le Miracle Morning, ou reprend celui qui attend (app fermée en route) ; [resume] force une session.
Future<void> showMiracleMorning(BuildContext context, {required AppLogic logic, PendingRun? resume}) {
  final p = resume ?? pendingMiracle(logic);
  return Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => MiracleMorningScreen(logic: logic, resume: p)));
}

/// Le Miracle Morning resté en route aujourd'hui (même jour vécu, moins de 45 min sans rien), sinon null.
PendingRun? pendingMiracle(AppLogic logic) {
  final p = RunSessionStore.current;
  return p != null && p.kind == kMiracleKind && p.isLive(DateTime.now(), logic.livedTodayYmd) ? p : null;
}

enum _StepState { done, skipped }

class MiracleMorningScreen extends StatefulWidget {
  final AppLogic logic;
  /// Session quittée en route (2026-11-16) : on reprend à l'étape où on en était.
  final PendingRun? resume;
  const MiracleMorningScreen({super.key, required this.logic, this.resume});

  @override
  State<MiracleMorningScreen> createState() => _MiracleMorningScreenState();
}

class _MiracleMorningScreenState extends State<MiracleMorningScreen> {
  late final List<MiracleStep> _steps = [...widget.logic.miracleNow.steps];
  final Map<String, _StepState> _states = {};
  final Map<String, int> _spent = {}; // secondes par étape
  final Set<String> _plusOne = {};
  final Set<String> _chrono = {};
  int _index = 0;
  bool _end = false;
  bool _saved = false;
  DayMode? _mode;
  late DateTime _startedAt = DateTime.now();
  late DateTime _stepStart = DateTime.now();
  late DateTime _endsAt = DateTime.now();
  bool _ownChrono = false;
  Timer? _tick;
  late final String _runId = widget.resume?.runId ?? ChainRun(date: '', startedAt: DateTime(0), endedAt: DateTime(0), doneCount: 0, total: 0, completed: false).id;

  AppLogic get logic => widget.logic;
  MiracleStep get _step => _steps[_index];

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    final r = widget.resume;
    if (r != null) {
      _restore(r);
    } else if (_steps.isEmpty) {
      _end = true;
    } else {
      _enter(0);
    }
  }

  /// Reprise : les étapes déjà faites / passées restent ; l'étape en cours repart avec son temps d'avant.
  void _restore(PendingRun r) {
    _startedAt = r.startedAt;
    final st = r.extra['states'];
    if (st is Map) {
      st.forEach((k, v) => _states['$k'] = v == 'done' ? _StepState.done : _StepState.skipped);
    }
    final sp = r.extra['spent'];
    if (sp is Map) sp.forEach((k, v) => _spent['$k'] = (v as num).toInt());
    _plusOne.addAll(r.strings('plusOne'));
    _chrono.addAll(r.strings('chrono'));
    final cur = r.extra['cur']?.toString();
    var i = _steps.indexWhere((s) => s.id == cur);
    if (i < 0) i = _steps.indexWhere((s) => !_states.containsKey(s.id));
    if (i < 0) {
      _save();
      RunSessionStore.clear();
      _end = true;
      return;
    }
    final start = r.intOf('stepStart'), ends = r.intOf('endsAt');
    if (_steps[i].id == cur && start != null && ends != null) {
      _enter(i, start: DateTime.fromMillisecondsSinceEpoch(start), ends: DateTime.fromMillisecondsSinceEpoch(ends));
    } else {
      _enter(i);
    }
  }

  void _persist() {
    final now = DateTime.now();
    RunSessionStore.save(PendingRun(
      kind: kMiracleKind,
      runId: _runId,
      date: ymdOf(livedDate(now, logic.dayStartMin)),
      startedAt: _startedAt,
      lastActiveAt: now,
      done: _states.values.where((v) => v == _StepState.done).length,
      extra: {
        'total': _steps.length,
        'cur': _end ? null : _step.id,
        'stepStart': _stepStart.millisecondsSinceEpoch,
        'endsAt': _endsAt.millisecondsSinceEpoch,
        'states': {for (final e in _states.entries) e.key: e.value == _StepState.done ? 'done' : 'skipped'},
        'spent': _spent,
        'plusOne': _plusOne.toList(),
        'chrono': _chrono.toList(),
      },
    ));
  }

  @override
  void dispose() {
    _tick?.cancel();
    CoupAlarm.cancel();
    if (_ownChrono) logic.stopActive();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  Activity? _routine(MiracleStep s) => s.routineId == null ? null : logic.state.activeActivities.where((a) => a.id == s.routineId).firstOrNull;

  void _enter(int i, {DateTime? start, DateTime? ends}) {
    _index = i;
    _stepStart = start ?? DateTime.now();
    _endsAt = ends ?? _stepStart.add(Duration(minutes: _steps[i].minutes));
    if (_endsAt.isAfter(DateTime.now())) {
      CoupAlarm.schedule(logic, endsAt: _endsAt, title: 'Miracle Morning', body: '${_steps[i].name} : c’est le temps prévu. Passe à la suite quand tu veux.');
    }
    // Le chrono de l'activité liée de la routine (Lecture, Sport), jamais par-dessus un chrono lancé à la main.
    final r = _routine(_steps[i]);
    final linked = (r?.linkedActivityId ?? '').trim();
    final running = logic.state.sessions.any((s) => s.endAt == null && !s.deleted);
    // Reprise : le chrono de cette étape tourne encore (app fermée en route), on le garde.
    if (start != null && linked.isNotEmpty && logic.state.sessions.any((s) => s.endAt == null && !s.deleted && s.activityId == linked && !s.startAt.isBefore(_startedAt))) {
      _ownChrono = true;
      _chrono.add(_steps[i].id);
    } else if (linked.isNotEmpty && (!running || _ownChrono) && logic.state.activities.any((a) => a.id == linked && !a.deleted)) {
      if (_ownChrono) logic.stopActive();
      logic.start(linked);
      _ownChrono = true;
      _chrono.add(_steps[i].id);
    } else if (_ownChrono) {
      logic.stopActive();
      _ownChrono = false;
    }
    _persist();
    if (mounted) setState(() {});
  }

  void _leave(_StepState st) {
    final s = _step;
    _states[s.id] = st;
    _spent[s.id] = DateTime.now().difference(_stepStart).inSeconds;
    if (st == _StepState.done) {
      final r = _routine(s);
      if (r != null && routineTodayCount(logic, r) < ((r.habitTarget ?? 1) < 1 ? 1 : (r.habitTarget ?? 1))) {
        routinePlus(logic, r);
        _plusOne.add(s.id);
      }
    }
    CoupAlarm.cancel();
    if (_index + 1 < _steps.length) {
      _enter(_index + 1);
    } else {
      _finish();
    }
  }

  void _finish() {
    if (_ownChrono) logic.stopActive();
    _ownChrono = false;
    CoupAlarm.cancel();
    _save();
    RunSessionStore.clear();
    if (mounted) setState(() => _end = true);
  }

  void _save() {
    final done = _states.values.where((v) => v == _StepState.done).length;
    if (_saved || done == 0) return;
    _saved = true;
    final now = DateTime.now();
    final run = ChainRun(
      id: _runId,
      date: ymdOf(livedDate(now, logic.dayStartMin)),
      startedAt: _startedAt,
      endedAt: now,
      doneCount: done,
      total: _steps.length,
      completed: _states.length == _steps.length,
      kind: kMiracleKind,
    );
    logic.recordChainRun(run);
    logic.sync?.saveChainRun(run);
  }

  Future<void> _stop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tu t’arrêtes là ?'),
        content: const Text('Ce que tu as fait reste fait.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continuer')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Je m’arrête')),
        ],
      ),
    );
    if (ok == true) _finish();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(scaffoldBackgroundColor: _bg),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: _end ? _bilan() : _stepView(),
          ),
        ),
      ),
    );
  }

  Widget _stepView() {
    final s = _step;
    final now = DateTime.now();
    final total = s.minutes * 60;
    final left = _endsAt.difference(now).inSeconds;
    final over = left < 0;
    final shown = over ? -left : left;
    final mmss = '${over ? '+' : ''}${shown ~/ 60}:${(shown % 60).toString().padLeft(2, '0')}';
    final progress = over ? 1.0 : (1 - left / total).clamp(0.0, 1.0);
    final next = _index + 1 < _steps.length ? _steps[_index + 1] : null;
    final r = _routine(s);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text('MIRACLE MORNING · ${_index + 1} / ${_steps.length}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1, color: kMiracleAccent)),
        ),
        TextButton(key: const ValueKey('miracle-stop'), onPressed: _stop, child: const Text('Je m’arrête', style: TextStyle(color: _text2))),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        for (var i = 0; i < _steps.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i < _index
                    ? (_states[_steps[i].id] == _StepState.done ? kMiracleAccent : Colors.white.withValues(alpha: .25))
                    : i == _index
                        ? kMiracleAccent.withValues(alpha: .55)
                        : Colors.white.withValues(alpha: .1),
              ),
            ),
          ),
        ],
      ]),
      const Spacer(),
      Center(
        child: SizedBox(
          width: 200,
          height: 200,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 10,
                backgroundColor: Colors.white.withValues(alpha: .08),
                color: over ? const Color(0xFF7FD3A0) : kMiracleAccent,
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(mmss, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
              Text(over ? 'en plus · prends ton temps' : 'sur ${fmtMin(s.minutes)}', style: const TextStyle(fontSize: 13, color: _text2)),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 22),
      Text(s.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
      if ((s.note ?? '').isNotEmpty || r != null) ...[
        const SizedBox(height: 6),
        Text(
          [if ((s.note ?? '').isNotEmpty) s.note!, if (r != null && (r.habitTarget ?? 1) > 1) '${r.habitTarget} ${r.unit ?? 'fois'}', if (_chrono.contains(s.id)) 'chrono en cours'].join(' · '),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: _text2, height: 1.4),
        ),
      ],
      const Spacer(),
      if (next != null)
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Text('ENSUITE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: _text3)),
            const SizedBox(width: 10),
            Expanded(child: Text('${next.name} · ${fmtMin(next.minutes)}', style: const TextStyle(fontSize: 14, color: Colors.white))),
          ]),
        ),
      SizedBox(
        height: 56,
        child: FilledButton(
          key: const ValueKey('miracle-done'),
          onPressed: () => _leave(_StepState.done),
          style: FilledButton.styleFrom(backgroundColor: kMiracleAccent, foregroundColor: _ink, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: Text(next == null ? 'Fait · terminer' : 'Fait · suivant', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        TextButton(
          key: const ValueKey('miracle-plus'),
          onPressed: () {
            final base = _endsAt.isBefore(DateTime.now()) ? DateTime.now() : _endsAt;
            setState(() => _endsAt = base.add(const Duration(minutes: 2)));
            _persist();
            CoupAlarm.schedule(logic, endsAt: _endsAt, title: 'Miracle Morning', body: '${s.name} : c’est le temps prévu.');
          },
          child: const Text('+2 min', style: TextStyle(color: _text2)),
        ),
        const SizedBox(width: 16),
        TextButton(key: const ValueKey('miracle-skip'), onPressed: () => _leave(_StepState.skipped), child: const Text('Passer', style: TextStyle(color: _text2))),
      ]),
    ]);
  }

  ScheduleBlock? get _nextBlock {
    final now = logic.livedNowMinNow;
    final blocks = logic.todayBlocks.where((b) => b.status == 'pending' && blockStartMin(b) >= now).toList()
      ..sort((a, b) => blockStartMin(a).compareTo(blockStartMin(b)));
    return blocks.firstOrNull;
  }

  Widget _bilan() {
    final done = _steps.where((s) => _states[s.id] == _StepState.done).length;
    final minutes = (_spent.values.fold<int>(0, (a, b) => a + b) / 60).round();
    final next = _nextBlock;
    return ListView(children: [
      const SizedBox(height: 12),
      const Text('MIRACLE MORNING · FAIT', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1, color: kMiracleAccent)),
      const SizedBox(height: 10),
      Text(_steps.isEmpty ? 'Aucune étape' : '$done sur ${_steps.length} · ${fmtMin(minutes)}',
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white)),
      if (_plusOne.isNotEmpty)
        Text('${_plusOne.length} routine${_plusOne.length > 1 ? 's ont' : ' a'} pris leur +1', style: const TextStyle(fontSize: 14, color: _text2)),
      const SizedBox(height: 16),
      for (final s in _steps)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _states[s.id] == _StepState.done ? kMiracleAccent : Colors.white.withValues(alpha: .12),
              ),
              child: Text(_states[s.id] == _StepState.done ? '✓' : '–',
                  style: TextStyle(fontWeight: FontWeight.w800, color: _states[s.id] == _StepState.done ? _ink : _text2)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(s.name, style: const TextStyle(fontSize: 15, color: Colors.white))),
            Text(
              switch (_states[s.id]) {
                _StepState.done => '${fmtMin(((_spent[s.id] ?? 0) / 60).round().clamp(1, 999))}${_chrono.contains(s.id) ? ' · chrono' : ''}',
                _StepState.skipped => 'passée',
                null => 'pas faite',
              },
              style: const TextStyle(fontSize: 13, color: _text3),
            ),
          ]),
        ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Comment tu démarres ta journée ?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 10),
          Row(children: [
            for (final m in DayMode.values) ...[
              if (m != DayMode.low) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: ValueKey('miracle-mode-${m.name}'),
                  onPressed: () {
                    setState(() => _mode = m);
                    logic.setMode(m);
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _mode == m ? kMiracleAccent.withValues(alpha: .18) : null,
                    foregroundColor: _mode == m ? kMiracleAccent : Colors.white,
                    side: BorderSide(color: _mode == m ? kMiracleAccent : Colors.white.withValues(alpha: .18)),
                  ),
                  child: Text(kModeLabels[m]!),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 6),
          const Text('c’est ton élan du matin : il choisit ce que MAINTENANT te propose ensuite', style: TextStyle(fontSize: 12, color: _text3)),
        ]),
      ),
      if (next != null) ...[
        const SizedBox(height: 14),
        Row(children: [
          const Text('ENSUITE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: _text3)),
          const SizedBox(width: 10),
          Expanded(child: Text('${next.title} · ${next.startTime}', style: const TextStyle(fontSize: 14, color: Colors.white))),
        ]),
      ],
      const SizedBox(height: 20),
      SizedBox(
        height: 56,
        child: FilledButton(
          key: const ValueKey('miracle-close'),
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(backgroundColor: kMiracleAccent, foregroundColor: _ink, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: const Text('Ta journée commence', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
      ),
    ]);
  }
}
