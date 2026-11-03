import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFolderProject, rootProjectOf;
import 'package:productivitwo_v1/utils/finances.dart';

/// « De qui ? » d'une rentrée (2026-11-03) — logique pure. Les clients connus
/// sont les dossiers de projets (un dossier racine dont d'autres projets
/// dépendent : un organisme de formation, une entreprise) ; s'y ajoutent les
/// noms déjà tapés sur des rentrées (un client individuel, sans dossier).

class IncomeClient {
  /// Id du dossier client ; null = un nom déjà tapé, sans dossier.
  final String? id;
  final String name;
  const IncomeClient({this.id, required this.name});
  String get key => id ?? 'nom:${name.toLowerCase()}';
}

/// Les clients proposés : les dossiers vivants (par nom), puis les noms des
/// rentrées passées qui ne sont pas un dossier (le plus récent d'abord).
List<IncomeClient> incomeClients(List<Project> projects, Iterable<Income> incomes, {int limit = 12}) {
  final folders = [
    for (final p in projects)
      if (p.parentProjectId == null && p.status != 'archived' && p.status != 'deleted' && isFolderProject(p, projects)) p,
  ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  final out = <IncomeClient>[for (final f in folders) IncomeClient(id: f.id, name: f.title)];
  final known = {for (final c in out) c.name.trim().toLowerCase()};
  final past = incomes.toList()..sort((a, b) => b.ymd.compareTo(a.ymd) != 0 ? b.ymd.compareTo(a.ymd) : (b.at ?? 0).compareTo(a.at ?? 0));
  for (final x in past) {
    final n = (x.from ?? '').trim();
    if (n.isEmpty || x.clientId != null || !known.add(n.toLowerCase())) continue;
    out.add(IncomeClient(name: n));
  }
  return out.take(limit).toList();
}

/// Les projets d'un client (sous son dossier), vivants.
List<Project> projectsOfClient(String clientId, List<Project> projects) => [
      for (final p in projects)
        if (p.id != clientId && p.status == 'active' && !p.paused && rootProjectOf(p, projects).id == clientId) p,
    ];

/// Ce qu'un client a versé sur une période (centimes), par client (clé `IncomeClient.key`).
Map<String, int> incomeByClient(Iterable<Income> incomes, String from, String to) {
  final out = <String, int>{};
  for (final x in incomes) {
    if (x.ymd.compareTo(from) < 0 || x.ymd.compareTo(to) > 0) continue;
    final n = (x.from ?? '').trim();
    final k = x.clientId ?? (n.isEmpty ? '' : 'nom:${n.toLowerCase()}');
    out[k] = (out[k] ?? 0) + x.amount;
  }
  return out;
}
