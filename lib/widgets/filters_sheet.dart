// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';

class FiltersSheet extends StatefulWidget {
  final AppState st;
  final AppLogic logic;
  final VoidCallback onChanged;

  const FiltersSheet({
    super.key,
    required this.st,
    required this.logic,
    required this.onChanged,
  });

  @override
  State<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<FiltersSheet> {
  FilterState get f => widget.st.filters;

  void _save() {
    widget.logic.onChange(); // persiste ton AppState
    widget.onChanged();
  }

  void _toggleDomain(String domainId) {
    setState(() {
      // 1) Toggle domaine
      if (f.domainIds.contains(domainId)) {
        f.domainIds.remove(domainId);
      } else {
        f.domainIds.add(domainId);
      }

      // 2) Si aucun domaine sélectionné => pas besoin de purger (on affiche tout)
      if (f.domainIds.isEmpty) return;

      // 3) Purge les activités sélectionnées qui ne sont plus dans les domaines cochés
      final allowedActivityIds = widget.st.activities
          .where((a) => !a.isHabit && f.domainIds.contains(a.domainId))
          .map((a) => a.id)
          .toSet();

      f.activityIds.removeWhere((actId) => !allowedActivityIds.contains(actId));

      // 4) (Optionnel) purge d’autres filtres dépendants si tu en as
      // ex: f.contextIds.removeWhere((ctxId) => !allowedContextIds.contains(ctxId));
    });

    _save();
  }

  void _toggleSet(Set<String> set, String id) {
    setState(() {
      if (set.contains(id)) {
        set.remove(id);
      } else {
        set.add(id);
      }
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final domains = widget.st.domains;
    final selectedDomains = f.domainIds;

// si aucun domaine sélectionné => on affiche tous les domaines
    final visibleDomainIds = selectedDomains.isEmpty
        ? widget.st.domains.map((d) => d.id).toSet()
        : selectedDomains;

    final activitiesByDomain = <String, List<Activity>>{};
    for (final a in widget.st.activities.where((a) => !a.isHabit)) {
      if (!visibleDomainIds.contains(a.domainId)) continue;
      (activitiesByDomain[a.domainId] ??= []).add(a);
    }

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Filtres",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          widget.st.filters = FilterState(); // reset
                        });
                        _save();
                      },
                      child: const Text("Réinitialiser"),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
/*                 SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: f.enabled,
                  title: const Text("Activer les filtres"),
                  onChanged: (v) {
                    setState(() => f.enabled = v);
                    _save();
                  },
                ), */
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 10,
                        color: f.isActive
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        f.isActive ? "Filtres actifs" : "Aucun filtre",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(.75),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text("Domaines",
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in domains)
                      FilterChip(
                        label: Text(d.name),
                        selected: f.domainIds.contains(d.id),
                        onSelected: (_) => _toggleDomain(d.id),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text("Activités",
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final d in widget.st.domains
                    .where((d) => visibleDomainIds.contains(d.id)))
                  if ((activitiesByDomain[d.id] ?? const <Activity>[])
                      .isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      title: Text(d.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final a
                                  in (activitiesByDomain[d.id]!
                                    ..sort((x, y) => x.name.compareTo(y.name))))
                                FilterChip(
                                  label: Text(a.name),
                                  selected: f.activityIds.contains(a.id),
                                  onSelected: (_) =>
                                      _toggleSet(f.activityIds, a.id),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Fermer"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Astuce : laisse vide = pas de filtre sur cette catégorie.",
                  style: TextStyle(
                      color: cs.onSurface.withOpacity(0.6), fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
