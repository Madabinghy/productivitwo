import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routine_match.dart';

// ─── SUGGESTIONS DE LIEN À LA SAISIE (ajout de bloc) ─────────────────────────
//
// Le user tape le titre d'un nouveau bloc : on lui propose ce qui existe déjà
// (routines, activités, tâches Gantt, actions) — un tap = le bloc naît LIÉ au
// bon objet (activityId / projectId+taskId / actionId) au lieu de compter sur
// le match par titre après coup. Déterministe, insensible casse/accents. 0 LLM.

class ScheduleSuggestion {
  final String title; // titre posé sur le bloc
  final String sublabel; // « Routine », « Projet · X », « Étape · Y »…
  final String kind; // routine | activity | task | action
  final String category; // catégorie du bloc créé
  final String? activityId;
  final String? projectId;
  final String? taskId;
  final String? actionId;
  final int? durationMin; // durée suggérée (minuteur de la routine/activité)

  const ScheduleSuggestion({
    required this.title,
    required this.sublabel,
    required this.kind,
    required this.category,
    this.activityId,
    this.projectId,
    this.taskId,
    this.actionId,
    this.durationMin,
  });
}

/// Tout ce qui correspond à [query] (≥ 2 caractères), préfixe d'abord puis
/// occurrence, routines/activités avant tâches avant actions, [max] résultats.
List<ScheduleSuggestion> scheduleSuggestions(
  String query, {
  required List<Activity> activities,
  required List<Project> projects,
  int max = 6,
}) {
  final q = foldName(query.trim());
  if (q.length < 2) return const [];

  // rank 0 = préfixe, 1 = occurrence ; groupe : routines/activités < tâches
  // < actions ; à rang et groupe égaux, l'ordre de déclaration départage
  // (List.sort n'est pas stable → l'index d'insertion l'impose).
  final scored = <({ScheduleSuggestion s, int rank, int group, int idx})>[];

  void add(ScheduleSuggestion s, String name, int group) {
    final f = foldName(name);
    if (!f.contains(q)) return;
    scored.add(
        (s: s, rank: f.startsWith(q) ? 0 : 1, group: group, idx: scored.length));
  }

  for (final a in activities) {
    if (a.deleted) continue;
    add(
        ScheduleSuggestion(
          title: a.name,
          sublabel: a.isHabit ? 'Routine' : 'Activité',
          kind: a.isHabit ? 'routine' : 'activity',
          category: a.isHabit ? 'routine' : 'personal',
          activityId: a.id,
          durationMin: (a.timerMin ?? 0) > 0 ? a.timerMin : null,
        ),
        a.name,
        0);
    // Actions propres d'une activité-temps → chrono ciblé (Session.actionId).
    for (final act in a.ownActions) {
      if (act.done) continue;
      add(
          ScheduleSuggestion(
            title: act.title,
            sublabel: 'Action · ${a.name}',
            kind: 'action',
            category: 'personal',
            activityId: a.id,
            actionId: act.id,
          ),
          act.title,
          2);
    }
  }

  for (final p in projects) {
    if (p.status != 'active' && p.status != 'draft') continue;
    for (final t in p.tasks) {
      if (t.status == 'done') continue;
      add(
          ScheduleSuggestion(
            title: t.title,
            sublabel: 'Projet · ${p.title}',
            kind: 'task',
            category: 'project',
            projectId: p.id,
            taskId: t.id,
          ),
          t.title,
          1);
      for (final act in t.actions) {
        if (act.done) continue;
        add(
            ScheduleSuggestion(
              title: act.title,
              sublabel: 'Étape · ${t.title}',
              kind: 'action',
              category: 'project',
              projectId: p.id,
              taskId: t.id,
              actionId: act.id,
            ),
            act.title,
            2);
      }
    }
  }

  scored.sort((a, b) {
    if (a.rank != b.rank) return a.rank.compareTo(b.rank);
    if (a.group != b.group) return a.group.compareTo(b.group);
    return a.idx.compareTo(b.idx);
  });
  return [for (final e in scored.take(max)) e.s];
}
