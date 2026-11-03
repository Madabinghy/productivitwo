import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/utils/mode_colors.dart';
import 'package:productivitwo_v1/utils/mode_moves.dart' show smallChain;
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/chain_session_store.dart';
import 'package:productivitwo_v1/utils/chain.dart';
import 'package:productivitwo_v1/utils/chain_session.dart';
import 'package:productivitwo_v1/utils/objective_day.dart' show buildObjectiveDays;
import 'package:productivitwo_v1/utils/checklist_logic.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/interventions.dart' show linkMirrorsToSessions;
import 'package:productivitwo_v1/utils/routines_today.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/widgets/elan_rows.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/now_card.dart' show NowPalette;
import 'package:productivitwo_v1/widgets/ring_painter.dart';
import 'package:productivitwo_v1/widgets/routines_day_view.dart'
    show kRoutineAccent, routineMinus, routinePlus, routineTodayCount;
import 'package:productivitwo_v1/widgets/routine_chrono_pill.dart';
import 'package:productivitwo_v1/widgets/running_chrono_bar.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Monde d'Enchaîner (maquette validée 2026-11-03 « Enchaîner, refait ») : fond sarcelle profond, accent menthe,
/// même grammaire que Sniper et Guérilla. Les routines gardent leur orange.
const kChainAccent = Color(0xFF5FE0C8);
const kChainInk = Color(0xFF05211C);
const _cBg = Color(0xFF071416);
const _cCard = Color(0xFF0F2226);
const _cCard2 = Color(0xFF16302F);
const _cLine = Color(0xFF1E3A3B);
const _chainPal = NowPalette(
  surface: _cCard,
  primary: kChainAccent,
  onPrimary: kChainInk,
  track: _cCard2,
  chip: Color(0x14FFFFFF),
  text: Color(0xFFE6F2EF),
  text2: Color(0xFFB2CCC6),
  text3: Color(0xFF7F9A94),
  text4: Color(0xFF5E7671),
);

/// Mode « Enchaîner » (2026-10) : une seule chose à l'écran, celle à faire
/// maintenant ; « Fait » amène la suivante. La file vient du programme du
/// jour (`buildChain`), le chrono suit le bloc affiché. Plein écran, sans
/// onglets : on en sort par « Sortir » (récap) ou quand la file est vide.
Future<void> showChainScreen(
  BuildContext context, {
  required AppLogic logic,
  required FirestoreSync sync,
  required String date,
  required void Function(ScheduleBlock block) onLaunch,
  required VoidCallback onStopTimer,
  void Function(ScheduleBlock block)? onOpenSource,
  StrategicObjective? objective,
  bool small = false,
}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _ChainScreen(
      logic: logic,
      sync: sync,
      small: small,
      date: date,
      onLaunch: onLaunch,
      onStopTimer: onStopTimer,
      onOpenSource: onOpenSource,
      objective: objective,
    ),
  ));
}

class _ChainScreen extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final String date;
  final void Function(ScheduleBlock block) onLaunch;
  final VoidCallback onStopTimer;
  final void Function(ScheduleBlock block)? onOpenSource;
  /// Enchaîner UN objectif (carte Objectif du moment) : file `buildObjectiveChain`
  /// au lieu du programme entier ; pas de session Enchaîner enregistrée.
  final StrategicObjective? objective;
  /// Mode Flemme : « 3 petites choses » (routines, étapes, actions ≤ 10 min).
  final bool small;
  const _ChainScreen({
    required this.logic,
    required this.sync,
    required this.date,
    required this.onLaunch,
    required this.onStopTimer,
    this.onOpenSource,
    this.objective,
    this.small = false,
  });

  @override
  State<_ChainScreen> createState() => _ChainScreenState();
}

