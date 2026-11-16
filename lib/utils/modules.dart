/// Modules (inventaire validé 2026-11-12) : un cœur que tout le monde voit, et des modules qu'on allume.
/// Stockage `data/meta.modules {v: 1, on: [clés]}`. Absent = un compte d'avant les modules : tout est
/// allumé, rien ne change pour lui.
enum AppModule { modes, planning, game, seasons, sleep, sport, kitchen, finances, freedom, analysis, trainer, assistant }

class ModuleInfo {
  final AppModule module;
  final String key;
  final String name;
  /// Ce que le module contient, en une ligne.
  final String contains;
  /// Ce qui le fera proposer par l'app (parcours, lot 3) ; null = jamais proposé.
  final String? proposedWhen;
  /// Privé : le coach ne voit jamais qu'il est allumé.
  final bool private;
  const ModuleInfo(this.module, this.key, this.name, this.contains, {this.proposedWhen, this.private = false});
}

const List<ModuleInfo> kModules = [
  ModuleInfo(AppModule.modes, 'modes', "Modes d'action", 'Guérilla, Sniper, Offensive et Deep work, Enchaîner',
      proposedWhen: "les jours où l'élan manque"),
  ModuleInfo(AppModule.planning, 'planning', 'Planification', 'Planifier demain, blocs de temps, Parole tenue, Revue du dimanche',
      proposedWhen: 'quand tu poses tes journées'),
  ModuleInfo(AppModule.game, 'game', 'Jeu et badges', 'Ta journée en enjeux, badges en cartes, Montre suisse, Métronome, rushs',
      proposedWhen: 'après 14 jours de routines tenues'),
  ModuleInfo(AppModule.seasons, 'seasons', 'Saisons', 'Une période pour tes objectifs, et son bilan',
      proposedWhen: 'après ton premier objectif'),
  ModuleInfo(AppModule.sleep, 'sleep', 'Sommeil', 'Tes nuits, ta dette, ton coucher, la Recharge',
      proposedWhen: 'quand tu chronomètres tes nuits'),
  ModuleInfo(AppModule.sport, 'sport', 'Sport', 'Tes séances, la muscu série par série, ta semaine',
      proposedWhen: 'après 3 séances chronométrées'),
  ModuleInfo(AppModule.kitchen, 'kitchen', 'Cuisine', 'Repas, plats, menu de la semaine, courses, placards',
      proposedWhen: 'avec une routine Repas tenue'),
  ModuleInfo(AppModule.finances, 'finances', 'Finances', 'Dépenses en cinq secondes, compte en direct, tickets',
      proposedWhen: "avec un objectif d'argent"),
  ModuleInfo(AppModule.freedom, 'freedom', 'Liberté', "Sortir d'une habitude : envies, écarts, jours libres",
      private: true),
  ModuleInfo(AppModule.analysis, 'analysis', 'Analyse', 'Les 168 heures, ton élan en détail, estimé contre réel',
      proposedWhen: 'après 30 jours'),
  ModuleInfo(AppModule.trainer, 'trainer', 'Formateur', 'Tes séances de formation : préparation, déroulé, bilan'),
  ModuleInfo(AppModule.assistant, 'assistant', 'Assistant', 'ORION et ses propositions'),
];

ModuleInfo moduleInfo(AppModule m) => kModules.firstWhere((i) => i.module == m);

AppModule? moduleOfKey(String key) {
  for (final i in kModules) {
    if (i.key == key) return i.module;
  }
  return null;
}

class ModuleSettings {
  /// null = tout est allumé (compte d'avant les modules, rien n'a encore été réglé).
  final Set<AppModule>? on;
  const ModuleSettings._(this.on);
  static const ModuleSettings everything = ModuleSettings._(null);
  const ModuleSettings.only(Set<AppModule> modules) : on = modules;

  bool get isEverything => on == null;
  bool isOn(AppModule m) => on == null || on!.contains(m);
  int get count => on == null ? kModules.length : on!.length;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'on': [for (final i in kModules) if (isOn(i.module)) i.key],
      };

  bool sameAs(ModuleSettings o) =>
      on == null ? o.on == null : (o.on != null && on!.length == o.on!.length && on!.containsAll(o.on!));
}

ModuleSettings parseModules(dynamic raw) {
  if (raw is! Map || raw['on'] is! List) return ModuleSettings.everything;
  final set = <AppModule>{};
  for (final k in raw['on'] as List) {
    final m = moduleOfKey('$k');
    if (m != null) set.add(m);
  }
  return ModuleSettings.only(set);
}

/// Allume ou éteint un module ; un réglage « tout allumé » devient la liste explicite.
ModuleSettings withModule(ModuleSettings s, AppModule m, bool on) {
  final next = {for (final i in kModules) if (s.isOn(i.module)) i.module};
  if (on) {
    next.add(m);
  } else {
    next.remove(m);
  }
  return ModuleSettings.only(next);
}
