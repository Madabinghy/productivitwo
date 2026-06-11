import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

String _todayYmd() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// Bascule l'étoile « priorité du jour » d'une tâche ET la programme dans le
/// programme du jour (onglet Maintenant) : étoile ON → demande heure + durée et
/// crée un bloc `project` lié ; étoile OFF → retire le bloc du jour.
/// Renvoie true si quelque chose a changé (false si l'utilisateur annule).
Future<bool> toggleTaskTodayAndSchedule(BuildContext context,
    FirestoreSync sync, Project project, ProjectTask task) async {
  final turningOn = !task.todayFlag;
  final ymd = _todayYmd();
  if (turningOn) {
    final res = await _pickTimeAndDuration(context);
    if (res == null) return false; // annulé → étoile inchangée, rien de programmé
    task.todayFlag = true; // maj immédiate de l'objet (UI appelante)
    await sync.toggleTaskTodayFlag(project.id, task.id, true);
    await sync.addScheduleBlock(
        ymd,
        ScheduleBlock(
          startTime: res.$1,
          durationMin: res.$2,
          title: task.title,
          category: 'project',
          projectId: project.id,
          taskId: task.id,
        ));
    return true;
  }
  task.todayFlag = false;
  await sync.toggleTaskTodayFlag(project.id, task.id, false);
  await sync.removeTaskScheduleBlocks(ymd, project.id, task.id);
  return true;
}

Future<(String, int)?> _pickTimeAndDuration(BuildContext context) {
  TimeOfDay time = TimeOfDay.now();
  int duration = 60;
  const durations = [30, 60, 90, 120];
  return showModalBottomSheet<(String, int)>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return StatefulBuilder(builder: (ctx, setSheet) {
        String hhmm() =>
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Programmer dans Aujourd\'hui',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                Row(children: [
                  Icon(Icons.schedule_rounded,
                      size: 18, color: cs.onSurface.withOpacity(.6)),
                  const SizedBox(width: 8),
                  Text('Début : ${hhmm()}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final t =
                          await showTimePicker(context: ctx, initialTime: time);
                      if (t != null) setSheet(() => time = t);
                    },
                    child: const Text('Modifier'),
                  ),
                ]),
                const SizedBox(height: 8),
                Text('Durée',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(.8))),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final d in durations)
                    ChoiceChip(
                      label: Text('$d min'),
                      selected: duration == d,
                      onSelected: (_) => setSheet(() => duration = d),
                    ),
                ]),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, (hhmm(), duration)),
                    icon: const Icon(Icons.event_available_rounded),
                    label: const Text('Programmer'),
                  ),
                ),
              ],
            ),
          ),
        );
      });
    },
  );
}
