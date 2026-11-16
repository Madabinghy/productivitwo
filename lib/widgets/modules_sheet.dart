import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/modules.dart';
import 'package:productivitwo_v1/widgets/fiche.dart';

/// « Mes modules » (2026-11-16, lot 1 des modules) : le cœur toujours là, puis chaque module avec son
/// interrupteur. Le coaché allume ce qu'il veut, quand il veut.
Future<void> showModulesSheet(BuildContext context, {required AppLogic logic}) {
  return showFiche<void>(context, builder: (ctx, scroll) => _ModulesView(logic: logic, scroll: scroll));
}

class _ModulesView extends StatefulWidget {
  final AppLogic logic;
  final ScrollController scroll;
  const _ModulesView({required this.logic, required this.scroll});

  @override
  State<_ModulesView> createState() => _ModulesViewState();
}

class _ModulesViewState extends State<_ModulesView> {
  Future<void> _toggle(AppModule m, bool on) async {
    setState(() {});
    await widget.logic.setModule(m, on);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.logic.modules;
    final on = [for (final i in kModules) if (s.isOn(i.module)) i];
    final off = [for (final i in kModules) if (!s.isOn(i.module)) i];
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      children: [
        FicheHeader(title: 'Mes modules', chip: '${on.length} / ${kModules.length} allumés', chipColor: cs.primary),
        const SizedBox(height: 6),
        Text("Commence simple, ajoute en avançant. Tu peux tout allumer ou éteindre toi-même : rien n'est effacé.",
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.4)),
        const SizedBox(height: 14),
        Container(
          key: const ValueKey('module-core'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(Icons.favorite_outline, size: 20, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Le cœur', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text("Aujourd'hui, projets, routines, objectifs, ton coach · toujours là",
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
        if (on.isNotEmpty) ...[
          const SizedBox(height: 16),
          FicheTitle('ALLUMÉS · ${on.length}'),
          for (final i in on) _row(cs, i, true),
        ],
        if (off.isNotEmpty) ...[
          const SizedBox(height: 16),
          FicheTitle('À DÉCOUVRIR · ${off.length}'),
          for (final i in off) _row(cs, i, false),
        ],
        const SizedBox(height: 20),
        // Repartir comme un débutant (lot 4) : le cœur seul, sans rien perdre ; le retour en un tap.
        if (widget.logic.journey.before != null)
          OutlinedButton.icon(
            key: const ValueKey('modules-restore'),
            onPressed: () async {
              await widget.logic.restoreFullApp();
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text('Retrouver mon app complète'),
          )
        else
          TextButton(
            key: const ValueKey('modules-restart'),
            onPressed: () async {
              final ok = await showRestartSheet(context, logic: widget.logic);
              if (ok == true && mounted) setState(() {});
            },
            child: const Text('Repartir comme un débutant'),
          ),
      ],
    );
  }

  Widget _row(ColorScheme cs, ModuleInfo i, bool on) {
    final sub = [
      i.contains,
      if (!on && widget.logic.journey.pending == i.module) 'proposé cette semaine'
      else if (!on && i.proposedWhen != null) 'proposé ${i.proposedWhen}',
      if (i.private) 'privé · ton coach ne le voit pas',
    ].join(' · ');
    return SwitchListTile(
      key: ValueKey('module-${i.key}'),
      contentPadding: EdgeInsets.zero,
      value: on,
      onChanged: (v) => _toggle(i.module, v),
      title: Text(i.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      subtitle: Text(sub, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
    );
  }
}

/// « Repartir comme un débutant » (maquette « Modules et parcours », écran 4) : ce qu'on garde, ce qui est mis de
/// côté, ce qui repart à zéro, puis le bouton. Renvoie true si le redémarrage est fait.
Future<bool?> showRestartSheet(BuildContext context, {required AppLogic logic}) {
  final st = logic.state;
  final routines = st.activities.where((a) => !a.deleted && a.isHabit).length;
  final projects = logic.currentProjects.where((p) => p.status != 'archived').length;
  final on = logic.modules.count;
  return showFiche<bool>(context, builder: (ctx, scroll) {
    final cs = Theme.of(ctx).colorScheme;
    Widget block(String label, Color c, String text) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: c)),
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(fontSize: 13.5, height: 1.45)),
          ]),
        );
    return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 14, 20, 32), children: [
      const FicheHeader(title: 'Repartir comme un débutant'),
      const SizedBox(height: 6),
      Text("L'app redevient celle du premier jour. Tu la redécouvres à ton rythme, sans rien perdre.",
          style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant, height: 1.4)),
      const SizedBox(height: 14),
      block('TU GARDES TOUT', const Color(0xFF3DDC84), '$routines routines et leurs séries · $projects projets · tes objectifs · ton historique de chronos'),
      block('MIS DE CÔTÉ, PAS EFFACÉ', const Color(0xFF8FB0EE),
          'Tes $on modules s’éteignent. Leurs données (finances, repas, sommeil, badges…) reviennent quand tu rallumes le module.'),
      block('CE QUI REPART À ZÉRO', const Color(0xFFF5B041),
          "Le parcours : les propositions se calculent à partir d'aujourd'hui, comme pour quelqu'un qui débute."),
      const SizedBox(height: 8),
      FilledButton(
        key: const ValueKey('restart-confirm'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        onPressed: () async {
          await logic.restartAsBeginner();
          if (ctx.mounted) Navigator.pop(ctx, true);
        },
        child: const Text('Repartir du premier jour', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      const SizedBox(height: 8),
      Text('« Retrouver mon app complète » reste dans Mes modules : un tap, et tout revient comme avant.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
    ]);
  });
}
