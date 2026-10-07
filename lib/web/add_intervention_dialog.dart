import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/intervention_builder.dart';

/// « Nouvelle séance » (fiche projet web, lot 2 des interventions) : titre,
/// date, créneau, lieu, modèle, déroulé. Crée l'intervention ET ses trois
/// tâches (📝 / 🎯 / ✅), sauvegarde le projet et retourne l'intervention ;
/// null si annulé.
Future<ProjectIntervention?> showAddInterventionDialog(
  BuildContext context, {
  required Project project,
  required FirestoreSync sync,
}) async {
  final templates = await sync.fetchInterventionTemplates();
  if (!context.mounted) return null;

  final titleCtrl = TextEditingController();
  final startCtrl = TextEditingController();
  final endCtrl = TextEditingController();
  final placeCtrl = TextEditingController();
  final stepsCtrl = TextEditingController();
  var template = templates.length > 1 ? templates[1] : templates.first;
  var date = DateTime.now().add(const Duration(days: 7));
  String? error;

  void applyTemplate(InterventionTemplate t) {
    template = t;
    if (t.startTime != null) startCtrl.text = t.startTime!;
    if (t.endTime != null) endCtrl.text = t.endTime!;
    if (t.place != null && placeCtrl.text.isEmpty) placeCtrl.text = t.place!;
  }

  applyTemplate(template);

  String fmt(DateTime d) => '${interventionDayLabel(d)} ${d.year}';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: const Text('Nouvelle séance'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Titre',
                    hintText: 'ex. Séance — 12 oct : contrôle + problèmes du tout',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<InterventionTemplate>(
                  value: template,
                  decoration: const InputDecoration(
                    labelText: 'Modèle',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final t in templates)
                      DropdownMenuItem(value: t, child: Text(t.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (t) {
                    if (t != null) setSt(() => applyTemplate(t));
                  },
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 730)),
                        );
                        if (picked != null) setSt(() => date = picked);
                      },
                      icon: const Icon(Icons.event, size: 16),
                      label: Text(fmt(date)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 92,
                    child: TextField(
                      controller: startCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Début', hintText: '13:15', border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 92,
                    child: TextField(
                      controller: endCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Fin', hintText: '15:00', border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: placeCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Lieu (optionnel)', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: stepsCtrl,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Déroulé (une étape par ligne, optionnel)',
                    hintText: '13h15 Ramasser le DM\n13h20 Contrôle 40 min\n14h00 Kahoot…',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Génère : 📝 Préparer (J-${template.prepDaysBefore} → J-${template.prepEndDaysBefore}, '
                  '${template.prepActions.length} actions) · 🎯 Séance (jalon) · '
                  '✅ Clôturer (J → J+${template.closureDaysAfter}, ${template.closureActions.length} actions).',
                  style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurface.withOpacity(.6)),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(fontSize: 12.5, color: Theme.of(ctx).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final s = hmToMin(startCtrl.text.trim()), e = hmToMin(endCtrl.text.trim());
              if (titleCtrl.text.trim().isEmpty) {
                setSt(() => error = 'Donne un titre à la séance.');
              } else if (s < 0 || e < 0) {
                setSt(() => error = 'Heures au format HH:mm (ex. 13:15).');
              } else if (e <= s) {
                setSt(() => error = 'La fin doit être après le début.');
              } else {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Créer la séance'),
          ),
        ],
      ),
    ),
  );

  final title = titleCtrl.text.trim();
  final start = startCtrl.text.trim(), end = endCtrl.text.trim();
  final place = placeCtrl.text.trim();
  final steps = stepsCtrl.text.split('\n');
  for (final c in [titleCtrl, startCtrl, endCtrl, placeCtrl, stepsCtrl]) {
    c.dispose();
  }
  if (confirmed != true) return null;

  final intervention = ProjectIntervention(
    title: title,
    date: DateTime(date.year, date.month, date.day),
    startTime: start,
    endTime: end,
    place: place.isEmpty ? null : place,
    templateId: template.id == 'default' ? null : template.id,
  );
  final built = buildInterventionTasks(intervention, template, phases: project.phases, steps: steps);
  project.interventions.add(intervention);
  project.tasks.addAll([built.prep, built.session, built.closure]);
  await sync.saveProject(project);
  return intervention;
}
