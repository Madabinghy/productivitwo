import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/main.dart' show ProductivitwoApp;
import 'package:productivitwo_v1/pro_manager.dart';

/// Page de DÉV : la vraie UI mobile native du « Monde » rendue dans un cadre
/// format téléphone, sur le web. Accès via `?mobilepreview=true`.
/// But : itérer le gameplay mobile en hot-reload (`R`) sans attendre Codemagic.
class MobilePreviewScreen extends StatefulWidget {
  final FirestoreSync sync;
  const MobilePreviewScreen({required this.sync, super.key});
  @override
  State<MobilePreviewScreen> createState() => _MobilePreviewScreenState();
}

class _MobilePreviewScreenState extends State<MobilePreviewScreen> {
  AppLogic? _logic;
  String? _error;
  FirestoreSync get sync => widget.sync;

  @override
  void initState() {
    super.initState();
    ProManager.setForcePro(true); // démo : tout le contenu Pro débloqué
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await sync.pull();
      if (state == null) {
        if (mounted) setState(() => _error = 'Impossible de charger les données.');
        return;
      }
      final logic = AppLogic(state, () {
        if (mounted) setState(() {});
      });
      logic.sync = sync;
      final projects = await sync.fetchProjects();
      logic.updateGanttCounts(projects);
      if (mounted) setState(() => _logic = logic);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = sync.uid;
    final isDemo = uid == 'demo-productivitwo';
    final account = isDemo
        ? '🧪 compte DÉMO (données de test)'
        : (sync.userEmail ?? uid ?? 'non connecté');
    // Téléphone « logique » de taille fixe (390×844), mis à l'échelle par
    // FittedBox pour TOUJOURS tenir dans le viewport — pas d'overflow même
    // sur petit écran ; le contenu garde 844px logiques.
    return Scaffold(
      backgroundColor: const Color(0xFF14110F),
      body: SafeArea(
        child: Column(
          children: [
            // Bandeau : quel compte est connecté (lève le doute démo vs réel).
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isDemo
                  ? const Color(0xFF3A2A0A)
                  : Colors.white.withOpacity(.04),
              child: Row(
                children: [
                  Expanded(
                    child: Text('📱 Prévisu mobile — $account',
                        style: TextStyle(
                            color: isDemo
                                ? const Color(0xFFE0B050)
                                : Colors.white60,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await sync.signOut();
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.logout, size: 14),
                    label: const Text('Déconnexion', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 390,
                height: 844,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E1512),
                    borderRadius: BorderRadius.circular(38),
                    border: Border.all(color: Colors.white24, width: 8),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black87, blurRadius: 48, spreadRadius: 4)
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                style:
                                    const TextStyle(color: Colors.redAccent)),
                          ),
                        )
                      : _logic == null
                          ? const Center(child: CircularProgressIndicator())
                          // CLONE COMPLET : toute l'app mobile (tous les onglets) dans
                          // le cadre téléphone. Elle se ré-initialise seule (son propre
                          // FirestoreSync sur la session web déjà connectée).
                          : const ProductivitwoApp(),
                ),
              ),
            ),
          ),
        ),
              ),
          ],
        ),
      ),
    );
  }
}
