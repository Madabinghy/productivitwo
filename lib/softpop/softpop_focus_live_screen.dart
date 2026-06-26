import 'dart:async';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'softpop_tokens.dart';
import 'softpop_theme.dart';
import 'softpop_components.dart';

/// Maintenant / Focus branché sur les vraies données (AppLogic).
///
/// File des routines du jour non faites : met UNE chose en avant, « Je l'ai
/// fait » → `incHabit` (vrai log), « Plus tard » → fin de file (local).
/// (Le chrono des routines minutées sera branché plus tard sur `Session`.)
class SoftPopFocusLiveScreen extends StatefulWidget {
  final AppLogic logic;
  const SoftPopFocusLiveScreen({super.key, required this.logic});

  @override
  State<SoftPopFocusLiveScreen> createState() => _SoftPopFocusLiveScreenState();
}

class _SoftPopFocusLiveScreenState extends State<SoftPopFocusLiveScreen> {
  AppLogic get logic => widget.logic;
  DateTime get _today => DateTime.now();
  final List<String> _later = []; // ids repoussés en fin de file

  static const _palette = [
    SoftPop.violet, SoftPop.coral, SoftPop.teal, SoftPop.amber, SoftPop.pink,
  ];
  Color _domColor(String? domainId) {
    final doms = logic.state.activeDomains;
    final idx = doms.indexWhere((d) => d.id == domainId);
    if (idx >= 0 && doms[idx].colorValue != null) return Color(doms[idx].colorValue!);
    return idx >= 0 ? _palette[idx % _palette.length] : SoftPop.violet;
  }

  bool _done(Activity a) {
    final tgt = logic.activeHabitTarget(a);
    return tgt > 0 && logic.habitValueOn(a.id, _today) >= tgt;
  }

  // Routines du jour, non faites, ordre : normales puis « plus tard ».
  List<Activity> get _queue {
    final due = logic.state.activeActivities.where((a) {
      if (!a.isHabit) return false;
      final daily = logic.effectiveHabitFreq(a) == HabitFreq.daily;
      final started = logic.habitValueOn(a.id, _today) > 0;
      return (daily || started) && !_done(a);
    }).toList();
    due.sort((a, b) {
      final la = _later.contains(a.id) ? 1 : 0;
      final lb = _later.contains(b.id) ? 1 : 0;
      if (la != lb) return la - lb;
      return _later.indexOf(a.id).compareTo(_later.indexOf(b.id));
    });
    return due;
  }

