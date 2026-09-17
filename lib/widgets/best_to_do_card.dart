import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';

/// « Le meilleur à faire » — les 3 meilleures routines PAS ENCORE ATTEINTES
/// (quotidiennes : cible du jour non remplie ; hebdos : cible des 7 jours non
/// remplie), classées par max(score du jour, score 7 j). Vit dans Maintenant :
/// +1 direct, −1 (correction), et « passer » (la routine recule en FIN de
/// liste pour aujourd'hui — elle reste visible et rattrapable, les autres
/// remontent ; réversible sur place).
class BestToDoCard extends StatefulWidget {
  final AppLogic logic;
  const BestToDoCard({super.key, required this.logic});

  @override
  State<BestToDoCard> createState() => _BestToDoCardState();
}

class _BestToDoCardState extends State<BestToDoCard> {
  final _sync = FirestoreSync();

  AppLogic get logic => widget.logic;

  // Le −1 doit retirer un hit (les chiffres affichés viennent de habitHits,
  // pas de habitProgress) : dernier hit de la routine, retiré localement ET
  // côté Firestore (le merge par union le ressusciterait sinon).
  void _decrement(Activity a) {
    final hits = logic.state.habitHits.where((h) => h.habitId == a.id).toList()
      ..sort((x, y) => x.ts.compareTo(y.ts));
    if (hits.isEmpty) return;
    final last = hits.last;
    logic.state.habitHits.remove(last);
    unawaited(_sync.hardDelete('habitHits', last.id));
    // Compteur du jour (habitProgress) sur la date du hit retiré.
    logic.incHabit(a.id, -1, last.ts); // appelle onChange()
    setState(() {});
  }

  // « Passer » = reculer en fin de liste pour aujourd'hui (pas de
  // disparition) : les autres routines remontent, celle-ci reste visible
  // et rattrapable. Re-tap sur une routine passée → elle revient en course.
  void _togglePasse(Activity a) {
    final ymd = yyyymmdd(DateTime.now());
    final ids = logic.nowSkippedSet(ymd);
    final wasSkipped = ids.contains(a.id);
    if (wasSkipped) {
      ids.remove(a.id);
    } else {
      ids.add(a.id);
    }
    logic.setNowSkipped(ymd, ids);
    setState(() {});
    if (!wasSkipped) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Reculée en fin de liste : ${a.name}'),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = logic.state;
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final skipped = logic.nowSkippedSet(yyyymmdd(now));

    final entries = <({
      Activity act,
      int dayDone,
      int? dayTarget,
      int weekDone,
      int weekTarget,
      double score,
      bool passed,
    })>[];
    for (final a in st.activeActivities) {
      if (!a.isHabit || a.habitFreq == HabitFreq.monthly) continue;
      final week = rollingStatFor(a, st.habitHits);
      if (week == null) continue;
      final weekRatio = (week.done / week.target).clamp(0.0, 1.0).toDouble();
      var dayDone = 0;
      int? dayTarget;
      var dayRatio = 0.0;
      if (a.habitFreq == HabitFreq.daily) {
        final t = a.habitTarget ?? 1;
        dayTarget = t <= 0 ? 1 : t;
        dayDone = st.habitHits
            .where((h) => h.habitId == a.id && !h.ts.isBefore(midnight))
            .length;
        dayRatio = (dayDone / dayTarget).clamp(0.0, 1.0).toDouble();
      }
      entries.add((
        act: a,
        dayDone: dayDone,
        dayTarget: dayTarget,
        weekDone: week.done,
        weekTarget: week.target,
        score: dayRatio > weekRatio ? dayRatio : weekRatio,
        passed: skipped.contains(a.id),
      ));
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    // Pas encore atteintes : quotidienne → cible du JOUR non remplie ;
    // hebdo → cible des 7 jours non remplie. Le déjà-atteint sort du top.
    // Les « passées » du jour restent dans la liste mais reculent EN FIN —
    // elles réapparaissent en tête de la queue si tout le reste est passé.
    final pending = entries.where((e) {
      final dt = e.dayTarget;
      if (dt != null) return e.dayDone < dt;
      return e.weekDone < e.weekTarget;
    }).toList()
      ..sort((x, y) {
        if (x.passed != y.passed) return x.passed ? 1 : -1;
        return x.score == y.score
            ? y.weekDone.compareTo(x.weekDone)
            : y.score.compareTo(x.score);
      });

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.local_fire_department_rounded,
                size: 15, color: cs.primary),
            const SizedBox(width: 6),
            Text('LE MEILLEUR À FAIRE',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                    color: cs.onSurface.withOpacity(.5))),
          ]),
          const SizedBox(height: 4),
          if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 8, 8),
              child: Text('Tout est atteint — rien à rattraper. ✓',
                  style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurface.withOpacity(.55))),
            ),
          // Deux lignes par routine : le nom respire en pleine largeur,
          // les chiffres et les gestes vivent en dessous (une seule ligne
          // tronquait le nom dès que la rangée se remplissait).
          for (final e in pending.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: palierColor((e.score * 100).round())
                              .withOpacity(e.passed ? .35 : 1),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e.act.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: e.passed
                                    ? cs.onSurface.withOpacity(.4)
                                    : null)),
                      ),
                    ]),
                    Row(children: [
                      const SizedBox(width: 18),
                      Text(
                          [
                            if (e.dayTarget != null)
                              'auj. ${e.dayDone}/${e.dayTarget}',
                            '7 j ${e.weekDone}/${e.weekTarget}',
                          ].join(' · '),
                          style: TextStyle(
                              fontSize: 11.5,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                              color: cs.onSurface.withOpacity(.55))),
                      const Spacer(),
                      IconButton(
                        tooltip: '−1',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.remove_circle_outline,
                            size: 20,
                            color: (e.dayTarget != null
                                    ? e.dayDone > 0
                                    : e.weekDone > 0)
                                ? cs.onSurface.withOpacity(.45)
                                : cs.onSurface.withOpacity(.15)),
                        onPressed: (e.dayTarget != null
                                ? e.dayDone > 0
                                : e.weekDone > 0)
                            ? () => _decrement(e.act)
                            : null,
                      ),
                      // +1 direct : même mécanique que les compteurs de routine
                      // (habitProgress + coche du jour + persistance via onChange).
                      IconButton(
                        tooltip: '+1',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        icon:
                            Icon(Icons.add_circle, size: 22, color: cs.primary),
                        onPressed: () {
                          logic.incHabit(e.act.id, 1, DateTime.now());
                          setState(() {});
                        },
                      ),
                      IconButton(
                        tooltip: e.passed
                            ? 'Remettre en course'
                            : 'Reculer en fin de liste',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        icon: Icon(
                            e.passed
                                ? Icons.undo_rounded
                                : Icons.skip_next_rounded,
                            size: 22,
                            color: cs.onSurface.withOpacity(.45)),
                        onPressed: () => _togglePasse(e.act),
                      ),
                    ]),
                  ]),
            ),
        ],
      ),
    );
  }
}
