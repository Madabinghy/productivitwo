import 'package:productivitwo_v1/widgets/mode_glyph.dart' show ModeGlyph;
import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/coup_alarm.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart' show nextChecklistItem, setActionDone, setChecklistItem;
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/game_rules.dart' show kRuleOffensive;
import 'package:productivitwo_v1/utils/landing.dart';
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate, livedNowMin;
import 'package:productivitwo_v1/utils/today_logic.dart' show blockEndMin, blockStartMin;
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show routinePlus, routineTodayCount;
import 'package:productivitwo_v1/utils/offensive.dart';
import 'package:productivitwo_v1/utils/progress_bricks.dart' show projectBricks;
import 'package:productivitwo_v1/utils/run_session.dart';
import 'package:productivitwo_v1/run_session_store.dart' show RunSessionStore, dropShortSession;
import 'package:productivitwo_v1/widgets/coup_activity_sheet.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/widgets/progress_bricks.dart' show ProgressBricks;

/// Écran Offensive (maquette validée 2026-10-30) : durée d'un coup (10 / 15
/// min) et front (un projet ou « tout mélanger »), puis les actions l'une
/// après l'autre, étape en avant, minuteur du coup ; « Étape faite » · « Action
/// faite » · « +N min » · « Pas ça ». Un coup est gagné au bout du minuteur.
/// Point d'étape tous les 3 coups (à fond · je ralentis = 10 min · c'est bon),
/// bilan : ce qui a avancé par projet (briques, retard sur le plan avant →
/// après), badge, « Caser la suite demain ». File : [buildOffensiveQueue].
const kOffensiveAccent = Color(0xFFFF9B6E);
const kOffensiveInk = Color(0xFF1F0E06);
const _bg = Color(0xFF130C08);
const _card = Color(0xFF1F130C);
const _track = Color(0xFF3A2418);
const _text2 = Color(0xFFD4C4BA);
const _text3 = Color(0xFFB8A69A);
const _sky = Color(0xFF7CC7FF);
const _amber = Color(0xFFF2C14E);

/// [resume] = une offensive en attente (quittée en route) : elle reprend au coup suivant.
/// [projectId] = front déjà choisi (fiche projet, page focus) ; [firstActionId] = l'action par laquelle commencer.
/// [activityId] = Deep work visé sur une activité : seuls les projets qui la servent sont proposés (tous si aucun).
Future<void> showOffensiveScreen(BuildContext context, AppLogic logic, {PendingRun? resume, String? projectId, String? firstActionId, String? activityId}) {
  return Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => OffensiveScreen(logic: logic, resume: resume, projectId: projectId, firstActionId: firstActionId, activityId: activityId)));
}

enum _Phase { setup, coup, pause, back, end }

class OffensiveScreen extends StatefulWidget {
  final AppLogic logic;
  final PendingRun? resume;
  final String? projectId;
  final String? firstActionId;
  final String? activityId;
  const OffensiveScreen({super.key, required this.logic, this.resume, this.projectId, this.firstActionId, this.activityId});

  @override
  State<OffensiveScreen> createState() => _OffensiveScreenState();
}

class _OffensiveScreenState extends State<OffensiveScreen> {
  late final List<OffensiveFront> _fronts;
  _Phase _phase = _Phase.setup;
  int _duration = 15;
  String? _front; // null = tout mélanger
  List<OffensiveTarget> _queue = const [];
  int _index = 0;
  int _won = 0;
  int _remaining = 15 * 60;
  DateTime? _endsAt;
  Timer? _timer;
  DateTime? _startedAt;
  bool _ownChrono = false;
  DateTime? _chronoFrom;
  int _chronoSec = 0;
  bool _saved = false;
  /// Retour après être resté plongé dans le coup, app fermée : ce qui a été compté pendant l'absence.
  String? _awayNote;
  /// Prochain rendez-vous daté (agenda, séance) : ligne « Ensuite » et alarme d'atterrissage.
  FixedAhead? _ahead;
  late final Set<String> _sessionTasks = sessionTaskIdsOf(logic.currentProjects);
  String? _armedFor;
  String? _landedFor;
  /// « Je finis ce coup, puis j'y vais » : l'offensive s'arrête au bout du coup.
  bool _leaveAfterCoup = false;
  /// Bloc Deep work dans lequel tourne l'offensive, et la fin déjà demandée (« On continue ? » une fois par fin).
  String? _deepId;
  String? _deepAsked;
  bool _sheetOpen = false;
  /// Reprise après être resté dedans : ce qui est passé sans toi, à régler avant de replonger.
  List<ScheduleBlock> _missed = const [];
  List<SeriesAtRisk> _backRisk = const [];
  final _handled = <String, String>{};
  DateTime? _resumeEndsAt;
  /// Point d'étape : « Je souffle 3 min » a arrêté le chrono.
  bool _breathing = false;
  final _passed = <String>{};
  final _asked = <String>{}; // actions sans activité déjà questionnées
  final _actionsDone = <String, List<String>>{}; // projet → titres
  final _stepsDone = <String, int>{}; // action → étapes cochées
  final _before = <String, ({int done, int total, int behind})>{};
  late final String _runId = widget.resume?.runId ?? ChainRun(date: '', startedAt: DateTime(0), endedAt: DateTime(0), doneCount: 0, total: 0, completed: false).id;

