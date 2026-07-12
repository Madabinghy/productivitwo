import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coach_moments.dart' show streakOf;

// ─── GUIDE DU MOMENT LIBRE ───────────────────────────────────────────────────
//
// « Rien de prévu pour le moment » n'est pas une impasse : le coach ramène au
// présent et guide vers l'action. D'abord l'intention (« Que souhaites-tu
// faire ? » — dormir, me poser, un projet, mes routines, planifier), puis des
// PROPOSITIONS tirées des vraies données : tâches Gantt par deadline, routines
// non faites avec l'intention de leur domaine, preps du soir. Fonctions pures,
// testables. 0 LLM — le champ libre reste le fallback.

enum FreeIntent { sleep, rest, project, routines, plan }

/// Les intentions proposées, fenêtrées par l'heure : « Dormir » n'existe que
/// le soir (20 h → 5 h) ; l'ordre met la plus probable en premier.
List<FreeIntent> freeIntentsFor(DateTime now) {
  final evening = now.hour >= 20 || now.hour < 5;
  return [
    if (evening) FreeIntent.sleep,
    if (evening) FreeIntent.rest else FreeIntent.project,
    if (evening) FreeIntent.project else FreeIntent.routines,
    if (evening) FreeIntent.routines else FreeIntent.rest,
    FreeIntent.plan,
  ];
}

String freeIntentLabel(FreeIntent i) => switch (i) {
      FreeIntent.sleep => 'Dormir',
      FreeIntent.rest => 'Me poser',
      FreeIntent.project => 'Avancer un projet',
      FreeIntent.routines => 'Mes routines',
      FreeIntent.plan => 'Planifier',
    };

/// Une tâche Gantt proposable maintenant — la plus urgente d'abord.
class TaskProposal {
  final Project project;
  final ProjectTask task;
  final String subtitle; // provenance réelle : deadline / retard / priorité

  const TaskProposal(
      {required this.project, required this.task, required this.subtitle});
}

/// Tâches ouvertes triées : en retard d'abord, puis deadline la plus proche,
/// puis priorités du jour, puis le reste. Jamais plus de [max].
List<TaskProposal> projectProposals(
  DateTime now,
  List<Project> projects, {
  int max = 3,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final entries = <({Project p, ProjectTask t, int rank, DateTime? end})>[];
  for (final p in projects) {
    for (final t in p.tasks) {
      if (t.status == 'done' || t.status == 'skipped' || t.isMilestone) {
        continue;
      }
      final end = t.endDate;
      final overdue = end != null && end.isBefore(today);
      final rank = overdue
          ? 0
          : t.todayFlag
              ? 1
              : end != null
                  ? 2
                  : 3;
      entries.add((p: p, t: t, rank: rank, end: end));
    }
  }
  entries.sort((a, b) {
    if (a.rank != b.rank) return a.rank.compareTo(b.rank);
    if (a.end != null && b.end != null) return a.end!.compareTo(b.end!);
    return a.end != null ? -1 : (b.end != null ? 1 : 0);
  });

  String fr(DateTime d) {
    const months = [
      'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
      'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  return [
    for (final e in entries.take(max))
      TaskProposal(
        project: e.p,
        task: e.t,
        subtitle: e.end != null
            ? (e.end!.isBefore(today)
                ? '${e.p.title} · en retard (deadline ${fr(e.end!)})'
                : '${e.p.title} · deadline ${fr(e.end!)}')
            : e.t.todayFlag
                ? '${e.p.title} · priorité du jour'
                : e.p.title,
      ),
  ];
}

/// Une routine du jour pas encore tenue — avec l'intention de son domaine
/// quand elle existe (jamais inventée), et l'élan en cours (série de jours).
/// [undefinedDomain] = nom du domaine si la routine appartient à un domaine
/// qui existe mais n'est pas encore défini — le guide propose alors un lien
/// discret « définir ce domaine ».
class RoutineProposal {
  final Activity routine;
  final String? subtitle;
  final String? undefinedDomain;

  const RoutineProposal(
      {required this.routine, this.subtitle, this.undefinedDomain});
}

/// Routines quotidiennes non tenues, dans l'ordre de l'utilisateur.
/// [routineDone] vient de l'appelant (logic.habitReached) — la fonction reste
/// pure et testable. Avec [now], le sous-titre porte aussi l'élan réel
/// (« 4 j d'affilée — on continue ? », série ≥ 3 uniquement).
List<RoutineProposal> routineProposals(
  AppState st,
  bool Function(Activity) routineDone, {
  int max = 4,
  DateTime? now,
}) {
  final routines = st.activities
      .where((a) => !a.deleted && a.isHabit && !routineDone(a))
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));

  Domain? domainOf(Activity a) {
    for (final d in st.domains) {
      if (!d.deleted && d.id == a.domainId) return d;
    }
    return null;
  }

  return [
    for (final a in routines.take(max))
      () {
        final d = domainOf(a);
        final i = d?.intention;
        final streak = now != null ? streakOf(a.id, st.habitHits, now) : 0;
        final parts = <String>[
          if (d != null && d.isDefined && i != null && i.isNotEmpty)
            '${d.name} — « $i »',
          if (streak >= 3) '$streak j d\'affilée — on continue ?',
        ];
        return RoutineProposal(
          routine: a,
          subtitle: parts.isEmpty ? null : parts.join(' · '),
          undefinedDomain: d != null && !d.isDefined ? d.name : null,
        );
      }(),
  ];
}
