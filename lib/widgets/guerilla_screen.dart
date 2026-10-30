import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/game_rules.dart' show kRuleGuerilla;
import 'package:productivitwo_v1/utils/guerilla.dart';
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;
import 'package:productivitwo_v1/utils/routine_moments.dart' show buildRoutineDay;
import 'package:productivitwo_v1/widgets/info_dot.dart';

/// Écran Guérilla (maquette validée 2026-10-30) : le corps de 1 à 5, puis un
/// coup à la fois (minuteur de 5 min, « Fait · suivant », « Pas ça », « Encore
/// 5 min »), un point d'étape tous les 3 coups (« moins bien » = on s'arrête),
/// un bilan avant → après et le badge. La guérilla s'écrit en [ChainRun]
/// `kind:"guerilla"`. File : [buildGuerillaQueue].
const kGuerillaAccent = Color(0xFFC5D38A);
const kGuerillaInk = Color(0xFF141C0C);
const _bg = Color(0xFF0B130A);
const _card = Color(0xFF12241B);
const _text2 = Color(0xFFB9CFC4);
const _text3 = Color(0xFFA3B8AD);

Future<void> showGuerillaScreen(BuildContext context, AppLogic logic) {
  return Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => GuerillaScreen(logic: logic)));
}

enum _Phase { intro, coup, pause, end }

class GuerillaScreen extends StatefulWidget {
  final AppLogic logic;
  const GuerillaScreen({super.key, required this.logic});

  @override
  State<GuerillaScreen> createState() => _GuerillaScreenState();
}

class _GuerillaScreenState extends State<GuerillaScreen> {
  late final List<GuerillaCoup> _queue;
  final _passed = <String>{};
  final _done = <GuerillaCoup>[];
  _Phase _phase = _Phase.intro;
  int _index = 0;
  int? _before, _after;
  int _remaining = kGuerillaCoupMin * 60;
  Timer? _timer;
  bool _ownChrono = false;
  bool _saved = false;
  DateTime? _startedAt;
  final String _runId = ChainRun(date: '', startedAt: DateTime(0), endedAt: DateTime(0), doneCount: 0, total: 0, completed: false).id;

  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
    final st = logic.state;
    final now = DateTime.now();
    final ymd = logic.livedYmdNow;
    final day = buildRoutineDay(
      activities: st.activeActivities,
      hits: st.habitHits,
      now: now,
      pushed: logic.routinePushed(ymd),
      deferred: st.nowSkippedByYmd[ymd] ?? const [],
      dismissed: logic.nowDoneSet(ymd),
      dayStartMin: logic.dayStartMin,
      moments: logic.moments,
    );
    final paused = {
      for (final e in st.snoozedUntil.entries)
        if (DateTime.tryParse(e.value)?.isAfter(now) ?? false) e.key,
    };
    _queue = buildGuerillaQueue(day: day, activities: st.activeActivities, projects: logic.currentProjects, now: now, pausedActivityIds: paused);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopOwnChrono();
    if (!_saved && _done.isNotEmpty) _save();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  // ── Coups ────────────────────────────────────────────────────────────────

  void _start() {
    _startedAt = DateTime.now();
    _enter(0);
  }

