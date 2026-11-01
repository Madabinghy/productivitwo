import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/game_rules.dart' show kRuleLetGo;
import 'package:productivitwo_v1/widgets/info_dot.dart' show InfoDot;

/// Retirer un bloc (maquette validée 2026-11-01 « Lâcher un bloc ») : on dit
/// pourquoi, en un tap — déplacer (rien n'est perdu), lâcher (compte comme non
/// fait), empêché (ne compte pas), posé par erreur (effacé).
enum RemoveBlockChoice { move, letGo, prevented, mistake, tenMin }

const kLetGoColor = Color(0xFFF2A33A);
const _kPreventedColor = Color(0xFF7FD3A0);
const _kMoveColor = Color(0xFF9DB8FF);

Future<RemoveBlockChoice?> showRemoveBlockSheet(BuildContext context, ScheduleBlock block, {bool flemme = false}) {
  final cs = Theme.of(context).colorScheme;
  // Rendez-vous de Google Agenda : il se déplace dans l'agenda ; lâché ou
  // empêché, le rendez-vous y reste (seule la trace change ici).
  final mirror = block.gcalEventId != null;
  Widget option(RemoveBlockChoice c, String icon, Color color, String title, String text, String cons) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(context, c),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(10)),
                  child: Text(icon, style: const TextStyle(fontSize: 17)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(text, style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .7), height: 1.35)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
                      child: Text(cons, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
  return showModalBottomSheet<RemoveBlockChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: Text('${block.title} · ${block.startTime}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            ),
            const InfoDot(kRuleLetGo),
          ]),
          const SizedBox(height: 4),
          Text('Tu le retires de ta journée. Pourquoi ?', style: TextStyle(fontSize: 13.5, color: cs.onSurface.withValues(alpha: .7))),
          const SizedBox(height: 12),
          if (flemme)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              decoration: BoxDecoration(color: kLetGoColor.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Expanded(child: Text('Mode Flemme. Avant de lâcher : juste 10 min ?', style: TextStyle(fontSize: 13))),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, RemoveBlockChoice.tenMin),
                  style: FilledButton.styleFrom(backgroundColor: kLetGoColor, foregroundColor: const Color(0xFF1F0B02), visualDensity: VisualDensity.compact),
                  child: const Text('10 min', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ]),
            ),
          if (!mirror) option(RemoveBlockChoice.move, '↪', _kMoveColor, 'Je le déplace', 'Plus tard aujourd’hui ou demain.', 'rien n’est perdu'),
          if (mirror)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Rendez-vous de ton agenda : pour le déplacer, fais-le dans Google Agenda. Lâché ou empêché, il y reste.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .6), height: 1.35)),
            ),
          option(RemoveBlockChoice.letGo, '✋', kLetGoColor, 'Je lâche ce bloc', 'J’aurais pu. Je choisis de ne pas le faire.', 'compte comme non fait'),
          option(RemoveBlockChoice.prevented, '⛔', _kPreventedColor, 'J’ai été empêché', 'Hors de mon contrôle : malade, imprévu, annulé.',
              'ne compte pas'),
          TextButton(
            onPressed: () => Navigator.pop(ctx, RemoveBlockChoice.mistake),
            child: Text(mirror ? 'Posé par erreur · le masquer ou le supprimer de l’agenda' : 'Posé par erreur · l’effacer', style: TextStyle(color: cs.onSurface.withValues(alpha: .55), decoration: TextDecoration.underline)),
          ),
        ]),
      ),
    ),
  );
}

/// Juste après « Je lâche » : la porte se ferme, la suite s'ouvre. [next] =
/// les prochains blocs à faire (titre, heure), [routinesLeft] = routines
/// quotidiennes pas encore atteintes, [capLine] = Cap tenu (null si la journée
/// n'a pas été posée la veille).
Future<void> showLetGoDoneSheet(
  BuildContext context, {
  required ScheduleBlock block,
  required List<ScheduleBlock> next,
  required int routinesLeft,
  String? capLine,
  VoidCallback? onGuerilla,
}) {
  final cs = Theme.of(context).colorScheme;
  Widget line(String title, String sub, {Widget? trailing}) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              Text(sub, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .6))),
            ]),
          ),
          if (trailing != null) trailing,
        ]),
      );
  Widget kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(fontSize: 13.5))),
          Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color ?? cs.onSurface.withValues(alpha: .75))),
        ]),
      );
  Text label(String t) => Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1, color: cs.onSurface.withValues(alpha: .55)));
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('✋ ${block.title.toUpperCase()} LÂCHÉ', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, letterSpacing: 1, color: kLetGoColor)),
          const SizedBox(height: 6),
          const Text('C’est décidé.', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text.rich(TextSpan(style: TextStyle(fontSize: 13.5, height: 1.5, color: cs.onSurface.withValues(alpha: .75)), children: const [
            TextSpan(text: 'Ne pas faire, c’est aussi décider. Ce bloc compte comme non fait, et c’est tout : '),
            TextSpan(text: 'le reste de ta journée est intact.', style: TextStyle(fontWeight: FontWeight.w800)),
          ])),
          const SizedBox(height: 14),
          label('CE QUI RESTE POSSIBLE AUJOURD’HUI'),
          const SizedBox(height: 6),
          for (final b in next.take(2)) line(b.title, 'bloc à ${b.startTime}'),
          if (routinesLeft > 0) line('$routinesLeft routine${routinesLeft > 1 ? 's' : ''} à atteindre', 'le Métronome est encore jouable'),
          if (onGuerilla != null)
            line('Guérilla · 5 min', 'un petit coup, pour redémarrer',
                trailing: TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onGuerilla();
                  },
                  child: const Text('⚡ Lancer'),
                )),
          if (next.isEmpty && routinesLeft == 0 && onGuerilla == null) line('Rien d’autre de prévu', 'la journée reste à toi'),
          const SizedBox(height: 10),
          label('CE QUE ÇA CHANGE'),
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              kv('Journée parfaite', 'plus possible aujourd’hui', color: kLetGoColor),
              if (capLine != null) kv('Cap tenu', capLine),
              kv('Montre suisse, Métronome, séries', 'intacts', color: _kPreventedColor),
            ]),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: const Text('Passer à la suite', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ]),
      ),
    ),
  );
}
