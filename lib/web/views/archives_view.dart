import 'dart:async';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

// Vue « Organisation » (Bibliothèque) : archives, restauration.

// ── Vue Archives ─────────────────────────────────────────────────────────────

class ArchivesView extends StatefulWidget {
  final FirestoreSync sync;
  const ArchivesView({super.key, required this.sync});

  @override
  State<ArchivesView> createState() => ArchivesViewState();
}

class ArchivesViewState extends State<ArchivesView> {
  List<Domain> _domains = [];
  List<Activity> _activities = [];
  List<Project> _projects = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _search = '';
  // Filtre : 'all' | 'active' | 'archived'
  String _filter = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.sync.fetchAllDomains(),
        widget.sync.fetchActivities(),
        widget.sync.fetchProjects(),
      ]);
      if (!mounted) return;
      setState(() {
        _domains = results[0] as List<Domain>;
        _activities = results[1] as List<Activity>;
        _projects = results[2] as List<Project>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _archive(String col, String id) async {
    await widget.sync.archiveItem(col, id);
    _load();
  }

  Future<void> _restore(String col, String id) async {
    await widget.sync.restoreDeleted(col, id);
    _load();
  }

  Future<void> _confirmHardDelete(String col, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer définitivement ?'),
        content: const Text(
          'L\'élément sera masqué partout (app iOS + web).\n\n'
          'Note : si l\'élément existe encore localement sur iOS, '
          'il sera supprimé au prochain démarrage de l\'app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.sync.hardDelete(col, id);
      _load();
    }
  }

  Future<void> _editActivity(Activity activity) async {
    final nameCtrl = TextEditingController(text: activity.name);
    String? domainId = activity.domainId.isEmpty ? null : activity.domainId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text(activity.isHabit
                ? 'Modifier la routine'
                : 'Modifier l\'activité'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nom',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Domaine',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    value: domainId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('— Aucun domaine —')),
                      for (final d in ([
                        ..._domains.where((d) => !d.deleted)
                      ]..sort((a, b) => a.name.compareTo(b.name))))
                        DropdownMenuItem(value: d.id, child: Text(d.name)),
                    ],
                    onChanged: (v) => setLocal(() => domainId = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enregistrer'),
              ),
            ],
          );
        });
      },
    );

    if (confirmed == true) {
      activity.name = nameCtrl.text.trim();
      activity.domainId = domainId ?? '';
      await widget.sync.saveActivity(activity);
      _load();
    }
    nameCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());

    // ── Données avec filtres ─────────────────────────────────────────────────
    final q = _search.toLowerCase().trim();

    bool matchesSearch(String name) =>
        q.isEmpty || name.toLowerCase().contains(q);

    bool showActive(bool isArchived) =>
        _filter == 'all' ||
        (_filter == 'active' && !isArchived) ||
        (_filter == 'archived' && isArchived);

    final archivedProjects = _projects
        .where((p) =>
            p.status == 'archived' &&
            matchesSearch(p.title) &&
            showActive(true))
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    final activeProjects = _projects
        .where((p) =>
            p.status != 'archived' &&
            matchesSearch(p.title) &&
            showActive(false))
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    // Domaines actifs + archivés triés
    final activeDomains = _domains
        .where((d) => !d.deleted && showActive(false))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final archivedDomains = _domains
        .where((d) => d.deleted && showActive(true))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final allDomains = [...activeDomains, ...archivedDomains];

    // Activités filtrées et indexées par domaine
    final filteredActivities = _activities
        .where((a) => matchesSearch(a.name) && showActive(a.deleted))
        .toList();

    final activitiesByDomain = <String, List<Activity>>{};
    final activitiesWithoutDomain = <Activity>[];
    for (final a in filteredActivities) {
      if (a.domainId.isEmpty) {
        activitiesWithoutDomain.add(a);
      } else {
        activitiesByDomain.putIfAbsent(a.domainId, () => []).add(a);
      }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────
    Widget sectionLabel(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: cs.onSurface.withOpacity(0.45),
            ),
          ),
        );

    Widget domainHeader(Domain d) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          child: Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: d.deleted ? cs.error.withOpacity(0.5) : cs.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              d.name.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: d.deleted ? cs.error.withOpacity(0.6) : cs.primary,
              ),
            ),
            if (d.deleted) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('archivé',
                    style: TextStyle(fontSize: 10, color: cs.error)),
              ),
            ],
            const SizedBox(width: 8),
            Expanded(child: Divider(color: cs.outlineVariant.withOpacity(0.3))),
            IconButton(
              icon: Icon(
                  d.deleted ? Icons.restore_outlined : Icons.archive_outlined,
                  size: 15,
                  color: cs.onSurface.withOpacity(0.4)),
              tooltip: d.deleted ? 'Restaurer' : 'Archiver',
              visualDensity: VisualDensity.compact,
              onPressed: d.deleted
                  ? () => _restore('domains', d.id)
                  : () => _archive('domains', d.id),
            ),
          ]),
        );

    Widget actRow(Activity a) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _ArchiveItemRow(
            label: a.name,
            isArchived: a.deleted,
            onEdit: () => _editActivity(a),
            onArchive: () => _archive('activities', a.id),
            onRestore: () => _restore('activities', a.id),
            onDelete: () => _confirmHardDelete('activities', a.id),
            cs: cs,
          ),
        );

    Widget buildDomainSection(String? domainId) {
      final all = domainId == null
          ? activitiesWithoutDomain
          : (activitiesByDomain[domainId] ?? []);

      final timeActs = [...all.where((a) => !a.isHabit)]
        ..sort((x, y) => x.name.compareTo(y.name));
      final habitActs = [...all.where((a) => a.isHabit)]
        ..sort((x, y) => x.name.compareTo(y.name));

      if (timeActs.isEmpty && habitActs.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text('Aucun élément',
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(0.35),
                  fontStyle: FontStyle.italic)),
        );
      }

      Widget column(String label, IconData icon, List<Activity> items) =>
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
                  child: Row(
                    children: [
                      Icon(icon,
                          size: 12, color: cs.onSurface.withOpacity(0.35)),
                      const SizedBox(width: 5),
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                          color: cs.onSurface.withOpacity(0.3),
                        ),
                      ),
                    ],
                  ),
                ),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('—',
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withOpacity(0.3))),
                  )
                else
                  for (final a in items) actRow(a),
              ],
            ),
          );

      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            column('Activités', Icons.timer_outlined, timeActs),
            const SizedBox(width: 16),
            column('Routines', Icons.repeat_rounded, habitActs),
          ],
        ),
      );
    }

    // ── Rendu (lot 5b) : recherche + filtres en tête, puis 2 colonnes ────────
    final searchField = TextField(
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _search = v),
      decoration: InputDecoration(
        hintText: 'Rechercher…',
        prefixIcon: const Icon(Icons.search_outlined, size: 18),
        suffixIcon: _search.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _search = '');
                },
              )
            : null,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      ),
    );
    final filterChips = Row(mainAxisSize: MainAxisSize.min, children: [
      for (final (val, label) in [
        ('all', 'Tout'),
        ('active', 'Actifs'),
        ('archived', 'Archivés'),
      ]) ...[
        ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: _filter == val,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => setState(() => _filter = val),
        ),
        const SizedBox(width: 6),
      ],
    ]);

    final projectsSection = <Widget>[
      sectionLabel(
          'PROJETS (${activeProjects.length + archivedProjects.length})'),
      if (activeProjects.isEmpty && archivedProjects.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text('Aucun projet',
              style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withOpacity(0.4),
                  fontStyle: FontStyle.italic)),
        )
      else ...[
        if (activeProjects.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Actifs',
                style: TextStyle(
                    fontSize: 11, color: cs.onSurface.withOpacity(0.5))),
          ),
          for (final p in activeProjects) ...[
            _ArchiveItemRow(
              label: p.title,
              isArchived: false,
              subtitle: () {
                final d = _domains.where((d) => d.id == p.domainId).firstOrNull;
                return d != null ? d.name : null;
              }(),
              onArchive: () async {
                await widget.sync.saveProject(p..status = 'archived');
                _load();
              },
              onRestore: () async {},
              cs: cs,
            ),
            const SizedBox(height: 6),
          ],
        ],
        if (archivedProjects.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Archivés',
                style: TextStyle(
                    fontSize: 11, color: cs.onSurface.withOpacity(0.5))),
          ),
          for (final p in archivedProjects) ...[
            _ArchiveItemRow(
              label: p.title,
              isArchived: true,
              subtitle: () {
                final d = _domains.where((d) => d.id == p.domainId).firstOrNull;
                return d != null ? d.name : null;
              }(),
              onArchive: () async {},
              onRestore: () async {
                await widget.sync.saveProject(p..status = 'active');
                _load();
              },
              cs: cs,
            ),
            const SizedBox(height: 6),
          ],
        ],
      ],
    ];

    // Chaque domaine devient une CARTE (lot 5b) — lisible en colonne dense.
    Widget domainCard(Widget header, Widget body) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withOpacity(.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [header, body],
          ),
        );

    final domainsSection = <Widget>[
      sectionLabel('ACTIVITÉS & ROUTINES PAR DOMAINE'),

      for (final d in allDomains)
        domainCard(domainHeader(d), buildDomainSection(d.id)),

      // Sans domaine
      if (activitiesWithoutDomain.isNotEmpty)
        domainCard(
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
            child: Row(children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: cs.onSurface.withOpacity(0.3),
                      shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('SANS DOMAINE',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: cs.onSurface.withOpacity(0.4))),
              const SizedBox(width: 8),
              Expanded(
                  child: Divider(color: cs.outlineVariant.withOpacity(0.3))),
            ]),
          ),
          buildDomainSection(null),
        ),
    ];

    // ── Composition : ≥ 1100 px = PROJETS | DOMAINES côte à côte ─────────────
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1100;
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 1360 : 860),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 60),
            children: [
              if (wide)
                Row(children: [
                  sectionLabel('ORGANISATION'),
                  const SizedBox(width: 20),
                  Expanded(child: searchField),
                  const SizedBox(width: 14),
                  filterChips,
                ])
              else ...[
                sectionLabel('ORGANISATION'),
                searchField,
                const SizedBox(height: 8),
                filterChips,
              ],
              const SizedBox(height: 18),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: projectsSection),
                    ),
                    const SizedBox(width: 28),
                    Expanded(
                      flex: 3,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: domainsSection),
                    ),
                  ],
                )
              else ...[
                ...projectsSection,
                const SizedBox(height: 20),
                ...domainsSection,
              ],
            ],
          ),
        ),
      );
    });
  }
}

