import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/inbox_sheet.dart';

/// Revue de la semaine (Phase 3) : « moment de mise au clair ». Agrège des flags
/// déterministes calculés côté client (projets en sommeil, idées en attente,
/// tâches à classer) avec actions directes.
Future<void> showWeeklyReviewSheet(BuildContext context, FirestoreSync sync) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _WeeklyReviewSheet(sync: sync),
  );
}

class _WeeklyReviewSheet extends StatefulWidget {
  final FirestoreSync sync;
  const _WeeklyReviewSheet({required this.sync});

  @override
  State<_WeeklyReviewSheet> createState() => _WeeklyReviewSheetState();
}

class _WeeklyReviewSheetState extends State<_WeeklyReviewSheet> {
  bool _triggering = false;

  Future<void> _runOrionReview() async {
    setState(() => _triggering = true);
    final ok = await widget.sync.triggerOrionTask('weekly_review');
    if (!mounted) return;
    setState(() => _triggering = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'ORION analyse tes projets — les propositions arriveront dans « À valider ».'
          : 'Impossible de lancer la revue ORION (réessaie plus tard).'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scroll) => StreamBuilder<List<Project>>(
        stream: widget.sync.streamProjects(),
        builder: (context, projSnap) {
          return StreamBuilder<List<CaptureItem>>(
            stream: widget.sync.streamCaptures(),
            builder: (context, capSnap) {
              final projects = projSnap.data ?? const <Project>[];
              final captures = capSnap.data ?? const <CaptureItem>[];
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final cutoff = today.subtract(const Duration(days: 14));

              bool hasUrgent(Project p) => p.tasks.any((t) =>
                  t.status != 'done' &&
                  t.status != 'skipped' &&
                  t.endDate != null &&
                  !t.endDate!.isBefore(today));

              final inactive = projects.where((p) {
                if (p.status != 'active') return false;
                final updated = p.updatedAt ?? p.createdAt;
                return !hasUrgent(p) && updated.isBefore(cutoff);
              }).toList()
                ..sort((a, b) => a.title.compareTo(b.title));

              final orphanIdeas =
                  captures.where((c) => c.status == 'pending').toList();

              // Tâches sans phase dans des projets qui ONT des phases
              final unclassified = <Project, int>{};
              for (final p in projects.where((p) => p.status == 'active')) {
                if (p.phases.isEmpty) continue;
                final n = p.tasks
                    .where((t) =>
                        t.status != 'done' &&
                        t.status != 'skipped' &&
                        (t.phaseId == null || t.phaseId!.isEmpty))
                    .length;
                if (n > 0) unclassified[p] = n;
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
                    child: Row(
                      children: [
                        Icon(Icons.cleaning_services_outlined,
                            size: 20, color: cs.primary),
                        const SizedBox(width: 8),
                        const Text('Revue de la semaine',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Text(
                      'Fais le point et range : archive ce qui dort, classe ce qui traîne.',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurface.withOpacity(.5)),
                    ),
                  ),
                  Divider(height: 1, color: cs.outlineVariant.withOpacity(.3)),
                  Expanded(
                    child: ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        // Projets en sommeil
                        _SectionHeader(
                            label: 'PROJETS EN SOMMEIL', count: inactive.length, cs: cs),
                        if (inactive.isEmpty)
                          _EmptyHint('Aucun projet inactif. 👌', cs)
                        else
                          for (final p in inactive)
                            _InactiveProjectTile(
                              project: p,
                              cs: cs,
                              onArchive: () async {
                                await widget.sync
                                    .saveProject(p..status = 'archived');
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              '« ${p.title} » archivé.')));
                                }
                              },
                            ),
                        const SizedBox(height: 16),

                        // Idées en attente
                        _SectionHeader(
                            label: 'IDÉES EN ATTENTE',
                            count: orphanIdeas.length,
                            cs: cs),
                        if (orphanIdeas.isEmpty)
                          _EmptyHint('Boîte à idées vide.', cs)
                        else
                          _ActionRow(
                            icon: Icons.lightbulb_outline,
                            label:
                                '${orphanIdeas.length} idée(s) à trier dans la boîte à idées',
                            color: Colors.amber.shade700,
                            onTap: () => showInboxSheet(context, widget.sync),
                          ),
                        const SizedBox(height: 16),

                        // Tâches à classer (sans phase)
                        _SectionHeader(
                            label: 'TÂCHES À CLASSER',
                            count: unclassified.values
                                .fold(0, (a, b) => a + b),
                            cs: cs),
                        if (unclassified.isEmpty)
                          _EmptyHint('Tout est rangé dans une phase.', cs)
                        else
                          for (final e in unclassified.entries)
                            _UnclassifiedTile(
                                project: e.key, count: e.value, cs: cs),
                        const SizedBox(height: 20),

                        // Lancer la revue ORION
                        OutlinedButton.icon(
                          icon: _triggering
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.auto_awesome, size: 18),
                          label: const Text(
                              'Demander à ORION de repérer les projets en sommeil'),
                          onPressed: _triggering ? null : _runOrionReview,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final ColorScheme cs;
  const _SectionHeader(
      {required this.label, required this.count, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: cs.onSurface.withOpacity(.5))),
          const SizedBox(width: 6),
          if (count > 0)
            Text('($count)',
                style: TextStyle(
                    fontSize: 11, color: cs.onSurface.withOpacity(.4))),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  final ColorScheme cs;
  const _EmptyHint(this.text, this.cs);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: cs.onSurface.withOpacity(.4))),
      );
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionRow(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(.3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label, style: const TextStyle(fontSize: 13.5))),
          Icon(Icons.chevron_right,
              size: 16, color: cs.onSurface.withOpacity(.25)),
        ]),
      ),
    );
  }
}

class _InactiveProjectTile extends StatelessWidget {
  final Project project;
  final ColorScheme cs;
  final Future<void> Function() onArchive;
  const _InactiveProjectTile(
      {required this.project, required this.cs, required this.onArchive});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          child: Text(project.title,
              style: const TextStyle(fontSize: 13.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        TextButton.icon(
          icon: const Icon(Icons.archive_outlined, size: 15),
          label: const Text('Archiver'),
          style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: cs.onSurface.withOpacity(.6)),
          onPressed: onArchive,
        ),
      ]),
    );
  }
}

class _UnclassifiedTile extends StatelessWidget {
  final Project project;
  final int count;
  final ColorScheme cs;
  const _UnclassifiedTile(
      {required this.project, required this.count, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(Icons.layers_clear_outlined,
            size: 15, color: cs.onSurface.withOpacity(.4)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(project.title,
              style: const TextStyle(fontSize: 13.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        Text('$count sans phase',
            style: TextStyle(
                fontSize: 11.5, color: cs.onSurface.withOpacity(.45))),
      ]),
    );
  }
}
