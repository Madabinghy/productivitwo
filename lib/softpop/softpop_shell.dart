import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'softpop_tokens.dart';
import 'softpop_theme.dart';
import 'softpop_components.dart';
import 'softpop_home_live_screen.dart';
import 'softpop_focus_live_screen.dart';
import 'softpop_balance_live_screen.dart';
import 'softpop_lair_screen.dart';

/// Coquille de l'app « Soft Pop » — la nouvelle UI quand le flag est actif.
///
/// Bottom-nav : Accueil (vraies données) · Jeu (Repaire) · Réglages. L'onglet
/// Réglages contient l'interrupteur pour **revenir à l'ancienne interface**
/// ([onExitToClassic]) → la bascule est toujours réversible.
class SoftPopShell extends StatefulWidget {
  final AppLogic logic;
  final VoidCallback onExitToClassic;
  const SoftPopShell(
      {super.key, required this.logic, required this.onExitToClassic});

  @override
  State<SoftPopShell> createState() => _SoftPopShellState();
}

class _SoftPopShellState extends State<SoftPopShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      SoftPopHomeLiveScreen(logic: widget.logic),
      SoftPopFocusLiveScreen(logic: widget.logic),
      SoftPopBalanceLiveScreen(logic: widget.logic),
      const SoftPopLairScreen(),
      _SettingsTab(onExitToClassic: widget.onExitToClassic),
    ];
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        body: IndexedStack(index: _tab, children: pages),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: SoftPop.card,
            boxShadow: SoftPop.cardShadow,
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: SoftPop.s8, vertical: SoftPop.s4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(0, Icons.home_rounded, 'Accueil'),
                  _navItem(1, Icons.play_circle_fill_rounded, 'Maintenant'),
                  _navItem(2, Icons.donut_large_rounded, 'Équilibre'),
                  _navItem(3, Icons.castle_rounded, 'Jeu'),
                  _navItem(4, Icons.settings_rounded, 'Réglages'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int i, IconData icon, String label) {
    final on = _tab == i;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(SoftPop.rCardSm),
        onTap: () => setState(() => _tab = i),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SoftPop.s8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 24, color: on ? SoftPop.violet : SoftPop.inkMuted),
              const SizedBox(height: 2),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: SoftPop.ui(
                      size: 10,
                      weight: on ? FontWeight.w700 : FontWeight.w500,
                      color: on ? SoftPop.violet : SoftPop.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  final VoidCallback onExitToClassic;
  const _SettingsTab({required this.onExitToClassic});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.all(SoftPop.s16),
        children: [
          SoftCard(
            radius: SoftPop.rCardSm,
            child: Row(
              children: [
                const PomoMascot(size: 40),
                const SizedBox(width: SoftPop.s12),
                Expanded(
                  child: Text(
                      'Tu utilises la nouvelle interface Soft Pop (aperçu).',
                      style: SoftPop.ui(
                          size: 13, color: SoftPop.inkSecondary, height: 1.3)),
                ),
              ],
            ),
          ),
          const SizedBox(height: SoftPop.s12),
          SoftCard(
            radius: SoftPop.rCardSm,
            onTap: onExitToClassic,
            child: Row(
              children: [
                const Icon(Icons.undo_rounded, color: SoftPop.violet),
                const SizedBox(width: SoftPop.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Revenir à l'ancienne interface",
                          style:
                              SoftPop.ui(size: 15, weight: FontWeight.w600)),
                      Text('Retour à l’app classique (toutes les fonctions).',
                          style: SoftPop.ui(
                              size: 11, color: SoftPop.inkMuted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: SoftPop.inkMuted),
              ],
            ),
          ),
          const SizedBox(height: SoftPop.s12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SoftPop.s4),
            child: Text(
                'Les écrans pas encore portés (projets, stats, abonnement…) restent dans l’app classique.',
                style: SoftPop.ui(size: 11, color: SoftPop.inkMuted, height: 1.3)),
          ),
        ],
      ),
    );
  }
}
