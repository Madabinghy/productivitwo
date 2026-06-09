import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/widgets/gold_sheet.dart';
import 'package:productivitwo_v1/widgets/leaderboard_sheet.dart';
import 'package:productivitwo_v1/widgets/scheduled_challenges_sheet.dart';

/// Hub gamification : un seul point d'entrée regroupant Mon or · Score ·
/// Classement · Défis. Réutilise les contenus embarquables des sheets existants ;
/// l'onglet Score est fourni par l'appelant (`scoreTab`) car il dépend de l'état
/// de l'écran d'accueil.
Future<void> showGamificationHub(
  BuildContext context,
  AppLogic logic,
  FirestoreSync sync, {
  required WidgetBuilder scoreTab,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _GamificationHub(logic: logic, sync: sync, scoreTab: scoreTab),
    ),
  );
}

class _GamificationHub extends StatelessWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final WidgetBuilder scoreTab;
  const _GamificationHub(
      {required this.logic, required this.sync, required this.scoreTab});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurface.withValues(alpha: .55),
            indicatorColor: cs.primary,
            tabs: const [
              Tab(text: '🪙 Mon or'),
              Tab(text: '🎯 Score'),
              Tab(text: '🏆 Classement'),
              Tab(text: '🔥 Défis'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                GoldSheetBody(logic: logic, sync: sync),
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
