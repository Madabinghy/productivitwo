import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/widgets/routine_tile_bits.dart';

/// « Le meilleur à faire » — les 3 meilleures routines PAS ENCORE ATTEINTES
/// (quotidiennes : cible du jour non remplie ; hebdos : cible des 7 jours non
/// remplie), classées par max(score du jour, score 7 j). Vit dans Maintenant.
///
/// Les rangées reprennent le STYLE des tuiles du lanceur de routines (FAB
/// « Lancer une routine ») : pastille domaine, nom + série, ▶ chrono /
/// ⏱ minuteur, compteur réel, − / + — avec EN PLUS le bouton ⏭ « reculer en
/// fin de liste » (la routine passée reste visible et rattrapable, réversible
/// d'un re-tap ↩).
class BestToDoCard extends StatefulWidget {
  final AppLogic logic;
  // Minuteur (⏱) : même flux que le lanceur — chrono ciblé + décompte,
  // routine cochée à la fin. Branché sur FocusView.onStartTimed.
  final void Function(Activity routine, int minutes)? onStartTimed;
  const BestToDoCard({super.key, required this.logic, this.onStartTimed});

  @override
  State<BestToDoCard> createState() => _BestToDoCardState();
}

class _BestToDoCardState extends State<BestToDoCard> {
  AppLogic get logic => widget.logic;

  // Le décrément est UNIFIÉ dans AppLogic.incHabit (delta < 0 retire aussi
  // le dernier hit du jour vécu, local + Firestore). On vise la journée du
  // dernier hit — pour une hebdo, il peut dater d'un autre jour.
  void _decrement(Activity a) {
    final hits = logic.state.habitHits.where((h) => h.habitId == a.id).toList()
      ..sort((x, y) => x.ts.compareTo(y.ts));
    if (hits.isEmpty) return;
    final t = hits.last.ts;
    final lived = t.hour * 60 + t.minute < 5 * 60
        ? t.subtract(const Duration(days: 1))
        : t;
    logic.incHabit(a.id, -1, DateTime(lived.year, lived.month, lived.day));
    setState(() {});
  }

