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

  @override
  Widget build(BuildContext context) {
    final queue = _queue;
    final total = logic.state.activeActivities.where((a) {
      if (!a.isHabit) return false;
      return logic.effectiveHabitFreq(a) == HabitFreq.daily ||
          logic.habitValueOn(a.id, _today) > 0;
    }).length;
    final done = total - queue.length;
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Maintenant')),
        body: queue.isEmpty
            ? _empty(done)
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                    SoftPop.s16, SoftPop.s8, SoftPop.s16, SoftPop.s32),
                children: [
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
                ],
              ),
      ),
    );
  }

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

  Widget _empty(int done) => Center(
        child: Padding(
          padding: const EdgeInsets.all(SoftPop.s32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PomoMascot(size: 96),
              const SizedBox(height: SoftPop.s20),
              Text('Tout est fait ! 🎉',
                  style: SoftPop.ui(size: 22, weight: FontWeight.w700)),
              const SizedBox(height: SoftPop.s8),
              Text('$done routine${done > 1 ? 's' : ''} accomplie${done > 1 ? 's' : ''} aujourd’hui. Profite 💛',
                  textAlign: TextAlign.center,
                  style: SoftPop.ui(
                      size: 14, color: SoftPop.inkSecondary, height: 1.4)),
            ],
          ),
        ),
      );
}
