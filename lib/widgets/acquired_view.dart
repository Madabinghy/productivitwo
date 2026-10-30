import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/acquired.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show routineSeries, routineReachedDays;
import 'package:productivitwo_v1/utils/engagement_stats.dart' show mondayOf, ymdOf;
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/badge_painter.dart' show kBadgeBrass;

/// Routine acquise (maquette validée 2026-10-30) : la proposition au palier de
/// 66 jours et l'alerte « une acquise décroche », en cartes dans Aujourd'hui ;
/// la section ACQUISES de la fiche Routines.

List<Activity> _dailyRoutines(AppLogic logic) =>
    logic.state.activeActivities.where((a) => a.isHabit && a.habitFreq == HabitFreq.daily).toList();

Set<String> _held(AppLogic logic, Activity a) => {...routineReachedDays(a, logic.state.habitHits, dayStartMin: logic.dayStartMin), ...logic.bridgedOf(a.id)};

/// Les cartes d'Aujourd'hui : une proposition (la plus longue série d'abord),
/// puis chaque acquise qui décroche. Rien quand rien n'est à dire.
class AcquiredPrompts extends StatelessWidget {
  final AppLogic logic;
  final VoidCallback? onChanged;
  const AcquiredPrompts({super.key, required this.logic, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = logic.livedToday;
    final cards = <Widget>[];
    (Activity, int)? propose;
    for (final a in _dailyRoutines(logic)) {
      if (logic.acquired.containsKey(a.id)) continue;
      final s = routineSeries(a, logic.state.habitHits, now, dayStartMin: logic.dayStartMin, bridged: logic.bridgedOf(a.id), frozen: logic.frozenOf(a.id));
      if (shouldProposeAcquire(id: a.id, longest: s.longest, acquired: logic.acquired, asked: logic.acquireAsked) && (propose == null || s.current > propose.$2)) {
        propose = (a, s.current);
      }
    }
    if (propose != null) cards.add(_proposal(context, propose.$1, propose.$2));
    for (final a in _dailyRoutines(logic)) {
      final acq = logic.acquired[a.id];
      if (acq == null) continue;
      final held = _held(logic, a);
      if (!isSlipping(acq, held, today)) continue;
      cards.add(_slipping(context, a, acq, held, today));
    }
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 8), cards[i]],
      ]),
    );
  }

  Future<void> _run(Future<void> f) async {
    await f;
    onChanged?.call();
  }

  Widget _card({required Color accent, required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: accent.withValues(alpha: .45))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _proposal(BuildContext context, Activity a, int current) => _card(accent: kBadgeBrass, children: [
        const Text('66 JOURS · L’HABITUDE EST INSTALLÉE', style: TextStyle(fontSize: 11, letterSpacing: .6, fontWeight: FontWeight.w700, color: kBadgeBrass)),
        const SizedBox(height: 6),
        Text('${a.name} : la passer en acquise ?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kBText)),
        const SizedBox(height: 8),
        for (final t in const [
          'Elle sort de la journée parfaite et des enjeux du jour.',
          'Elle reste cochable ; sa série et ses paliers continuent.',
          'Elle compte toujours dans le contrat de son objectif.',
          'Si elle décroche deux semaines de suite, on te le dit.',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('· $t', style: const TextStyle(fontSize: 13, height: 1.35, color: kBText2)),
          ),
        const SizedBox(height: 8),
        FilledButton(onPressed: () => _run(logic.acquireRoutine(a.id)), child: const Text('Passer en acquise')),
        TextButton(onPressed: () => _run(logic.declineAcquire(a.id)), child: const Text('La garder comme maintenant')),
      ]);

  Widget _slipping(BuildContext context, Activity a, Acquired acq, Set<String> held, DateTime today) {
    final monday = mondayOf(today);
    final weeks = [
      for (var k = 4; k >= 1; k--)
        () {
          final m = monday.subtract(Duration(days: 7 * k));
          final n = [for (var i = 0; i < 7; i++) ymdOf(DateTime(m.year, m.month, m.day + i))].where(held.contains).length;
          return (m, n);
        }(),
    ];
    final since = today.difference(DateTime.parse(acq.since)).inDays;
    return _card(accent: kBAttention, children: [
      const Text('UNE ACQUISE DÉCROCHE', style: TextStyle(fontSize: 11, letterSpacing: .6, fontWeight: FontWeight.w700, color: kBAttention)),
      const SizedBox(height: 6),
      Text(a.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kBText)),
      Text('acquise depuis $since j', style: const TextStyle(fontSize: 13, color: kBText3)),
      const SizedBox(height: 10),
      for (final (m, n) in weeks)
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(children: [
            SizedBox(width: 64, child: Text('${m.day}/${m.month}', style: const TextStyle(fontSize: 12, color: kBText3))),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                return SizedBox(
                  height: 12,
                  child: Stack(children: [
                    Positioned(left: 0, right: 0, top: 2, height: 8, child: Container(decoration: BoxDecoration(color: kBRaised, borderRadius: BorderRadius.circular(4)))),
                    Positioned(
                        left: 0,
                        top: 2,
                        height: 8,
                        width: c.maxWidth * n / 7,
                        child: Container(decoration: BoxDecoration(color: n >= kSlipDays ? kBPrimaryDark : kBAttention, borderRadius: BorderRadius.circular(4)))),
                    Positioned(left: c.maxWidth * kSlipDays / 7 - 1, top: 0, width: 2, height: 12, child: Container(color: kBText3)),
                  ]),
                );
              }),
            ),
            SizedBox(width: 40, child: Text('$n / 7', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: kBText2))),
          ]),
        ),
      const SizedBox(height: 6),
      const Text('Deux semaines sous la moitié. La remettre en routine active la ramène dans ta journée et tes enjeux.',
          style: TextStyle(fontSize: 13, height: 1.35, color: kBText2)),
      const SizedBox(height: 10),
      FilledButton(onPressed: () => _run(logic.releaseRoutine(a.id)), child: const Text('La remettre en routine active')),
      TextButton(onPressed: () => _run(logic.quietAcquired(a.id)), child: const Text('C’est voulu (silence 4 semaines)')),
    ]);
  }
}

