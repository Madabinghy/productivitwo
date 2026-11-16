import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/module_journey.dart';
import 'package:productivitwo_v1/utils/modules.dart';
import 'package:productivitwo_v1/widgets/undo_snack.dart';

/// Où retrouver un module une fois allumé.
const kModuleWhere = {
  AppModule.modes: "les ronds Guérilla, Sniper et Offensive en haut d'Aujourd'hui",
  AppModule.planning: "le rond 🧭 en haut d'Aujourd'hui",
  AppModule.game: "Ta journée, en tête d'Aujourd'hui",
  AppModule.seasons: "le bandeau de saison, en tête d'Organisation",
  AppModule.sleep: 'les barres de sommeil, en haut',
  AppModule.sport: 'le rond Sport, en haut',
  AppModule.kitchen: 'le rond Repas, en haut',
  AppModule.finances: "la tuile Finances d'Organisation",
  AppModule.analysis: "le compteur des 168 h, en tête d'Organisation",
};

const _kAccent = Color(0xFF8FB0EE);

/// La carte « Nouveau pour toi » (maquette validée « Modules et parcours », écran 2) : le module proposé,
/// ce qui l'a déclenché, ce qu'il apporte ; Essayer · Plus tard · Pas pour moi.
class ModuleProposalCard extends StatelessWidget {
  final AppLogic logic;
  final AppModule module;
  final JourneyFacts facts;
  const ModuleProposalCard({super.key, required this.logic, required this.module, required this.facts});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = moduleInfo(module);
    final signal = moduleSignal(module, facts);
    final on = logic.modules.count;
    return Container(
      key: const ValueKey('module-proposal'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kAccent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kAccent.withValues(alpha: .45), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(
            child: Text('NOUVEAU POUR TOI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: _kAccent)),
          ),
          Text('$on / ${kModules.length} modules', style: const TextStyle(fontSize: 12, color: _kAccent)),
        ]),
        const SizedBox(height: 8),
        Text(signal?.pitch ?? info.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.25, color: cs.onSurface)),
        if (signal != null) ...[
          const SizedBox(height: 6),
          Text('Pourquoi maintenant : ${signal.why}', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .05), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Le module ${info.name} t’apporte', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(info.contains, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.4)),
          ]),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('module-proposal-accept'),
          style: FilledButton.styleFrom(backgroundColor: _kAccent, foregroundColor: const Color(0xFF0A1630), minimumSize: const Size.fromHeight(48)),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            await logic.setModule(module, true);
            final where = kModuleWhere[module];
            messenger.showClosingSnackBar(SnackBar(content: Text('${info.name} allumé${where == null ? '' : ' · tu le trouves dans $where'}')));
          },
          child: Text('Essayer ${info.name}', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton(key: const ValueKey('module-proposal-later'), onPressed: () => logic.declineModule(module), child: const Text('Plus tard')),
          TextButton(key: const ValueKey('module-proposal-never'), onPressed: () => logic.declineModule(module, never: true), child: const Text('Pas pour moi')),
        ]),
      ]),
    );
  }
}
