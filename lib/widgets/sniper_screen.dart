import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/coup_alarm.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/run_session_store.dart' show RunSessionStore, dropShortSession;
import 'package:productivitwo_v1/utils/duration_fmt.dart' show fmtMin;
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/game_rules.dart' show kRuleSniper;
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;
import 'package:productivitwo_v1/utils/parole.dart' show kParoleMin, paroleIndex, paroleOfDay;
import 'package:productivitwo_v1/utils/run_session.dart';
import 'package:productivitwo_v1/utils/sniper.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/utils/time_spent.dart' show estimateFactor, spentByAction;
import 'package:productivitwo_v1/widgets/confirm_done.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/widgets/objective_readings_card.dart' show noteReadingQuick;
import 'package:productivitwo_v1/utils/checklist_logic.dart' show setActionDone;

/// Écran Sniper (maquette validée 2026-11-01) : le viseur (cibles au temps
/// exact dans le temps libre), un tir à la fois (minuteur pile, alarme),
/// « Touché » puis le tir suivant part tout seul après une courte pause, et
/// le bilan (cibles touchées, précision, badge). Logique : `utils/sniper.dart`.
const kSniperAccent = Color(0xFF7FD3FF);
const kSniperInk = Color(0xFF062130);
const _bg = Color(0xFF0A1218);
const _card = Color(0xFF13202A);
const _card2 = Color(0xFF1A2A35);
const _line = Color(0xFF24384A);
const _text2 = Color(0xFFB4C8D4);
const _text3 = Color(0xFF8DA2AF);
const _green = Color(0xFF3DDC84);
const _amber = Color(0xFFF5B041);

Future<void> showSniperScreen(BuildContext context, AppLogic logic, {BadgeCenter? badges, PendingRun? resume}) {
  return Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => SniperScreen(logic: logic, badges: badges, resume: resume)));
}

enum _Phase { aim, shot, hit, end }

class SniperScreen extends StatefulWidget {
  final AppLogic logic;
  final BadgeCenter? badges;
  final PendingRun? resume;
  const SniperScreen({super.key, required this.logic, this.badges, this.resume});

  @override
  State<SniperScreen> createState() => _SniperScreenState();
}

class _SniperScreenState extends State<SniperScreen> {
  List<Stake> _stakes = const [];
  Map<String, int> _routineLeft = const {};
  double _factor = 1;
  int _endMin = 22 * 60;
  final _excluded = <String>{};
  SniperPlan _plan = const SniperPlan(budgetMin: 0);
  ({int minutes, int untilMin, ScheduleBlock? until}) _budget = (minutes: 0, untilMin: 0, until: null);
  bool _loading = true;

