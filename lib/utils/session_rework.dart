import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';
import 'package:productivitwo_v1/utils/default_estimate.dart';
import 'package:productivitwo_v1/utils/intervention_builder.dart' show prepTitle, sessionTitle, closureTitle;
import 'package:productivitwo_v1/utils/interventions.dart';
import 'package:productivitwo_v1/widgets/session_player_screen.dart' show sessionScriptAction;

/// Retoucher une séance (2026-11-16) : changer ce qu'on y fait sans quitter
/// Cette semaine — son thème, les actions de sa préparation, les étapes de son
/// déroulé. Une ligne garde l'id de ce qu'elle modifie ; sans id, elle est
/// nouvelle ; une ligne absente (ou vidée) retire son action / son étape.
class ReworkLine {
  final String? id;
  final String text;
  const ReworkLine(this.id, this.text);
}

/// Les actions OUVERTES de la préparation, telles qu'on les retouche.
List<ReworkLine> prepLinesOf(Intervention s) => [
      for (final a in s.prep?.actions ?? const <TaskAction>[])
        if (!a.done) ReworkLine(a.id, a.title),
    ];

/// Les étapes pas encore cochées du déroulé de la séance.
List<ReworkLine> stepLinesOf(Intervention s) => [
      for (final c in sessionScriptAction(s.milestone)?.checklist ?? const <ChecklistItem>[])
        if (!c.done) ReworkLine(c.id, c.title),
    ];

/// Applique la retouche aux objets du projet (à enregistrer ensuite par
/// `saveProject`). Le fait reste : une action faite, une étape cochée ne sont
/// jamais touchées. Renvoie true si quelque chose a changé.
bool applySessionRework(Intervention s, {String? title, List<ReworkLine>? prep, List<ReworkLine>? steps}) {
  var changed = false;

  // Le thème : la séance et ses trois tâches portent le même titre.
  final n = s.native;
  final t = (title ?? '').trim();
  if (n != null && t.isNotEmpty && t != n.title) {
    final old = n.title;
    n.title = t;
    for (final task in s.project.tasks) {
      if (task.interventionId != n.id) continue;
      if (task.groupLabel == old) task.groupLabel = t;
      switch (task.interventionRole) {
        case 'prep':
          task.title = prepTitle(t);
        case 'session':
          task.title = sessionTitle(t, n.date);
        case 'closure':
          task.title = closureTitle(t);
      }
    }
    changed = true;
  }

  // La préparation : ses actions ouvertes suivent les lignes.
  final p = s.prep;
  if (p != null && prep != null) {
    final byId = {for (final l in prep) if (l.id != null) l.id!: l.text.trim()};
    final before = p.actions.length;
    p.actions.removeWhere((a) => !a.done && (byId[a.id] ?? '').isEmpty);
    if (p.actions.length != before) changed = true;
    for (final a in p.actions) {
      final text = byId[a.id];
      if (a.done || text == null || text == a.title) continue;
      a.title = text;
      changed = true;
    }
    for (final l in prep) {
      final text = l.text.trim();
      if (l.id != null || text.isEmpty) continue;
      p.actions.add(TaskAction(title: text, estimatedMin: defaultEstimateFor(text)));
      changed = true;
    }
  }

  // Le déroulé : les étapes pas encore cochées suivent les lignes.
  final script = sessionScriptAction(s.milestone);
  if (script != null && steps != null) {
    final byId = {for (final l in steps) if (l.id != null) l.id!: l.text.trim()};
    for (final c in [...script.checklist]) {
      if (c.done) continue;
      final text = byId[c.id] ?? '';
      if (text.isEmpty) {
        removeChecklistItem(script, c.id);
        changed = true;
      } else if (text != c.title) {
        renameChecklistItem(script, c.id, text);
        changed = true;
      }
    }
    for (final l in steps) {
      final text = l.text.trim();
      if (l.id != null || text.isEmpty) continue;
      addChecklistItem(script, text);
      changed = true;
    }
  }
  return changed;
}

/// Les tâches d'une séance (préparation, séance, clôture) : un bloc qui en vise
/// une est un bloc de cette séance.
Set<String> sessionTaskIds(Intervention s) => {s.milestone.id, if (s.prep != null) s.prep!.id, if (s.closure != null) s.closure!.id};