/// Section ACQUISES de la fiche Routines : cochables, en retrait.
class AcquiredSection extends StatelessWidget {
  final AppLogic logic;
  final void Function(Activity a) onPlus;
  final void Function(Activity a)? onOpen;
  const AcquiredSection({super.key, required this.logic, required this.onPlus, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final list = _dailyRoutines(logic).where((a) => logic.isAcquired(a.id)).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (list.isEmpty) return const SizedBox.shrink();
    final today = logic.livedToday;
    final todayYmd = ymdOf(today);
    final monday = mondayOf(today);
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('ACQUISES · ${list.length}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3))),
        const Text('hors journée parfaite', style: TextStyle(fontSize: 11.5, color: kBText4)),
      ]),
      const SizedBox(height: 6),
      for (final a in list)
        () {
          final held = _held(logic, a);
          final week = [for (var i = 0; i < 7; i++) ymdOf(DateTime(monday.year, monday.month, monday.day + i))].where(held.contains).length;
          final s = routineSeries(a, logic.state.habitHits, now, dayStartMin: logic.dayStartMin, bridged: logic.bridgedOf(a.id), frozen: logic.frozenOf(a.id));
          final since = today.difference(DateTime.parse(logic.acquired[a.id]!.since)).inDays;
          final doneToday = held.contains(todayYmd);
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: Colors.white.withValues(alpha: .02),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onLongPress: onOpen == null ? null : () => onOpen!(a),
                onTap: () => onPlus(a),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                  child: Row(children: [
                    Icon(doneToday ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, size: 26, color: doneToday ? kBPrimaryDark : kBText4),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.name, style: const TextStyle(fontSize: 14, color: kBText2)),
                        Text('acquise depuis $since j${s.current > 0 ? ' · série ${s.current} j' : ''}', style: const TextStyle(fontSize: 12, color: kBText4)),
                      ]),
                    ),
                    Text('$week / 7', style: const TextStyle(fontSize: 12, color: kBText3)),
                  ]),
                ),
              ),
            ),
          );
        }(),
    ]);
  }
}
