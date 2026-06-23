import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/widgets/collection_sheet.dart';
import 'package:productivitwo_v1/widgets/expedition_sheet.dart';
import 'package:productivitwo_v1/web/docks_sheet.dart';
import 'package:productivitwo_v1/web/invasion_defense_sheet.dart';

/// Affichage des modes EXPÉRIMENTAUX ("Labs") sortis de la boucle principale.
///
/// Donjon, Mes cartes (collection), Mes Docks et Invasion vivaient en vrac dans
/// l'onglet Arène et lui faisaient perdre toute cohérence. On les regroupe ici,
/// derrière une entrée discrète, sans rien supprimer du code : ils restent
/// jouables et réintégrables quand ils auront un rôle clair dans le Royaume.
const bool kLabsEnabled = bool.fromEnvironment('LABS', defaultValue: true);

Future<void> showLabsSheet(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  final inDungeon = logic.state.expeditionDonjonLevel > 0;
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      void open(void Function(BuildContext, AppLogic, FirestoreSync) fn) {
        Navigator.pop(ctx);
        fn(context, logic, sync);
      }

      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 4),
              child: Row(children: [
                const Icon(Icons.science_outlined, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Labs — expérimental',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Modes en cours de conception, hors de la boucle principale.',
                style: TextStyle(
                    fontSize: 12, color: cs.onSurface.withOpacity(.55)),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LabBtn(
                        emoji: inDungeon ? '🏰' : '🔒',
                        title: inDungeon ? 'Reprendre le donjon' : 'Donjon',
                        subtitle: inDungeon
                            ? 'Reprends où tu t\'es arrêté'
                            : 'Atteins le château sur la carte d\'abord',
                        color: const Color(0xFF8B5CF6),
                        onTap: inDungeon
                            ? () => open(showExpeditionSheet)
                            : null,
                      ),
                      const SizedBox(height: 10),
                      _LabBtn(
                        emoji: '🗺️',
                        title: 'Mes cartes',
                        subtitle:
                            'Ta collection de créatures et recettes de chasse',
                        color: const Color(0xFF22C55E),
                        onTap: () => open(showCollectionSheet),
                      ),
                      const SizedBox(height: 10),
                      _LabBtn(
                        emoji: '🗃️',
                        title: 'Mes Docks',
                        subtitle:
                            'Tes decks en colonnes : vert · rouge · cartes · territoires',
                        color: const Color(0xFF06B6D4),
                        onTap: () => open(showDocksSheet),
                      ),
                      const SizedBox(height: 10),
                      _LabBtn(
                        emoji: '👑',
                        title: 'Invasion',
                        subtitle:
                            'Forge ton armée, envahis le ladder, défends ton territoire',
                        color: const Color(0xFFA855F7),
                        onTap: () => open(showInvasionSheet),
                      ),
                    ]),
              ),
            ),
          ]),
        ),
      );
    },
  );
}

class _LabBtn extends StatelessWidget {
  final String emoji, title, subtitle;
  final Color color;
  final VoidCallback? onTap;
  const _LabBtn({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(.35)),
          ),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurface.withOpacity(.55))),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: cs.onSurface.withOpacity(.35), size: 18),
          ]),
        ),
      ),
    );
  }
}
