import 'package:productivitwo_v1/models.dart';

/// Le bloc [base] retouché par « Modifier le bloc » : la feuille ne règle que
/// l'heure, la durée, le titre, la catégorie, le mode et ce que le bloc vise.
/// Tout le reste est GARDÉ — le lien avec Google Agenda, le doc qui porte un
/// bloc de la nuit, les rappels, l'origine d'un report… (bug user 2026-11-21 :
/// la feuille reconstruisait le bloc, un rendez-vous d'agenda y perdait son lien).
/// Changer de projet lâche les cibles suivantes, qui étaient celles de l'ancien.
ScheduleBlock editedBlock(
  ScheduleBlock base, {
  required String startTime,
  required int durationMin,
  required String title,
  required String category,
  String? projectId,
  String? taskId,
  String? activityId,
  String? actionId,
  String? timeBlock,
}) {
  final j = Map<String, dynamic>.from(base.toJson())
    ..['startTime'] = startTime
    ..['durationMin'] = durationMin
    ..['title'] = title
    ..['category'] = category
    ..['projectId'] = projectId
    ..['taskId'] = taskId
    ..['activityId'] = activityId
    ..['actionId'] = actionId
    ..['timeBlock'] = timeBlock;
  if (projectId != base.projectId) j.remove('extraTargets');
  return ScheduleBlock.from(j)
    ..docDate = base.docDate
    ..dayOffset = base.dayOffset;
}
