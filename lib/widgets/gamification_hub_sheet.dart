import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/widgets/gold_sheet.dart';
import 'package:productivitwo_v1/widgets/gold_icon.dart';
import 'package:productivitwo_v1/widgets/leaderboard_sheet.dart';
import 'package:productivitwo_v1/widgets/scheduled_challenges_sheet.dart';
import 'package:productivitwo_v1/web/unified_world_sheet.dart';

/// Hub gamification : un seul point d'entrée regroupant Mon or · Score ·
/// Classement · Défis. Réutilise les contenus embarquables des sheets existants ;
/// l'onglet Score est fourni par l'appelant (`scoreTab`) car il dépend de l'état
/// de l'écran d'accueil.
Future<void> showGamificationHub(
  BuildContext context,
  AppLogic logic,
  FirestoreSync sync, {
  required WidgetBuilder scoreTab,
  RoutineLaunch? onLaunchRoutine,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Pas de drag-to-dismiss : le drag vertical sur la carte (onglet Monde) fermait
    // le sheet. Fermeture via la croix (cf. _GamificationHub).
    enableDrag: false,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _GamificationHub(
          logic: logic,
          sync: sync,
          scoreTab: scoreTab,
          onLaunchRoutine: onLaunchRoutine),
    ),
  );
}

class _GamificationHub extends StatelessWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final WidgetBuilder scoreTab;
  final RoutineLaunch? onLaunchRoutine;
  const _GamificationHub(
      {required this.logic,
      required this.sync,
      required this.scoreTab,
      this.onLaunchRoutine});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Row(children: [
            Expanded(
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: cs.primary,
                unselectedLabelColor: cs.onSurface.withValues(alpha: .55),
                indicatorColor: cs.primary,
                tabs: [
                  const Tab(text: '⚔️ Combat'),
                  Tab(
                    child:
                        Row(mainAxisSize: MainAxisSize.min, children: const [
                      GoldIcon(size: 15),
                      SizedBox(width: 5),
                      Text('Mon or'),
                    ]),
                  ),
                  const Tab(text: '📊 Progrès'),
                  const Tab(text: '🌍 Monde'),
                ],
              ),
            ),
            // Croix de fermeture (le drag-dismiss du sheet est désactivé).
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Fermer',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ]),
          Expanded(
            child: TabBarView(
              // Le swipe horizontal des onglets entre en conflit avec le pan de la
              // carte (onglet Monde) : on désactive le swipe → les onglets se
              // changent au tap des chips, et la carte récupère le drag.
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // ⚔️ Combat : l'action (backlog + cartes + combats en cours)
                GoldSheetBody(
                    logic: logic,
                    sync: sync,
                    onLaunchRoutine: onLaunchRoutine,
                    embeddedInSheet: true,
                    showEconomySection: false),
                // 🪙 Mon or : économie pure (solde, arsenal, boutique, histo…)
                GoldSheetBody(
                    logic: logic,
                    sync: sync,
                    onLaunchRoutine: onLaunchRoutine,
                    embeddedInSheet: true,
                    showCombatSection: false),
                // 📊 Progrès : XP · Classement · Défis regroupés (peu visités)
                _ProgressTab(logic: logic, sync: sync, scoreTab: scoreTab),
                // 🌍 Monde : carte cinématique web (mode mobile embarqué)
                UnifiedWorldScreen(logic: logic, sync: sync),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Onglet « Progrès » : regroupe XP · Classement · Défis en sous-onglets
/// (on y va peu → un seul onglet de haut niveau).
class _ProgressTab extends StatelessWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final WidgetBuilder scoreTab;
  const _ProgressTab(
      {required this.logic, required this.sync, required this.scoreTab});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurface.withValues(alpha: .55),
            indicatorColor: cs.primary,
            labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: '⭐ XP'),
              Tab(text: '🏆 Classement'),
              Tab(text: '🔥 Défis'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                Builder(builder: scoreTab),
                LeaderboardBody(sync: sync),
                ScheduledChallengesBody(logic: logic, sync: sync),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
