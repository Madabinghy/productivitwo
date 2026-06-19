// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';

class AssignActivitySheet extends StatefulWidget {
  final AppState st;
  final void Function(Activity act) onPick;
  final VoidCallback onKeepInbox;

  // Optionnel: si tu veux ouvrir certains domaines par défaut
  final Set<String>? initiallyExpandedDomainIds;

  // Optionnel: si tu veux n’afficher que les activités des domaines filtrés
  final Set<String>? allowedDomainIds;

  const AssignActivitySheet({
    super.key,
    required this.st,
    required this.onPick,
    required this.onKeepInbox,
    this.initiallyExpandedDomainIds,
    this.allowedDomainIds,
  });

  @override
  State<AssignActivitySheet> createState() => _AssignActivitySheetState();
}

class _AssignActivitySheetState extends State<AssignActivitySheet> {
  final _q = ValueNotifier<String>('');
  late final Set<String> _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = {...?widget.initiallyExpandedDomainIds};
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final domainsById = {for (final d in widget.st.domains) d.id: d};

    // 1) Activities candidates
    final allActs = widget.st.activities.where((a) {
      if (a.isHabit) return false; // on ne veut pas associer une action à une routine/habit
      if (a.domainId.isEmpty) return false;
      if (widget.allowedDomainIds != null &&
          !widget.allowedDomainIds!.contains(a.domainId)) return false;
      return true;
    }).toList();

    // 2) Group by domainId
    final byDom = <String, List<Activity>>{};
    for (final a in allActs) {
      (byDom[a.domainId] ??= []).add(a);
    }

    // 3) Sort domains by domain name
    final domainIds = byDom.keys.toList()
      ..sort((a, b) {
        final na = domainsById[a]?.name ?? '';
        final nb = domainsById[b]?.name ?? '';
        return na.toLowerCase().compareTo(nb.toLowerCase());
      });

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Associer à une activité",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: widget.onKeepInbox,
                  child: const Text("Garder Inbox"),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Search
            ValueListenableBuilder<String>(
              valueListenable: _q,
              builder: (_, q, __) {
                return TextField(
                  onChanged: (v) => _q.value = v.trim(),
                  decoration: InputDecoration(
                    hintText: "Rechercher une activité…",
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surface
                        .withOpacity(0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                );
              },
            ),

            const SizedBox(height: 12),

            // Body (scrollable)
            Flexible(
              child: ValueListenableBuilder<String>(
                valueListenable: _q,
                builder: (_, q, __) {
                  String norm(String s) => s.toLowerCase();

                  // Si recherche active, on affiche une liste simple (plus rapide et UX OK)
                  if (q.isNotEmpty) {
                    final hits = allActs
                        .where((a) => norm(a.name).contains(norm(q)))
                        .toList()
                      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                    if (hits.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          "Aucun résultat.",
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(.7),
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: hits.length,
                      separatorBuilder: (_, __) => const Divider(height: 16),
                      itemBuilder: (_, i) {
                        final a = hits[i];
                        final domName = domainsById[a.domainId]?.name ?? "Domaine";
                        return ListTile(
                          title: Text(a.name,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(domName),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => widget.onPick(a),
                        );
                      },
                    );
                  }

                  // Sinon: accordéon par domaine (comme ton filtre)
                  return ListView(
                    children: [
                      for (final domId in domainIds) ...[
                        _DomainAccordion(
                          title: domainsById[domId]?.name ?? "Domaine",
                          initiallyExpanded: _expanded.contains(domId),
                          onToggle: (isOpen) {
                            setState(() {
                              if (isOpen) {
                                _expanded.add(domId);
                              } else {
                                _expanded.remove(domId);
                              }
                            });
                          },
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final a in (byDom[domId]!..sort(
                                (x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()),
                              )))
                                ActionChip(
                                  label: Text(a.name),
                                  onPressed: () => widget.onPick(a),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Fermer"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DomainAccordion extends StatelessWidget {
  final String title;
  final bool initiallyExpanded;
  final void Function(bool isOpen) onToggle;
  final Widget child;

  const _DomainAccordion({
    required this.title,
    required this.initiallyExpanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      // évite le Divider/chevrons moches si tu veux un style “clean”
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 0),
        childrenPadding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        trailing: Icon(
          initiallyExpanded ? Icons.expand_less : Icons.expand_more,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(.7),
        ),
        onExpansionChanged: onToggle,
        children: [
          Align(alignment: Alignment.centerLeft, child: child),
        ],
      ),
    );
  }
}

/// Ouvre le picker d'activité-temps et renvoie le choix via [onPick] (l'appelant
/// gère la persistance). Réutilisé pour lier une action de projet à une activité.
Future<void> showActivityPicker(
  BuildContext context,
  AppState st,
  void Function(Activity act) onPick, {
  String? domainId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetCtx) => AssignActivitySheet(
      st: st,
      allowedDomainIds: domainId != null ? {domainId} : null,
      initiallyExpandedDomainIds: domainId != null ? {domainId} : null,
      onKeepInbox: () => Navigator.pop(sheetCtx),
      onPick: (act) {
        Navigator.pop(sheetCtx);
        onPick(act);
      },
    ),
  );
}