class _ChainScreenState extends State<_ChainScreen> {
  StreamSubscription<DailySchedule?>? _sub;
  Timer? _tick;
  List<ScheduleBlock> _blocks = const [];
  bool _loaded = false;
  // Choix de la session : écrans remis à plus tard (fin de file) et écartés.
  final List<String> _deferred = [];
  final Set<String> _dismissed = {};
  late DateTime _startedAt;
  int _doneCount = 0;
  /// Session en attente reprise (même id de ChainRun → la session écrite est réécrite, total cumulé).
  String? _runId;
  int _resumedCount = 0;
  /// Instants des choses faites dans la session (chips du récap : « dont 2 malgré tout »).
  final List<DateTime> _doneAts = [];
  int _totalAtStart = 0;
  // Blocs dont les écrans sont épuisés : la file les considère faits même si
  // le programme n'a pas encore répercuté l'écriture.
  final Set<String> _finishedBlocks = {};
  // Transition entre deux blocs : le bloc qui vient d'être terminé.
  ScheduleBlock? _between;
  int _betweenMin = 0;
  // Transition : « Attendre HH:MM » / « Souffler 5 min » → reprise automatique.
  DateTime? _waitUntil;
  // Bloc dont on a lancé le chrono (une fois par entrée dans le bloc).
  String? _enteredBlockId;
  ChainItem? _entered;
  // Dépassement : blocs pour lesquels on a choisi « Laisser ».
  final Set<String> _overrunIgnored = {};
  bool _paused = false;
  bool _summary = false;
  bool _leaving = false;
  bool _busy = false;
  // Session d'Enchaîner (badges, 2026-10) : premier bloc réel de la file au
  // départ, dernier bloc réel épuisé, sortie avant la fin, écrite une fois au récap.
  String? _firstBlockId;
  String? _lastBlockId;
  bool _exited = false;
  bool _recorded = false;
  // Routine affichée : la file la retire dès que la cible est atteinte (un +1
  // sur une cible à 1), on la garde en tête jusqu'à « Suivante ».
  ChainItem? _held;

  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    // L'écran reste allumé pendant la session (téléphone posé à côté).
    WakelockPlus.enable().catchError((_) {});
    logic.addListener(_onLogic);
    _sub = widget.sync.streamDailySchedule(widget.date).listen((s) {
      if (!mounted) return;
      final blocks = (s?.blocks.where((b) => b.status != 'deleted').toList() ?? [])
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      final day = DateTime.tryParse(widget.date);
      if (day != null) linkMirrorsToSessions(blocks, logic.currentProjects, day);
      setState(() {
        _blocks = blocks;
        if (!_loaded) {
          _loaded = true;
          if (!_restorePending()) {
            final first = _ordered();
            _totalAtStart = first.length;
            _firstBlockId = first.where((i) => !i.synthetic).firstOrNull?.block.id;
          }
        }
      });
      _afterChange();
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final w = _waitUntil;
      if (w != null && _between != null && !DateTime.now().isBefore(w)) {
        _startNext();
        return;
      }
      setState(() {});
    });
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  /// Session en attente du même jour vécu, inactive depuis moins de 45 min :
  /// on repart où on en était, et ce qui a été fait pendant la pause compte.
  bool _restorePending() {
    if (widget.objective != null || widget.small) return false;
    final pc = ChainSessionStore.current;
    final now = DateTime.now();
    if (pc == null || !pc.isLive(now, widget.date)) {
      if (pc != null) ChainSessionStore.clear();
      return false;
    }
    final extra = resumedDoneAts(_blocks, logic.state.habitHits, logic.state.activities,
        since: pc.lastActiveAt, now: now, dayStartMin: logic.dayStartMin, finishedBlocks: pc.finishedBlocks);
    _runId = pc.runId;
    _startedAt = pc.startedAt;
    _doneCount = pc.doneCount + extra.length;
    _doneAts
      ..clear()
      ..addAll(pc.doneAts)
      ..addAll(extra);
    _deferred
      ..clear()
      ..addAll(pc.deferred);
    _dismissed
      ..clear()
      ..addAll(pc.dismissed);
    _finishedBlocks
      ..clear()
      ..addAll(pc.finishedBlocks);
    _firstBlockId = pc.firstBlockId;
    _lastBlockId = pc.lastBlockId;
    _totalAtStart = pc.totalAtStart;
    _resumedCount = extra.length;
    return true;
  }

  /// Mémorise la session (reprenable depuis MAINTENANT) ; jamais pour une
  /// file d'objectif ni « petites choses ».
  void _persist() {
    if (widget.objective != null || widget.small || !_loaded) return;
    ChainSessionStore.save(PendingChain(
      runId: _runId ??= ChainRun(date: widget.date, startedAt: _startedAt, endedAt: _startedAt, doneCount: 0, total: 0, completed: false).id,
      date: widget.date,
      startedAt: _startedAt,
      lastActiveAt: DateTime.now(),
      doneCount: _doneCount,
      doneAts: List.of(_doneAts),
      deferred: List.of(_deferred),
      dismissed: Set.of(_dismissed),
      finishedBlocks: Set.of(_finishedBlocks),
      firstBlockId: _firstBlockId,
      lastBlockId: _lastBlockId,
      totalAtStart: _totalAtStart,
    ));
  }

  /// Fin réelle de la session : « Terminer » dans le récap ou file vide.
  void _closeSession() {
    if (widget.objective == null && !widget.small) ChainSessionStore.clear();
  }

