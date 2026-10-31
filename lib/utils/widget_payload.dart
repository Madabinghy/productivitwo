import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/block_work.dart';

/// Widgets iOS (refonte 2026-10-31, maquette « Widgets revus ») : ce que
/// l'app calcule pour l'écran d'accueil, en données plates. Le widget ne
/// recalcule rien, sauf le bloc en cours, qu'il retrouve d'après les heures
/// (`startMs` / `endMs`) pour basculer sans que l'app soit ouverte.

/// Début d'un bloc en heure locale : jour de son doc (la nuit après minuit
/// appartient au doc du lendemain) + `startTime`.
DateTime blockStartAt(ScheduleBlock b, DateTime livedDay) {
  final p = b.startTime.split(':');
  final h = int.tryParse(p.first) ?? 0;
  final m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
  return DateTime(livedDay.year, livedDay.month, livedDay.day + (b.dayOffset), h, m);
}

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Un bloc du programme pour le widget : heures, titre, et pour un bloc de
/// tâche l'action visée avec son étape en cours (« Étape faite » depuis le widget).
Map<String, dynamic> widgetBlock(ScheduleBlock b, DateTime livedDay, String docYmd, List<Project> projects) {
  final start = blockStartAt(b, livedDay);
  final end = start.add(Duration(minutes: b.durationMin));
  String? ctx, action, step, itemId, actionId;
  int stepIdx = 0, stepTotal = 0;
  if (b.projectId != null && b.taskId != null) {
    final p = projects.where((x) => x.id == b.projectId).firstOrNull;
    final t = p?.tasks.where((x) => x.id == b.taskId).firstOrNull;
    if (p != null && t != null) {
      ctx = '${p.title} › ${t.title}';
      final f = blockWork(t, b.actionId).focus;
      if (f != null) {
        action = f.title;
        actionId = f.id;
        stepTotal = f.checklist.length;
        final i = f.checklist.indexWhere((c) => !c.done);
        if (i >= 0) {
          stepIdx = i + 1;
          step = f.checklist[i].title;
          itemId = f.checklist[i].id;
        } else {
          stepIdx = stepTotal;
        }
      }
    }
  }
  return {
    'id': b.id,
    'doc': docYmd,
    'startMs': start.millisecondsSinceEpoch,
    'endMs': end.millisecondsSinceEpoch,
    'time': _hm(start),
    'end': _hm(end),
    'title': b.title.isEmpty ? 'Bloc' : b.title,
    'status': b.status,
    'mirror': b.gcalEventId != null,
    if (ctx != null) 'ctx': ctx,
    if (action != null) 'action': action,
    if (step != null) 'step': step,
    if (stepTotal > 0) 'stepIdx': stepIdx,
    if (stepTotal > 0) 'stepTotal': stepTotal,
    if (b.projectId != null) 'projectId': b.projectId,
    if (b.taskId != null) 'taskId': b.taskId,
    if (actionId != null) 'actionId': actionId,
    if (itemId != null) 'itemId': itemId,
  };
}

/// Cases de la journée parfaite (une par chose à tenir, 12 au plus), pleines
/// si tenues — même découpe que la tuile d'Aujourd'hui.
List<bool> perfectCells(int done, int total, {int cap = 12}) {
  if (total <= 0) return const [];
  final cells = total <= cap ? total : cap;
  final filled = (done * cells / total).floor();
  return [for (var i = 0; i < cells; i++) i < filled];
}
