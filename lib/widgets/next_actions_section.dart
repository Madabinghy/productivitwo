import 'dart:async';

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
  String? activityId;
  final timeActivities =
      logic.state.activeActivities.where((a) => a.type == 'time').toList();
  if (timeActivities.isNotEmpty) activityId = timeActivities.first.id;
  // « Sur l'activité » groupé PAR DOMAINE — plus lisible qu'une nappe de chips.
  final domains = logic.state.activeDomains;
  final actGroups = <({String label, List<Activity> acts})>[];
  for (final d in domains) {
    final acts = timeActivities.where((a) => a.domainId == d.id).toList();
    if (acts.isNotEmpty) actGroups.add((label: d.name, acts: acts));
  }
  final orphans = timeActivities
      .where((a) => domains.every((d) => d.id != a.domainId))
      .toList();
  if (orphans.isNotEmpty) actGroups.add((label: 'Autres', acts: orphans));

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // La poignée rend le tirer-vers-le-bas évident (comme la sheet projet).
    showDragHandle: true,
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
            Row(children: [
              const Text('Créer',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                tooltip: 'Fermer',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ]),
            const SizedBox(height: 8),
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
              selected: const {'action'},
              // « Nouveau projet » ouvre DIRECTEMENT le formulaire — l'étape
              // intermédiaire « Continuer » ne servait à rien (retour user).
              onSelectionChanged: (s) {
                if (s.first != 'project') return;
                Navigator.pop(ctx);
                showNewProjectSheet(
                  context,
                  domains: logic.state.activeDomains,
                  sync: sync,
                  activities: logic.state.activeActivities,
                  onCreated: () => onCreated?.call(),
                );
              },
            ),
            const SizedBox(height: 14),
            ...[
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
                for (final g in actGroups) ...[
                  const SizedBox(height: 8),
                  Text(g.label.toUpperCase(),
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .8,
                          color: Theme.of(ctx).colorScheme.onSurface
                              .withOpacity(.35))),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final a in g.acts)
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
                ],
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
                  final title = titleCtrl.text.trim();
                  final actId = activityId;
                  if (title.isEmpty || actId == null) return;
                  // OPTIMISTE : pas d'await sur l'ack serveur (hors-ligne il
                  // n'arrive jamais → la sheet moulinait). Le SDK met
                  // l'écriture en file ; l'état local reflète tout de suite.
                  unawaited(sync.addOwnActionToActivity(actId, title,
                      contexts: pickedContexts));
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
                child: const Text('Créer l\'action'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  titleCtrl.dispose();
}
