import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';

/// Carte « état des lieux » de l'onglet Maintenant : le contexte de ce qu'on
/// s'apprête à faire (ou de ce qui tourne) — les chiffres de la routine /
/// activité / action visée, et une phrase d'encouragement DÉTERMINISTE
/// (état des lieux, jamais de morale — posture produit).
///
/// Sources : bloc du programme (à venir ou en cours) OU activité du chrono.
/// Tout est calculé depuis l'état local — aucun appel réseau.
class NowContextCard extends StatelessWidget {
  final AppLogic logic;

  /// Mode « bloc du programme » (Maintenant au repos).
  final ScheduleBlock? block;

  /// Mode « chrono en cours » : l'activité qui tourne (+ action ciblée).
  final Activity? runningActivity;
  final String? runningActionId;

  const NowContextCard({
    super.key,
    required this.logic,
    this.block,
    this.runningActivity,
    this.runningActionId,
  });

  AppState get _state => logic.state;

  Activity? get _activity {
    if (runningActivity != null) return runningActivity;
    final id = block?.activityId;
    if (id == null) return null;
    return _state.activities.firstWhereOrNull((a) => a.id == id && !a.deleted);
  }

  Project? get _project {
    final id = block?.projectId;
    if (id == null) return null;
    return logic.currentProjects.firstWhereOrNull((p) => p.id == id);
  }

  /// Action ciblée : sous-action de tâche (projectId+taskId) ou action propre.
  ({TaskAction action, ProjectTask? task})? get _action {
    final actionId = runningActionId ?? block?.actionId;
    if (actionId == null) return null;
    final p = _project;
    final taskId = block?.taskId;
    if (p != null && taskId != null) {
      final t = p.tasks.firstWhereOrNull((t) => t.id == taskId);
      final a = t?.actions.firstWhereOrNull((a) => a.id == actionId);
      if (t != null && a != null) return (action: a, task: t);
    }
    final own = logic.ownActionById(actionId);
    if (own != null) return (action: own.action, task: null);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final act = _activity;
    final action = _action;
    final project = _project;

    // Rien de rattaché (bloc perso/pause sans source) → pas de carte.
    if (act == null && action == null && project == null) {
      return const SizedBox.shrink();
    }

    final color = domainColor(
            act?.domainId ?? project?.domainId, _state.activeDomains) ??
        cs.primary;

    String? statLine;
    String message;
    int? pct; // couleur du chiffre au palier si pertinent

    if (act != null && act.isHabit) {
      // ── Routine : x/y sur 7 jours glissants ──────────────────────────────
      final stat = rollingStatFor(act, _state.habitHits);
      final last = lastHitOf(act.id, _state.habitHits);
      final done = stat?.done ?? 0;
      final target = stat?.target ?? 1;
      pct = ((done / target).clamp(0.0, 1.0) * 100).round();
      statLine = '$done / $target sur 7 jours';
      if (last == null) {
        message = 'Première fois — pose la première pierre, le reste suivra.';
      } else if (done >= target) {
        message = 'Tenue. Celle-ci consolide — rien à rattraper.';
      } else if (done > 0) {
        message = 'Celle-ci te rapproche du compte.';
      } else {
        final n = DateTime.now().difference(last).inDays;
        message = n <= 1
            ? 'La refaire aujourd\'hui, c\'est garder le fil.'
            : 'Pas cochée depuis $n jours. La faire maintenant, c\'est la '
                'relancer — sans dette.';
      }
    } else if (act != null) {
      // ── Activité-temps : minutes sur 7 jours ─────────────────────────────
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));
      var min7 = 0;
      DateTime? lastSession;
      for (final s in _state.sessions) {
        if (s.activityId != act.id) continue;
        if (lastSession == null || s.startAt.isAfter(lastSession)) {
          lastSession = s.startAt;
        }
        final end = s.endAt;
        if (end == null || s.startAt.isBefore(weekAgo)) continue;
        min7 += end.difference(s.startAt).inMinutes;
      }
      statLine = min7 >= 60
          ? '${min7 ~/ 60} h ${(min7 % 60).toString().padLeft(2, '0')} sur 7 jours'
          : '$min7 min sur 7 jours';
      if (min7 == 0) {
        message = lastSession == null
            ? 'Premier chrono sur « ${act.name} » — même 15 minutes comptent.'
            : 'Rien de loggé cette semaine — cette session rouvre le compteur.';
      } else {
        message = 'La régularité bat l\'intensité — cette session s\'ajoute '
            'au réel.';
      }
    } else {
      statLine = null;
      message = '';
    }

    // ── Action ciblée : ancienneté + reste à faire ─────────────────────────
    String? actionLine;
    if (action != null) {
      final age = DateTime.now().difference(action.action.createdAt).inDays;
      final parts = <String>[
        if (age >= 1) 'dans ta liste depuis $age j',
        if (action.task != null)
          () {
            final left =
                action.task!.actions.where((a) => !a.done).length;
            return left <= 1
                ? 'dernière action de « ${action.task!.title} »'
                : 'encore $left actions dans « ${action.task!.title} »';
          }(),
      ];
      actionLine = parts.isEmpty ? null : parts.join(' · ');
      if (message.isEmpty) {
        message = project != null
            ? 'Celle-ci fait avancer « ${project.title} » — concrètement.'
            : 'Une action cochée vaut mieux qu\'un plan parfait.';
      }
    } else if (project != null && message.isEmpty) {
      message = 'Un pas de plus sur « ${project.title} ».';
    }

    if (statLine == null && actionLine == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('ÉTAT DES LIEUX',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .9,
                    color: cs.onSurface.withOpacity(.4))),
          ]),
          const SizedBox(height: 5),
          if (statLine != null)
            Text(statLine,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: pct != null ? palierColor(pct) : cs.onSurface)),
          if (actionLine != null)
            Padding(
              padding: EdgeInsets.only(top: statLine != null ? 2 : 0),
              child: Text(actionLine,
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withOpacity(.6))),
            ),
          if (message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(message,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurface.withOpacity(.65))),
            ),
        ],
      ),
    );
  }
}
