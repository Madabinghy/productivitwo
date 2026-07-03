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
  // Boucle « gagner la prochaine action Gantt » (docs/manoir_missions_v2.md §1) :
  // l'action est poussée SCELLÉE (sans titre) ; le jeu demande la révélation
  // après une mission gagnée (reveal_action).
  final Set<String> _revealedActionIds = {};
  ({String projectId, String taskId, String actionId, String projectTitle, String actionTitle})?
      _nextAction;

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
            _pushNextAction();
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
      case 'reveal_action':
        // Mission gagnée : on descelle l'action courante et on renvoie son titre.
        final na = _nextAction;
        if (na != null) {
          _revealedActionIds.add(na.actionId);
          _writeNextAction(na);
        }
        break;
    }
  }

  String _todayYmd() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // Cherche la « prochaine action » : premier projet actif (racines d'abord),
  // première tâche pending (par date de début), première sous-action non faite.
  // Les projets ne vivent pas dans AppState → fetch Firestore à la demande.
  Future<void> _pushNextAction() async {
    final sync = widget.logic.sync;
    if (_ctrl == null || sync == null) return;
    List<Project> projects;
    try {
      projects = await sync.fetchProjects();
    } catch (_) {
      return;
    }
    final actives = projects.where((p) => p.status == 'active').toList()
      ..sort((a, b) {
        final ra = a.parentProjectId == null ? 0 : 1;
        final rb = b.parentProjectId == null ? 0 : 1;
        if (ra != rb) return ra - rb;
        return a.createdAt.compareTo(b.createdAt);
      });
    _nextAction = null;
    for (final p in actives) {
      final tasks = p.tasks.where((t) => t.status == 'pending').toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      for (final t in tasks) {
        final a = t.actions.firstWhereOrNull((x) => !x.done);
        if (a != null) {
          _nextAction = (
            projectId: p.id,
            taskId: t.id,
            actionId: a.id,
            projectTitle: p.title,
            actionTitle: a.title,
          );
          break;
        }
      }
      if (_nextAction != null) break;
    }
    _writeNextAction(_nextAction);
  }

  void _writeNextAction(
      ({String projectId, String taskId, String actionId, String projectTitle, String actionTitle})?
          na) {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final String js;
    if (na == null) {
      js = "localStorage.removeItem('ombrelune_next_action');";
    } else {
      final revealed = _revealedActionIds.contains(na.actionId);
      final payload = jsonEncode({
        'd': _todayYmd(),
        'projectId': na.projectId,
        'taskId': na.taskId,
        'actionId': na.actionId,
        'projectName': na.projectTitle,
        'sealed': !revealed,
        'title': revealed ? na.actionTitle : null,
      });
      js = "localStorage.setItem('ombrelune_next_action', ${jsonEncode(payload)});";
    }
    ctrl.runJavaScript('''
      try {
        $js
        window.dispatchEvent(new StorageEvent('storage', {key:'ombrelune_next_action'}));
      } catch (e) {}
    ''');
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
