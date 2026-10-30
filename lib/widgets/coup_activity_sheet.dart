import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/activity_picker.dart';

/// Guérilla / Offensive (2026-10-30, retour user) : une action sans activité
/// ne compte son temps nulle part. Au moment du coup, on demande où le compter
/// — pour cette action ou pour tout le projet — ou on passe sans chrono.

Future<String?> _pick(BuildContext context, AppLogic logic, {required String title, String? subtitle, String? preferDomainId}) {
  final st = logic.state;
  return showActivityPicker(context,
      activities: st.activeActivities.where((a) => a.type == 'time').toList(),
      domains: st.activeDomains,
      title: title,
      subtitle: subtitle,
      preferDomainId: preferDomainId);
}

/// Lie le projet entier à une activité (toutes ses actions comptent ensuite).
/// Renvoie l'activité choisie, ou null.
Future<String?> linkProjectActivity(BuildContext context, AppLogic logic, Project project) async {
  final id = await _pick(context, logic, title: 'Où compter le temps de « ${project.title} » ?', subtitle: 'Toutes ses actions compteront dans cette activité.', preferDomainId: project.domainId);
  if (id == null || id.isEmpty) return null;
  project.linkedActivityId = id;
  await logic.sync?.saveProject(project);
  return id;
}

/// « Où compter ce temps ? » pour une action de projet sans activité : pour
/// cette action, pour tout le projet, ou sans chrono (null).
Future<String?> askCoupActivity(BuildContext context, AppLogic logic, {required Project project, required TaskAction action}) async {
  final scope = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) {
      final cs = Theme.of(c).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Où compter ce temps ?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('« ${action.title} » n’est liée à aucune activité : sans elle, ces minutes ne comptent nulle part.',
                style: TextStyle(fontSize: 13.5, height: 1.4, color: cs.onSurface.withValues(alpha: .7))),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.pop(c, 'action'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('Choisir une activité pour cette action'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(c, 'project'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text('Pour tout le projet « ${project.title} »', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Sans chrono')),
          ]),
        ),
      );
    },
  );
  if (scope == null || !context.mounted) return null;
  if (scope == 'project') return linkProjectActivity(context, logic, project);
  final id = await _pick(context, logic, title: 'Où compter « ${action.title} » ?', preferDomainId: project.domainId);
  if (id == null || id.isEmpty) return null;
  action.linkedActivityId = id;
  await logic.sync?.patchActionOf(project, action);
  return id;
}