  @override
  void dispose() {
    if (!_summary || !_ordered().isEmpty) _persist();
    WakelockPlus.disable().catchError((_) {});
    logic.removeListener(_onLogic);
    _sub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  // ── File ────────────────────────────────────────────────────────────────────

  List<ChainItem> _ordered() {
    final now = DateTime.now();
    final o = widget.objective;
    final items = o != null
        ? _objectiveItems(o, now)
        : buildChain(
      blocks: _blocks.where((b) => !_finishedBlocks.contains(b.id)).toList(),
      projects: logic.currentProjects,
      activities: logic.state.activities,
      hits: logic.state.habitHits,
      now: now,
      pushed: _pushed,
      deferred: _routineDeferred,
      dismissed: _routineDismissed,
          dayStartMin: logic.dayStartMin,
          moments: logic.moments,
    );
    var list = orderChain(widget.small ? smallChain(items) : items, deferred: _deferred, dismissed: _dismissed);
    final h = _held;
    if (h != null &&
        !_dismissed.contains(h.key) &&
        !_deferred.contains(h.key) &&
        !list.any((x) => x.key == h.key)) {
      list = [h, ...list];
    }
    _held = list.firstOrNull?.kind == ChainKind.routine ? list.first : null;
    return list;
  }

  List<ChainItem> _objectiveItems(StrategicObjective o, DateTime now) {
    final day = buildObjectiveDays(
      objectives: [o],
      activities: logic.state.activeActivities,
      sessions: logic.state.sessions,
      blocks: _blocks.where((b) => !_finishedBlocks.contains(b.id)).toList(),
      projects: logic.currentProjects,
      now: now,
      dayStartMin: logic.dayStartMin,
    ).firstOrNull;
    if (day == null) return const [];
    return buildObjectiveChain(day,
        projects: logic.currentProjects,
        activities: logic.state.activities,
        hits: logic.state.habitHits,
        now: now,
        dismissed: _routineDismissed,
        dayStartMin: logic.dayStartMin);
  }

  Session? get _openSession {
    Session? last;
    for (final s in logic.state.sessions) {
      if (s.endAt != null) continue;
      if (last == null || s.startAt.isAfter(last.startAt)) last = s;
    }
    return last;
  }

  /// Minute vécue : après minuit, la file de la veille continue (24 h 30).
  int get _nowMin => logic.livedNowMinNow;

  String _clock(int min) =>
      '${((min ~/ 60) % 24).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';

  /// Après un changement (coche, programme) : bloc épuisé → transition ;
  /// nouveau bloc affiché → chrono dessus.
  void _afterChange() {
    if (!mounted || _summary) return;
    _persist();
    final items = _ordered();
    final cur = items.firstOrNull;
    if (_enteredBlockId != null &&
        _between == null &&
        (cur == null || cur.block.id != _enteredBlockId) &&
        !_deferred.any((k) => k.startsWith('$_enteredBlockId/'))) {
      final finished = _blocks.where((b) => b.id == _enteredBlockId).firstOrNull;
      if (finished != null) {
        _finishBlock(finished);
        return;
      }
      // Bloc fabriqué (routines accrochées, file d'un objectif) : pas de
      // transition, on enchaîne — mais un chrono lancé pour lui s'arrête.
      final e = _entered;
      final open = _openSession;
      if (e != null && e.timed && open != null && logic.sessionOnBlock(open, e.block)) logic.stopActive(notify: false);
      _enteredBlockId = null;
      _entered = null;
    }
    if (cur != null && _between == null && cur.block.id != _enteredBlockId) {
      _enterBlock(cur);
    }
  }

  void _enterBlock(ChainItem item) {
    _enteredBlockId = item.block.id;
    _entered = item;
    _paused = false;
    if (!item.timed) return;
    final open = _openSession;
    if (open != null && logic.sessionOnBlock(open, item.block)) return;
    // Bloc fabriqué (file d'un objectif) : rien n'est programmé à cette heure,
    // on ne lance pas le chrono à sa place — bouton « Lancer le chrono ».
    if (item.synthetic) {
      _paused = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLaunch(item.block);
    });
  }

  Future<void> _finishBlock(ScheduleBlock b) async {
    _finishedBlocks.add(b.id);
    final minutes = chainMinutesOn(b, logic.state.sessions, _startedAt, DateTime.now(), logic.sessionOnBlock);
    if (_openSession != null && logic.sessionOnBlock(_openSession!, b)) logic.stopActive(notify: false);
    setState(() {
      _between = b;
      _betweenMin = minutes;
      _enteredBlockId = null;
      _entered = null;
    });
    if (b.status == 'pending') {
      await widget.sync.updateBlockStatus(widget.date, b.id, 'done', manual: true);
    }
  }

  // ── Gestes ──────────────────────────────────────────────────────────────────

  Future<void> _guard(Future<void> Function() f) async {
    if (_busy) return;
    _busy = true;
    try {
      await f();
    } finally {
      _busy = false;
    }
  }

  Future<void> _saveAction(ChainItem i) async {
    if (i.project != null) {
      await widget.sync.saveProjectTasks(i.project!.id, i.project!.tasks);
    } else if (i.activity != null) {
      await widget.sync.updateOwnActions(i.activity!.id, i.activity!.ownActions);
    }
  }

  Future<void> _done(ChainItem i) => _guard(() async {
        HapticFeedback.lightImpact();
        switch (i.kind) {
          case ChainKind.step:
            setState(() => setChecklistItem(i.action!, i.step!.id, true));
            await _saveAction(i);
            break;
          case ChainKind.action:
            setState(() => setActionDone(i.action!, true));
            await _saveAction(i);
            break;
          case ChainKind.routine:
          case ChainKind.session:
          case ChainKind.block:
            setState(() => _dismissed.add(i.key));
            break;
        }
        _doneCount++;
        _doneAts.add(DateTime.now());
        if (!i.synthetic) _lastBlockId = i.block.id;
        _afterChange();
      });

