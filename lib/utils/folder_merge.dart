import 'package:collection/collection.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart';

/// Projet « dossier » (client) : un projet sans tâche dont d'autres projets
/// dépendent (`parentProjectId`). Sa fiche montre une VUE FUSIONNÉE de ses
/// sous-projets — une section par sous-projet (les sous-projets jouent le
/// rôle des phases), toutes leurs tâches — et chaque écriture est répartie
/// vers le bon sous-projet : le dossier lui-même ne porte jamais de tâche.

class MergedFolder {
  /// Vue fusionnée : même id que le dossier, phases = sous-projets, tâches =
  /// copies des tâches des sous-projets (phaseId = id du sous-projet).
  final Project view;
  final List<Project> children;
  /// Tâche → sous-projet d'origine.
  final Map<String, String> originProject;
  /// Tâche → phaseId d'origine dans son sous-projet.
  final Map<String, String?> originPhase;
  const MergedFolder({
    required this.view,
    required this.children,
    required this.originProject,
    required this.originPhase,
  });

  bool get isEmpty => children.isEmpty;
  Set<String> get childIds => {for (final c in children) c.id};
}

bool isFolder(Project p, List<Project> all) => isFolderProject(p, all);

/// Sous-projets directs non archivés, les actifs d'abord, puis par titre.
List<Project> folderChildren(Project folder, List<Project> all) {
  final kids = all.where((p) => p.parentProjectId == folder.id && p.status != 'archived').toList();
  kids.sort((a, b) {
    final pa = a.paused ? 1 : 0, pb = b.paused ? 1 : 0;
    if (pa != pb) return pa.compareTo(pb);
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return kids;
}

MergedFolder mergeFolder(Project folder, List<Project> all) {
  final children = folderChildren(folder, all);
  final phases = <ProjectPhase>[];
  final tasks = <ProjectTask>[];
  final originProject = <String, String>{};
  final originPhase = <String, String?>{};
  DateTime? start, end;
  for (final c in children) {
    final cEnd = c.endDate ??
        c.tasks.map((t) => t.endDate ?? t.startDate).fold<DateTime?>(null, (m, d) => m == null || d.isAfter(m) ? d : m) ??
        c.startDate;
    phases.add(ProjectPhase(id: c.id, label: c.title, startDate: c.startDate, endDate: cEnd));
    if (start == null || c.startDate.isBefore(start)) start = c.startDate;
    if (end == null || cEnd.isAfter(end)) end = cEnd;
    for (final t in c.tasks) {
      final copy = ProjectTask.from(t.toJson())..phaseId = c.id;
      tasks.add(copy);
      originProject[t.id] = c.id;
      originPhase[t.id] = t.phaseId;
    }
  }
  final view = Project.from(folder.toJson())
    ..phases = phases
    ..tasks = tasks;
  if (start != null) view.startDate = start;
  if (end != null) view.endDate = folder.endDate ?? end;
  return MergedFolder(
      view: view, children: children, originProject: originProject, originPhase: originPhase);
}

/// Répartit les tâches de la vue fusionnée vers les sous-projets, phaseId
/// d'origine restauré. Une tâche déplacée vers une autre section change de
/// sous-projet (sans phase) ; une tâche nouvelle va dans la section où elle
/// a été créée, sinon dans le premier sous-projet.
Map<String, List<ProjectTask>> splitMergedTasks(MergedFolder m, List<ProjectTask> merged) {
  final out = <String, List<ProjectTask>>{for (final c in m.children) c.id: <ProjectTask>[]};
  if (m.children.isEmpty) return out;
  final ids = m.childIds;
  for (final t in merged) {
    final origin = m.originProject[t.id];
    final section = ids.contains(t.phaseId) ? t.phaseId : null;
    final target = section ?? origin ?? m.children.first.id;
    final copy = ProjectTask.from(t.toJson())
      ..phaseId = (origin != null && target == origin) ? m.originPhase[t.id] : null;
    out[target]!.add(copy);
  }
  return out;
}

/// Dossiers actuellement affichés : `FirestoreSync` y répartit les écritures
/// faites sur la vue fusionnée (id du dossier) vers les sous-projets.
final Map<String, MergedFolder> openMergedFolders = {};

MergedFolder? mergedFolderFor(String projectId) => openMergedFolders[projectId];

/// Première tâche ouverte d'un sous-projet (pour « prochaine action »).
Project? childOfTask(MergedFolder m, String taskId) =>
    m.children.firstWhereOrNull((c) => c.id == m.originProject[taskId]);
