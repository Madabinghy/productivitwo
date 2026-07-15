import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

/// File « À valider » : propositions de réorganisation émises par ORION autonome.
/// L'utilisateur accepte / refuse / redirige. L'acceptation applique la mutation
/// côté client via FirestoreSync (déterministe, sans LLM).
Future<void> showProposalsSheet(BuildContext context, FirestoreSync sync) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ProposalsSheet(sync: sync),
  );
}

class _ProposalsSheet extends StatelessWidget {
  final FirestoreSync sync;
  const _ProposalsSheet({required this.sync});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scroll) => StreamBuilder<List<OrionProposal>>(
        stream: sync.streamProposals(),
        builder: (context, snap) {
          final items = snap.data ?? const <OrionProposal>[];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.fact_check_outlined, size: 20, color: cs.primary),
                    const SizedBox(width: 8),
                    const Text('À valider',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (items.isNotEmpty)
                      Text('${items.length}',
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withOpacity(.5))),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'ORION propose, tu décides. Rien ne touche tes projets sans ton accord.',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurface.withOpacity(.5)),
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant.withOpacity(.3)),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'Aucune proposition en attente 🎉',
                            style: TextStyle(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: cs.onSurface.withOpacity(.4)),
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _ProposalCard(sync: sync, proposal: items[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProposalCard extends StatefulWidget {
  final FirestoreSync sync;
  final OrionProposal proposal;
  const _ProposalCard({required this.sync, required this.proposal});

  @override
  State<_ProposalCard> createState() => _ProposalCardState();
}

class _ProposalCardState extends State<_ProposalCard> {
  bool _busy = false;

  static const _kindLabels = {
    'new_project': 'Nouveau projet',
    'attach_idea_as_task': 'Tâche d\'un projet',
    'create_subproject': 'Sous-projet',
    'archive_project': 'Archiver',
    'add_phase': 'Phase d\'un projet',
    'attach_action_to_task': 'Action d\'une tâche',
    'restructure_project': 'Recaler un projet',
  };

  OrionProposal get p => widget.proposal;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Choisit un projet cible (redirection / rattachement).
  Future<Project?> _pickProject(String title, {String? excludeId}) async {
    final projects = await widget.sync.fetchProjects();
    if (!mounted) return null;
    final candidates = projects
        .where((x) => x.id != excludeId && x.status != 'archived')
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun projet disponible.')));
      return null;
    }
    return showModalBottomSheet<Project>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final x in candidates)
                    ListTile(
                      title: Text(x.title),
                      onTap: () => Navigator.pop(ctx, x),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _redirect() async {
    switch (p.kind) {
      case 'new_project':
        // Cas clé : l'idée est en fait une tâche d'un projet existant.
        final target = await _pickProject('Rattacher comme tâche à…');
        if (target == null) return;
        await _run(
          () => widget.sync.acceptProposal(p,
              kindOverride: 'attach_idea_as_task',
              overrides: {
                'projectId': target.id,
                'taskTitle': (p.payload['projectTitle'] ?? p.title).toString(),
              }),
          'Rattaché à « ${target.title} ».',
        );
        break;
      case 'attach_idea_as_task':
        final target = await _pickProject('Rattacher à un autre projet…');
        if (target == null) return;
        await _run(
          () => widget.sync
              .acceptProposal(p, overrides: {'projectId': target.id}),
          'Rattaché à « ${target.title} ».',
        );
        break;
      case 'create_subproject':
        final target = await _pickProject('Sous-projet d\'un autre projet…');
        if (target == null) return;
        await _run(
          () => widget.sync
              .acceptProposal(p, overrides: {'parentProjectId': target.id}),
          'Sous-projet de « ${target.title} ».',
        );
        break;
    }
  }

  static const _redirectableKinds = {
    'new_project',
    'attach_idea_as_task',
    'create_subproject',
  };

  bool get _canRedirect => _redirectableKinds.contains(p.kind);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _kindLabels[p.kind] ?? p.kind,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(p.title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if (p.rationale.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(p.rationale,
                style: TextStyle(
                    fontSize: 12.5, color: cs.onSurface.withOpacity(.6))),
          ],
          const SizedBox(height: 6),
          _busy
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Accepter'),
                      onPressed: () => _run(
                        () => widget.sync.acceptProposal(p),
                        'Proposition appliquée.',
                      ),
                    ),
                    if (_canRedirect)
                      TextButton.icon(
                        icon: const Icon(Icons.alt_route, size: 16),
                        label: const Text('Rediriger'),
                        onPressed: _redirect,
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _run(
                        () => widget.sync.rejectProposal(p),
                        'Proposition refusée.',
                      ),
                      child: Text('Refuser',
                          style: TextStyle(color: cs.onSurface.withOpacity(.5))),
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}
