// Pont vers le jeu web « Manoir d'Ombrelune » (déployé sur Firebase Hosting) et
// amorce de migration : semer les routines du scénario dans les vraies routines.
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Écran d'entrée du jeu (choix de profil du Compagnon).
const String kManoirUrl =
    'https://productivitwo-app.web.app/manoir-td/Compagnon%20-%20Choix%20de%20profil.html';

/// Domaine sous lequel on range les routines « scénario » du Manoir.
const String kManoirDomainName = "Manoir d'Ombrelune";

/// Routines forcées du scénario (compagnon Lampyre) à injecter dans les routines
/// réelles pour amorcer la migration Productivitwo → Manoir d'Ombrelune.
const List<String> kManoirScenarioRoutines = [
  "Bois un verre d'eau",
  'Fais la vaisselle',
  'Lis quelques pages',
  'Range un coin',
  'Médite 1 minute',
];

/// Sème les routines du scénario (idempotent : ne recrée pas les doublons).
/// Renvoie le nombre de routines réellement ajoutées.
int seedManoirRoutines(AppLogic logic) {
  final existing =
      logic.state.domains.firstWhereOrNull((d) => d.name == kManoirDomainName);
  final domain = existing ?? logic.createDomain(kManoirDomainName);
  final have = logic.state.activities
      .where((a) => a.domainId == domain.id)
      .map((a) => a.name)
      .toSet();
  int added = 0;
  for (final name in kManoirScenarioRoutines) {
    if (have.contains(name)) continue;
    logic.createHabit(
        domainId: domain.id, name: name, freq: HabitFreq.daily, target: 1);
    added++;
  }
  return added;
}

WebViewController _buildController() => WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..setBackgroundColor(const Color(0xFF0B0710))
  ..loadRequest(Uri.parse(kManoirUrl));

/// Onglet Manoir — WebView embarquée (sans barre : elle vit sous l'app bar
/// principale et la barre d'onglets). Chargement paresseux : la WebView ne
/// démarre qu'à la première ouverture de l'onglet.
class ManoirTab extends StatefulWidget {
  final bool active;
  const ManoirTab({super.key, this.active = false});

  @override
  State<ManoirTab> createState() => _ManoirTabState();
}

class _ManoirTabState extends State<ManoirTab> {
  WebViewController? _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant ManoirTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && _ctrl == null) _start();
  }

  void _start() {
    if (kIsWeb || _ctrl != null) return;
    _ctrl = _buildController()
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _ready = true);
        },
      ));
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Center(
          child: Text("Ouvre le Manoir depuis l'app mobile.",
              style: TextStyle(color: Colors.white54)));
    }
    return ColoredBox(
      color: const Color(0xFF0B0710),
      child: Stack(children: [
        if (_ctrl != null) WebViewWidget(controller: _ctrl!),
        if (_ctrl == null || !_ready)
          const Center(child: CircularProgressIndicator()),
      ]),
    );
  }
}

/// Écran plein écran embarquant le jeu (ouvert depuis un bouton/route).
class ManoirScreen extends StatefulWidget {
  const ManoirScreen({super.key});

  @override
  State<ManoirScreen> createState() => _ManoirScreenState();
}

class _ManoirScreenState extends State<ManoirScreen> {
  WebViewController? _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _ctrl = _buildController()
        ..setNavigationDelegate(NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _ready = true);
          },
        ));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0B0710),
        appBar: AppBar(
          backgroundColor: const Color(0xFF160D22),
          foregroundColor: Colors.white,
          title: const Text("Manoir d'Ombrelune",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          elevation: 0,
          actions: [
            IconButton(
              tooltip: 'Recharger',
              icon: const Icon(Icons.refresh),
              onPressed: () => _ctrl?.loadRequest(Uri.parse(kManoirUrl)),
            ),
          ],
        ),
        body: kIsWeb
            ? const Center(
                child: Text("Ouvre le Manoir depuis l'app mobile.",
                    style: TextStyle(color: Colors.white54)))
            : Stack(children: [
                if (_ctrl != null) WebViewWidget(controller: _ctrl!),
                if (!_ready)
                  const Center(child: CircularProgressIndicator()),
              ]),
      );
}