  // ✅ « Valider » : atteindre la cible ne sort PLUS la routine de la liste
  // (retour user : cible 1 traction en reprise, 3 saisies voulues — la
  // routine disparaissait dès la première). Elle descend en fin de liste,
  // reste incrémentable, et c'est CE bouton qui la sort pour la journée.
  void _validate(Activity a) {
    final ymd = yyyymmdd(DateTime.now());
    logic.setNowDone(ymd, logic.nowDoneSet(ymd)..add(a.id));
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Validée pour aujourd\'hui : ${a.name}'),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () {
          logic.setNowDone(ymd, logic.nowDoneSet(ymd)..remove(a.id));
          if (mounted) setState(() {});
        },
      ),
    ));
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
    // Validées ✅ du jour : sorties de la liste par un geste EXPLICITE —
    // atteindre la cible ne suffit plus (on peut continuer à saisir).
    final validated = logic.nowDoneSet(yyyymmdd(now));

    final entries = <({
      Activity act,
      int dayDone,
      int? dayTarget,
      int weekDone,
      int weekTarget,
      double score,
      bool passed,
      bool reached,
    })>[];
    for (final a in st.activeActivities) {
      if (!a.isHabit || a.habitFreq == HabitFreq.monthly) continue;
      if (validated.contains(a.id)) continue;
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
      final dt = dayTarget;
      final reached =
          dt != null ? dayDone >= dt : week.done >= week.target;
      entries.add((
        act: a,
        dayDone: dayDone,
        dayTarget: dayTarget,
        weekDone: week.done,
        weekTarget: week.target,
        score: dayRatio > weekRatio ? dayRatio : weekRatio,
        passed: skipped.contains(a.id),
        reached: reached,
      ));
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    // Ordre : à faire (score desc) → passées non atteintes → ATTEINTES.
    // Atteindre la cible ne sort plus la routine (elle descend tout en bas,
    // toujours incrémentable) ; seul ✅ la sort, pour la journée.
    final unreached = entries.where((e) => !e.reached).toList()
      ..sort((x, y) {
        if (x.passed != y.passed) return x.passed ? 1 : -1;
        return x.score == y.score
            ? y.weekDone.compareTo(x.weekDone)
            : y.score.compareTo(x.score);
      });
    final reachedList = entries.where((e) => e.reached).toList()
      ..sort((x, y) => y.score.compareTo(x.score));
    final pending = [...unreached.take(3), ...reachedList];

    return Container(
      margin: const EdgeInsets.only(top: 14),
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
          const SizedBox(height: 8),
          if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 8, 4),
              child: Text('Tout est atteint — rien à rattraper. ✓',
                  style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurface.withOpacity(.55))),
            ),
          for (final e in pending) _tile(cs, e, now),
        ],
      ),
    );
  }

  /// Rangée au style du lanceur de routines (FAB) : carte arrondie, pastille
  /// domaine, nom + série, contrôles ▶/⏱, compteur, − / + — et ⏭ en plus.
  Widget _tile(
      ColorScheme cs,
      ({
        Activity act,
        int dayDone,
        int? dayTarget,
        int weekDone,
        int weekTarget,
        double score,
        bool passed,
        bool reached,
      }) e,
      DateTime now) {
    final r = e.act;
    final dColor = domainColor(r.domainId, logic.state.activeDomains);
    final accent = dColor ?? cs.primary;
    final streak = logic.habitCurrentStreak(r.id);

    // ▶ chrono (activité liée) / ⏱ minuteur (si réglé) — comme le lanceur.
    final linkedId = (r.linkedActivityId ?? '').trim();
    final linked = linkedId.isEmpty
        ? null
        : logic.state.activities.firstWhereOrNull((a) => a.id == linkedId);
    final timerMin = r.timerMin ?? 0;

    return Opacity(
      opacity: e.passed ? .55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withOpacity(.3)),
        ),
        child: Row(
          children: [
            if (dColor != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: dColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
            ] else ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: palierColor((e.score * 100).round()),
                    shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (streak > 0) ...[
                      routineStreakBadge(streak),
                      const SizedBox(width: 6),
                    ],
                    // UNE seule stat (désencombrement) : quotidienne → le
                    // jour tant qu'il n'est pas atteint, puis les 7 j ;
                    // hebdo → toujours les 7 j.
                    Text(
                        e.dayTarget != null && e.dayDone < e.dayTarget!
                            ? 'auj. ${e.dayDone}/${e.dayTarget}'
                            : '7 j ${e.weekDone}/${e.weekTarget}',
                        style: TextStyle(
                            fontSize: 11,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                            color: cs.onSurface.withOpacity(.5))),
                  ]),
                ],
              ),
            ),
            // ▶ chrono libre sur l'activité liée (on est déjà dans Maintenant)
            if (linked != null)
              routineTileButton(
                icon: Icons.play_arrow_rounded,
                tooltip: 'Démarrer le chrono sur « ${linked.name} »',
                color: accent,
                background: accent.withOpacity(.12),
                onTap: () {
                  logic.start(linked.id);
                  logic.rev.value++;
                  setState(() {});
                },
              ),
            // ⏱ minuteur — même flux que le lanceur (routine cochée à la fin)
            if (timerMin > 0 && widget.onStartTimed != null)
              routineTileButton(
                icon: Icons.timer_outlined,
                tooltip: 'Démarrer le minuteur ($timerMin min)',
                color: accent,
                background: accent.withOpacity(.12),
                onTap: () => widget.onStartTimed!(r, timerMin),
              ),
            // − (correction) — grisé quand il n'y a rien à décrémenter
            routineTileButton(
              icon: Icons.remove,
              tooltip: '−1',
              color: cs.onSurface.withOpacity(
                  (e.dayTarget != null ? e.dayDone > 0 : e.weekDone > 0)
                      ? .4
                      : .15),
              background: cs.onSurface.withOpacity(.08),
              onTap: (e.dayTarget != null ? e.dayDone > 0 : e.weekDone > 0)
                  ? () => _decrement(r)
                  : null,
            ),
            // +1 — même mécanique que les compteurs de routine
            routineTileButton(
              icon: Icons.add,
              tooltip: '+1',
              color: accent,
              background: accent.withOpacity(.12),
              onTap: () {
                logic.incHabit(r.id, 1, DateTime.now());
                setState(() {});
              },
            ),
            // ⏭ — UN seul geste de sortie : cible atteinte → sort de la
            // liste pour la journée (vert, annulable en snackbar) ; pas
            // atteinte → recule en fin de liste (↩ pour revenir).
            routineTileButton(
              icon: e.passed && !e.reached
                  ? Icons.undo_rounded
                  : Icons.skip_next_rounded,
              tooltip: e.reached
                  ? 'Fait — sortir de la liste pour aujourd\'hui'
                  : e.passed
                      ? 'Remettre en course'
                      : 'Reculer en fin de liste',
              color: e.reached
                  ? Colors.green.shade500
                  : cs.onSurface.withOpacity(.45),
              background: e.reached
                  ? Colors.green.withOpacity(.14)
                  : cs.onSurface.withOpacity(.08),
              onTap: () => e.reached ? _validate(r) : _togglePasse(r),
            ),
          ],
        ),
      ),
    );
  }
}
