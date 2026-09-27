import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

/// « Nouvelle tâche » (ex-dialog du Gantt, partagé avec la fiche projet) :
/// titre, phase, dates, jalon. Ajoute la tâche au projet, la sauvegarde et
/// la retourne ; null si annulé.
Future<ProjectTask?> showAddTaskDialog(
  BuildContext context, {
  required Project project,
  required FirestoreSync sync,
}) async {
  final titleCtrl = TextEditingController();
  String? selectedPhaseId;
  var startDate = DateTime.now();
  DateTime? endDate;
  var isMilestone = false;

  String fmt(DateTime d) {
    const m = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin', 'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: const Text('Nouvelle tâche'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Titre',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (project.phases.isNotEmpty)
                DropdownButtonFormField<String?>(
                  value: selectedPhaseId,
                  decoration: const InputDecoration(
                    labelText: 'Phase (optionnel)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Aucune phase')),
                    ...project.phases.map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Row(children: [
                            Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: _hex(p.color, const Color(0xFF6B57F0)),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Text(p.label),
                          ]),
                        )),
                  ],
                  onChanged: (v) => setSt(() => selectedPhaseId = v),
                ),
              if (project.phases.isNotEmpty) const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: startDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2032),
                  );
                  if (d != null) setSt(() => startDate = d);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date de début',
                    border: OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: Icon(Icons.calendar_today_outlined, size: 16),
                  ),
                  child: Text(fmt(startDate), style: const TextStyle(fontSize: 14)),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: endDate ?? startDate.add(const Duration(days: 7)),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2032),
                  );
                  if (d != null) setSt(() => endDate = d);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Date de fin (optionnel)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: endDate != null
                        ? GestureDetector(
                            onTap: () => setSt(() => endDate = null),
                            child: const Icon(Icons.clear, size: 16),
                          )
                        : const Icon(Icons.calendar_today_outlined, size: 16),
                  ),
                  child: Text(
                    endDate != null ? fmt(endDate!) : '—',
                    style: TextStyle(
                      fontSize: 14,
                      color: endDate != null ? null : const Color(0xFFAAAAAA),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                title: const Text('Jalon (milestone)', style: TextStyle(fontSize: 13)),
                value: isMilestone,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setSt(() => isMilestone = v ?? false),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (titleCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    ),
  );
  final title = titleCtrl.text.trim();
  titleCtrl.dispose();
  if (confirmed != true) return null;

  final phase = project.phases.where((p) => p.id == selectedPhaseId).firstOrNull;
  final task = ProjectTask(
    title: title.isNotEmpty ? title : 'Nouvelle tâche',
    phaseId: selectedPhaseId,
    groupLabel: phase?.label, // synchronise le groupe visuel dans le Gantt
    startDate: startDate,
    endDate: endDate,
    isMilestone: isMilestone,
    color: phase?.color,
  );
  project.tasks.add(task);
  await sync.saveProjectTasks(project.id, project.tasks);
  return task;
}

Color _hex(String? hex, Color fallback) {
  if (hex == null || hex.isEmpty) return fallback;
  final s = hex.replaceFirst('#', '');
  if (s.length != 6) return fallback;
  try {
    return Color(int.parse('FF$s', radix: 16));
  } catch (_) {
    return fallback;
  }
}
