import 'dart:convert';

import 'package:productivitwo_v1/models.dart';

// Sauvegarde d'un projet SANS écraser ce qui a changé ailleurs (2026-10).
// Chaque tâche chargée garde l'empreinte de sa version au chargement ; à la
// sauvegarde, on relit le serveur et on fusionne à trois voies, tâche par
// tâche : modifiée ici → version locale ; inchangée ici → version serveur
// (modifiée ailleurs ou non) ; ajoutée ailleurs → conservée ; supprimée ici
// (connue au chargement, absente de la liste locale) → retirée.
// Même principe pour les champs du projet (titre, statut, phases…).

final _taskBase = Expando<String>('taskBase');
final _knownIds = Expando<Set<String>>('knownTaskIds');
final _fieldBase = Expando<Map<String, String>>('projectFieldBase');

String _sig(Object? v) => jsonEncode(v);

/// À appeler sur tout projet lu depuis Firestore.
void markProjectLoaded(Project p) {
  final json = p.toJson();
  _fieldBase[p] = {
    for (final e in json.entries)
      if (e.key != 'tasks') e.key: _sig(e.value),
  };
  markTasksSaved(p.tasks);
}

/// La liste [tasks] et ses tâches reflètent maintenant le serveur.
void markTasksSaved(List<ProjectTask> tasks) {
  for (final t in tasks) {
    _taskBase[t] = _sig(t.toJson());
  }
  _knownIds[tasks] = {for (final t in tasks) t.id};
}

void markTaskSaved(ProjectTask t) => _taskBase[t] = _sig(t.toJson());

/// Empreinte explicite (vue fusionnée : la forme écrite dans le sous-projet).
void setTaskBase(ProjectTask t, Map<String, dynamic> json) => _taskBase[t] = _sig(json);

/// Une copie (vue fusionnée d'un dossier) hérite de l'empreinte de l'original.
void copyTaskBase(ProjectTask from, ProjectTask to) {
  final b = _taskBase[from];
  if (b != null) _taskBase[to] = b;
}

String? taskBaseOf(ProjectTask t) => _taskBase[t];
Set<String>? knownTaskIdsOf(List<ProjectTask> tasks) => _knownIds[tasks];
void setKnownTaskIds(List<ProjectTask> tasks, Set<String> ids) => _knownIds[tasks] = ids;

/// Vrai si [t] a changé localement depuis son chargement (ou est nouvelle).
bool taskChangedLocally(ProjectTask t, [Map<String, dynamic>? json]) {
  final b = _taskBase[t];
  return b == null || b != _sig(json ?? t.toJson());
}

/// Fusion pure des tâches. [local] dans l'ordre local ; [changed] dit si une
/// tâche locale a été modifiée ici ; [known] = ids connus au chargement de la
/// liste locale (null = inconnu : comportement historique, la liste locale
/// fait foi pour les présences).
List<Map<String, dynamic>> mergeTaskLists({
  required List server,
  required List<Map<String, dynamic>> local,
  required bool Function(String id) changed,
  Set<String>? known,
}) {
  final serverById = <String, Map<String, dynamic>>{};
  final serverOrder = <String>[];
  for (final raw in server) {
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    final id = m['id'] as String?;
    if (id == null) continue;
    serverById[id] = m;
    serverOrder.add(id);
  }
  final out = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final l in local) {
    final id = l['id'] as String;
    seen.add(id);
    final s = serverById[id];
    if (changed(id) || known == null) {
      out.add(l);
    } else if (s != null) {
      out.add(s);
    }
    // inchangée ici et supprimée ailleurs : on ne la ressuscite pas.
  }
  if (known != null) {
    for (final id in serverOrder) {
      if (seen.contains(id) || known.contains(id)) continue;
      out.add(serverById[id]!); // ajoutée ailleurs
    }
  }
  return out;
}

/// Fusion pure des champs du projet (hors `tasks`) : un champ modifié ici
/// (empreinte différente de celle du chargement) prend la valeur locale,
/// sinon la valeur serveur ; [base] null = la version locale fait foi.
Map<String, dynamic> mergeProjectFields({
  required Map server,
  required Map<String, dynamic> local,
  Map<String, String>? base,
}) {
  final out = <String, dynamic>{...Map<String, dynamic>.from(server)};
  for (final e in local.entries) {
    if (e.key == 'tasks') continue;
    final changedHere = base == null || base[e.key] != _sig(e.value);
    if (changedHere || !server.containsKey(e.key)) out[e.key] = e.value;
  }
  return out;
}

Map<String, String>? projectFieldBaseOf(Project p) => _fieldBase[p];
void markProjectFieldsSaved(Project p) => _fieldBase[p] = {
      for (final e in p.toJson().entries)
        if (e.key != 'tasks') e.key: _sig(e.value),
    };