  void _enter(int i) {
    _index = i;
    _remaining = kGuerillaCoupMin * 60;
    _phase = _Phase.coup;
    final c = _queue[i];
    if (c.kind == GuerillaKind.action && c.activityId != null && !logic.state.sessions.any((s) => s.endAt == null)) {
      logic.start(c.activityId!, taskId: c.taskId, actionId: c.action?.id);
      _ownChrono = true;
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining = _remaining > 0 ? _remaining - 1 : 0);
    });
    setState(() {});
  }

  void _stopOwnChrono() {
    if (!_ownChrono) return;
    _ownChrono = false;
    logic.stopActive(notify: false);
  }

  void _next() {
    _timer?.cancel();
    final n = nextCoupIndex(_queue, _index, _passed);
    if (n == null) {
      setState(() => _phase = _Phase.end);
    } else {
      _enter(n);
    }
  }

  void _doneCoup() {
    final c = _queue[_index];
    _stopOwnChrono();
    if (c.kind == GuerillaKind.routine && c.activityId != null) {
      logic.incHabit(c.activityId!, c.delta, livedDate(DateTime.now(), logic.dayStartMin));
    }
    _done.add(c);
    _passed.add(c.key);
    if (guerillaPauseDue(_done.length) && nextCoupIndex(_queue, _index, _passed) != null) {
      _timer?.cancel();
      setState(() => _phase = _Phase.pause);
    } else {
      _next();
    }
  }

  void _skipCoup() {
    _stopOwnChrono();
    _passed.add(_queue[_index].key);
    _next();
  }

  void _stop() {
    _timer?.cancel();
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
      doneCount: _done.length,
      total: _done.length,
      completed: nextCoupIndex(_queue, _index, _passed) == null,
      kind: kGuerillaKind,
      bodyBefore: _before,
      bodyAfter: _after,
    );
    logic.recordChainRun(run);
    logic.sync?.saveChainRun(run);
  }

  void _finish() {
    if (_done.isNotEmpty) _save();
    _saved = true;
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
            child: switch (_phase) {
              _Phase.intro => _intro(),
              _Phase.coup => _coup(),
              _Phase.pause => _pause(),
              _Phase.end => _end(),
            },
          ),
        ),
      ),
    );
  }

  Widget _header({Widget? trailing}) => SizedBox(
        height: 48,
        child: Row(children: [
          const Icon(Icons.bolt, color: kGuerillaAccent, size: 20),
          const SizedBox(width: 6),
          const Text('GUÉRILLA', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1, color: kGuerillaAccent)),
          const InfoDot(kRuleGuerilla),
          const Spacer(),
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
            backgroundColor: kGuerillaAccent,
            foregroundColor: kGuerillaInk,
            disabledBackgroundColor: kGuerillaAccent.withValues(alpha: .25),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _outline(String label, VoidCallback onTap) => SizedBox(
        height: 48,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: .18)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _bodyPicker(int? value, ValueChanged<int> onPick) => Column(children: [
        Row(children: [
          for (var v = 1; v <= 5; v++) ...[
            if (v > 1) const SizedBox(width: 6),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: () => onPick(v),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: value == v ? kGuerillaAccent.withValues(alpha: .16) : null,
                    foregroundColor: value == v ? kGuerillaAccent : Colors.white,
                    side: BorderSide(color: value == v ? kGuerillaAccent : Colors.white.withValues(alpha: .14), width: value == v ? 2 : 1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('$v', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 4),
        const Row(children: [
          Text('au fond du trou', style: TextStyle(fontSize: 11.5, color: _text3)),
          Spacer(),
          Text('ça va', style: TextStyle(fontSize: 11.5, color: _text3)),
        ]),
      ]);

  Widget _intro() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(trailing: IconButton(tooltip: 'Fermer', icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop())),
      Expanded(
        child: ListView(children: [
          const SizedBox(height: 8),
          const Text('La flemme ou moi', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Pas bien, mais debout. L’app choisit, tu enchaînes des coups de 5 min, sans réfléchir. Tu t’arrêtes quand tu veux : tout ce qui est fait compte.',
              style: TextStyle(fontSize: 14.5, height: 1.4, color: _text2)),
          _label('TON CORPS, LÀ'),
          _bodyPicker(_before, (v) => setState(() => _before = v)),
          _label(_queue.isEmpty ? 'AU MENU' : 'AU MENU · ${_queue.length} COUP${_queue.length > 1 ? 'S' : ''} PRÊT${_queue.length > 1 ? 'S' : ''}'),
          if (_queue.isEmpty)
            const Text('Rien à faire en ce moment : toutes tes routines du moment sont atteintes et aucune action n’attend.', style: TextStyle(fontSize: 13.5, height: 1.4, color: _text2))
          else
            Text(_queue.map((c) => c.kind == GuerillaKind.action ? '5 min sur ${c.title}' : c.title).join(' · '),
                style: const TextStyle(fontSize: 13.5, height: 1.5, color: _text2)),
          const SizedBox(height: 18),
          const Text('Fièvre, vertiges, douleur forte : ce n’est pas un jour de guérilla. Repos, ça compte aussi.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: _text3)),
        ]),
      ),
      const SizedBox(height: 12),
      _primary(_before == null ? 'Note ton corps pour lancer' : 'Lancer la guérilla', _before == null || _queue.isEmpty ? null : _start),
    ]);
  }

  Widget _progress() => Row(children: [
        for (var i = 0; i < _done.length + 1 && i < 8; i++) ...[
          Container(
            width: 22,
            height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: i < _done.length ? kGuerillaAccent : null,
              borderRadius: BorderRadius.circular(4),
              border: i < _done.length ? null : Border.all(color: kGuerillaAccent, width: 2),
            ),
          ),
        ],
        const Spacer(),
        Text('${_done.length} coup${_done.length > 1 ? 's' : ''} · ${_elapsedMin()} min', style: const TextStyle(fontSize: 13, color: _text2, fontFeatures: [FontFeature.tabularFigures()])),
      ]);

  int _elapsedMin() => _startedAt == null ? 0 : DateTime.now().difference(_startedAt!).inMinutes;

  Widget _coup() {
    final c = _queue[_index];
    final total = kGuerillaCoupMin * 60;
    final left = _remaining.clamp(0, 1 << 30);
    final mm = (left ~/ 60).toString();
    final ss = (left % 60).toString().padLeft(2, '0');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(trailing: TextButton(onPressed: _stop, child: const Text('Je m’arrête', style: TextStyle(color: _text2, fontSize: 14)))),
      const SizedBox(height: 6),
      _progress(),
      Expanded(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('COUP ${_done.length + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: _text3)),
          const SizedBox(height: 14),
          Text(c.title, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 32, height: 1.2, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(c.hint, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: _text2)),
          const SizedBox(height: 26),
          SizedBox(
            width: 190,
            height: 190,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: 1 - left / (total < _remaining ? _remaining : total),
                  strokeWidth: 11,
                  backgroundColor: const Color(0xFF2A3A1C),
                  color: kGuerillaAccent,
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$mm:$ss', style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                Text(left == 0 ? 'temps écoulé' : 'sur 5:00', style: const TextStyle(fontSize: 12, color: _text3)),
              ]),
            ]),
          ),
        ]),
      ),
      _primary('Fait · suivant', _doneCoup, height: 60),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _outline('Pas ça', _skipCoup)),
        const SizedBox(width: 10),
        Expanded(child: _outline('Encore 5 min', () => setState(() => _remaining += kGuerillaCoupMin * 60))),
      ]),
      const SizedBox(height: 8),
      const Text('« Pas ça » passe au suivant, sans question.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: _text3)),
    ]);
  }

  Widget _pause() {
    Widget choice(String label, VoidCallback onTap, {bool strong = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SizedBox(
            height: 56,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                backgroundColor: strong ? kGuerillaAccent.withValues(alpha: .12) : null,
                foregroundColor: strong ? kGuerillaAccent : Colors.white,
                side: BorderSide(color: strong ? kGuerillaAccent.withValues(alpha: .5) : Colors.white.withValues(alpha: .16)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(),
      const SizedBox(height: 6),
      _progress(),
      Expanded(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('POINT D’ÉTAPE · 1 MIN', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: _text3)),
          const SizedBox(height: 14),
          const Text('Un verre d’eau.\nTrois respirations.', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, height: 1.2, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          const Text('Puis dis-moi, ta tête :', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: _text2)),
          const SizedBox(height: 20),
          choice('Mieux · on continue', _next, strong: true),
          choice('Pareil · on continue', _next),
          choice('Moins bien · je m’arrête', _stop),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
            child: Text('« Moins bien » n’est pas un échec : la guérilla s’arrête, tes ${_done.length} coups restent comptés.',
                style: const TextStyle(fontSize: 13, height: 1.35, color: _text2)),
          ),
        ]),
      ),
      TextButton(onPressed: _next, child: const Text('Passer la pause', style: TextStyle(color: _text3))),
    ]);
  }

  Widget _end() {
    final counted = logic.state.chainRuns.where((r) => r.id != _runId && guerillaCounts(r)).length + (_done.length >= kGuerillaCountedMin ? 1 : 0);
    final nextTier = kGuerillaTiers.firstWhere((t) => t > counted, orElse: () => kGuerillaTiers.last);
    final previews = [
      ...logic.state.chainRuns.where((r) => r.id != _runId && isGuerillaRun(r)),
      if (_before != null && _after != null)
        ChainRun(date: '', startedAt: DateTime.now(), endedAt: DateTime.now(), doneCount: _done.length, total: _done.length, completed: false, kind: kGuerillaKind, bodyBefore: _before, bodyAfter: _after),
    ];
    final lift = guerillaLiftLine(previews);
    final passed = _queue.where((c) => _passed.contains(c.key) && !_done.contains(c)).toList();
    final more = nextCoupIndex(_queue, _index, _passed) != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(children: [
          const SizedBox(height: 12),
          const Text('GUÉRILLA TERMINÉE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: _text3)),
          const SizedBox(height: 6),
          Text(_done.isEmpty ? 'Aucun coup cette fois' : '${_done.length} coup${_done.length > 1 ? 's' : ''} gagné${_done.length > 1 ? 's' : ''} sur la flemme',
              style: const TextStyle(fontSize: 28, height: 1.2, fontWeight: FontWeight.w800)),
          Text('en ${_elapsedMin()} min · ${guerillaCountLine(_done.length)}', style: const TextStyle(fontSize: 13.5, color: _text2)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('TON CORPS, MAINTENANT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8, color: _text3)),
                const Spacer(),
                if (_before != null)
                  Text(_after == null ? 'avant : $_before' : '$_before → $_after',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: (_after ?? 0) > _before! ? kGuerillaAccent : Colors.white)),
              ]),
              const SizedBox(height: 10),
              _bodyPicker(_after, (v) => setState(() => _after = v)),
              if (lift != null) ...[
                const SizedBox(height: 10),
                Text(lift, style: const TextStyle(fontSize: 13, color: _text2)),
              ],
            ]),
          ),
          if (_done.isNotEmpty) ...[
            _label('FAIT'),
            Text(_done.map((c) => c.kind == GuerillaKind.action ? '${c.title} 5 min' : c.title).join(' · '), style: const TextStyle(fontSize: 14, height: 1.5)),
          ],
          if (passed.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Passé : ${passed.map((c) => c.title).join(' · ')}', style: const TextStyle(fontSize: 12.5, color: _text3)),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF141C0C),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kGuerillaAccent.withValues(alpha: .45)),
            ),
            child: Row(children: [
              const Icon(Icons.bolt, color: kGuerillaAccent, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Guérilla', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kGuerillaAccent)),
                  Text(counted >= kGuerillaTiers.last ? '$counted guérillas · tous les paliers' : '$counted / $nextTier guérillas · palier $nextTier',
                      style: const TextStyle(fontSize: 13, color: _text2)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (counted / nextTier).clamp(0, 1).toDouble(),
                      minHeight: 6,
                      backgroundColor: const Color(0xFF2A3A1C),
                      color: kGuerillaAccent,
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      _primary('Terminer', _finish, height: 54),
      if (more) ...[
        const SizedBox(height: 8),
        _outline('Encore 3 coups', () {
          final n = nextCoupIndex(_queue, _index, _passed);
          if (n != null) _enter(n);
        }),
      ],
    ]);
  }
}