// ── Ligne d'un item dans la vue Archives ─────────────────────────────────────

class _ArchiveItemRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool isArchived;
  final VoidCallback? onEdit;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback? onDelete;
  final ColorScheme cs;

  const _ArchiveItemRow({
    required this.label,
    required this.isArchived,
    required this.onArchive,
    required this.onRestore,
    required this.cs,
    this.subtitle,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isArchived
        ? cs.errorContainer.withOpacity(0.2)
        : cs.surfaceContainerHighest.withOpacity(0.3);
    final borderColor = isArchived
        ? cs.error.withOpacity(0.25)
        : cs.outlineVariant.withOpacity(0.4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ● bullet
          Text(
            '●',
            style: TextStyle(
              fontSize: 10,
              color: isArchived
                  ? cs.error.withOpacity(0.6)
                  : Colors.green.shade600,
            ),
          ),
          const SizedBox(width: 10),
          // Nom + sous-titre
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Bouton édition
          if (onEdit != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.edit_outlined,
                  size: 15, color: cs.onSurface.withOpacity(0.4)),
              tooltip: 'Modifier',
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
            ),
          ],
          const SizedBox(width: 4),
          // Badge statut
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isArchived ? cs.errorContainer : Colors.green.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isArchived ? 'Archivé' : 'Actif',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isArchived ? cs.error : Colors.green.shade800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Boutons d'action
          if (!isArchived) ...[
            OutlinedButton(
              onPressed: onArchive,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amber.shade800,
                side: BorderSide(color: Colors.amber.shade600),
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('Archiver'),
            ),
          ] else ...[
            OutlinedButton(
              onPressed: onRestore,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.green.shade700,
                side: BorderSide(color: Colors.green.shade400),
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('Restaurer'),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 6),
              TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(
                  foregroundColor: cs.error,
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                child: const Text('Supprimer'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
