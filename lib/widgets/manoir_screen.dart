// Pont vers le jeu web « Manoir d'Ombrelune » (déployé sur Firebase Hosting).
// Le Manoir est le MONDE ; Productivitwo est la « Console du Commander » —
// l'interface technique où les actions réelles (routines, chronos, projets)
// sont enregistrées. Ce fichier fait les deux liens :
//  - seedManoirRoutines : injecte les routines du scénario dans les vraies routines ;
//  - ManoirScreen : WebView plein écran + pont JS bidirectionnel (ManoirBridge) —
//    l'app pousse l'état du jour dans le jeu (ombrelune_sync / ombrelune_water),
//    le jeu remonte les validations de routine (un vrai HabitHit est loggué).
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:webview_flutter/webview_flutter.dart';
// Sur le web (dont ?mobilepreview), webview_flutter n'existe pas → repli iframe.
import 'package:productivitwo_v1/widgets/manoir_iframe_stub.dart'
    if (dart.library.html) 'package:productivitwo_v1/widgets/manoir_iframe_web.dart';

/// Écran d'entrée du jeu (choix de profil du Compagnon — auto-skip si déjà choisi).
const String kManoirUrl =
    'https://productivitwo-app.web.app/manoir-td/Compagnon%20-%20Choix%20de%20profil.html';

/// Domaine sous lequel on range les routines « scénario » du Manoir.
const String kManoirDomainName = "Manoir d'Ombrelune";

/// Routines forcées du scénario, indexées par leur clé `rk` côté jeu
/// (clé partagée du store ombrelune_sync — ne pas renommer sans migrer le jeu).
const Map<String, String> kManoirRoutinesByRk = {
  'eau': "Bois un verre d'eau",
  'vaisselle': 'Fais la vaisselle',
  'lecture': 'Lis quelques pages',
  'rangement': 'Range un coin',
  'meditation': 'Médite 1 minute',
};

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
  for (final name in kManoirRoutinesByRk.values) {
    if (have.contains(name)) continue;
    logic.createHabit(
        domainId: domain.id, name: name, freq: HabitFreq.daily, target: 1);
    added++;
  }
  return added;
}

/// Écran plein écran embarquant le jeu (ouvert depuis Paramètres → Manoir).
class ManoirScreen extends StatefulWidget {
  final AppLogic logic;
  const ManoirScreen({super.key, required this.logic});

  @override
  State<ManoirScreen> createState() => _ManoirScreenState();
}

class _ManoirScreenState extends State<ManoirScreen> {
  WebViewController? _ctrl;
  bool _ready = false;
  int _webNonce = 0; // bump → nouvelle iframe (rechargement web)

  @override
  void initState() {
    super.initState();
    // Les routines du scénario doivent exister pour que le pont ait des cibles.
    seedManoirRoutines(widget.logic);
    if (!kIsWeb) {
      _ctrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0B0710))
        ..addJavaScriptChannel('ManoirBridge', onMessageReceived: _onBridge)
        ..setNavigationDelegate(NavigationDelegate(
          onPageFinished: (_) {
            _pushSync();
            if (mounted && !_ready) setState(() => _ready = true);
          },
        ))
        ..loadRequest(Uri.parse(kManoirUrl));
    }
  }

  Activity? _routineForRk(String rk) {
    final name = kManoirRoutinesByRk[rk];
    if (name == null) return null;
    final domain = widget.logic.state.domains
        .firstWhereOrNull((d) => d.name == kManoirDomainName);
    if (domain == null) return null;
    return widget.logic.state.activities.firstWhereOrNull(
        (a) => a.domainId == domain.id && a.name == name && !a.deleted);
  }

  // Jeu → app : validation d'une routine dans le jeu = vrai HabitHit,
  // ou demande d'ouvrir la Console (= revenir à Productivitwo).
  void _onBridge(JavaScriptMessage msg) {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(msg.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'routine_done':
        final a = _routineForRk((m['rk'] ?? '') as String);
        if (a != null) {
          widget.logic.incHabit(a.id, 1, DateTime.now());
          _pushSync(); // renvoie l'état de vérité au jeu
        }
        break;
      case 'open_console':
        if (mounted) Navigator.of(context).maybePop();
        break;
    }
  }

  // App → jeu : pousse l'état réel du jour dans le localStorage du jeu
  // (le jeu écoute et rallume ses salles). Clés : ombrelune_sync + ombrelune_water.
  void _pushSync() {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final routines = <String, Map<String, int>>{};
    for (final rk in kManoirRoutinesByRk.keys) {
      final a = _routineForRk(rk);
      if (a == null) continue;
      routines[rk] = {
        'n': widget.logic.habitValueOn(a.id, now),
        't': widget.logic.activeHabitTarget(a),
      };
    }
    final sync = jsonEncode({
      'd': today,
      'routines': routines,
      'focusMin': widget.logic.totalForDay(now).inMinutes,
    });
    final water = jsonEncode({'d': today, 'n': routines['eau']?['n'] ?? 0});
    // Écrit puis émet des StorageEvent synthétiques : les écritures locales ne
    // déclenchent pas l'event `storage` dans la page qui écrit, or le jeu
    // s'appuie dessus pour rafraîchir en direct.
    ctrl.runJavaScript('''
      try {
        localStorage.setItem('ombrelune_sync', ${jsonEncode(sync)});
        localStorage.setItem('ombrelune_water', ${jsonEncode(water)});
        window.dispatchEvent(new StorageEvent('storage', {key:'ombrelune_sync'}));
        window.dispatchEvent(new StorageEvent('storage', {key:'ombrelune_water'}));
      } catch (e) {}
    ''');
  }

  void _reload() {
    if (kIsWeb) {
      setState(() => _webNonce++);
    } else {
      _ctrl?.loadRequest(Uri.parse(kManoirUrl));
    }
  }

  // Petit bouton flottant translucide (contrôles superposés au jeu plein écran).
  Widget _roundBtn(IconData icon, String tip, VoidCallback onTap) => Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          tooltip: tip,
          iconSize: 20,
          icon: Icon(icon, color: Colors.white),
          onPressed: onTap,
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Plein écran : pas d'app bar. Sur web (ex. ?mobilepreview) le jeu est rendu
    // dans une iframe (sans pont) ; sur natif, dans la WebView pontée.
    final Widget content = kIsWeb
        ? manoirIframe(kManoirUrl, key: ValueKey(_webNonce))
        : (_ctrl != null
            ? WebViewWidget(controller: _ctrl!)
            : const SizedBox.shrink());
    return Scaffold(
      backgroundColor: const Color(0xFF0B0710),
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(child: content),
          if (!kIsWeb && !_ready)
            const Center(child: CircularProgressIndicator()),
          Positioned(
            top: 6,
            left: 6,
            child: _roundBtn(Icons.close, 'Retour à la Console',
                () => Navigator.of(context).maybePop()),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: _roundBtn(Icons.refresh, 'Recharger', _reload),
          ),
        ]),
      ),
    );
  }
}
