import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

/// Activités d'un domaine, pour les sélecteurs groupés.
typedef ActivityGroup = ({String? domainId, String name, Color? color, List<Activity> activities});

/// Activités groupées par domaine (ordre des domaines, [preferDomainId] en
/// tête, sans domaine à la fin), triées par nom dans chaque groupe.
List<ActivityGroup> groupActivitiesByDomain(List<Activity> acts, List<Domain> domains, {String? preferDomainId}) {
  int byName(Activity a, Activity b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
  final out = <ActivityGroup>[];
  for (final d in domains) {
    final list = acts.where((a) => a.domainId == d.id).toList()..sort(byName);
    if (list.isNotEmpty) out.add((domainId: d.id, name: d.name, color: domainColor(d.id, domains), activities: list));
  }
  if (preferDomainId != null) {
    final i = out.indexWhere((g) => g.domainId == preferDomainId);
    if (i > 0) out.insert(0, out.removeAt(i));
  }
  final known = domains.map((d) => d.id).toSet();
  final rest = acts.where((a) => !known.contains(a.domainId)).toList()..sort(byName);
  if (rest.isNotEmpty) out.add((domainId: null, name: 'Sans domaine', color: null, activities: rest));
  return out;
}

/// En-tête de domaine d'un sélecteur : pastille de couleur + nom en capitales.
class ActivityDomainHeader extends StatelessWidget {
  final String name;
  final Color? color;
  final EdgeInsetsGeometry padding;
  const ActivityDomainHeader({super.key, required this.name, this.color, this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 2)});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color ?? cs.primary, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: cs.onSurface.withValues(alpha: .55))),
        ),
      ]),
    );
  }
}

/// Entrée hors activités d'un sélecteur (« Aucune », « Juste cocher »…).
class ActivityPickerExtra {
  final String value;
  final String label;
  final IconData icon;
  final bool selected;
  const ActivityPickerExtra(this.value, this.label, {this.icon = Icons.block, this.selected = false});
}

/// Sélecteur d'activité partagé (2026-10-30, retour user : « partout où je
/// choisis une activité, groupé par domaine avec sa couleur ») : feuille
/// défilante, une section par domaine, coche sur [selectedId]. Renvoie l'id de
/// l'activité choisie ou la valeur d'une [extras], null si fermée.
Future<String?> showActivityPicker(
  BuildContext context, {
  required List<Activity> activities,
  required List<Domain> domains,
  required String title,
  String? subtitle,
  String? selectedId,
  String? preferDomainId,
  List<ActivityPickerExtra> extras = const [],
  List<ActivityPickerExtra> trailingExtras = const [],
}) {
  final groups = groupActivitiesByDomain(activities, domains, preferDomainId: preferDomainId);
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      Widget extra(ActivityPickerExtra e) => ListTile(
            dense: true,
            leading: Icon(e.icon, size: 20),
            title: Text(e.label, style: const TextStyle(fontSize: 15)),
            trailing: e.selected ? Icon(Icons.check_rounded, size: 18, color: cs.primary) : null,
            onTap: () => Navigator.pop(ctx, e.value),
          );
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .8),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 16), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(subtitle, style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .55))),
              ),
            for (final e in extras) extra(e),
            if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Aucune activité disponible.', style: TextStyle(fontStyle: FontStyle.italic)),
              ),
            for (final g in groups) ...[
              ActivityDomainHeader(name: g.name, color: g.color),
              for (final a in g.activities)
                ListTile(
                  dense: true,
                  leading: Icon(
                      a.iconCode != null ? IconData(a.iconCode!, fontFamily: 'MaterialIcons') : Icons.timer_outlined,
                      size: 20,
                      color: g.color),
                  title: Text(a.name, style: const TextStyle(fontSize: 15)),
                  trailing: a.id == selectedId ? Icon(Icons.check_rounded, size: 18, color: g.color ?? cs.primary) : null,
                  onTap: () => Navigator.pop(ctx, a.id),
                ),
            ],
            for (final e in trailingExtras) extra(e),
          ]),
        ),
      );
    },
  );
}

/// Entrées d'une liste déroulante groupées par domaine (web) : en-têtes non
/// sélectionnables, pastille de couleur devant chaque activité.
List<DropdownMenuItem<String>> groupedActivityItems(List<ActivityGroup> groups, {Color? headerColor}) => [
      for (final g in groups) ...[
        DropdownMenuItem<String>(
          value: '__domain:${g.domainId ?? ''}',
          enabled: false,
          child: Text(g.name.toUpperCase(),
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: g.color ?? headerColor)),
        ),
        for (final a in g.activities)
          DropdownMenuItem<String>(
            value: a.id,
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: g.color ?? headerColor, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Flexible(child: Text(a.name, overflow: TextOverflow.ellipsis)),
            ]),
          ),
      ],
    ];
