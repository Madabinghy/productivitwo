import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/miracle_morning.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart' show momentWindowLabel;
import 'package:productivitwo_v1/widgets/undo_snack.dart';

/// Le passage (2026-11-21, maquette validée « Sniper par moment ») : l'ancien Miracle Morning, ses étapes dans un
/// écran à part, devient un MOMENT de la journée que le Sniper déroule. Une fois, tant que des étapes réglées
/// n'ont pas été passées en routines du moment.
const kPassageAccent = Color(0xFFFFB870);

/// La carte d'Aujourd'hui : elle annonce le passage et ouvre sa feuille. « Plus tard » la cache jusqu'au
/// prochain lancement.
class MiraclePassageCard extends StatefulWidget {
  final AppLogic logic;
  const MiraclePassageCard({super.key, required this.logic});

  @override
  State<MiraclePassageCard> createState() => _MiraclePassageCardState();
}

class _MiraclePassageCardState extends State<MiraclePassageCard> {
  static bool _later = false;

  @override
  Widget build(BuildContext context) {
    final logic = widget.logic;
    if (_later || !logic.miraclePassageDue) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final n = logic.miracleMorning!.steps.length;
    return Container(
      key: const Key('miracle-passage-card'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: kPassageAccent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPassageAccent.withValues(alpha: .5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('MIRACLE MORNING', style: TextStyle(fontSize: 11, letterSpacing: .8, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: .7))),
        const SizedBox(height: 4),
        const Text('Ton Miracle Morning devient un moment de la journée', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Tes $n étape${n > 1 ? 's' : ''} passent dans le Sniper : il te les propose au réveil, dans ton ordre. Rien n’est effacé.',
            style: TextStyle(fontSize: 13.5, height: 1.35, color: cs.onSurface.withValues(alpha: .75))),
        const SizedBox(height: 6),
        Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton(
            key: const Key('miracle-passage-open'),
            onPressed: () async {
              await showMiraclePassage(context, logic: logic);
              if (mounted) setState(() {});
            },
            child: const Text('Voir le passage'),
          ),
          TextButton(onPressed: () => setState(() => _later = true), child: const Text('Plus tard')),
        ]),
      ]),
    );
  }
}

Future<void> showMiraclePassage(BuildContext context, {required AppLogic logic}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => MiraclePassageSheet(logic: logic),
    );

class MiraclePassageSheet extends StatefulWidget {
  final AppLogic logic;
  const MiraclePassageSheet({super.key, required this.logic});

  @override
  State<MiraclePassageSheet> createState() => _MiraclePassageSheetState();
}

class _MiraclePassageSheetState extends State<MiraclePassageSheet> {
  /// Étapes libres à ne pas garder.
  final _dropped = <String>{};
  bool _busy = false;

  Future<void> _run() async {
    final logic = widget.logic;
    final messenger = ScaffoldMessenger.maybeOf(context), nav = Navigator.of(context);
    setState(() => _busy = true);
    await logic.runMiraclePassage(dropped: _dropped);
    final window = momentWindowLabel(logic.dayStartMin, logic.miraclePassageEnd);
    nav.pop();
    messenger?.showClosingSnackBar(SnackBar(
        content: Text('Passage fait · ton Miracle Morning est un moment ($window). Ouvre le Sniper au réveil.'), duration: const Duration(seconds: 6)));
  }

  @override
  Widget build(BuildContext context) {
    final logic = widget.logic, cs = Theme.of(context).colorScheme;
    final lines = logic.miraclePassageLines;
    final mute = cs.onSurface.withValues(alpha: .6);
    final window = momentWindowLabel(logic.dayStartMin, logic.miraclePassageEnd);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Text('Ton Miracle Morning devient un moment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              'Comme le matin ou le soir. Au réveil, le Sniper te propose ses routines, dans ton ordre ; ce qui n’est pas fait revient le matin. '
              'L’écran d’avant et le rond 🌅 disparaissent.',
              style: TextStyle(fontSize: 13, height: 1.35, color: mute)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .05), borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              for (final (i, l) in lines.indexed) ...[
                if (i > 0) Divider(height: 1, color: cs.onSurface.withValues(alpha: .08)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text.rich(TextSpan(children: [
                          TextSpan(text: l.step.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                          TextSpan(text: '   ${l.before}', style: TextStyle(fontSize: 12, color: mute)),
                        ])),
                        const SizedBox(height: 2),
                        Text(
                            l.kind == PassageKind.created && _dropped.contains(l.step.id) ? 'ne sera pas gardée' : l.after,
                            style: TextStyle(fontSize: 13, color: l.kind == PassageKind.created && _dropped.contains(l.step.id) ? mute : cs.onSurface.withValues(alpha: .85))),
                      ]),
                    ),
                    if (l.kind == PassageKind.created)
                      Switch(
                        key: Key('miracle-passage-keep-${l.step.id}'),
                        value: !_dropped.contains(l.step.id),
                        onChanged: (on) => setState(() => on ? _dropped.remove(l.step.id) : _dropped.add(l.step.id)),
                      ),
                  ]),
                ),
              ],
            ]),
          ),
          if (lines.any((l) => l.kind == PassageKind.created)) ...[
            const SizedBox(height: 8),
            Text('Une étape libre gardée devient une vraie routine : elle comptera dans ta journée (Métronome, Journée parfaite). Éteins celles que tu ne veux pas.',
                style: TextStyle(fontSize: 12.5, height: 1.35, color: mute)),
          ],
          const SizedBox(height: 12),
          Text('Le moment : $window · ordre et durées gardés. Tu le règles ensuite dans « Moments de la journée ».',
              key: const Key('miracle-passage-window'), style: TextStyle(fontSize: 13, height: 1.35, color: cs.onSurface.withValues(alpha: .8))),
          const SizedBox(height: 14),
          FilledButton(key: const Key('miracle-passage-run'), onPressed: _busy ? null : _run, child: const Text('Faire le passage')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Plus tard')),
        ]),
      ),
    );
  }
}
