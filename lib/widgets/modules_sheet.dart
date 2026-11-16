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
      ],
    );
  }

  Widget _row(ColorScheme cs, ModuleInfo i, bool on) {
    final sub = [
      i.contains,
      if (!on && i.proposedWhen != null) 'proposé ${i.proposedWhen}',
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
