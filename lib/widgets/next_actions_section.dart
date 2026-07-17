import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/context_picker.dart';
import 'package:productivitwo_v1/widgets/new_project_sheet.dart';

// L'ancien widget NextActionsSection (section « Prochaines actions » de
// l'onglet Aujourd'hui) a été retiré : le canal pull GTD vit en entier dans
// l'onglet Actions. Ce fichier ne garde que la sheet « Créer » partagée.

/// Sheet « Créer » (onglet Actions) : action simple (ownAction d'une
/// activité, avec contextes GTD multi) ou nouveau projet (flux déterministe).
Future<void> showCreateActionOrProjectSheet(
  BuildContext context, {
  required AppLogic logic,
  required FirestoreSync sync,
  VoidCallback? onCreated,
}) async {
  final titleCtrl = TextEditingController();
  var pickedContexts = <String>[];
  String mode = 'action'; // 'action' | 'project'
  String? activityId;
  final timeActivities =
      logic.state.activeActivities.where((a) => a.type == 'time').toList();
  if (timeActivities.isNotEmpty) activityId = timeActivities.first.id;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(
      // Scrollable : quand le clavier est ouvert, le bouton « Créer » reste
      // atteignable (le viewInset pousse le contenu, le scroll fait le reste).
      builder: (ctx, setLocal) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Créer',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'action',
                    label: Text('Action simple'),
                    icon: Icon(Icons.bolt, size: 16)),
                ButtonSegment(
                    value: 'project',
                    label: Text('Nouveau projet'),
                    icon: Icon(Icons.flag, size: 16)),
              ],
              selected: {mode},
              onSelectionChanged: (s) => setLocal(() => mode = s.first),
            ),
            const SizedBox(height: 14),
            if (mode == 'project')
              Text(
                'Nom, échéance, première action — dans la fiche qui suit.',
                style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(ctx).colorScheme.onSurface
                        .withOpacity(.55)),
              )
            else ...[
              TextField(
                controller: titleCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Ex : Réserver le contrôle technique',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ContextPicker(
                values: pickedContexts,
                sync: sync,
                onValuesChanged: (list) =>
                    setLocal(() => pickedContexts = list),
              ),
              if (timeActivities.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('SUR L\'ACTIVITÉ',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: Theme.of(ctx).colorScheme.onSurface
                            .withOpacity(.45))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in timeActivities)
                      ChoiceChip(
                        selected: activityId == a.id,
                        onSelected: (_) =>
                            setLocal(() => activityId = a.id),
                        showCheckmark: false,
                        label: Text(a.name),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Crée d\'abord une activité-temps pour porter tes actions simples.',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(ctx).colorScheme.onSurface
                            .withOpacity(.55)),
                  ),
                ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  if (mode == 'project') {
                    Navigator.pop(ctx);
                    await showNewProjectSheet(
                      context,
                      domains: logic.state.activeDomains,
                      sync: sync,
                      onCreated: () => onCreated?.call(),
                    );
                    return;
                  }
                  final title = titleCtrl.text.trim();
                  final actId = activityId;
                  if (title.isEmpty || actId == null) return;
                  await sync.addOwnActionToActivity(actId, title,
                      contexts: pickedContexts);
                  // Reflète immédiatement dans l'état local (le doc Firestore
                  // est la source ; le prochain pull réconciliera par ID).
                  final act = logic.state.activities
                      .where((a) => a.id == actId)
                      .firstOrNull;
                  act?.ownActions.add(TaskAction(
                      title: title,
                      linkedActivityId: actId,
                      context: pickedContexts.isEmpty
                          ? null
                          : pickedContexts.first,
                      contexts: List.of(pickedContexts)));
                  logic.onChange();
                  if (ctx.mounted) Navigator.pop(ctx);
                  onCreated?.call();
                },
                child: Text(mode == 'project'
                    ? 'Continuer'
                    : 'Créer l\'action'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  titleCtrl.dispose();
}
