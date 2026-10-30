import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/badge_gallery_screen.dart' show showBadgeGallerySheet;
import 'package:productivitwo_v1/widgets/badge_painter.dart' show kBadgeBrass;
import 'package:productivitwo_v1/widgets/objectives_card.dart';
import 'package:productivitwo_v1/widgets/season_view.dart';

/// Onglet OBJECTIFS (refonte « une liste, une fiche », 2026-10-30) : deux tuiles
/// (Saison, Badges) puis la liste des coups et objectifs ; tap sur une ligne =
/// fiche de l'objectif, appui long = édition. L'intention du jour, le prochain
/// bloc et les engagements 7 j (doublons d'Aujourd'hui et de Ma semaine) sont
/// partis ; l'ancien Accueil n'a plus d'entrée ici.
class ObjectivesHomeView extends StatelessWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final BadgeCenter? badges;
  final List<Project> projects;
  final VoidCallback onOpenDashboard;
  final VoidCallback? onOpenNow;

  const ObjectivesHomeView({
    super.key,
    required this.logic,
    required this.sync,
    this.badges,
    required this.projects,
    required this.onOpenDashboard,
    this.onOpenNow,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text('Objectifs', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.onSurface)),
          ),
          if (badges case final bc?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(children: [
                Expanded(child: SeasonTile(logic: logic, center: bc)),
                const SizedBox(width: 8),
                Expanded(child: _BadgesTile(logic: logic, center: bc, sync: sync)),
              ]),
            ),
          ObjectivesCard(logic: logic, sync: sync, projects: projects),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// « BADGES · 14 / 43 · 5 séries » ; tap = tous les badges en feuille.
class _BadgesTile extends StatelessWidget {
  final AppLogic logic;
  final BadgeCenter center;
  final FirestoreSync sync;
  const _BadgesTile({required this.logic, required this.center, required this.sync});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: center,
      builder: (context, _) {
        final d = center.deck;
        return SmallTile(
          eyebrow: 'BADGES',
          onTap: () => showBadgeGallerySheet(context, logic: logic, sync: sync, center: center),
          child: d == null
              ? const Text('…', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))
              : Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${d.acquired}', style: const TextStyle(color: kBadgeBrass)),
                    TextSpan(text: ' / ${d.total}${d.seriesRunning > 0 ? ' · ${d.seriesRunning} séries' : ''} ›'),
                  ]),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
        );
      },
    );
  }
}
