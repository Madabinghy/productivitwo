import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isUpcomingTask, kFlowTaskId, shortDateFr, upcomingLabel;
import 'package:productivitwo_v1/utils/project_health.dart' show phaseSections;
import 'package:productivitwo_v1/widgets/task_fiche_sheet.dart' show stripLeadingEmoji;

/// Valeur rendue pour « Au fil de l'eau » (sans tâche précise).
const kPickFlowTask = '';

final RegExp _lead = RegExp(r'^\s*((?:\p{Extended_Pictographic}|[☀-➿])️?)', unicode: true);

/// Choisir la tâche d'un projet (2026-10-30, retour user : la liste plate était
/// illisible) : tâches ouvertes rangées par phase, titre sans son émoji (l'émoji
/// passe en icône), avancement des actions et échéance dessous, tâche proposée
/// mise en avant. Rend l'id de la tâche, [kPickFlowTask] pour « Au fil de
/// l'eau », null si annulé.
Future<String?> showTaskPicker(
  BuildContext context, {
  required Project project,
  String? currentTaskId,
  bool includeFlow = true,
  bool includeUpcoming = true,
}) {
  final today = DateTime.now();
  final sections = [
    for (final s in phaseSections(project))
      (
        phase: s.phase,
        tasks: [
          for (final t in s.tasks)
            if (t.status != 'done' && t.status != 'skipped' && t.id != kFlowTaskId && (includeUpcoming || !isUpcomingTask(t, today))) t,
        ],
      ),
  ].where((s) => s.tasks.isNotEmpty).toList();
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .75,
      maxChildSize: .95,
      builder: (ctx, scroll) {
        final cs = Theme.of(ctx).colorScheme;
        final text3 = cs.onSurface.withValues(alpha: .55);
        Widget header(String label, int n) => Padding(
              padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
              child: Text('${label.toUpperCase()} · $n',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: text3)),
            );
        Widget row({required Widget leading, required String title, String? sub, required String value, bool dim = false}) {
          final current = value == (currentTaskId ?? '__none__');
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: current ? cs.primary.withValues(alpha: .12) : cs.onSurface.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(ctx, value),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: current ? Border.all(color: cs.primary.withValues(alpha: .6)) : null,
                  ),
                  child: Row(children: [
                    SizedBox(width: 28, child: Center(child: leading)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: dim ? .55 : 1))),
                        if (sub != null && sub.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: text3)),
                        ],
                      ]),
                    ),
                    if (current) Icon(Icons.check_rounded, size: 20, color: cs.primary),
                  ]),
                ),
              ),
            ),
          );
        }

        String subOf(ProjectTask t) {
          final open = t.actions.where((a) => !a.done).length;
          return [
            if (t.actions.isNotEmpty) '${t.actions.length - open} / ${t.actions.length} actions',
            if (isUpcomingTask(t, today)) upcomingLabel(t.startDate, today),
            if (t.endDate != null) 'éch. ${shortDateFr(t.endDate!, today: today)}',
          ].join(' · ');
        }

        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text('Dans quelle tâche de « ${project.title} » ?',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            if (includeFlow)
              row(
                leading: Icon(Icons.waves_rounded, color: text3),
                title: 'Au fil de l\'eau',
                sub: 'sans tâche précise',
                value: kPickFlowTask,
              ),
            for (final s in sections) ...[
              if (sections.length > 1 || s.phase != null) header(s.phase?.label ?? 'Sans phase', s.tasks.length),
              for (final t in s.tasks)
                row(
                  leading: _leadingOf(t.title, text3),
                  title: stripLeadingEmoji(t.title),
                  sub: subOf(t),
                  value: t.id,
                  dim: isUpcomingTask(t, today),
                ),
            ],
            if (sections.isEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Aucune tâche ouverte dans ce projet.', style: TextStyle(color: text3)),
              ),
          ],
        );
      },
    ),
  );
}

Widget _leadingOf(String title, Color fallback) {
  final m = _lead.firstMatch(title);
  if (m == null) return Icon(Icons.radio_button_unchecked, size: 18, color: fallback);
  return Text(m.group(1)!, style: const TextStyle(fontSize: 18));
}