  void _later(ChainItem i) {
    setState(() {
      _deferred.remove(i.key);
      _deferred.add(i.key);
    });
    _afterChange();
  }

  void _dismiss(ChainItem i) {
    // Routine « pas aujourd'hui » : écartée pour la journée partout (vue
    // Routines comprise), pas seulement dans cette session.
    if (i.kind == ChainKind.routine && i.activity != null) {
      final ymd = logic.livedYmdNow;
      logic.setNowDone(ymd, logic.nowDoneSet(ymd)..add(i.activity!.id));
    }
    setState(() => _dismissed.add(i.key));
    _afterChange();
  }

  Map<String, String> get _pushed => logic.routinePushed(logic.livedYmdNow);
  List<String> get _routineDeferred => logic.state.nowSkippedByYmd[logic.livedYmdNow] ?? const [];
  Set<String> get _routineDismissed => logic.nowDoneSet(logic.livedYmdNow);

  void _pause() {
    widget.onStopTimer();
    setState(() => _paused = true);
  }

  /// Pause / Reprendre, ou « Lancer le chrono » quand aucun chrono ne tourne
  /// sur cet écran (bloc fabriqué entré sans lancement automatique).
  Widget _chronoButton(ChainItem i) {
    final s = _openSession;
    final onBlock = s != null && logic.sessionOnBlock(s, i.block);
    if (!_paused) return _secondary('Pause', _pause);
    return _secondary(onBlock ? 'Reprendre' : 'Lancer le chrono', () => _resume(i));
  }

  void _resume(ChainItem i) {
    setState(() => _paused = false);
    if (i.timed) widget.onLaunch(i.block);
  }

  void _startNext() {
    setState(() {
      _between = null;
      _waitUntil = null;
    });
    _afterChange();
  }

  void _waitFor(DateTime until) => setState(() => _waitUntil = until);

