import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/web/document_viewer_dialog.dart';

// Vue « Documents » (Bibliothèque) : documents par projet, filtre projet.

// ── Vue Documents (lot 5) : accès direct aux documents par projet ────────────

class DocumentsView extends StatelessWidget {
  final List<Project> projects;
  final List<Domain> domains;
  final Map<String, List<Map<String, dynamic>>> documentsByProject;
  final FirestoreSync sync;
  final VoidCallback onChanged;
  // Filtre « Tout voir » de la fiche projet : n'affiche que ce projet.
  final String? projectId;
  final VoidCallback? onClearFilter;
  const DocumentsView({
    super.key,
    required this.projects,
    required this.domains,
    required this.documentsByProject,
    required this.sync,
    required this.onChanged,
    this.projectId,
    this.onClearFilter,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Projets ayant au moins un document, dans l'ordre de la liste projets ;
    // documents orphelins (projet supprimé) regroupés à la fin.
    final known = <(Project, List<Map<String, dynamic>>)>[];
    final seen = <String>{};
    for (final p in projects) {
      if (projectId != null && p.id != projectId) continue;
      final docs = documentsByProject[p.id];
      if (docs != null && docs.isNotEmpty) {
        known.add((p, docs));
        seen.add(p.id);
      }
    }
    final orphans = <Map<String, dynamic>>[
      if (projectId == null)
        for (final e in documentsByProject.entries)
          if (!seen.contains(e.key)) ...e.value,
    ];
    final filteredProject = projectId == null
        ? null
        : projects.where((p) => p.id == projectId).firstOrNull;

    Widget docRow(String projectTitle, List<Map<String, dynamic>> group,
        Map<String, dynamic> doc) {
      final title = (doc['title'] as String?) ?? 'Document';
      final category = (doc['category'] as String?) ?? 'notes';
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => DocumentViewerDialog(
            projectTitle: projectTitle,
            documents: group,
            sync: sync,
            onDeleted: onChanged,
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(.3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(Icons.description_outlined,
                size: 15, color: cs.onSurface.withOpacity(.45)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(category,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: cs.primary.withOpacity(.8))),
            ),
          ]),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 60),
          children: [
            Row(children: [
              Text(
                  filteredProject == null
                      ? 'DOCUMENTS'
                      : 'DOCUMENTS · ${filteredProject.title.toUpperCase()}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: cs.onSurface.withOpacity(0.45))),
              if (projectId != null && onClearFilter != null) ...[
                const SizedBox(width: 12),
                TextButton(
                    onPressed: onClearFilter,
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    child: const Text('Tous les projets')),
              ],
            ]),
            const SizedBox(height: 16),
            if (known.isEmpty && orphans.isEmpty)
              Text(
                  'Aucun document. Claude en crée via save_document '
                  '(programmes, briefs, livrables…) — ils apparaîtront ici, '
                  'groupés par projet.',
                  style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurface.withOpacity(.45))),
            for (final (p, docs) in known) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: domainColor(p.domainId, domains) ?? cs.primary,
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface.withOpacity(.8))),
                  ),
                  Text('${docs.length}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface.withOpacity(.4))),
                ]),
              ),
              for (final doc in docs) docRow(p.title, docs, doc),
            ],
            if (orphans.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text('SANS PROJET',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: cs.onSurface.withOpacity(.4))),
              ),
              for (final doc in orphans) docRow('Sans projet', orphans, doc),
            ],
          ],
        ),
      ),
    );
  }
}
