import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/web/chrono_launcher.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

/// Onglets du shell web (refonte 2026-09, § 1). L'ordre est celui de la barre
/// ET celui des enfants de l'`IndexedStack` de `WebHomeScreen`.
enum WebTab {
  today("Aujourd'hui"),
  week('Cette semaine'),
  projects('Projets'),
  actions('Actions'),
  library('Bibliothèque');

  final String label;
  const WebTab(this.label);
}

/// Entrées du menu ⋯ (« Réglages, Claude et aide »).
enum WebMenuItem { orion, messages, vision, coachConsole, claude, uiScale, help, logout }

/// Barre du haut (64 px) : logo · onglets · chrono global · « Mon coach » ·
/// menu ⋯ · avatar. Sans état : `WebHomeScreen` garde l'onglet courant.
class WebTopBar extends StatelessWidget {
  final WebTab selected;
  final ValueChanged<WebTab> onSelect;
  final FirestoreSync sync;
  final bool signedIn;
  final String userName;
  final bool isCoach;
  final bool isDemo;
  final bool hasAssistantMessages;
  final VoidCallback onMyCoach;
  final ValueChanged<WebMenuItem> onMenu;
  /// Zone chrono (pastille Focus + lanceur) ; null = lanceur seul.
  final Widget? chrono;

  const WebTopBar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.sync,
    required this.signedIn,
    required this.userName,
    required this.isCoach,
    required this.isDemo,
    required this.hasAssistantMessages,
    required this.onMyCoach,
    required this.onMenu,
    this.chrono,
  });

  @override
  Widget build(BuildContext context) {
    final name = userName.trim();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: kBBar,
        border: Border(bottom: BorderSide(color: kBLine)),
      ),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: kBPrimary,
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(Icons.grid_view_rounded, size: 16, color: kBBg),
        ),
        const SizedBox(width: 10),
        const Text('Productivitwo',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kBText,
                letterSpacing: -.2)),
        const SizedBox(width: 36),
        for (final t in WebTab.values)
          _Tab(t.label, selected: t == selected, onTap: () => onSelect(t)),
        const Spacer(),
        if (signedIn) chrono ?? ChronoLauncher(sync: sync),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Mon coach',
          icon: const Icon(Icons.supervisor_account_outlined,
              size: 19, color: kBText2),
          onPressed: onMyCoach,
        ),
        PopupMenuButton<WebMenuItem>(
          tooltip: 'Réglages, Claude et aide',
          icon: Badge(
            isLabelVisible: hasAssistantMessages,
            smallSize: 7,
            backgroundColor: kBPrimary,
            child: const Icon(Icons.more_horiz, size: 20, color: kBText2),
          ),
          onSelected: onMenu,
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: WebMenuItem.orion, child: Text('Agent ORION')),
            const PopupMenuItem(
                value: WebMenuItem.messages, child: Text('Messages ORION')),
            const PopupMenuItem(
                value: WebMenuItem.vision, child: Text('Vision')),
            if (isCoach)
              const PopupMenuItem(
                  value: WebMenuItem.coachConsole,
                  child: Text('Espace coach')),
            if (!isDemo)
              const PopupMenuItem(
                  value: WebMenuItem.claude, child: Text('Connecter Claude')),
            const PopupMenuItem(
                value: WebMenuItem.uiScale, child: Text("Taille de l'interface")),
            const PopupMenuItem(value: WebMenuItem.help, child: Text('Aide')),
            const PopupMenuDivider(),
            const PopupMenuItem(
                value: WebMenuItem.logout, child: Text('Déconnexion')),
          ],
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: name,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration:
                const BoxDecoration(color: kBRaised, shape: BoxShape.circle),
            child: Text(initial,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kBPrimary)),
          ),
        ),
      ]),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Tab(this.label, {required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: selected ? kBPrimary : Colors.transparent, width: 2),
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? kBText : kBText2)),
      ),
    );
  }
}

/// Bandeau « mode démo » sous la barre.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE8A94A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: const Row(children: [
        Icon(Icons.info_outline, size: 15, color: Color(0xFF1A1000)),
        SizedBox(width: 8),
        Text('Mode démo — données fictives, remises à zéro chaque nuit',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1A1000))),
      ]),
    );
  }
}