  AppLogic get logic => widget.logic;
  OffensiveTarget? get _cur => _index < _queue.length ? _queue[_index] : null;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
    final fronts = frontsForActivity(offensiveFronts(logic.currentProjects, DateTime.now()), widget.activityId);
    // Front déjà choisi (fiche projet, page focus) : en tête de liste, sélectionné.
    final pre = fronts.indexWhere((f) => f.project.id == widget.projectId);
    _fronts = pre > 0 ? [fronts[pre], ...fronts.sublist(0, pre), ...fronts.sublist(pre + 1)] : fronts;
    if (_fronts.isNotEmpty) _front = _fronts.first.project.id;
    final r = widget.resume;
    if (r != null) _restore(r);
  }

  void _restore(PendingRun r) {
    final front = r.extra['front']?.toString();
    _front = front == null || front.isEmpty ? null : front;
    _duration = r.intOf('duration') ?? 15;
    _won = r.done;
    _chronoSec = r.intOf('chronoSec') ?? 0;
    _startedAt = r.startedAt;
    _passed.addAll(r.strings('passed'));
    for (final e in r.strings('actionsDone')) {
      final i = e.indexOf('|');
      if (i > 0) _actionsDone.putIfAbsent(e.substring(0, i), () => []).add(e.substring(i + 1));
    }
    final before = r.extra['before'];
    if (before is Map) {
      for (final e in before.entries) {
        final v = e.value;
        if (v is List && v.length == 3) {
          _before[e.key.toString()] = (done: (v[0] as num).toInt(), total: (v[1] as num).toInt(), behind: (v[2] as num).toInt());
        }
      }
    }
    // Resté plongé dans le coup, app fermée (retour user 2026-11-03) : si le chrono du coup tourne encore, l'offensive
    // reprend là où elle en est, le chrono continue et les coups passés pendant l'absence comptent.
    final cur = r.extra['cur']?.toString();
    final ends = r.intOf('endsAt');
    final open = logic.state.sessions.where((x) => !x.deleted && x.endAt == null && !x.startAt.isBefore(r.startedAt)).firstOrNull;
    final keep = cur != null && ends != null && open != null && open.actionId == cur;
    if (open != null && !keep) logic.stopActive(notify: false);
    _queue = _previewQueue();
    final ki = keep ? _queue.indexWhere((t) => t.action.id == cur) : -1;
    if (keep && ki >= 0) {
      _index = ki;
      _ownChrono = true;
      _chronoSec = r.intOf('chronoBase') ?? _chronoSec;
      final from = r.intOf('chronoFrom');
      _chronoFrom = from == null ? open.startAt : DateTime.fromMillisecondsSinceEpoch(from);
      final endsAt = DateTime.fromMillisecondsSinceEpoch(ends);
      final now = DateTime.now();
      final extra = overtimeCoups(endsAt, now, _duration);
      _won += extra;
      if (extra > 0) {
        final m = now.difference(open.startAt).inMinutes;
        _awayNote = 'Tu es resté dedans : +$extra coup${extra > 1 ? 's' : ''} compté${extra > 1 ? 's' : ''} · chrono ${m ~/ 60 > 0 ? '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}' : '$m min'} sur cette action';
      }
      // Resté dedans au-delà du coup : d'abord ce qui est passé sans toi (« Plongé, pas perdu », lot 4).
      _missed = extra > 0 ? missedWhileAway(logic.todayBlocks, endsAt, now, logic.dayStartMin) : const [];
      _backRisk = extra > 0 ? _atRisk() : const [];
      _resumeEndsAt = extra > 0 ? null : endsAt;
      if (_missed.isNotEmpty || _backRisk.isNotEmpty) {
        _phase = _Phase.back;
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startCoup(endsAt: _resumeEndsAt);
      });
      return;
    }
    final i = _queue.indexWhere((t) => !_passed.contains(t.action.id) && !t.action.done);
    if (i < 0) {
      _phase = _Phase.end;
      return;
    }
    _index = i;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startCoup();
    });
  }

  /// Le projet choisi comme front, quand aucune de ses actions prêtes n'a
  /// d'activité où compter le temps.
  Project? _unlinkedFront() {
    if (_front == null) return null;
    final q = _previewQueue();
    if (q.isEmpty || q.any((t) => t.chronoActivityId != null)) return null;
    return q.first.project;
  }

  /// Le chrono lancé à la main avant l'offensive (il s'arrête au lancement).
  Session? get _runningBefore => logic.state.sessions.where((x) => x.endAt == null).firstOrNull;

  void _saveSession() {
    if (_startedAt == null) return;
    final now = DateTime.now();
    RunSessionStore.save(PendingRun(
      kind: kOffensiveKind,
      runId: _runId,
      date: ymdOf(livedDate(now, logic.dayStartMin)),
      startedAt: _startedAt!,
      // Un coup en cours garde la session vivante jusqu'à sa fin (puis la fenêtre habituelle).
      lastActiveAt: _phase == _Phase.coup && _endsAt != null && _endsAt!.isAfter(now) ? _endsAt! : now,
      done: _won,
      extra: {
        'front': _front ?? '',
        'duration': _duration,
        'chronoSec': _chronoSec + (_chronoFrom == null ? 0 : now.difference(_chronoFrom!).inSeconds),
        'chronoBase': _chronoSec,
        if (_chronoFrom case final f?) 'chronoFrom': f.millisecondsSinceEpoch,
        if ((_phase == _Phase.coup || _phase == _Phase.pause) && _cur != null) 'cur': _cur!.action.id,
        if ((_phase == _Phase.coup || _phase == _Phase.pause) && _endsAt != null) 'endsAt': _endsAt!.millisecondsSinceEpoch,
        'own': _ownChrono,
        'passed': _passed.toList(),
        'actionsDone': [for (final e in _actionsDone.entries) for (final t in e.value) '${e.key}|$t'],
        'total': _actionsDone.values.fold(0, (s, l) => s + l.length),
        'before': {for (final e in _before.entries) e.key: [e.value.done, e.value.total, e.value.behind]},
      },
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_phase != _Phase.pause) CoupAlarm.cancel();
    if (_phase == _Phase.end) CoupAlarm.cancelLanding();
    _stopOwnChrono();
    // Quittée en route : l'offensive reste en attente (reprenable) ; au bilan, elle se clôt.
    if (!_saved && _phase == _Phase.end) {
      if (_won > 0) _save();
      RunSessionStore.clear();
    }
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  // ── Mécanique ────────────────────────────────────────────────────────────

  List<OffensiveTarget> _previewQueue() => buildOffensiveQueue(logic.currentProjects, DateTime.now(), projectId: _front);

  void _launch() {
    final now = DateTime.now();
    _queue = _previewQueue();
    final first = widget.firstActionId;
    if (first != null) {
      final i = _queue.indexWhere((t) => t.action.id == first);
      if (i > 0) _queue = [_queue[i], ..._queue.sublist(0, i), ..._queue.sublist(i + 1)];
    }
    if (_queue.isEmpty) return;
    if (_runningBefore != null) logic.stopActive(notify: false);
    _startedAt = now;
    for (final t in _queue) {
      _before.putIfAbsent(t.project.id, () => planSnapshot(t.project, now));
    }
    _index = 0;
    _startCoup();
  }

  void _startCoup({DateTime? endsAt}) {
    _endsAt = endsAt ?? DateTime.now().add(Duration(minutes: _duration));
    _remaining = _endsAt!.difference(DateTime.now()).inSeconds.clamp(0, 1 << 30);
    if (endsAt != null) CoupAlarm.cancel(all: false);
    _phase = _Phase.coup;
    _startChrono();
    _armAlarm();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = _endsAt!.difference(DateTime.now()).inSeconds;
      _refreshAhead();
      if (left > 0) {
        setState(() => _remaining = left);
      } else {
        _coupWon();
      }
    });
    _refreshAhead();
    _saveSession();
    setState(() {});
  }

  String _keyOf(FixedAhead a) => '${a.block.id}@${a.block.startTime}';

  /// Ligne « Ensuite » + alarme d'atterrissage (une seule par rendez-vous) +
  /// feuille « Atterrissage » quand on entre dans les 10 dernières minutes.
  void _refreshAhead() {
    final now = DateTime.now();
    _checkDeepEnd(now);
    final a = nextFixed(logic.todayBlocks, now, logic.dayStartMin, sessionTaskIds: _sessionTasks);
    _ahead = a;
    if (a == null) {
      if (_armedFor != null) CoupAlarm.cancelLanding();
      _armedFor = null;
      return;
    }
    final key = _keyOf(a);
    if (_armedFor != key && a.landingAt.isAfter(now)) {
      _armedFor = key;
      CoupAlarm.scheduleLanding(logic, at: a.landingAt, title: '🔔 ${a.block.title} dans $kLandingLeadMin min', body: 'À ${a.block.startTime} · finis ton coup, prépare-toi.');
    }
    if (_phase == _Phase.coup && !_sheetOpen && !now.isBefore(a.landingAt) && _landedFor != key) {
      _landedFor = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showLanding(a);
      });
    }
  }

  /// Fin du bloc Deep work pendant un coup : « Tu es lancé. On continue ? » (une fois par fin de bloc).
  void _checkDeepEnd(DateTime now) {
    if (_phase != _Phase.coup) return;
    final blocks = logic.todayBlocks;
    _deepId ??= currentDeepBlock(blocks, now, logic.dayStartMin)?.id;
    final deep = _deepId == null ? null : blocks.where((b) => b.id == _deepId).firstOrNull;
    if (deep == null || deep.status != 'pending' || _sheetOpen) return;
    final end = blockEndMin(deep);
    if (livedNowMin(now, logic.dayStartMin) < end) return;
    final key = '${deep.id}@$end';
    if (_deepAsked == key) return;
    _deepAsked = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showDeepEnd(deep);
    });
  }

  Future<void> _showDeepEnd(ScheduleBlock deep) async {
    final blocks = logic.todayBlocks;
    final room = continueRoom(blocks, deep, sessionTaskIds: _sessionTasks);
    final soft = softFollowing(blocks, deep, sessionTaskIds: _sessionTasks);
    final fixed = nextFixed(blocks, DateTime.now(), logic.dayStartMin, sessionTaskIds: _sessionTasks);
    _sheetOpen = true;
    final choice = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF221A10),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('TON BLOC DEEP WORK SE TERMINE · ${hmOf(blockEndMin(deep))}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .8, color: _text3)),
            const SizedBox(height: 6),
            const Text('Tu es lancé. On continue ?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
            _label(fixed == null ? 'PLUS RIEN DE DATÉ AUJOURD’HUI' : 'RIEN DE DATÉ AVANT ${fixed.block.startTime}'),
            for (final b in soft.take(3))
              _li(b.startTime, b.title, room > 0 ? 'passerait à ${hmOf(blockStartMin(b) + room)}' : null, _pill('souple', _text3)),
            if (fixed != null) _li(fixed.block.startTime, fixed.block.title, 'ne bouge pas', _pill('daté', _sky)),
            const SizedBox(height: 12),
            if (room > 0) ...[
              _primary('Continuer $room min · la suite se décale', () => Navigator.pop(ctx, true)),
              const SizedBox(height: 10),
            ],
            _outline('Passer à la suite', () => Navigator.pop(ctx, false), strong: room == 0),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Laisser tourner sans rien changer', style: TextStyle(color: _text3))),
          ]),
        ),
      ),
    );
    _sheetOpen = false;
    if (!mounted || choice == null) return;
    if (!choice) return _end();
    final changed = extendDeep(blocks, deep, room, sessionTaskIds: _sessionTasks);
    for (final c in changed) {
      logic.sync?.upsertScheduleBlock(c.docDate ?? logic.livedTodayYmd, c, rememberMirror: false);
    }
    final moved = changed.length - 1;
    ScaffoldMessenger.maybeOf(context)?.showClosingSnackBar(SnackBar(
        content: Text('Deep work jusqu’à ${hmOf(blockEndMin(deep))}${moved > 0 ? ' · $moved bloc${moved > 1 ? 's' : ''} décalé${moved > 1 ? 's' : ''}' : ''}')));
  }

  Future<void> _showLanding(FixedAhead a) async {
    _sheetOpen = true;
    final leftMin = (_remaining / 60).ceil();
    final choice = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF221A10),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('🔔 ATTERRISSAGE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .8, color: _amber)),
            const SizedBox(height: 6),
            Text('${a.block.title} ${inLabel(a.inMin)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 6),
            Text('À ${a.block.startTime}. Il te reste $leftMin min sur ce coup.', style: const TextStyle(fontSize: 14, color: _text2)),
            const SizedBox(height: 16),
            _primary('Je finis ce coup, puis j’y vais', () => Navigator.pop(ctx, true)),
            const SizedBox(height: 10),
            _outline('J’arrête maintenant', () => Navigator.pop(ctx, false)),
          ]),
        ),
      ),
    );
    _sheetOpen = false;
    if (!mounted || choice == null) return;
    if (choice) {
      setState(() => _leaveAfterCoup = true);
    } else {
      _end();
    }
  }

  /// Alarme de fin du coup (le minuteur se lit sur l'heure de fin : il continue en veille).
  void _armAlarm() {
    final t = _cur;
    CoupAlarm.schedule(logic,
        endsAt: _endsAt!,
        title: '🎯 Coup gagné',
        body: '$_duration min${t == null ? '' : ' sur ${t.action.title}'}${offensivePauseDue(_won + 1) ? ' · point d’étape' : ' · le suivant démarre'}');
  }

  void _moreTime() {
    _endsAt = _endsAt!.add(Duration(minutes: _duration));
    CoupAlarm.cancel(all: false);
    _armAlarm();
    setState(() => _remaining = _endsAt!.difference(DateTime.now()).inSeconds);
    _saveSession();
  }

  void _coupWon() {
    _timer?.cancel();
    _won++;
    _saveSession();
    if (_leaveAfterCoup) {
      _end();
      return;
    }
    if (offensivePauseDue(_won)) {
      // Le point d'étape n'arrête plus le chrono (« Plongé, pas perdu », lot 2) : on lève la tête, on replonge.
      _breathing = false;
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
      setState(() => _phase = _Phase.pause);
    } else {
      _startCoup();
    }
  }

  void _startChrono() {
    final t = _cur;
    if (t == null) return;
    final act = t.chronoActivityId;
    if (act == null) {
      // Le chrono de l'action précédente ne doit pas compter pour celle-ci.
      _stopOwnChrono();
      if (_asked.add(t.action.id)) _askActivity(t);
      return;
    }
    final running = logic.state.sessions.where((s) => s.endAt == null).firstOrNull;
    if (running != null && !_ownChrono) return; // un chrono à toi tourne : on n'y touche pas
    if (running != null && running.actionId == t.action.id) return;
    _stopOwnChrono();
    logic.start(act, taskId: t.task.id, actionId: t.action.id);
    _ownChrono = true;
    _chronoFrom = DateTime.now();
  }

  /// Action sans activité : « Où compter ce temps ? » (une fois par action),
  /// puis le chrono part sur l'activité choisie.
  Future<void> _askActivity(OffensiveTarget t) async {
    final id = await askCoupActivity(context, logic, project: t.project, action: t.action);
    if (!mounted || id == null || _cur != t || _phase != _Phase.coup) return;
    _startChrono();
    setState(() {});
  }

  void _stopOwnChrono() {
    if (!_ownChrono) return;
    _ownChrono = false;
    if (_chronoFrom != null) _chronoSec += DateTime.now().difference(_chronoFrom!).inSeconds;
    _chronoFrom = null;
    dropShortSession(logic, logic.stopActive(notify: false));
  }

  /// Action suivante de la file (même coup, le minuteur continue).
  void _advance() {
    var i = _index + 1;
    while (i < _queue.length && (_passed.contains(_queue[i].action.id) || _queue[i].action.done)) {
      i++;
    }
    if (i >= _queue.length) {
      _end(lastCoupWon: _remaining <= 60);
      return;
    }
    setState(() => _index = i);
    _startChrono();
    _saveSession();
  }

  void _persist(OffensiveTarget t) => logic.sync?.patchActionOf(t.project, t.action);

  void _stepDone() {
    final t = _cur;
    if (t == null) return;
    final step = nextChecklistItem(t.action);
    if (step == null) return _actionDone();
    setChecklistItem(t.action, step.id, true);
    _stepsDone[t.action.id] = (_stepsDone[t.action.id] ?? 0) + 1;
    _persist(t);
    if (t.action.done) {
      _actionsDone.putIfAbsent(t.project.id, () => []).add(t.action.title);
      _advance();
    } else {
      setState(() {});
    }
  }

  void _actionDone() {
    final t = _cur;
    if (t == null) return;
    setActionDone(t.action, true);
    _persist(t);
    _actionsDone.putIfAbsent(t.project.id, () => []).add(t.action.title);
    _advance();
  }

  void _skip() {
    final t = _cur;
    if (t == null) return;
    _passed.add(t.action.id);
    _advance();
  }

  void _end({bool lastCoupWon = false}) {
    _timer?.cancel();
    CoupAlarm.cancel();
    CoupAlarm.cancelLanding();
    if (lastCoupWon) _won++;
    _stopOwnChrono();
    setState(() => _phase = _Phase.end);
  }

  void _save() {
    _saved = true;
    final now = DateTime.now();
    final run = ChainRun(
      id: _runId,
      date: ymdOf(livedDate(now, logic.dayStartMin)),
      startedAt: _startedAt ?? now,
      endedAt: now,
      doneCount: _won,
      total: _actionsDone.values.fold(0, (s, l) => s + l.length),
      completed: _cur == null,
      kind: kOffensiveKind,
    );
    logic.recordChainRun(run);
    logic.sync?.saveChainRun(run);
  }

  void _finish() {
    if (_won > 0) _save();
    _saved = true;
    RunSessionStore.clear();
    Navigator.of(context).pop();
  }

  void _carryTomorrow() {
    final t = _cur;
    if (t != null && !t.action.done) {
      final n = DateTime.now();
      t.action.focusDate = DateTime(n.year, n.month, n.day + 1);
      _persist(t);
      ScaffoldMessenger.maybeOf(context)?.showClosingSnackBar(SnackBar(content: Text('« ${t.action.title} » visée demain')));
    }
    _finish();
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
            child: switch (_phase) {
              _Phase.setup => _setup(),
              _Phase.coup => _coup(),
              _Phase.pause => _pause(),
              _Phase.back => _back(),
              _Phase.end => _endView(),
            },
          ),
        ),
      ),
    );
  }

  Widget _header(String title, {Widget? trailing}) => SizedBox(
        height: 48,
        // Le titre et son ⓘ prennent toute la place restante : le bouton de droite
        // reste collé au bord (un Flexible + un Spacer se partageaient la largeur).
        child: Row(children: [
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1, color: kOffensiveAccent)),
              ),
              const InfoDot(kRuleOffensive),
            ]),
          ),
          if (trailing != null) trailing,
        ]),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8, color: _text3)),
      );

  Widget _primary(String label, VoidCallback? onTap, {double height = 56}) => SizedBox(
        height: height,
        width: double.infinity,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: kOffensiveAccent,
            foregroundColor: kOffensiveInk,
            disabledBackgroundColor: kOffensiveAccent.withValues(alpha: .25),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _outline(String label, VoidCallback onTap, {bool strong = false, bool left = false}) => SizedBox(
        height: left ? 56 : 48,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            alignment: left ? Alignment.centerLeft : Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: left ? 16 : 6),
            backgroundColor: strong ? kOffensiveAccent.withValues(alpha: .12) : null,
            foregroundColor: strong ? kOffensiveAccent : Colors.white,
            side: BorderSide(color: strong ? kOffensiveAccent.withValues(alpha: .55) : Colors.white.withValues(alpha: .16)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(label, style: TextStyle(fontSize: left ? 16 : 13.5, fontWeight: strong ? FontWeight.w700 : FontWeight.w600)),
        ),
      );

  Widget _choice({required bool selected, required VoidCallback onTap, required Widget child}) => Material(
        color: selected ? kOffensiveAccent.withValues(alpha: .10) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? kOffensiveAccent : Colors.white.withValues(alpha: .14), width: selected ? 2 : 1),
            ),
            child: child,
          ),
        ),
      );

  Widget _setup() {
    final preview = _previewQueue();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header('OFFENSIVE', trailing: IconButton(tooltip: 'Fermer', icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop())),
      Expanded(
        child: ListView(children: [
          const SizedBox(height: 6),
          const Text('En forme : on avance à fond', style: TextStyle(fontSize: 28, height: 1.15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Des coups de 10, 15 ou 25 min sur tes vraies actions de projet, l’une après l’autre. Tu choisis le front, l’app enchaîne.',
              style: TextStyle(fontSize: 14.5, height: 1.4, color: _text2)),
          _label('DURÉE D’UN COUP'),
          Row(children: [
            for (final d in kOffensiveDurations) ...[
              if (d != kOffensiveDurations.first) const SizedBox(width: 8),
              Expanded(
                child: _choice(
                  selected: _duration == d,
                  onTap: () => setState(() => _duration = d),
                  child: Center(child: Text('$d min', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _duration == d ? kOffensiveAccent : Colors.white))),
                ),
              ),
            ],
          ]),
          _label('LE FRONT'),
          if (_fronts.isEmpty)
            const Text('Aucune action de projet prête aujourd’hui.', style: TextStyle(fontSize: 13.5, color: _text2)),
          for (final f in _fronts.take(4)) ...[
            _choice(
              selected: _front == f.project.id,
              onTap: () => setState(() => _front = f.project.id),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f.project.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(frontLine(f), style: const TextStyle(fontSize: 12, color: _text2)),
              ]),
            ),
            const SizedBox(height: 6),
          ],
          if (_fronts.length > 1)
            _choice(
              selected: _front == null,
              onTap: () => setState(() => _front = null),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Tout mélanger', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Text('la prochaine action de chaque projet, la plus en retard d’abord', style: TextStyle(fontSize: 12, color: _text2)),
              ]),
            ),
        ]),
      ),
      if (_unlinkedFront() case final p?) ...[
        const SizedBox(height: 10),
        Material(
          color: kOffensiveAccent.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              await linkProjectActivity(context, logic, p);
              if (mounted) setState(() {});
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                const Icon(Icons.link, size: 18, color: kOffensiveAccent),
                const SizedBox(width: 8),
                const Expanded(child: Text('Le temps de ce projet ne compte nulle part', style: TextStyle(fontSize: 13, color: _text2))),
                Text('Lier une activité', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kOffensiveAccent.withValues(alpha: .95))),
              ]),
            ),
          ),
        ),
      ],
      if (_runningBefore case final r?) ...[
        const SizedBox(height: 10),
        Text('Le chrono « ${logic.state.activities.where((a) => a.id == r.activityId).firstOrNull?.name ?? 'en cours'} » s’arrête au lancement : l’offensive prend la main.',
            style: const TextStyle(fontSize: 13, height: 1.4, color: kOffensiveAccent)),
      ],
      const SizedBox(height: 12),
      _primary(preview.isEmpty ? 'Rien à attaquer' : 'Lancer l’offensive · ${preview.length} action${preview.length > 1 ? 's' : ''}', preview.isEmpty ? null : _launch),
    ]);
  }

  int _elapsedMin() => _startedAt == null ? 0 : DateTime.now().difference(_startedAt!).inMinutes;

  Widget _progress() => Row(children: [
        Expanded(
          child: Row(children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: i < _won % kOffensivePauseEvery ? kOffensiveAccent : (i == _won % kOffensivePauseEvery ? null : _track),
                    borderRadius: BorderRadius.circular(4),
                    border: i == _won % kOffensivePauseEvery ? Border.all(color: kOffensiveAccent, width: 2) : null,
                  ),
                ),
              ),
            ],
          ]),
        ),
        const SizedBox(width: 10),
        Text('coup ${_won + 1} · ${fmtOffensiveMin(_elapsedMin())}', style: const TextStyle(fontSize: 13, color: _text2, fontFeatures: [FontFeature.tabularFigures()])),
      ]);

  Widget _coup() {
    final t = _cur!;
    final steps = t.action.checklist;
    final step = nextChecklistItem(t.action);
    final stepIdx = step == null ? -1 : steps.indexOf(step);
    final after = stepIdx >= 0 && stepIdx + 1 < steps.length ? steps.skip(stepIdx + 1).where((s) => !s.done).firstOrNull : null;
    final total = _duration * 60;
    final left = _remaining;
    final mm = (left ~/ 60).toString();
    final ss = (left % 60).toString().padLeft(2, '0');
    final front = _front == null ? 'OFFENSIVE' : 'OFFENSIVE · ${t.project.title.toUpperCase()}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(front, trailing: TextButton(onPressed: () => _end(), child: const Text('Je m’arrête', style: TextStyle(color: _text2, fontSize: 14)))),
      const SizedBox(height: 4),
      _progress(),
      if (_ahead case final a?) _aheadLine(a),
      if (_awayNote case final note?)
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(color: kOffensiveAccent.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.local_fire_department_rounded, size: 18, color: kOffensiveAccent),
            const SizedBox(width: 8),
            Expanded(child: Text(note, style: const TextStyle(fontSize: 13, height: 1.3, color: _text2))),
            IconButton(icon: const Icon(Icons.close, size: 16, color: _text3), onPressed: () => setState(() => _awayNote = null)),
          ]),
        ),
      const SizedBox(height: 16),
      Text('${_front == null ? '${t.project.title} › ' : ''}${t.task.title}', style: const TextStyle(fontSize: 12.5, color: _text3)),
      const SizedBox(height: 4),
      Text(t.action.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 27, height: 1.2, fontWeight: FontWeight.w800)),
      const SizedBox(height: 16),
      Row(children: [
        SizedBox(
          width: 128,
          height: 128,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: 1 - left / (total < _remaining ? _remaining : total),
                strokeWidth: 10,
                backgroundColor: _track,
                color: kOffensiveAccent,
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$mm:$ss', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
              Text('reste sur $_duration', style: const TextStyle(fontSize: 11, color: _text3)),
            ]),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (step != null) ...[
              Text('ÉTAPE ${stepIdx + 1} / ${steps.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6, color: _text3)),
              const SizedBox(height: 4),
              Text(step.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, height: 1.25, fontWeight: FontWeight.w700)),
              if (after != null) ...[
                const SizedBox(height: 4),
                Text('Ensuite : ${after.title}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: _text3)),
              ],
            ] else
              const Text('Pas d’étape : tu avances, tu coches quand c’est fait.', style: TextStyle(fontSize: 14, height: 1.35, color: _text2)),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      if (steps.isNotEmpty)
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
            child: ListView(children: [
              for (final s in steps)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: s.done ? kOffensiveAccent : null,
                        border: s.done ? null : Border.all(color: identical(s, step) ? kOffensiveAccent : const Color(0xFF5A4032), width: 2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(s.title,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: identical(s, step) ? FontWeight.w700 : FontWeight.w400,
                              color: s.done ? _text3 : Colors.white,
                              decoration: s.done ? TextDecoration.lineThrough : null)),
                    ),
                  ]),
                ),
            ]),
          ),
        )
      else
        const Spacer(),
      const SizedBox(height: 12),
      _primary(step != null ? 'Étape faite' : 'Action faite', step != null ? _stepDone : _actionDone, height: 58),
      const SizedBox(height: 10),
      Row(children: [
        if (step != null) ...[
          Expanded(child: _outline('Action faite', _actionDone)),
          const SizedBox(width: 8),
        ],
        Expanded(child: _outline('+$_duration min', _moreTime)),
        const SizedBox(width: 8),
        Expanded(child: _outline('Pas ça', _skip)),
      ]),
      const SizedBox(height: 8),
      Text(
        t.chronoActivityId == null
            ? 'Au bout de $_duration:00, le coup est gagné même sans finir.'
            : 'Le chrono tourne sur ${logic.state.activities.where((a) => a.id == t.chronoActivityId).firstOrNull?.name ?? 'l’activité liée'}. Au bout de $_duration:00, le coup est gagné même sans finir.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: _text3),
      ),
    ]);
  }

  /// « Ensuite Cours 6e à 14:00 · dans 1 h 05 » (ambre dans les 10 dernières minutes).
  Widget _aheadLine(FixedAhead a) {
    final hot = a.inMin <= kLandingLeadMin;
    final c = hot ? _amber : _sky;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: hot ? _amber : const Color(0xFF3A2F22))),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Ensuite ', style: TextStyle(color: _text3)),
              TextSpan(text: a.block.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' à ${a.block.startTime}', style: const TextStyle(color: _text3)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
        const SizedBox(width: 8),
        Text(_leaveAfterCoup ? 'fin du coup, puis j’y vais' : inLabel(a.inMin),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c, fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }

  String _gainedLine() {
    final parts = <String>[];
    for (final e in _actionsDone.entries) {
      parts.addAll(e.value.map((x) => '$x ✓'));
    }
    final cur = _cur;
    if (cur != null && !cur.action.done && (_stepsDone[cur.action.id] ?? 0) > 0) {
      final done = cur.action.checklist.where((c) => c.done).length;
      parts.add('${cur.action.title} : $done étape${done > 1 ? 's' : ''} sur ${cur.action.checklist.length}');
    } else if (cur != null && !cur.action.done) {
      parts.add('${cur.action.title} : lancé');
    }
    return parts.isEmpty ? 'Le temps passé compte : les coups sont gagnés.' : parts.join(' · ');
  }

  /// Séries qui se perdent ce soir si rien : routines quotidiennes pas atteintes, série ≥ 2 j jusqu'à hier.
  List<SeriesAtRisk> _atRisk() {
    final today = logic.livedToday;
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final ymd = logic.livedTodayYmd;
    return seriesAtRisk([
      for (final a in logic.state.activeActivities)
        if (a.isHabit && a.habitFreq == HabitFreq.daily && !logic.isAcquired(a.id) && !logic.frozenOf(a.id).contains(ymd))
          SeriesAtRisk(a.name, routineTodayCount(logic, a), logic.dayQuotaFor(a), logic.habitStreakEndingOn(a.id, yesterday), id: a.id),
    ]);
  }

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
        child: Text(t, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
      );

  Widget _li(String left, String title, String? sub, Widget pill) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          SizedBox(width: 46, child: Text(left, style: const TextStyle(fontSize: 13, color: _text3, fontFeatures: [FontFeature.tabularFigures()]))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              if (sub != null) Text(sub, style: const TextStyle(fontSize: 11.5, color: _text3)),
            ]),
          ),
          pill,
        ]),
      );

  Widget _pause() {
    final now = DateTime.now();
    final running = _ownChrono ? logic.state.sessions.where((x) => x.endAt == null).firstOrNull : null;
    final actName = running == null ? null : logic.state.activities.where((a) => a.id == running.activityId).firstOrNull?.name;
    final upcoming = upcomingBlocks(logic.todayBlocks, now, logic.dayStartMin, sessionTaskIds: _sessionTasks);
    final risk = _atRisk();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header('OFFENSIVE · $_won COUPS GAGNÉS', trailing: Text(fmtOffensiveMin(_elapsedMin()), style: const TextStyle(fontSize: 13, color: _text2))),
      Expanded(
        child: ListView(children: [
          const SizedBox(height: 8),
          if (running != null)
            Row(children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF5FE0C8), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Le chrono continue · ${fmtOffensiveMin(now.difference(running.startAt).inMinutes)}${actName == null ? '' : ' sur $actName'}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF5FE0C8))),
              ),
            ])
          else if (_breathing)
            const Text('Chrono en pause · reprends quand tu veux', style: TextStyle(fontSize: 13, color: _text3)),
          const SizedBox(height: 10),
          Text(_breathing ? 'Lève-toi, bois,\nregarde au loin.' : 'Lève la tête\n20 secondes', style: const TextStyle(fontSize: 28, height: 1.15, fontWeight: FontWeight.w800)),
          _label('CE QUI ARRIVE'),
          if (upcoming.isEmpty)
            const Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Plus rien de prévu aujourd’hui.', style: TextStyle(fontSize: 13.5, color: _text2)))
          else
            for (final u in upcoming)
              _li(u.block.startTime, u.block.title, inLabel((u.at.difference(now).inSeconds / 60).ceil()),
                  u.fixed ? _pill('daté', _sky) : _pill('souple', _text3)),
          if (risk.isNotEmpty) ...[
            _label('SE PERD CE SOIR SI RIEN'),
            for (final r in risk) _li('🔥', '${r.name} · série de ${r.streak} j', '${r.count} / ${r.target} aujourd’hui', _pill('ce soir', const Color(0xFFFF6B6B))),
          ],
          _label('DÉJÀ GAGNÉ'),
          Text(_gainedLine(), style: const TextStyle(fontSize: 14, height: 1.5)),
        ]),
      ),
      const SizedBox(height: 10),
      _primary('Je continue', _startCoup),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: _outline(_breathing ? 'Je souffle…' : 'Je souffle 3 min', () {
            if (_breathing) return;
            _stopOwnChrono();
            setState(() => _breathing = true);
          }),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _outline('Coups de 10 min', () {
            _duration = 10;
            _startCoup();
          }),
        ),
        const SizedBox(width: 8),
        Expanded(child: _outline('C’est bon', () => _end())),
      ]),
    ]);
  }

  Future<void> _settleBlock(ScheduleBlock b, String how) async {
    final doc = b.docDate ?? logic.livedTodayYmd;
    final sync = logic.sync;
    setState(() => _handled[b.id] = how);
    if (sync == null) return;
    switch (how) {
      case 'fait':
        await sync.updateBlockStatus(doc, b.id, 'done', manual: true);
      case 'demain':
        await sync.reportBlockToTomorrow(doc, b);
      case 'lâché':
        await sync.setBlockLetGo(doc, b.id, true);
    }
  }

  Widget _mini(String label, VoidCallback onTap) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF5A4032)),
              padding: const EdgeInsets.symmetric(vertical: 6),
              minimumSize: const Size(0, 34),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            ),
            child: Text(label, style: const TextStyle(fontSize: 12.5)),
          ),
        ),
      );

  Widget _backLine(String left, String title, String? done, List<Widget> actions) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 9, 10),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox(width: 46, child: Text(left, style: const TextStyle(fontSize: 13, color: _text3, fontFeatures: [FontFeature.tabularFigures()]))),
            Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            if (done != null) _pill(done, const Color(0xFF5FE0C8)) else _pill('passé', _amber),
          ]),
          if (done == null) ...[
            const SizedBox(height: 8),
            Row(children: actions),
          ],
        ]),
      );

  /// « Pendant que tu étais dedans » : ce qui est passé sans toi, réglé sur place, puis on replonge.
  Widget _back() {
    final now = DateTime.now();
    final running = logic.state.sessions.where((x) => x.endAt == null).firstOrNull;
    final fixed = nextFixed(logic.todayBlocks, now, logic.dayStartMin, sessionTaskIds: _sessionTasks);
    final acts = {for (final a in logic.state.activities) a.id: a};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header('OFFENSIVE · REPRISE', trailing: TextButton(onPressed: () => _end(), child: const Text('Je m’arrête', style: TextStyle(color: _text2, fontSize: 14)))),
      Expanded(
        child: ListView(children: [
          const SizedBox(height: 6),
          const Text('Pendant que tu étais dedans', style: TextStyle(fontSize: 27, height: 1.15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (_awayNote case final note?)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kOffensiveAccent.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
              child: Text(note, style: const TextStyle(fontSize: 13.5, height: 1.35, color: _text2)),
            ),
          if (_missed.isNotEmpty) ...[
            _label('PASSÉ SANS TOI'),
            for (final b in _missed)
              _backLine(b.startTime, b.title, _handled[b.id], [
                _mini('Fait', () => _settleBlock(b, 'fait')),
                if (b.gcalEventId == null) _mini('Demain', () => _settleBlock(b, 'demain')),
                _mini('Je lâche', () => _settleBlock(b, 'lâché')),
              ]),
          ],
          if (_backRisk.isNotEmpty) ...[
            _label('SE PERD CE SOIR SI RIEN'),
            for (final r in _backRisk)
              _backLine('🔥', '${r.name} · ${r.count} / ${r.target}', _handled[r.id], [
                if (acts[r.id] case final a?)
                  _mini('+1', () {
                    routinePlus(logic, a);
                    final c = routineTodayCount(logic, a);
                    setState(() {
                      if (c >= r.target) _handled[r.id] = 'atteinte';
                      _backRisk = [for (final x in _backRisk) x.id == r.id ? SeriesAtRisk(x.name, c, x.target, x.streak, id: x.id) : x];
                    });
                  }),
                _mini('Plus tard', () => setState(() => _handled[r.id] = 'plus tard')),
              ]),
          ],
          if (fixed != null) ...[
            _label('ENCORE À VENIR'),
            _li(fixed.block.startTime, fixed.block.title, inLabel(fixed.inMin), _pill('daté', _sky)),
          ],
        ]),
      ),
      const SizedBox(height: 10),
      _primary(running == null ? 'Reprendre l’offensive' : 'Reprendre l’offensive · le chrono tourne', () => _startCoup(endsAt: _resumeEndsAt)),
    ]);
  }

  Widget _endView() {
    final now = DateTime.now();
    final counted = logic.state.chainRuns.where((r) => r.id != _runId && offensiveCounts(r)).length + (_won >= kOffensiveCountedMin ? 1 : 0);
    final nextTier = kOffensiveTiers.firstWhere((t) => t > counted, orElse: () => kOffensiveTiers.last);
    final chronoMin = (_chronoSec / 60).round();
    final chronoName = _queue.map((t) => t.chronoActivityId).whereType<String>().toSet();
    final actName = chronoName.length == 1 ? logic.state.activities.where((a) => a.id == chronoName.first).firstOrNull?.name : null;
    final touched = <Project>[
      for (final id in _before.keys)
        if (_actionsDone.containsKey(id) || _queue.any((t) => t.project.id == id && (_stepsDone[t.action.id] ?? 0) > 0))
          logic.currentProjects.where((p) => p.id == id).firstOrNull ?? _queue.firstWhere((t) => t.project.id == id).project,
    ];
    final cur = _cur;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(children: [
          const SizedBox(height: 12),
          const Text('OFFENSIVE TERMINÉE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: _text3)),
          const SizedBox(height: 6),
          Text('$_won coup${_won > 1 ? 's' : ''} · ${fmtOffensiveMin(_elapsedMin())}', style: const TextStyle(fontSize: 30, height: 1.15, fontWeight: FontWeight.w800)),
          if (chronoMin > 0) Text('dont ${fmtOffensiveMin(chronoMin)} de chrono${actName == null ? '' : ' sur $actName'}', style: const TextStyle(fontSize: 13.5, color: _text2)),
          for (final p in touched) ...[
            const SizedBox(height: 14),
            _advanced(p, now),
          ],
          if (touched.isEmpty) ...[
            const SizedBox(height: 14),
            Text(_gainedLine(), style: const TextStyle(fontSize: 14, height: 1.5, color: _text2)),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: kOffensiveAccent.withValues(alpha: .45))),
            child: Row(children: [
              const ModeGlyph(kind: kOffensiveKind, size: 34, color: kOffensiveAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Offensive', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kOffensiveAccent)),
                  Text(counted >= kOffensiveTiers.last ? '$counted offensives · tous les paliers' : '$counted / $nextTier offensives · palier $nextTier',
                      style: const TextStyle(fontSize: 13, color: _text2)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: (counted / nextTier).clamp(0, 1).toDouble(), minHeight: 6, backgroundColor: _track, color: kOffensiveAccent),
                  ),
                  const SizedBox(height: 4),
                  Text(_won >= kOffensiveCountedMin ? 'Celle-ci compte.' : 'Compte dès $kOffensiveCountedMin coups.', style: const TextStyle(fontSize: 11.5, color: _text3)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      _primary('Terminer', _finish, height: 54),
      if (cur != null && !cur.action.done) ...[
        const SizedBox(height: 8),
        _outline('Caser la suite demain', _carryTomorrow),
      ],
    ]);
  }

  Widget _advanced(Project p, DateTime now) {
    final before = _before[p.id];
    final after = planSnapshot(p, now);
    final done = _actionsDone[p.id] ?? const [];
    final partial = [
      for (final t in _queue)
        if (t.project.id == p.id && !t.action.done && (_stepsDone[t.action.id] ?? 0) > 0)
          '${t.action.title} : ${t.action.checklist.where((c) => c.done).length} étapes sur ${t.action.checklist.length}',
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('CE QUI A AVANCÉ · ${p.title.toUpperCase()}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8, color: _text3)),
        const SizedBox(height: 10),
        ProgressBricks(row: projectBricks(p, now), height: 16),
        const SizedBox(height: 8),
        if (before != null)
          Text('${before.done} → ${after.done} tâches faites sur ${after.total}', style: const TextStyle(fontSize: 12, color: _text3)),
        const SizedBox(height: 6),
        Text([...done.map((x) => '$x ✓'), ...partial].join(' · '), style: const TextStyle(fontSize: 14, height: 1.5)),
        if (before != null && before.behind != after.behind) ...[
          const SizedBox(height: 6),
          Text('Le retard sur le plan passe de ${before.behind} tâche${before.behind > 1 ? 's' : ''} à ${after.behind}.', style: const TextStyle(fontSize: 12.5, color: _text3)),
        ],
      ]),
    );
  }
}