  Future<void> _shift(ScheduleBlock b, int delta) async {
    final changed = shiftFollowing(_blocks, b, delta);
    setState(() => _overrunIgnored.add(b.id));
    for (final c in changed) {
      await widget.sync.upsertScheduleBlock(widget.date, c);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
      content: Text(changed.isEmpty
          ? 'Rien à décaler après ce bloc.'
          : '${changed.length} bloc${changed.length > 1 ? 's' : ''} décalé${changed.length > 1 ? 's' : ''} de ${fmtMin(delta)}'),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _carry(ScheduleBlock b) => _guard(() async {
        await widget.sync.reportBlockToTomorrow(widget.date, b);
        await widget.sync.updateBlockStatus(widget.date, b.id, 'skipped');
        await widget.sync.updateBlockSkipReason(widget.date, b.id, 'reporte');
        setState(() => _finishedBlocks.add(b.id));
      });

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const pal = _chainPal;
    final items = _ordered();
    final cur = items.firstOrNull;
    final showSummary = _summary || (_loaded && cur == null && _between == null);
    // Plus d'écran récap (retour user 2026-10-30 : « il ne sert à rien ») :
    // la session s'enregistre et l'écran se ferme.
    if (showSummary) {
      if (!_leaving) {
        _leaving = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_recorded) _recordRun();
          if (mounted) Navigator.of(context).maybePop();
        });
      }
      return const Scaffold(backgroundColor: _cBg, body: SizedBox.shrink());
    }
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: _cBg,
        colorScheme: const ColorScheme.dark(primary: kChainAccent, onPrimary: kChainInk, surface: _cCard),
      ),
      child: Scaffold(
        backgroundColor: _cBg,
        body: SafeArea(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator(color: kChainAccent))
              : _between != null
                  ? _transition(pal, _between!, cur, items)
                  : _focus(pal, cur!, items),
        ),
      ),
    );
  }

  /// En-tête du mode (comme Sniper / Guérilla) : « ⛓ ENCHAÎNER · k / n » et « Je m'arrête ».
  Widget _header(NowPalette pal, {String? label}) {
    final total = _totalAtStart <= 0 ? 1 : _totalAtStart;
    final pos = (_doneCount + 1).clamp(1, total < _doneCount + 1 ? _doneCount + 1 : total);
    return SizedBox(
      height: 44,
      child: Row(children: [
        const Icon(Icons.link_rounded, color: kChainAccent, size: 20),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label ?? 'ENCHAÎNER · $pos / ${total < pos ? pos : total}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, letterSpacing: 1.5, fontWeight: FontWeight.w900, color: pal.text2)),
        ),
        TextButton(
          onPressed: () => setState(() {
            _exited = true;
            _summary = true;
          }),
          child: Text('Je m’arrête', style: TextStyle(fontSize: 14, color: pal.text2)),
        ),
      ]),
    );
  }

  /// La piste : un segment par chose — faites, en cours, à venir —, regroupées par bloc, routines en orange.
  Widget _track(List<ChainItem> items) {
    final segs = <Widget>[];
    Widget seg(Color c, {double flex = 1}) => Expanded(
          flex: (flex * 4).round(),
          child: Container(height: 6, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        );
    for (var k = 0; k < _doneCount && k < 30; k++) {
      segs.add(seg(kChainAccent.withValues(alpha: .55)));
    }
    String? lastBlock;
    for (var k = 0; k < items.length && k < 40; k++) {
      final it = items[k];
      if (lastBlock != null && it.block.id != lastBlock) segs.add(const Expanded(flex: 1, child: SizedBox()));
      lastBlock = it.block.id;
      final routine = it.kind == ChainKind.routine;
      final cur = k == 0 && _between == null;
      segs.add(seg(cur ? (routine ? kRoutineAccent : kChainAccent) : (routine ? const Color(0xFF4A3424) : _cCard2)));
    }
    if (segs.isEmpty) return const SizedBox(height: 6);
    final spaced = <Widget>[];
    for (var k = 0; k < segs.length; k++) {
      if (k > 0) spaced.add(const SizedBox(width: 3));
      spaced.add(segs[k]);
    }
    return Row(children: spaced);
  }

  Widget _label(NowPalette pal, String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(text, style: TextStyle(fontSize: 11, letterSpacing: 1.3, fontWeight: FontWeight.w800, color: pal.text3)),
      );

  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: _cCard, borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _chip(NowPalette pal, String text, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
            color: (color ?? pal.primary).withOpacity(.14), borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .6, color: color ?? pal.primary)),
      );

  /// Compteur − x / y + sur place (même geste que l'Enchaîner routines) : on
  /// peut faire plusieurs +1 avant de passer à la suite — une cible à 1 ne
  /// coupe plus la série.
  Widget _routineCounter(NowPalette pal, Activity a, RoutineToDo r) {
    final todayN = routineTodayCount(logic, a);
    final dayTarget = r.dayTarget;
    final count = dayTarget != null ? r.dayDone : r.weekDone;
    final target = dayTarget ?? r.weekTarget;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _round(pal, '−', todayN > 0 || (dayTarget == null && r.weekDone > 0)
          ? () {
              if (routineMinus(logic, a)) HapticFeedback.selectionClick();
              setState(() {});
            }
          : null),
      const SizedBox(width: 28),
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$count / $target',
            style: TextStyle(
                fontSize: 34, fontWeight: FontWeight.w800, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()])),
        Text(dayTarget != null ? 'AUJOURD\'HUI' : 'CETTE SEMAINE',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: pal.text3)),
      ]),
      const SizedBox(width: 28),
      _round(pal, '+', () {
        HapticFeedback.lightImpact();
        routinePlus(logic, a);
        setState(() {});
      }, bg: kRoutineAccent, fg: kBBg),
    ]);
  }

  Widget _round(NowPalette pal, String label, VoidCallback? onTap, {Color? bg, Color? fg}) => SizedBox(
        width: 56,
        height: 56,
        child: Material(
          color: onTap == null ? pal.chip : (bg ?? pal.chip),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: onTap == null ? Colors.white.withOpacity(.18) : (fg ?? pal.text2))),
            ),
          ),
        ),
      );

  Widget _primary(String label, VoidCallback onTap, {IconData? icon, Color? color}) => SizedBox(
        height: 56,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: color ?? kChainAccent,
            foregroundColor: color == null ? kChainInk : const Color(0xFF1E0E03),
            shape: const StadiumBorder(),
          ),
          onPressed: onTap,
          icon: Icon(icon ?? Icons.check_rounded),
          label: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _secondary(String label, VoidCallback onTap) => Expanded(
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 13),
            foregroundColor: _chainPal.text2,
            side: const BorderSide(color: _cLine),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );

  Widget _ensuite(NowPalette pal, List<ChainItem> items) {
    final next = items.length > 1 ? items[1] : null;
    final other = next != null && next.block.id != items.first.block.id && !next.synthetic;
    return Container(
      padding: EdgeInsets.zero,
      child: Row(children: [
        if (other)
          SizedBox(
            width: 50,
            child: Text(_clock(blockStartMin(next.block)),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: kChainAccent, fontFeatures: [FontFeature.tabularFigures()])),
          ),
        Expanded(
          child: Text(
            next == null
                ? 'Rien d\'autre : c\'est la dernière.'
                : next.block.id == items.first.block.id || next.synthetic
                    ? next.title
                    : next.block.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.text2),
          ),
        ),
      ]),
    );
  }

  Widget _focus(NowPalette pal, ChainItem i, List<ChainItem> items) {
    final b = i.block;
    final nowMin = _nowMin;
    final start = blockStartMin(b), end = blockEndMin(b);
    // Une routine accrochée à un moment (~soir) n'a pas d'heure à dépasser.
    final over = i.synthetic ? 0 : overrunMin(b, nowMin);
    final session = _openSession;
    final onBlock = session != null && logic.sessionOnBlock(session, b);
    final elapsed = onBlock ? DateTime.now().difference(session.startAt) : null;
    final ringProgress = over > 0
        ? 1.0
        : (nowMin >= start ? (nowMin - start) / b.durationMin : 0.0).clamp(0.0, 1.0);
    final ringColor = over > 0 ? kBAttention : pal.primary;
    final remaining = end - nowMin;
    final String under = over > 0
        ? '+${fmtMin(nowMin - end)}'
        : nowMin < start
            ? 'à ${_clock(start)}'
            : 'reste ${fmtMin(remaining)}';
    final center = elapsed != null
        ? _mmss(elapsed)
        : i.kind == ChainKind.routine
            ? '+1'
            : _clock(nowMin);

    final String kindLabel;
    switch (i.kind) {
      case ChainKind.step:
        kindLabel = 'Étape ${i.index} / ${i.total}';
        break;
      case ChainKind.action:
        kindLabel = 'Action';
        break;
      case ChainKind.routine:
        kindLabel = 'Routine';
        break;
      case ChainKind.session:
        kindLabel = 'Séance';
        break;
      case ChainKind.block:
        kindLabel = b.gcalEventId != null ? 'Rendez-vous' : 'Bloc';
        break;
    }
    final kindColor = i.kind == ChainKind.routine ? kRoutineAccent : null;
    final routine = i.kind == ChainKind.routine
        ? routinesForToday([i.activity!], logic.state.habitHits, DateTime.now(), dayStartMin: logic.dayStartMin).firstOrNull
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(pal),
        _track(items),
        RunningChronoBar(logic: logic),
        const SizedBox(height: 6),
        Row(children: [
          _chip(pal, kindLabel, color: kindColor),
          if (widget.objective != null) ...[
            const SizedBox(width: 6),
            _chip(pal, widget.objective!.title, color: const Color(0xFF00897B)),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: Text(i.synthetic ? b.title : '${b.title} · ${_clock(start)} → ${_clock(end)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.5, color: pal.text3, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ]),
        Expanded(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 18),
              if (i.kind != ChainKind.routine)
                SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(alignment: Alignment.center, children: [
                    CustomPaint(
                      size: const Size(200, 200),
                      painter: RingPainter(
                          progress: ringProgress, color: ringColor, stroke: 12, trackColor: pal.track, cap: StrokeCap.round),
                    ),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(center,
                          style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.5,
                              color: pal.text,
                              fontFeatures: const [FontFeature.tabularFigures()])),
                      Text(under,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: over > 0 ? kBAttention : pal.text3,
                              fontFeatures: const [FontFeature.tabularFigures()])),
                      if (_paused)
                        Text(onBlock ? 'en pause' : 'chrono à lancer', style: TextStyle(fontSize: 11, color: pal.text4)),
                    ]),
                  ]),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 14),
                  child: Icon(
                      i.activity!.iconCode != null
                          ? IconData(i.activity!.iconCode!, fontFamily: 'MaterialIcons')
                          : Icons.repeat_rounded,
                      size: 56,
                      color: kindColor),
                ),
                if (routine != null) _routineCounter(pal, i.activity!, routine),
                const SizedBox(height: 14),
                RoutineChronoPill(logic: logic, routine: i.activity!, centered: true, onChanged: () => setState(() {})),
              ],
              const SizedBox(height: 18),
              if (i.context != null)
                Text(i.context!.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                        color: i.kind == ChainKind.routine ? kRoutineAccent : kChainAccent)),
              const SizedBox(height: 6),
              Text(i.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, height: 1.2, color: pal.text)),
              if (_subLine(i, onBlock) case final sub?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(sub, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: pal.text2)),
                ),
              if (i.kind == ChainKind.step && i.action!.checklist.length > 1) ...[
                _label(pal, 'LES ÉTAPES'),
                _box(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final st in i.action!.checklist) _stepLine(pal, st, current: st.id == i.step?.id),
                ])),
              ],
              if (over > 0 && !_overrunIgnored.contains(b.id)) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: kBAttention.withOpacity(.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kBAttention.withOpacity(.4)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Le bloc a dépassé son heure',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: pal.text)),
                    const SizedBox(height: 2),
                    Text('Le chrono continue. La suite commencerait en retard.',
                        style: TextStyle(fontSize: 12.5, color: pal.text3)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: () => _shift(b, over),
                          child: Text('Décaler la suite de ${fmtMin(over)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                          onPressed: () => setState(() => _overrunIgnored.add(b.id)), child: const Text('Laisser')),
                    ]),
                  ]),
                ),
              ],
              _label(pal, 'ENSUITE'),
              _box(_ensuite(pal, items)),
              const SizedBox(height: 8),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        ..._buttons(pal, i),
      ]),
    );
  }

  /// « étape 2 sur 4 · chrono sur Formation IA » sous le titre.
  String? _subLine(ChainItem i, bool onBlock) {
    final chrono = onBlock ? logic.runningActivity()?.name : null;
    final parts = <String>[
      if (i.kind == ChainKind.step) 'étape ${i.index} sur ${i.total}',
      if (i.kind == ChainKind.step && i.action!.estimatedMin != null) 'action ≈ ${fmtMin(i.action!.estimatedMin!)}',
      if (chrono != null) 'chrono sur $chrono',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _stepLine(NowPalette pal, ChecklistItem st, {required bool current}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: st.done ? kChainAccent : null,
              border: Border.all(color: st.done || current ? kChainAccent : _cLine, width: 2),
            ),
            child: st.done ? const Icon(Icons.check, size: 12, color: kChainInk) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(st.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: current ? FontWeight.w800 : FontWeight.w500,
                  color: st.done ? pal.text3 : pal.text,
                  decoration: st.done ? TextDecoration.lineThrough : null,
                )),
          ),
        ]),
      );

  List<Widget> _buttons(NowPalette pal, ChainItem i) {
    switch (i.kind) {
      case ChainKind.step:
        return [
          _primary(i.index == i.total ? 'Dernière étape faite' : 'Étape faite', () => _done(i)),
          const SizedBox(height: 8),
          Row(children: [
            _secondary('Plus tard', () => _later(i)),
            const SizedBox(width: 8),
            _chronoButton(i),
          ]),
        ];
      case ChainKind.action:
        return [
          _primary('Action faite', () => _done(i)),
          const SizedBox(height: 8),
          Row(children: [
            _secondary('Plus tard', () => _later(i)),
            const SizedBox(width: 8),
            _chronoButton(i),
          ]),
        ];
      case ChainKind.routine:
        final r = routinesForToday([i.activity!], logic.state.habitHits, DateTime.now(), dayStartMin: logic.dayStartMin).firstOrNull;
        final count = r == null ? 0 : (r.dayTarget != null ? r.dayDone : r.weekDone);
        final target = r == null ? 0 : (r.dayTarget ?? r.weekTarget);
        final reached = r?.reached ?? false;
        return [
          if (reached)
            _primary('Cible atteinte · suivante', () => _done(i), color: kRoutineAccent)
          else if (count > 0)
            _primary('Garder $count / $target · suivante', () => _done(i),
                icon: Icons.arrow_forward_rounded, color: kRoutineAccent.withOpacity(.55))
          else
            SizedBox(
              height: 56,
              child: OutlinedButton(
                onPressed: null,
                child: Text('Suivante', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white.withOpacity(.22))),
              ),
            ),
          const SizedBox(height: 8),
          Row(children: [
            _secondary('Pas maintenant', () => _later(i)),
            const SizedBox(width: 8),
            _secondary('Pas aujourd\'hui', () => _dismiss(i)),
          ]),
        ];
      case ChainKind.session:
        return [
          if (widget.onOpenSource != null)
            _primary('Ouvrir la séance', () => widget.onOpenSource!(i.block), icon: Icons.play_arrow_rounded),
          const SizedBox(height: 8),
          Row(children: [
            _secondary('Plus tard', () => _later(i)),
            const SizedBox(width: 8),
            _secondary('Séance terminée', () => _done(i)),
          ]),
        ];
      case ChainKind.block:
        return [
          _primary('Fait', () => _done(i)),
          const SizedBox(height: 8),
          Row(children: [
            _secondary('Plus tard', () => _later(i)),
            const SizedBox(width: 8),
            if (i.timed) _chronoButton(i)
            else _secondary('Passer', () => _dismiss(i)),
          ]),
        ];
    }
  }

  Widget _transition(NowPalette pal, ScheduleBlock finished, ChainItem? next, List<ChainItem> items) {
    final nowMin = _nowMin;
    final nb = next?.block;
    final startsIn = nb == null ? 0 : blockStartMin(nb) - nowMin;
    Widget stat(String big, String small) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(color: _cCard, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text(big, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()])),
              Text(small, style: TextStyle(fontSize: 11.5, color: pal.text3)),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(pal),
        _track(items),
        RunningChronoBar(logic: logic),
        Expanded(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 18),
        Center(
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kChainAccent.withValues(alpha: .13),
              border: Border.all(color: kChainAccent, width: 3),
            ),
            child: const Icon(Icons.check_rounded, size: 38, color: kChainAccent),
          ),
        ),
        const SizedBox(height: 12),
        Text('Bloc fait', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: pal.text)),
        const SizedBox(height: 2),
        Text(finished.title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: pal.text2)),
        const SizedBox(height: 14),
        Row(children: [
          stat(_betweenMin > 0 ? fmtMin(_betweenMin) : '—', 'tenues'),
          const SizedBox(width: 6),
          stat('$_doneCount', _doneCount > 1 ? 'faites' : 'faite'),
          const SizedBox(width: 6),
          stat('${items.length}', 'à suivre'),
        ]),
        const SizedBox(height: 14),
        ChipRow(
          question: 'C\u2019était ?',
          labels: kEffortLabels,
          value: effortOfBlock(logic.state.moodMarks, finished.id)?.value ?? -1,
          onPick: (v) => setState(() => logic.logMood(kMoodEffort, v, block: finished)),
          text: pal.text,
          text2: pal.text2,
          text3: pal.text3,
          surface: pal.surface,
          raised: pal.track,
          accent: pal.primary,
        ),
        const SizedBox(height: 10),
        if (nb != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _cCard2, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(startsIn > 1 ? 'BLOC SUIVANT · DANS ${fmtMin(startsIn).toUpperCase()}' : 'BLOC SUIVANT',
                  style: const TextStyle(fontSize: 11, letterSpacing: 1.3, fontWeight: FontWeight.w800, color: kChainAccent)),
              const SizedBox(height: 4),
              Text(nb.title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: pal.text)),
              const SizedBox(height: 2),
              Text(
                '${_clock(blockStartMin(nb))} → ${_clock(blockEndMin(nb))}'
                '${startsIn > 1 ? ' · dans ${fmtMin(startsIn)}' : startsIn < -1 ? ' · a commencé' : ''}',
                style: TextStyle(fontSize: 12.5, color: pal.text3, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ]),
          )
        else
          Text('C\'était le dernier bloc de la file.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: pal.text3)),
        if (nb != null && elanPromptDue(logic.state.moodMarks, livedProgramYmd(DateTime.now(), logic.dayStartMin), elanBucket(_nowMin), logic.elanSkipped, allMoments: logic.elanPromptsAll))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ElanRow(
              value: 0,
              question: 'Ton élan pour la suite ?',
              onPick: (v) => setState(() => logic.logMood(kMoodElan, v, moment: elanBucket(_nowMin), block: nb)),
              onSkip: () => setState(() => logic.elanSkipped.add('${livedProgramYmd(DateTime.now(), logic.dayStartMin)}:${elanBucket(_nowMin)}')),
              text: pal.text,
              text2: pal.text2,
              text3: pal.text3,
              surface: pal.surface,
              raised: pal.track,
            ),
          ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        if (nb != null) ...[
          if (_waitUntil case final w?)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Reprise à ${_clock(w.hour * 60 + w.minute)} · dans ${fmtMin(w.difference(DateTime.now()).inMinutes + 1)}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.text3, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          _primary(startsIn > 1 || _waitUntil != null ? 'Commencer maintenant' : 'Commencer', _startNext,
              icon: Icons.play_arrow_rounded),
          const SizedBox(height: 8),
          Row(children: [
            if (_waitUntil != null)
              _secondary('Annuler l\'attente', () => setState(() => _waitUntil = null))
            else ...[
              _secondary('Souffler 5 min', () => _waitFor(DateTime.now().add(const Duration(minutes: 5)))),
              if (startsIn > 5) ...[
                const SizedBox(width: 8),
                _secondary('Attendre ${_clock(blockStartMin(nb))}', () {
                  final n = DateTime.now();
                  final s = blockStartMin(nb);
                  _waitFor(DateTime(n.year, n.month, n.day, s ~/ 60, s % 60));
                }),
              ],
            ],
          ]),
          TextButton(
            onPressed: () => setState(() {
              _exited = true;
              _summary = true;
            }),
            child: Text('Terminer l’enchaînement', style: TextStyle(fontSize: 13.5, color: pal.text3)),
          ),
        ] else
          _primary('Terminer', () => setState(() => _summary = true), icon: Icons.flag_rounded),
      ]),
    );
  }

  /// Écrit la session une fois le récap atteint : menée au bout si la file
  /// s'est vidée (pas « Sortir »), « plein jour » si elle va du premier au
  /// dernier bloc du programme (blocs à faire ou faits, miroirs compris).
  void _recordRun() {
    if (_recorded || !mounted || widget.objective != null) return;
    _recorded = true;
    final program = _blocks
        .where((b) => (b.status == 'pending' || b.status == 'done') && b.kind == 'normal')
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final run = ChainRun(
      id: _runId,
      date: widget.date,
      startedAt: _startedAt,
      endedAt: DateTime.now(),
      doneCount: _doneCount,
      total: _totalAtStart,
      completed: !_exited,
      firstBlockId: _firstBlockId,
      lastBlockId: _lastBlockId,
      programFirstBlockId: program.firstOrNull?.id,
      programLastBlockId: program.lastOrNull?.id,
    );
    _runId = run.id;
    logic.recordChainRun(run);
    widget.sync.saveChainRun(run);
    if (!_exited) _closeSession();
  }

  Widget? _modeRecap() {
    var low = 0, high = 0;
    for (final t in _doneAts) {
      final m = modeAt(logic.state.moodMarks, t, logic.dayStartMin);
      if (m == DayMode.low) low++;
      if (m == DayMode.high) high++;
    }
    if (low == 0 && high == 0) return null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget chip(int n, DayMode m, String label) {
      final c = modeChipColor(m, dark: dark);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: .16), borderRadius: BorderRadius.circular(999)),
        child: Text('$n $label', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
      );
    }
    return Wrap(spacing: 6, children: [
      if (low > 0) chip(low, DayMode.low, 'malgré tout'),
      if (high > 0) chip(high, DayMode.high, 'à fond'),
    ]);
  }

  String _mmss(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