  // Session
  List<SniperTarget> _aimed = const [];
  int _aimedMin = 0;
  int _index = 0;
  final _hit = <String>[];
  final _skipped = <String>{};
  final _fired = <String, int>{}; // minutes tirées par cible
  _Phase _phase = _Phase.aim;
  DateTime? _startedAt;
  DateTime? _shotStart;
  DateTime? _endsAt;
  int? _pausedLeft; // secondes restantes quand le tir est en pause
  int _remaining = 0;
  int _breakSec = 0;
  Timer? _timer;
  bool _ownChrono = false;
  bool _saved = false;
  String? _lastHit;
  late final String _runId = widget.resume?.runId ?? ChainRun(date: '', startedAt: DateTime(0), endedAt: DateTime(0), doneCount: 0, total: 0, completed: false).id;

  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
    _load();
  }

  Future<void> _load() async {
    try {
      final w = await logic.sync?.fetchDayWindow();
      if (w != null) _endMin = w.endMin;
    } catch (_) {}
    if (widget.badges != null && widget.badges!.deck == null) {
      try {
        await widget.badges!.load();
      } catch (_) {}
    }
    if (!mounted) return;
    _compute();
    final r = widget.resume;
    if (r != null) _restore(r);
    setState(() => _loading = false);
  }

  void _compute() {
    final bc = widget.badges;
    final st = logic.state;
    StakeBoard board = StakeBoard.empty;
    if (bc != null) {
      try {
        final facts = bc.todayFacts();
        _routineLeft = {for (final r in facts.routines) r.activity.id: r.target - r.done};
        final pd = paroleOfDay(logic.paroles, paroleIndex(logic.currentProjects, st.activeActivities), logic.livedTodayYmd, logic.dayStartMin);
        board = buildStakeBoard(
          deck: bc.deck,
          facts: facts,
          hunts: logic.badgeHunts,
          projects: logic.currentProjects,
          activities: st.activeActivities,
          dayStartMin: logic.dayStartMin,
          parole: pd == null || pd.ids.length < kParoleMin ? null : pd,
          top: 1 << 20,
          familyCap: 1 << 20,
        );
      } catch (_) {}
    }
    _stakes = [...board.top, ...board.rest];
    _factor = estimateFactor(logic.currentProjects, spentByAction(st.sessions)) ?? 1;
    final nowMin = logic.livedNowMinNow;
    final end = nowMin >= _endMin - 15 ? nowMin + 90 : _endMin;
    _budget = sniperBudget(blocks: logic.todayBlocks, nowMin: nowMin, endMin: end);
    _replan();
  }

  void _replan() {
    _plan = planSniper(
      stakes: _stakes,
      budgetMin: _budget.minutes,
      untilMin: _budget.untilMin,
      routineLeft: _routineLeft,
      factor: _factor,
      excluded: _excluded,
    );
  }

  /// Les cibles écartées à la main (pour les remettre).
  List<SniperTarget> get _excludedTargets => [
        for (final s in _stakes)
          if (_excluded.contains(s.gesture.key)) sniperTargetOf(s, routineLeft: _routineLeft, factor: _factor),
      ].whereType<SniperTarget>().toList();

  void _restore(PendingRun r) {
    final keys = r.strings('aimed');
    final byKey = {
      for (final s in _stakes)
        if (sniperTargetOf(s, routineLeft: _routineLeft, factor: _factor) case final t?) t.key: t,
    };
    _startedAt = r.startedAt;
    _hit.addAll(r.strings('hit'));
    _skipped.addAll(r.strings('skipped'));
    _aimedMin = r.intOf('aimedMin') ?? 0;
    final fired = r.extra['fired'];
    if (fired is Map) fired.forEach((k, v) => _fired[k.toString()] = (v as num).toInt());
    // Une cible qui a disparu des enjeux est tombée ailleurs : elle compte
    // touchée (seulement si les enjeux ont pu être recalculés).
    final known = widget.badges?.deck != null;
    final aimed = <SniperTarget>[];
    for (final k in keys) {
      final t = byKey[k];
      if (t != null) {
        aimed.add(t);
      } else if (known && !_hit.contains(k) && !_skipped.contains(k)) {
        _hit.add(k);
      }
    }
    _aimed = aimed;
    _totalAimed = keys.length;
    if (logic.state.sessions.any((x) => x.endAt == null && !x.startAt.isBefore(r.startedAt))) logic.stopActive(notify: false);
    final n = _nextIndex(-1);
    if (n == null) {
      _phase = _Phase.end;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enter(n);
      });
    }
  }

  int _totalAimed = 0;

  int? _nextIndex(int from) {
    for (var i = from + 1; i < _aimed.length; i++) {
      final k = _aimed[i].key;
      if (!_hit.contains(k) && !_skipped.contains(k)) return i;
    }
    return null;
  }

  Session? get _runningBefore => logic.state.sessions.where((x) => x.endAt == null).firstOrNull;

  void _persist() {
    if (_startedAt == null) return;
    final now = DateTime.now();
    RunSessionStore.save(PendingRun(
      kind: kSniperKind,
      runId: _runId,
      date: ymdOf(livedDate(now, logic.dayStartMin)),
      startedAt: _startedAt!,
      lastActiveAt: now,
      done: _hit.length,
      extra: {
        'aimed': [for (final t in _aimed) t.key],
        'hit': _hit,
        'skipped': _skipped.toList(),
        'fired': _fired,
        'aimedMin': _aimedMin,
        'total': _totalAimed,
      },
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_startedAt != null) CoupAlarm.cancel();
    _stopOwnChrono();
    if (!_saved && _phase == _Phase.end) {
      if (_hit.isNotEmpty) _save();
      RunSessionStore.clear();
    }
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  // ── Tirs ─────────────────────────────────────────────────────────────────

  void _start() {
    if (_plan.aimed.isEmpty) return;
    if (_runningBefore != null) logic.stopActive(notify: false);
    _aimed = [..._plan.aimed];
    _totalAimed = _aimed.length;
    _aimedMin = _plan.totalMin;
    _startedAt = DateTime.now();
    _enter(0);
  }

  void _enter(int i) {
    _timer?.cancel();
    _index = i;
    _phase = _Phase.shot;
    _pausedLeft = null;
    _shotStart = DateTime.now();
    final t = _aimed[i];
    if (t.minutes > 0) {
      _endsAt = DateTime.now().add(Duration(minutes: t.minutes));
      _remaining = t.minutes * 60;
      _arm(t);
      _startChrono(t);
      _ticking();
    } else {
      _endsAt = null;
    }
    _persist();
    setState(() {});
  }

  void _ticking() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(_tick);
    });
  }

  void _tick() {
    if (_phase == _Phase.hit) {
      if (_breakSec > 0) _breakSec--;
      if (_breakSec <= 0) Future.microtask(_fireNext);
      return;
    }
    if (_phase != _Phase.shot || _endsAt == null || _pausedLeft != null) return;
    final left = _endsAt!.difference(DateTime.now()).inSeconds;
    _remaining = left > 0 ? left : 0;
    // Une activité tombe pile au bout du minuteur ; une action attend « faite ».
    if (_remaining == 0 && _aimed[_index].kind == SniperKind.timed) Future.microtask(_touch);
  }

  void _arm(SniperTarget t) => CoupAlarm.schedule(logic, endsAt: _endsAt!, title: '◎ Touché', body: '${t.title} · ${t.minutes} min pile');

  String? _chronoActivity(SniperTarget t) {
    final g = t.stake.gesture;
    switch (t.kind) {
      case SniperKind.timed:
        return g.activity?.id;
      case SniperKind.action:
        return g.action?.linkedActivityId ?? g.project?.linkedActivityId ?? g.owner?.id;
      case SniperKind.routine:
        return g.activity?.linkedActivityId;
      case SniperKind.reading:
        return null;
    }
  }

  void _startChrono(SniperTarget t) {
    if (logic.state.sessions.any((s) => s.endAt == null)) return;
    final act = _chronoActivity(t);
    if (act == null) return;
    final g = t.stake.gesture;
    logic.start(act, taskId: g.task?.id, actionId: g.action?.id);
    _ownChrono = true;
  }

  void _stopOwnChrono() {
    if (!_ownChrono) return;
    _ownChrono = false;
    dropShortSession(logic, logic.stopActive(notify: false));
  }

  void _togglePause() {
    if (_endsAt == null) return;
    if (_pausedLeft == null) {
      _pausedLeft = _remaining;
      CoupAlarm.cancel();
      _stopOwnChrono();
    } else {
      _endsAt = DateTime.now().add(Duration(seconds: _pausedLeft!));
      _pausedLeft = null;
      _arm(_aimed[_index]);
      _startChrono(_aimed[_index]);
    }
    setState(() {});
  }

  void _more() {
    final now = DateTime.now();
    if (_pausedLeft != null) {
      _pausedLeft = _pausedLeft! + 300;
    } else {
      final base = _endsAt == null || _endsAt!.isBefore(now) ? now : _endsAt!;
      _endsAt = base.add(const Duration(minutes: 5));
      CoupAlarm.cancel(all: false);
      _arm(_aimed[_index]);
    }
    setState(_tick);
  }

  int get _firedNowMin {
    final t = _aimed[_index];
    if (t.minutes == 0 || _shotStart == null) return t.cost;
    if (_endsAt == null) return t.minutes;
    final planned = _endsAt!.difference(_shotStart!).inSeconds;
    final left = _pausedLeft ?? _remaining;
    return ((planned - left) / 60).round().clamp(0, 1 << 20);
  }

  /// La cible tombe : on écrit ce qu'il faut (coches, action faite), puis pause.
  Future<void> _touch() async {
    if (_phase != _Phase.shot) return;
    final t = _aimed[_index];
    final g = t.stake.gesture;
    if (t.kind == SniperKind.action && g.action != null) {
      if (!await confirmDone(context, title: g.action!.title)) return;
      _markActionDone(t);
    }
    if (t.kind == SniperKind.routine && g.activity != null) {
      logic.incHabit(g.activity!.id, t.delta, livedDate(DateTime.now(), logic.dayStartMin));
    }
    _fired[t.key] = _firedNowMin;
    _finishShot(t);
  }

  Future<void> _noteReading() async {
    final t = _aimed[_index];
    final o = t.stake.gesture.objective;
    final sync = logic.sync;
    if (o == null || sync == null) return;
    final ok = await noteReadingQuick(context, sync: sync, objective: o);
    if (!ok || !mounted) return;
    _fired[t.key] = 1;
    _finishShot(t);
  }

  void _markActionDone(SniperTarget t) {
    final g = t.stake.gesture;
    final a = g.action!;
    setActionDone(a, true);
    if (g.project != null) {
      logic.sync?.patchActionOf(g.project!, a);
    } else if (g.owner != null) {
      logic.sync?.updateOwnActions(g.owner!.id, g.owner!.ownActions);
    }
    logic.onChange();
  }

  void _finishShot(SniperTarget t) {
    _timer?.cancel();
    CoupAlarm.cancel();
    _stopOwnChrono();
    _hit.add(t.key);
    _lastHit = t.key;
    _persist();
    if (_nextIndex(_index) == null) {
      setState(() => _phase = _Phase.end);
      return;
    }
    _breakSec = kSniperPauseMin * 60;
    _phase = _Phase.hit;
    _ticking();
    setState(() {});
  }

  void _skip() {
    _timer?.cancel();
    CoupAlarm.cancel();
    _stopOwnChrono();
    _skipped.add(_aimed[_index].key);
    _persist();
    final n = _nextIndex(_index);
    if (n == null) {
      setState(() => _phase = _Phase.end);
    } else {
      _enter(n);
    }
  }

  void _fireNext() {
    final n = _nextIndex(_index);
    if (n == null) {
      _timer?.cancel();
      setState(() => _phase = _Phase.end);
    } else {
      _enter(n);
    }
  }

  void _skipNext() {
    final n = _nextIndex(_index);
    if (n == null) return;
    _skipped.add(_aimed[n].key);
    _persist();
    if (_nextIndex(_index) == null) {
      _timer?.cancel();
      _phase = _Phase.end;
    }
    setState(() {});
  }

  void _stop() {
    _timer?.cancel();
    CoupAlarm.cancel();
    _stopOwnChrono();
    setState(() => _phase = _Phase.end);
  }

  int get _firedTotal => _fired.values.fold(0, (s, v) => s + v);

  void _save() {
    _saved = true;
    final now = DateTime.now();
    final run = ChainRun(
      id: _runId,
      date: ymdOf(livedDate(now, logic.dayStartMin)),
      startedAt: _startedAt ?? now,
      endedAt: now,
      doneCount: _hit.length,
      total: _totalAimed,
      completed: _nextIndex(_index) == null,
      kind: kSniperKind,
    );
    logic.recordChainRun(run);
    logic.sync?.saveChainRun(run);
  }

  void _finish() {
    if (_hit.isNotEmpty) _save();
    _saved = true;
    RunSessionStore.clear();
    widget.badges?.load(refresh: true).ignore();
    Navigator.of(context).pop();
  }

  // ── Écrans ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(scaffoldBackgroundColor: _bg),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kSniperAccent))
                : switch (_phase) {
                    _Phase.aim => _aim(),
                    _Phase.shot => _shot(),
                    _Phase.hit => _hitView(),
                    _Phase.end => _end(),
                  },
          ),
        ),
      ),
    );
  }

  Widget _header({Widget? trailing, String label = 'SNIPER'}) => SizedBox(
        height: 48,
        child: Row(children: [
          const Icon(Icons.gps_fixed, color: kSniperAccent, size: 20),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1, color: kSniperAccent)),
          const InfoDot(kRuleSniper),
          const Spacer(),
          if (trailing != null) trailing,
        ]),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8, color: _text3)),
      );

  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
        child: child,
      );

  Widget _primary(String label, VoidCallback? onTap, {double height = 56}) => SizedBox(
        height: height,
        width: double.infinity,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: kSniperAccent,
            foregroundColor: kSniperInk,
            disabledBackgroundColor: kSniperAccent.withValues(alpha: .25),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _outline(String label, VoidCallback? onTap) => SizedBox(
        height: 48,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            side: BorderSide(color: Colors.white.withValues(alpha: .18)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
        ),
      );

  Color _gainColor(StakeGain g) {
    if (g.losesTonight) return const Color(0xFFFFB3AB);
    return switch (g.kind) {
      StakeGainKind.tierTonight || StakeGainKind.series || StakeGainKind.reprise || StakeGainKind.reading => const Color(0xFFFFD98A),
      StakeGainKind.halfDay || StakeGainKind.week => const Color(0xFF9FF0C1),
      StakeGainKind.objective || StakeGainKind.session => const Color(0xFFD3C6FF),
      _ => _text2,
    };
  }

  Widget _chips(List<StakeGain> gains) => Wrap(spacing: 5, runSpacing: 5, children: [
        for (final g in gains)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: _card2, borderRadius: BorderRadius.circular(99), border: Border.all(color: _gainColor(g).withValues(alpha: .35))),
            child: Text(g.label, style: TextStyle(fontSize: 11.5, color: _gainColor(g))),
          ),
      ]);

  String _hm(int min) {
    final m = min % (24 * 60);
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  Widget _targetRow(SniperTarget t, {required bool on, VoidCallback? onTap, String? reason}) {
    final sub = switch (t.kind) {
      SniperKind.action => t.stake.gesture.action?.estimatedMin == null
          ? 'estimation par défaut'
          : 'estimé ${fmtMin(t.stake.gesture.action!.estimatedMin!)}${_factor > 1.05 ? ' · d’habitude ${_factor.toStringAsFixed(1).replaceAll('.', ',')}×' : ''}',
      SniperKind.timed => 'il manque pile ${fmtMin(t.minutes)}',
      SniperKind.routine => t.stake.gesture.progress == null ? null : '${t.stake.gesture.progress} aujourd’hui',
      SniperKind.reading => 'une valeur à noter',
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: on ? kSniperAccent : null,
              borderRadius: BorderRadius.circular(6),
              border: on ? null : Border.all(color: _line, width: 2),
            ),
            child: on ? const Icon(Icons.check, size: 15, color: kSniperInk) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: reason == null ? Colors.white : _text3)),
              if (reason != null)
                Text(reason, style: const TextStyle(fontSize: 12.5, color: _text3))
              else if (sub != null)
                Text(sub, style: const TextStyle(fontSize: 12.5, color: _text3)),
              if (reason == null) ...[const SizedBox(height: 5), _chips(t.gains)],
            ]),
          ),
          const SizedBox(width: 8),
          Text(t.durLabel, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: reason == null ? kSniperAccent : _text3, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }

  Widget _aim() {
    final b = _budget;
    final total = _plan.totalMin;
    final until = b.until;
    final untilLabel = until == null ? 'Libre jusqu’à ${_hm(b.untilMin)}' : 'Libre jusqu’à ${_hm(b.untilMin)} · ${until.title}';
    final excluded = _excludedTargets;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(trailing: IconButton(tooltip: 'Fermer', icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop())),
      Expanded(
        child: ListView(children: [
          const Text('Chaque minute, pile où elle compte', style: TextStyle(fontSize: 26, height: 1.15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('L’app a calculé le temps exact qui fait tomber chaque enjeu du jour. Tu enchaînes, sans décider entre deux.',
              style: TextStyle(fontSize: 14, height: 1.4, color: _text2)),
          const SizedBox(height: 14),
          _box(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(untilLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: _text2))),
              Text(fmtMin(b.minutes), style: const TextStyle(fontSize: 13, color: _text2)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: b.minutes <= 0 ? 0 : (total / b.minutes).clamp(0, 1).toDouble(),
                minHeight: 8,
                backgroundColor: _card2,
                color: kSniperAccent,
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Text('${_plan.aimed.length} cible${_plan.aimed.length > 1 ? 's' : ''} · ', style: const TextStyle(fontSize: 13, color: _text3)),
              Text(fmtMin(total), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kSniperAccent)),
              const SizedBox(width: 8),
              if (b.minutes > total)
                Expanded(child: Text('reste ${fmtMin(b.minutes - total)} d’air', textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: _text3))),
            ]),
          ])),
          _label('CIBLES · CE QUI SE PERD CE SOIR D’ABORD'),
          if (_plan.aimed.isEmpty)
            _box(Text(
                _stakes.isEmpty
                    ? 'Rien en jeu pour l’instant : pas de série à sauver, pas de minimum en retard, pas d’action visée.'
                    : 'Aucune cible ne tient dans ton temps libre. Regarde plus bas ce qui reste hors de portée.',
                style: const TextStyle(fontSize: 13.5, height: 1.4, color: _text2)))
          else
            _box(Column(children: [
              for (final t in _plan.aimed)
                _targetRow(t, on: true, onTap: () => setState(() {
                      _excluded.add(t.key);
                      _replan();
                    })),
            ])),
          if (excluded.isNotEmpty) ...[
            _label('ÉCARTÉES · TOUCHE POUR REMETTRE'),
            _box(Column(children: [
              for (final t in excluded)
                _targetRow(t, on: false, onTap: () => setState(() {
                      _excluded.remove(t.key);
                      _replan();
                    })),
            ])),
          ],
          if (_plan.outOfReach.isNotEmpty) ...[
            _label('HORS DE PORTÉE'),
            Opacity(
              opacity: .7,
              child: _box(Column(children: [for (final m in _plan.outOfReach) _targetRow(m.target, on: false, reason: m.reason)])),
            ),
          ],
          if (_runningBefore case final r?) ...[
            const SizedBox(height: 14),
            Text('Le chrono « ${logic.state.activities.where((a) => a.id == r.activityId).firstOrNull?.name ?? 'en cours'} » s’arrête au lancement : le Sniper prend la main.',
                style: const TextStyle(fontSize: 13, height: 1.4, color: kSniperAccent)),
          ],
          const SizedBox(height: 10),
          Text('Pause de $kSniperPauseMin min entre deux tirs · touche une cible pour l’écarter.', style: const TextStyle(fontSize: 12, color: _text3)),
        ]),
      ),
      const SizedBox(height: 12),
      _primary(_plan.aimed.isEmpty ? 'Rien à viser' : 'Viser · ${_plan.aimed.length} cible${_plan.aimed.length > 1 ? 's' : ''} · ${fmtMin(total)}', _plan.aimed.isEmpty ? null : _start),
    ]);
  }

  Widget _track() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < _aimed.length; i++)
          Container(
            width: 26,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              color: _hit.contains(_aimed[i].key)
                  ? _green
                  : _skipped.contains(_aimed[i].key)
                      ? _line
                      : i == _index
                          ? kSniperAccent
                          : _card2,
            ),
          ),
      ]);

  int get _shotNumber => _aimed.isEmpty ? 0 : _index + 1;

  Widget _nextLine() {
    final n = _nextIndex(_index);
    if (n == null) return const SizedBox.shrink();
    final t = _aimed[n];
    final after = _nextIndex(n);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label('ENSUITE'),
      _box(Text.rich(TextSpan(style: const TextStyle(fontSize: 13.5, color: _text2), children: [
        TextSpan(text: '${t.title} · '),
        TextSpan(text: t.durLabel, style: const TextStyle(fontWeight: FontWeight.w800, color: kSniperAccent)),
        if (after != null) TextSpan(text: ' · puis ${_aimed[after].title}'),
      ]))),
    ]);
  }

  Widget _shot() {
    final t = _aimed[_index];
    final timed = t.minutes > 0;
    final total = timed ? (_endsAt != null && _shotStart != null ? _endsAt!.difference(_shotStart!).inSeconds : t.minutes * 60) : 1;
    final left = _pausedLeft ?? _remaining;
    final mm = (left ~/ 60).toString();
    final ss = (left % 60).toString().padLeft(2, '0');
    final endAt = _endsAt == null ? null : TimeOfDay.fromDateTime(_endsAt!);
    final chrono = _ownChrono ? logic.runningActivity()?.name : null;
    final action = t.kind == SniperKind.action;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(label: 'TIR $_shotNumber / ${_aimed.length}', trailing: TextButton(onPressed: _stop, child: const Text('Je m’arrête', style: TextStyle(color: _text2, fontSize: 14)))),
      _track(),
      Expanded(
        child: ListView(children: [
          const SizedBox(height: 12),
          if (timed)
            Center(
              child: SizedBox(
                width: 210,
                height: 210,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: total <= 0 ? 1 : (1 - left / total).clamp(0, 1).toDouble(),
                      strokeWidth: 11,
                      backgroundColor: _card2,
                      color: kSniperAccent,
                    ),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('$mm:$ss', style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                    Text(
                        _pausedLeft != null
                            ? 'en pause'
                            : left == 0
                                ? 'temps écoulé'
                                : 'sur ${t.minutes}:00${endAt == null ? '' : ' · fin à ${endAt.hour.toString().padLeft(2, '0')}:${endAt.minute.toString().padLeft(2, '0')}'}',
                        style: const TextStyle(fontSize: 12, color: _text3)),
                  ]),
                ]),
              ),
            )
          else
            Center(
              child: Container(
                width: 150,
                height: 150,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kSniperAccent, width: 3)),
                child: Text(t.durLabel, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: kSniperAccent)),
              ),
            ),
          const SizedBox(height: 14),
          Text(t.title, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 26, height: 1.2, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            switch (t.kind) {
              SniperKind.timed => chrono != null ? 'chrono sur $chrono · alarme à la fin' : 'alarme à la fin',
              SniperKind.action => chrono != null ? 'chrono sur $chrono · l’action tombe quand elle est faite' : 'l’action tombe quand elle est faite',
              SniperKind.routine => t.delta > 1 ? '${t.delta} coches pour l’atteindre' : 'une coche pour l’atteindre',
              SniperKind.reading => 'note la valeur du jour',
            },
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, color: _text2),
          ),
          _label('CE TIR FAIT TOMBER'),
          _box(Align(alignment: Alignment.centerLeft, child: _chips(t.gains))),
          _nextLine(),
        ]),
      ),
      const SizedBox(height: 10),
      switch (t.kind) {
        SniperKind.timed => _primary(left == 0 ? 'Touché' : 'Fait plus tôt · touché', _touch, height: 56),
        SniperKind.action => _primary('Action faite', () => _touch(), height: 56),
        SniperKind.routine => _primary(timed && left > 0 ? 'Fait · +${t.delta}' : '+${t.delta} · touché', () => _touch(), height: 56),
        SniperKind.reading => _primary('Noter le relevé', _noteReading, height: 56),
      },
      const SizedBox(height: 10),
      Row(children: [
        if (timed) ...[
          Expanded(child: _outline(_pausedLeft != null ? 'Reprendre' : 'Pause', _togglePause)),
          const SizedBox(width: 8),
          Expanded(child: _outline('+5 min', _more)),
          const SizedBox(width: 8),
        ],
        Expanded(child: _outline(action ? 'Pas finie · suivante' : 'Passer', _skip)),
      ]),
    ]);
  }

  Widget _hitView() {
    final t = _aimed.where((x) => x.key == _lastHit).firstOrNull ?? _aimed[_index];
    final fired = _fired[t.key] ?? t.cost;
    final n = _nextIndex(_index);
    final next = n == null ? null : _aimed[n];
    final gap = fired - t.cost;
    final mm = (_breakSec ~/ 60).toString();
    final ss = (_breakSec % 60).toString().padLeft(2, '0');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(label: 'TIR $_shotNumber / ${_aimed.length}', trailing: TextButton(onPressed: _stop, child: const Text('Je m’arrête', style: TextStyle(color: _text2, fontSize: 14)))),
      _track(),
      Expanded(
        child: ListView(children: [
          const SizedBox(height: 16),
          const Icon(Icons.gps_fixed, size: 52, color: _green),
          const SizedBox(height: 8),
          Text('Touché · ${t.title}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          if (t.minutes > 0)
            Text(gap == 0 ? '${fmtMin(fired)} pile · écart 0' : '${fmtMin(fired)} pour ${fmtMin(t.cost)} visées · ${gap > 0 ? '+' : '−'}${gap.abs()} min',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: _text2)),
          _label('CE QUI VIENT DE TOMBER'),
          _box(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final g in t.gains)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  const Icon(Icons.check, size: 16, color: _green),
                  const SizedBox(width: 8),
                  Expanded(child: Text(g.label, style: const TextStyle(fontSize: 14))),
                ]),
              ),
          ])),
          if (next != null) ...[
            _label('PROCHAIN TIR DANS'),
            _box(Column(children: [
              Text('$mm:$ss', style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
              Text('${next.title} · ${next.durLabel}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: _text2)),
            ])),
          ],
        ]),
      ),
      const SizedBox(height: 10),
      _primary('Tirer maintenant', _fireNext, height: 56),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _outline('Souffler 5 min', () => setState(() => _breakSec = 300))),
        const SizedBox(width: 8),
        Expanded(child: _outline('Passer cette cible', _skipNext)),
      ]),
    ]);
  }

  Widget _end() {
    final hitTargets = _aimed.where((t) => _hit.contains(t.key)).toList();
    final missed = _aimed.where((t) => !_hit.contains(t.key)).toList();
    final hitN = _hit.length;
    final counted = logic.state.chainRuns.where((r) => r.id != _runId && sniperCounts(r)).length + (hitN >= kSniperCountedMin && hitN >= _totalAimed ? 1 : 0);
    final nextTier = kSniperTiers.firstWhere((t) => t > counted, orElse: () => kSniperTiers.last);
    final aimedHitMin = hitTargets.fold<int>(0, (s, t) => s + t.cost);
    final precision = sniperPrecision(aimedHitMin, _firedTotal);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(children: [
          const SizedBox(height: 12),
          const Text('SESSION SNIPER', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: _text3)),
          const SizedBox(height: 6),
          Text(hitN == 0 ? 'Aucune cible cette fois' : '$hitN / $_totalAimed cible${_totalAimed > 1 ? 's' : ''} touchée${hitN > 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 28, height: 1.2, fontWeight: FontWeight.w800)),
          Text('${fmtMin(_firedTotal)} tirées pour ${fmtMin(aimedHitMin)} visées · ${sniperCountLine(hitN, _totalAimed)}', style: const TextStyle(fontSize: 13.5, color: _text2)),
          const SizedBox(height: 14),
          Row(children: [
            for (final (v, l) in [('$precision %', 'précision'), ('${hitTargets.fold<int>(0, (s, t) => s + t.gains.length)}', 'enjeux tombés'), ('0', 'décision')]) ...[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: _card2, borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(l, style: const TextStyle(fontSize: 12, color: _text3)),
                  ]),
                ),
              ),
              if (l != 'décision') const SizedBox(width: 8),
            ],
          ]),
          if (hitTargets.isNotEmpty) ...[
            _label('TOMBÉ'),
            _box(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final t in hitTargets)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.check, size: 16, color: _green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        Text(t.gains.map((g) => g.label).join(' · '), style: const TextStyle(fontSize: 12.5, color: _text3)),
                      ]),
                    ),
                  ]),
                ),
            ])),
          ],
          if (missed.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Pas tiré : ${missed.map((t) => t.title).join(' · ')}', style: const TextStyle(fontSize: 12.5, color: _amber)),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: kSniperInk, borderRadius: BorderRadius.circular(14), border: Border.all(color: kSniperAccent.withValues(alpha: .45))),
            child: Row(children: [
              const Icon(Icons.gps_fixed, color: kSniperAccent, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Sniper', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kSniperAccent)),
                  Text(counted >= kSniperTiers.last ? '$counted sessions · tous les paliers' : '$counted / $nextTier sessions · palier $nextTier',
                      style: const TextStyle(fontSize: 13, color: _text2)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: (counted / nextTier).clamp(0, 1).toDouble(), minHeight: 6, backgroundColor: _card2, color: kSniperAccent),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      _primary('Terminer', _finish, height: 54),
    ]);
  }
}