  void _markDone(Activity a) {
    final tgt = logic.activeHabitTarget(a).clamp(1, 1 << 30);
    final cur = logic.habitValueOn(a.id, _today);
    logic.incHabit(a.id, tgt - cur, _today);
    _later.remove(a.id);
    setState(() {});
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('Bravo ! « ${a.name} » ✓',
            style: SoftPop.ui(color: Colors.white, weight: FontWeight.w600)),
        backgroundColor: SoftPop.teal,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 900),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SoftPop.rChip)),
      ));
  }

  void _later_(Activity a) {
    setState(() {
      _later.remove(a.id);
      _later.add(a.id);
    });
  }

  // ── Chrono (Session) ────────────────────────────────────────────────────────
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _openSession() != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Session? _openSession() {
    Session? last;
    for (final s in logic.state.sessions) {
      if (s.endAt != null) continue;
      if (last == null || s.startAt.isAfter(last.startAt)) last = s;
    }
    return last;
  }

  void _stopChrono() {
    for (final s in logic.state.sessions.where((s) => s.endAt == null)) {
      s.endAt = DateTime.now();
    }
    logic.onChange();
    setState(() {});
  }

  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  // Activités-temps (chronométrables).
  List<Activity> get _timeActivities =>
      logic.state.activeActivities.where((a) => !a.isHabit).toList();

  @override
  Widget build(BuildContext context) {
    final queue = _queue;
    final total = logic.state.activeActivities.where((a) {
      if (!a.isHabit) return false;
      return logic.effectiveHabitFreq(a) == HabitFreq.daily ||
          logic.habitValueOn(a.id, _today) > 0;
    }).length;
    final done = total - queue.length;
    final open = _openSession();
    final timeActs = _timeActivities;
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Maintenant')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
              SoftPop.s16, SoftPop.s8, SoftPop.s16, SoftPop.s32),
          children: [
            if (open != null) ...[
              _runningCard(open),
              const SizedBox(height: SoftPop.s16),
            ],
            if (queue.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerRight,
                child: Text('$done faites · ${queue.length} à faire',
                    style: SoftPop.ui(size: 12, color: SoftPop.inkMuted)),
              ),
              const SizedBox(height: SoftPop.s8),
              _focusCard(queue.first),
              if (queue.length > 1) ...[
                const SizedBox(height: SoftPop.s24),
                Text('À suivre',
                    style: SoftPop.ui(size: 16, weight: FontWeight.w700)),
                const SizedBox(height: SoftPop.s12),
                for (final a in queue.skip(1).take(4)) _upNext(a),
              ],
            ] else
              _allDone(done),
            if (timeActs.isNotEmpty) ...[
              const SizedBox(height: SoftPop.s24),
              Text('Chrono',
                  style: SoftPop.ui(size: 16, weight: FontWeight.w700)),
              const SizedBox(height: SoftPop.s4),
              Text('Lance un minuteur sur une activité-temps.',
                  style: SoftPop.ui(size: 12, color: SoftPop.inkSecondary)),
              const SizedBox(height: SoftPop.s12),
              for (final a in timeActs) _chronoRow(a, open),
            ],
          ],
        ),
      ),
    );
  }

  Widget _runningCard(Session open) {
    final a = logic.state.activeActivities.firstWhere(
      (x) => x.id == open.activityId,
      orElse: () => Activity(domainId: '', name: '—', habitTarget: 1),
    );
    final c = _domColor(a.domainId);
    return SoftCard(
      gradient: SoftPop.heroGradient,
      radius: SoftPop.rCardLg,
      padding: const EdgeInsets.all(SoftPop.s20),
      child: Column(
        children: [
          Text('EN COURS',
              style: SoftPop.ui(
                  size: 11,
                  weight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: .85),
                  letterSpacing: 1)),
          const SizedBox(height: SoftPop.s8),
          Text(a.name,
              textAlign: TextAlign.center,
              style: SoftPop.ui(size: 18, weight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: SoftPop.s8),
          Text(_fmt(DateTime.now().difference(open.startAt)),
              style: SoftPop.mono(size: 40, weight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: SoftPop.s16),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(SoftPop.rPill),
            child: InkWell(
              borderRadius: BorderRadius.circular(SoftPop.rPill),
              onTap: _stopChrono,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: SoftPop.s24, vertical: SoftPop.s12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.stop_rounded, color: c, size: 20),
                    const SizedBox(width: SoftPop.s8),
                    Text('Arrêter',
                        style: SoftPop.ui(
                            size: 15, weight: FontWeight.w700, color: c)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chronoRow(Activity a, Session? open) {
    final c = _domColor(a.domainId);
    final isRunning = open?.activityId == a.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: SoftPop.s8),
      child: SoftCard(
        padding: const EdgeInsets.all(SoftPop.s12),
        radius: SoftPop.rCardSm,
        onTap: () {
          if (isRunning) {
            _stopChrono();
          } else {
            logic.start(a.id);
            setState(() {});
          }
        },
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: c.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(
                a.iconCode != null
                    // ignore: non_const_argument_for_const_parameter
                    ? IconData(a.iconCode!, fontFamily: 'MaterialIcons')
                    : Icons.timer_outlined,
                size: 18,
                color: c,
              ),
            ),
            const SizedBox(width: SoftPop.s12),
            Expanded(
              child: Text(a.name,
                  style: SoftPop.ui(size: 14, weight: FontWeight.w600)),
            ),
            Icon(isRunning ? Icons.stop_circle : Icons.play_circle_fill,
                size: 30, color: c),
          ],
        ),
      ),
    );
  }

  Widget _allDone(int done) => Padding(
        padding: const EdgeInsets.symmetric(vertical: SoftPop.s24),
        child: Column(
          children: [
            const PomoMascot(size: 72),
            const SizedBox(height: SoftPop.s12),
            Text('Routines du jour faites ! 🎉',
                style: SoftPop.ui(size: 18, weight: FontWeight.w700)),
          ],
        ),
      );

  Widget _focusCard(Activity a) {
    final c = _domColor(a.domainId);
    final tgt = logic.activeHabitTarget(a);
    final val = logic.habitValueOn(a.id, _today);
    final target = tgt > 1
        ? '$val / $tgt${a.unit != null ? ' ${a.unit}' : ''}'
        : 'objectif du jour';
    return SoftCard(
      radius: SoftPop.rCardLg,
      padding: const EdgeInsets.all(SoftPop.s24),
      child: Column(
        children: [
          Text('À FAIRE MAINTENANT',
              style: SoftPop.ui(
                  size: 11,
                  weight: FontWeight.w700,
                  color: c,
                  letterSpacing: 1)),
          const SizedBox(height: SoftPop.s16),
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.withValues(alpha: .14), shape: BoxShape.circle),
            child: Icon(
              a.iconCode != null
                  // ignore: non_const_argument_for_const_parameter
                  ? IconData(a.iconCode!, fontFamily: 'MaterialIcons')
                  : Icons.bolt,
              size: 38,
              color: c,
            ),
          ),
          const SizedBox(height: SoftPop.s12),
          Text(a.name,
              textAlign: TextAlign.center,
              style: SoftPop.ui(size: 20, weight: FontWeight.w700)),
          Text(target, style: SoftPop.ui(size: 13, color: SoftPop.inkMuted)),
          const SizedBox(height: SoftPop.s20),
          SoftHeroButton(label: "Je l'ai fait ✓", onPressed: () => _markDone(a)),
          const SizedBox(height: SoftPop.s8),
          TextButton(
            onPressed: () => _later_(a),
            child: Text('Plus tard · remettre en fin de file ↓',
                style: SoftPop.ui(size: 13, color: SoftPop.inkSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _upNext(Activity a) {
    final c = _domColor(a.domainId);
    return Padding(
      padding: const EdgeInsets.only(bottom: SoftPop.s8),
      child: SoftCard(
        padding: const EdgeInsets.all(SoftPop.s12),
        radius: SoftPop.rCardSm,
        onTap: () => _markDone(a),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: c.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(
                a.iconCode != null
                    // ignore: non_const_argument_for_const_parameter
                    ? IconData(a.iconCode!, fontFamily: 'MaterialIcons')
                    : Icons.bolt,
                size: 18,
                color: c,
              ),
            ),
            const SizedBox(width: SoftPop.s12),
            Expanded(
              child: Text(a.name,
                  style: SoftPop.ui(size: 14, weight: FontWeight.w600)),
            ),
            Icon(Icons.radio_button_unchecked,
                size: 22, color: SoftPop.inkMuted.withValues(alpha: .5)),
          ],
        ),
      ),
    );
  }

}
