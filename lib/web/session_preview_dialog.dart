import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';
import 'package:productivitwo_v1/utils/intervention_builder.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/session_player_screen.dart'
    show sessionScriptAction, stepPlannedMin, stepLabel;

/// Aperçu d'une séance (web, 2026-10) : le déroulé d'une intervention, à
/// venir ou passée, avec ses étapes cochables — pour voir d'un coup d'œil ce
/// qui reste à cocher sans attendre que la séance soit « en cours ». Même
/// source que le player mobile (`sessionScriptAction` → checklist), même
/// mutation (`setChecklistItem` + `saveProjectTasks`).
Future<void> showSessionPreviewDialog(
  BuildContext context, {
  required Project project,
  required ProjectIntervention intervention,
  required ProjectTask sessionTask,
  required FirestoreSync sync,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SessionPreviewDialog(
        project: project, intervention: intervention, sessionTask: sessionTask, sync: sync),
  );
}

class _SessionPreviewDialog extends StatefulWidget {
  final Project project;
  final ProjectIntervention intervention;
  final ProjectTask sessionTask;
  final FirestoreSync sync;
  const _SessionPreviewDialog(
      {required this.project,
      required this.intervention,
      required this.sessionTask,
      required this.sync});

  @override
  State<_SessionPreviewDialog> createState() => _SessionPreviewDialogState();
}

class _SessionPreviewDialogState extends State<_SessionPreviewDialog> {
  TaskAction? get _action => sessionScriptAction(widget.sessionTask);
  List<ChecklistItem> get _steps => _action?.checklist ?? const [];

  String get _when {
    final i = widget.intervention;
    final d = i.date;
    final today = DateTime.now();
    final sameDay = d.year == today.year && d.month == today.month && d.day == today.day;
    final day = interventionDayLabel(d);
    final past = d.isBefore(DateTime(today.year, today.month, today.day));
    return '${sameDay ? 'Aujourd\'hui' : day} · ${hmFr(i.startTime)}–${hmFr(i.endTime)}'
        '${(i.place ?? '').trim().isNotEmpty ? ' · ${i.place}' : ''}'
        '${sameDay ? '' : past ? ' · séance passée' : ' · à venir'}';
  }

  Future<void> _toggle(ChecklistItem c, bool v) async {
    final a = _action;
    if (a == null) return;
    setState(() => setChecklistItem(a, c.id, v));
    await widget.sync.saveProjectTasks(widget.project.id, widget.project.tasks);
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final done = steps.where((c) => c.done).length;
    return AlertDialog(
      backgroundColor: kBRaised,
      titlePadding: const EdgeInsets.fromLTRB(22, 18, 14, 0),
      contentPadding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      title: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.intervention.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kBText)),
            const SizedBox(height: 2),
            Text('${widget.project.title} · $_when',
                style: const TextStyle(fontSize: 12.5, color: kBText3)),
          ]),
        ),
        IconButton(
          tooltip: 'Fermer',
          icon: const Icon(Icons.close, size: 18, color: kBText3),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ]),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (steps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                        value: done / steps.length,
                        minHeight: 5,
                        backgroundColor: kBLine,
                        valueColor: const AlwaysStoppedAnimation(kBPrimary)),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$done / ${steps.length}',
                    style: const TextStyle(fontSize: 12, color: kBText3, fontWeight: FontWeight.w700)),
              ]),
            ),
          Flexible(
            child: steps.isEmpty
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 16),
                    child: Text('Cette séance n\'a pas encore d\'étapes de déroulé.',
                        style: TextStyle(fontSize: 13, color: kBText3)),
                  )
                : ListView(shrinkWrap: true, children: [
                    for (final c in steps)
                      InkWell(
                        onTap: () => _toggle(c, !c.done),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(c.done ? Icons.check_circle : Icons.radio_button_unchecked,
                                size: 18, color: c.done ? kBPrimary : kBText4),
                            const SizedBox(width: 10),
                            if (stepPlannedMin(c.title) != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 8, top: 1),
                                child: Text(hmFr(_hm(stepPlannedMin(c.title)!)),
                                    style: const TextStyle(
                                        fontSize: 12.5, color: kBText3, fontWeight: FontWeight.w700,
                                        fontFeatures: [FontFeature.tabularFigures()])),
                              ),
                            Expanded(
                              child: Text(stepLabel(c.title),
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      height: 1.3,
                                      color: c.done ? kBText4 : kBText,
                                      decoration: c.done ? TextDecoration.lineThrough : null)),
                            ),
                          ]),
                        ),
                      ),
                  ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer')),
      ],
    );
  }

  String _hm(int min) => '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';
}
