// Écritures ciblées d'un projet (2026-10). Avant, cocher une action réécrivait
// tout le tableau `tasks` depuis la copie locale : un onglet web resté ouvert
// effaçait ce qui avait été modifié ailleurs (MCP, mobile) — perte réelle sur
// « 6e — Mathématiques ». Ces fonctions s'appliquent au tableau RELU sur le
// serveur et ne touchent qu'une action ou que quelques champs d'une tâche.

List<Map<String, dynamic>> _copy(List raw) =>
    [for (final t in raw) Map<String, dynamic>.from(t as Map)];

/// Remplace dans la tâche [taskId] l'action de même id par [action] (forme
/// JSON). Action ancienne en simple texte : reconnue par son titre. Action
/// absente côté serveur (ajoutée ici) : ajoutée en fin. Null si la tâche
/// n'existe plus côté serveur (rien à écrire).
List<Map<String, dynamic>>? replaceActionIn(
    List raw, String taskId, Map<String, dynamic> action) {
  final tasks = _copy(raw);
  final i = tasks.indexWhere((t) => t['id'] == taskId);
  if (i == -1) return null;
  final actions = List<dynamic>.from(tasks[i]['actions'] as List? ?? const []);
  var j = actions.indexWhere((a) => a is Map && a['id'] == action['id']);
  if (j == -1) {
    final title = action['title'];
    j = actions.indexWhere((a) => a is String ? a == title : (a is Map && a['title'] == title && a['id'] == null));
  }
  if (j == -1) {
    actions.add(action);
  } else {
    actions[j] = action;
  }
  tasks[i] = {...tasks[i], 'actions': actions};
  return tasks;
}

/// Copie dans la tâche [taskId] les seuls champs [fields] (forme JSON). Null
/// si la tâche n'existe plus côté serveur.
List<Map<String, dynamic>>? patchTaskFieldsIn(
    List raw, String taskId, Map<String, dynamic> fields) {
  final tasks = _copy(raw);
  final i = tasks.indexWhere((t) => t['id'] == taskId);
  if (i == -1) return null;
  tasks[i] = {...tasks[i], ...fields};
  return tasks;
}
