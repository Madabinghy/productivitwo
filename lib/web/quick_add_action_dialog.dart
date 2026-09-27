import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/context_picker.dart';

/// Tâche réceptacle des actions « au fil de l'eau » (même id que le mobile).
const kFlowTaskId = 'gtd-flow';

/// « Définir la prochaine action » d'un projet : dialog titre + contextes,
/// puis ajout dans la tâche « Au fil de l'eau » (créée ou réouverte au
/// besoin) et sauvegarde. Retourne true si une action a été ajoutée.
Future<bool> showQuickAddActionDialog(
  BuildContext context, {
  required Project project,
  required FirestoreSync sync,
}) async {
  final ctrl = TextEditingController();
  var picked = <String>[];
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: const Text('Prochaine action'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(project.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(ctx).colorScheme.onSurface.withOpacity(.55))),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  const InputDecoration(hintText: 'La prochaine action concrète…'),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) Navigator.pop(ctx, true);
              },
            ),
            const SizedBox(height: 12),
            ContextPicker(
              values: picked,
              sync: sync,
              onValuesChanged: (list) => picked = list,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) Navigator.pop(ctx, true);
            },
            child: const Text('Ajouter')),
      ],
    ),
  );
  final title = ctrl.text.trim();
  ctrl.dispose();
  if (saved != true || title.isEmpty) return false;
  var flow = project.tasks.firstWhereOrNull((t) => t.id == kFlowTaskId);
  if (flow == null) {
    flow = ProjectTask(
        id: kFlowTaskId, title: 'Au fil de l\'eau', startDate: DateTime.now());
    project.tasks.add(flow);
  } else if (flow.status != 'pending') {
    flow.status = 'pending';
  }
  flow.actions.add(TaskAction(
    title: title,
    context: picked.isEmpty ? null : picked.first,
    contexts: List.of(picked),
  ));
  await sync.saveProjectTasks(project.id, project.tasks);
  return true;
}
