import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart'
    show KeyEvent, KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/territory.dart';
import 'package:productivitwo_v1/unified_world.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/widgets/backlog_combat.dart';
import 'package:productivitwo_v1/web/invasion_defense_sheet.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/web/assistant_widget.dart' show assistantOverlaySuppressed;

// MONDE UNIFIÉ — Tranche 0 : la grande carte traversable à l'avatar (farm gauche ·
// château centre · grottes droite). On marche, le brouillard se lève autour de soi,
// les 4 grottes affichent leur niveau lu depuis `territories/{uid}` (read-only ici ;
// défendre = T1, invasion spatiale = T2). État de marche LOCAL (la persistance est
// tranchée en T4) ; seules les grottes viennent du doc persisté.

const _kBg = Color(0xFF0E0A0A);
const _kBlue = Color(0xFF3B82F6); // grotte à moi
const _kGold = Color(0xFFD4A017); // château
const _kEnemy = Color(0xFFFF2B2B); // grotte prise
const _kFarm = Color(0xFF22C55E); // accent zone farm
const _kCharge = Color(0xFF4FC26B); // vert — chargeur de la tour (munitions)
const _kLife = Color(0xFFF5C518); // jaune — vie moyenne

// Code couleur de la vie : bleu (≥5/7) → jaune (≥3/7) → rouge.
Color _lifeColor(double frac) =>
    frac >= 5 / 7 ? _kBlue : (frac >= 3 / 7 ? _kLife : _kEnemy);

const int _kReveal = 2; // rayon de brouillard levé autour de l'avatar (Chebyshev)

// Outils dev (convocation manuelle, forcer l'auto-trigger, toggle de cadence) :
// affichés tant que true. ⚠️ à passer à false avant une vraie prod (comme pour
// territory_sheet). kDebugMode ne convient pas : le build web release le met à
// false → on ne pourrait plus tester en ligne.
const bool _kDev = true;

Future<void> showUnifiedWorldSheet(
    BuildContext context, AppLogic logic, FirestoreSync sync,
    {bool mobile = false}) {
  // Coupe l'overlay Orion tant qu'on est dans le Monde (il gênerait le jeu).
  assistantOverlaySuppressed.value = true;
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(.65),
    builder: (_) => Dialog(
      // Plein écran : toute la place pour la map (grosses cases + panneau latéral).
      insetPadding: EdgeInsets.zero,
      backgroundColor: _kBg,
      shape: const RoundedRectangleBorder(),
      child: SizedBox.expand(
        child: _UnifiedWorldView(logic: logic, sync: sync, mobile: mobile),
      ),
    ),
  ).whenComplete(() => assistantOverlaySuppressed.value = false);
}

class _UnifiedWorldView extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  // Mobile : pas de map principale, on affiche direct le calendrier par domaine.
  final bool mobile;
  const _UnifiedWorldView(
      {required this.logic, required this.sync, this.mobile = false});

  @override
  State<_UnifiedWorldView> createState() => _UnifiedWorldViewState();
}

class _UnifiedWorldViewState extends State<_UnifiedWorldView>
    with TickerProviderStateMixin {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => widget.sync;

  Territory? _t;
  UnifiedWorld? _w;
  bool _loading = true;
  bool _busy = false;
  bool _paused = false; // gelé pendant un combat (pas d'avance/résolution)
  StreamSubscription<Territory?>? _sub;
  Timer? _timer;

  // État de marche LOCAL (éphémère en T0).
  late Point<int> _pos;
  final Set<String> _revealed = {};
  // Nuisibles de FARM (zone gauche) = tes VRAIS ennemis backlog (routines/activités/
  // tâches négligées), placés à la révélation, retirés quand l'item est rattrapé.
  // tileId "x_y" → (type, id de l'item). Placement local/éphémère ; les PV vivent
  // dans l'état réel (logic.enemyHp), pas dans le doc.
  final Map<String, ({String type, String id})> _farmPests = {};

  // Cadence de marche de l'araignée, configurable test/prod (portée depuis
  // territory_sheet : la position est dérivée du temps écoulé → tout stepMs marche).
  static const int _kStepMsTest = 3000; // 3 s/pas
  static const int _kStepMsReal = 3600000; // 1 h/pas (prod)
  static const int _kCaveWindowMsTest = 9000; // 9 s devant la cible
  static const int _kCaveWindowMsReal = 3600000; // 1 h
  bool _realCadence = false; // défaut Test (jouable en session)
  int get _stepMs => _realCadence ? _kStepMsReal : _kStepMsTest;
  int get _caveWindowMs => _realCadence ? _kCaveWindowMsReal : _kCaveWindowMsTest;
  bool _autoThreatChecked = false; // auto-trigger hebdo évalué 1× par ouverture
  bool _showCoords = false; // dev : lève le fog + affiche x,y sur chaque case

  // ── PHASE 1 d'invasion (cinématique TD accélérée, dev) ──────────────────────
  // Convoquer = positionne l'envahisseur à gauche. Mon deck (copie) envoie 1 de
  // chaque type possédé /10 s (décalé 3 s) ; chaque sbire à moi qui l'atteint le
  // force à lâcher 1/2/3 sbires (araignée/scorpion/serpent) qui filent vers la
  // porte. Tourelles globales = SANS niveau, un tir = un mort, GRATUIT en Phase 1.
  bool _tdMode = false;
  static const double _kTurretRange = 4.5; // rayon de tir (cases), partagé logique/affichage
  final Map<String, int> _turrets = {}; // tileId "x_y" → tour POSÉE (dev-only)
  final Map<String, int> _turretLastFireMs = {};
  // Le « BÂTI » : tourelles AUTO dérivées des STREAKS de routines (1 routine tenue
  // = 1 tour dans la zone de sa grotte de domaine, niveau = streak). Recalculées au
  // chargement. Streak ↑ = cadence ↑. Pas posées à la main (la pose = dev).
  final Map<String, ({int streak, Color color, String name})> _streakTurrets = {};
  final Map<String, int> _streakTurretFireMs = {};
  String? _selectedTurret; // tour sélectionnée (tap, fallback tactile) → portée
  String? _hoveredTurret; // tour survolée (souris) → affiche sa portée
  // Arcs fixes : 🏹 en (8,1) et (8,13). Portée ~demi-map, GRATUIT one-shot, mais
  // MUETS sauf si l'avatar se tient sur une de leurs cases blanches (gâchette).
  // Cases blanches + arcs sont sur des murs → rendus marchables/révélés, reliés au
  // sol farm par une tuile-pont (8,2)/(8,12).
  static const double _kBowRange = 8.5; // rayon de tir (cases) ≈ moitié de la map
  static final List<({Point<int> at, Set<Point<int>> pads})> _bows = [
    (
      at: const Point(8, 1),
      pads: {const Point(8, 0), const Point(9, 0), const Point(9, 1)}
    ),
    (
      at: const Point(8, 13),
      pads: {const Point(8, 14), const Point(9, 14), const Point(9, 13)}
    ),
  ];
  static final Set<Point<int>> _bowTiles = {
    const Point(8, 1),
    const Point(8, 13)
  };
  static final Set<Point<int>> _bowPads = {
    for (final b in _bows) ...b.pads
  };
  static final Set<Point<int>> _bowBridges = {
    const Point(8, 2),
    const Point(8, 12)
  };
  // Cases d'accès GRISES aux tourelles (haut/bas du territoire).
  static final Set<Point<int>> _greyTiles = {
    const Point(10, 0),
    const Point(10, 14),
    const Point(11, 0),
    const Point(11, 14),
  };
  final Map<String, int> _bowLastFireMs = {};
  bool _isBowWalkable(int x, int y) {
    final p = Point(x, y);
    return _bowTiles.contains(p) ||
        _bowPads.contains(p) ||
        _bowBridges.contains(p) ||
        _greyTiles.contains(p);
  }

  // Un arc tire si l'AVATAR ou mon 🦂 défenseur se tient sur une de ses cases.
  bool _bowManned(Set<Point<int>> pads) {
    if (pads.contains(_pos)) return true;
    return pads.contains(Point(_redSpawn.dx.round(), _redSpawn.dy.round()));
  }
  // Combat de nuisible affiché en ENCART à droite (carte visible derrière).
  ({String type, String id, String tileId})? _combat;
  final List<_Sbire> _sbires = []; // sbires ENNEMIS lâchés (marchent vers la porte)
  final List<_Atk> _myAtk = []; // MES sbires en route vers l'envahisseur
  final List<_Shot> _shots = [];
  static const double _gateHpMax = 120;
  double _gateHp = _gateHpMax;
  Ticker? _gameTicker;
  int _gameMs = 0; // horloge monotone (ms depuis le 1er frame)
  int _lastSimMs = 0;
  int _sbireSeq = 0;
  // Phase 1
  final Random _rng = Random();
  bool _phase1 = false;
  double _invX = 0.5, _invY = 7; // envahisseur FIXE (placé au hasard au lancement)
  int _garrison = 0; // garnison restante de l'envahisseur (ENNEMI)
  int _enemyDeckPower = 0; // puissance du deck ennemi (affichée sur la grotte prise)
  bool _assault = false; // mon deck fini → l'envahisseur a déjà tout déversé
  Offset _grotteTarget = const Offset(16, 7); // grotte visée une fois la porte cassée
  // Phase 2 : la grotte ciblée a des PV (= niveau bleu) ; les sbires les drainent.
  String? _grotteCaveId; // id de la grotte assaillie
  int _grotteHp = 0, _grotteHpMax = 0;
  bool _grotteTaken = false; // capture finie → grotte prise (rouge, visuel ce run)
  int? _captureStartMs; // ms où l'araignée a touché la grotte (anim de capture 5 s)
  int _grotteHpAtCapture = 0; // PV restants quand l'araignée commence à finir
  bool _invaderGone = false; // araignée disparue (fin de l'anim) → la horde rentre
  static const int _kCaptureMs = 5000; // durée de l'anim de capture
  Offset _redHome = const Offset(16, 6); // spawn du défenseur (y retourne si grotte prise)
  int _arrows = 0; // pool de flèches du run (chaque tir tourelle/arc en coûte 1 en P2)
  // ── Intérieur de grotte (reconquête) : on entre dans un CLONE de la map, gazon
  //    teinté au domaine, avatar dans le gazon. On échange le monde actif
  //    (_w/_pos/_revealed) et on restaure en sortant.
  bool _inInterior = false;
  String? _interiorCaveId; // domaine de la grotte intérieure (= filtre nuisibles)
  String? _interiorDomainId; // domainId courant (clé de persistance des tours)
  Color _interiorColor = _kBlue;
  int _reconquestDeck = 0; // masse gagnée en battant les nuisibles du domaine
  // La porte x9 = TOILES 🕸️ : tombent PENDANT le combat d'assaut (= _gateHp ≤ 0),
  // pas par un tap. _webBroken ouvre alors le passage (`_passable`) + rend 💥.
  bool _webBroken = false;
  // Tourelles de DÉFENSE du domaine (intérieur) : posées en zone de départ
  // (0,0)→(7,1), draggables où l'user veut. Niveau = streak = chargeur.
  final List<_DomTurret> _domTurrets = [];
  bool _legacyDragTurrets = false; // ancien rendu draggable (off ; calendrier l'a remplacé)
  // SIMULATION de défense (preview, ne consomme rien — chargeur restauré après).
  bool _simDefense = false;
  final List<_DefAttacker> _defAttackers = []; // vrais nuisibles du domaine
  static const List<Offset> _defPath = [Offset(3, 2), Offset(16, 7)];
  int _simTurretFireMs = 0;
  String? _simResult; // null pendant | 'hold' | 'fall'
  int _simEndMs = 0; // ms de fin (pour laisser le message + restaurer)
  UnifiedWorld? _savedW;
  Point<int>? _savedPos;
  Set<String>? _savedRevealed;
  Map<String, ({String type, String id})>? _savedFarmPests;
  Offset _redSpawn = const Offset(16, 6); // mon défenseur 🦂 : vit sur sa case (16,6)
  Offset? _redWander; // cible d'errance de mon attaquant rouge
  int _myMass = 0; // masse de MON deck (décrémentée à chaque sbire émis)
  static const Map<String, int> _massByType = {
    'spider': GoldEconomy.masseSpider,
    'scorpion': GoldEconomy.masseScorpion,
    'snake': GoldEconomy.masseSerpent,
  };
  final Map<String, int> _myDeck = {}; // copie d'attaque {spider,scorpion,snake}
  int _nextWaveMs = 0; // prochaine vague d'émission
  int _emitBatch = 1; // sbires émis par vague = 1/10 du deck au spawn

  @override
  void initState() {
    super.initState();
    _gameTicker = createTicker(_onGameFrame)..start();
    _boot();
  }

  // Boucle de jeu (~30 fps). Avance la simulation TD et purge les flèches finies.
  void _onGameFrame(Duration elapsed) {
    _gameMs = elapsed.inMilliseconds;
    final dt = _gameMs - _lastSimMs;
    if (dt < 33) return;
    _lastSimMs = _gameMs;
    final hadShots = _shots.isNotEmpty;
    _shots.removeWhere((s) => _gameMs - s.startMs > s.durMs);
    if (_tdMode) {
      _simulate(dt / 1000.0);
      if (mounted) setState(() {});
    } else if (_simDefense) {
      _simulateDefense(dt / 1000.0);
      if (mounted) setState(() {});
    } else if (hadShots && mounted) {
      setState(() {});
    }
  }

  void _simulate(double dt) {
    final w = _w;
    if (w == null) return;
    if (!_phase1) {
      // Hors attaque : le défenseur RENTRE À PIED chez lui (pas de téléport).
      const defSpeed = 0.30;
      final dx = _redHome.dx - _redSpawn.dx, dy = _redHome.dy - _redSpawn.dy;
      final d = sqrt(dx * dx + dy * dy);
      if (d > 0.05) {
        _redSpawn = Offset(_redSpawn.dx + dx / d * defSpeed * dt,
            _redSpawn.dy + dy / d * defSpeed * dt);
      }
      return;
    }
    // 0) Mouvement du 🦂 défenseur (l'envahisseur 🕷️ reste FIXE). Il erre tant qu'il
    //    lui reste du deck OU des sbires en vie. Deck VIDE + sbires TOUS MORTS → il
    //    file en (9,1) manier l'arc (comme le user peut le faire sur une case blanche).
    const wanderSpeed = 0.45; // vitesse de l'envahisseur (avance vers la grotte)
    const defSpeed = 0.30; // vitesse de MON défenseur (errance + rejoint l'arc)
    final deckEmpty = (_myDeck['spider'] ?? 0) +
            (_myDeck['scorpion'] ?? 0) +
            (_myDeck['snake'] ?? 0) ==
        0;
    final manBow = deckEmpty && _myAtk.isEmpty;
    if (_grotteTaken) {
      // Grotte prise → le défenseur se replie sur son point de spawn.
      final dx = _redHome.dx - _redSpawn.dx, dy = _redHome.dy - _redSpawn.dy;
      final d = sqrt(dx * dx + dy * dy);
      if (d > 0.05) {
        _redSpawn = Offset(_redSpawn.dx + dx / d * defSpeed * dt,
            _redSpawn.dy + dy / d * defSpeed * dt);
      }
    } else if (manBow) {
      // Rejoint la case blanche la PLUS PROCHE entre l'arc haut (9,1) et bas (9,13).
      const top = Offset(9, 1), bot = Offset(9, 13);
      final dTop = pow(top.dx - _redSpawn.dx, 2) + pow(top.dy - _redSpawn.dy, 2);
      final dBot = pow(bot.dx - _redSpawn.dx, 2) + pow(bot.dy - _redSpawn.dy, 2);
      final target = dTop <= dBot ? top : bot;
      final dx = target.dx - _redSpawn.dx, dy = target.dy - _redSpawn.dy;
      final d = sqrt(dx * dx + dy * dy);
      if (d <= 0.05) {
        _redSpawn = target; // posté sur la case → l'arc tire
      } else {
        _redSpawn = Offset(_redSpawn.dx + dx / d * defSpeed * dt,
            _redSpawn.dy + dy / d * defSpeed * dt);
      }
    } else {
      _redWander ??= _randomMapTile(w);
      final rdx = _redWander!.dx - _redSpawn.dx,
          rdy = _redWander!.dy - _redSpawn.dy;
      final rd = sqrt(rdx * rdx + rdy * rdy);
      if (rd < 0.4) {
        _redWander = _randomMapTile(w);
      } else {
        _redSpawn = Offset(_redSpawn.dx + rdx / rd * defSpeed * dt,
            _redSpawn.dy + rdy / rd * defSpeed * dt);
      }
    }
    // 0b) Porte EXPLOSÉE → l'envahisseur avance sur la grotte. Dès qu'il la TOUCHE,
    //     démarre l'anim de capture (défenses muettes, sbires en attente dehors).
    if (_gateHp <= 0 && !_invaderGone) {
      final dx = _grotteTarget.dx - _invX, dy = _grotteTarget.dy - _invY;
      final d = sqrt(dx * dx + dy * dy);
      if (d > 0.6) {
        _invX += dx / d * wanderSpeed * dt;
        _invY += dy / d * wanderSpeed * dt;
      } else if (_captureStartMs == null) {
        // Touche la grotte → l'araignée FINIT les PV restants (laissés par les sbires).
        _captureStartMs = _gameMs;
        _grotteHpAtCapture = _grotteHp;
      }
    }
    // 0c) Anim de capture : les PV restants tombent à 0 en 5 s, PUIS l'araignée
    //     disparaît et SEULEMENT après la horde rentre (cf. bloc 3).
    if (_captureStartMs != null && !_grotteTaken) {
      final p = ((_gameMs - _captureStartMs!) / _kCaptureMs).clamp(0.0, 1.0);
      _grotteHp = (_grotteHpAtCapture * (1 - p)).round();
      if (p >= 1.0) {
        _grotteHp = 0;
        _invaderGone = true; // araignée disparue
        _grotteTaken = true; // → les sbires rentrent maintenant
      }
    }
    // 1) Émission par VAGUES : 1/10 du deck (au spawn) toutes les 10 s, émis depuis
    //    mon attaquant rouge. Pioche serpent > scorpion > araignée (variété).
    if (_gameMs >= _nextWaveMs) {
      for (int i = 0; i < _emitBatch; i++) {
        String? type;
        for (final t in const ['spider', 'scorpion', 'snake']) {
          if ((_myDeck[t] ?? 0) > 0) {
            type = t;
            break;
          }
        }
        if (type == null) break; // deck vidé
        _myDeck[type] = _myDeck[type]! - 1;
        _myMass = (_myMass - (_massByType[type] ?? 0)).clamp(0, 1 << 30);
        // À l'intérieur, les sbires de l'araignée jaillissent de SA GROTTE (repaire) ;
        // sur la map principale, ils partent de mon défenseur.
        final ox = _inInterior ? _grotteTarget.dx : _redSpawn.dx;
        final oy = _inInterior ? _grotteTarget.dy : _redSpawn.dy;
        _myAtk.add(_Atk(_sbireSeq++, type, ox, oy)..wp = _randomWaypoint(w));
      }
      _nextWaveMs += 10000;
    }
    // 2) Mes sbires : waypoint aléatoire D'ABORD, puis foncent SUR l'envahisseur
    //    (ne chassent jamais les sbires ennemis). Ralentis + ondulants → ils
    //    partent dans tous les sens. Au contact de l'envahisseur → release.
    for (final a in _myAtk) {
      if (a.x < -100) continue;
      final tx = a.wp?.dx ?? _invX, ty = a.wp?.dy ?? _invY;
      final dx = tx - a.x, dy = ty - a.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist > 0.4) {
        const speed = 0.5; // ralenti (symétrique aux sbires ennemis)
        final ux = dx / dist, uy = dy / dist;
        // Ondulation amortie à l'approche (sinon orbite sans atteindre la cible).
        final wob =
            sin(_gameMs / 500.0 + a.phase) * 0.5 * (dist - 0.5).clamp(0.0, 1.0);
        a.x += (ux * speed - uy * wob) * dt;
        a.y += (uy * speed + ux * wob) * dt;
      } else if (a.wp != null) {
        a.wp = null; // waypoint atteint → cap sur l'envahisseur
      } else {
        // 1 masse = 1 unité de garnison sortie (🕷️5 / 🦂10 / 🐍15) → duel symétrique.
        final n = (_massByType[a.type] ?? 1).clamp(0, _garrison);
        _garrison -= n;
        for (int i = 0; i < n; i++) {
          final ox = (_rng.nextDouble() - 0.5) * 0.9;
          final oy = (_rng.nextDouble() - 0.5) * 0.9;
          _sbires.add(_Sbire(_sbireSeq++, _invX + 0.3 + ox, _invY + oy, 1)
            ..wp = _gateApproachWaypoint(w));
        }
        a.x = -999; // consommé
      }
    }
    _myAtk.removeWhere((a) => a.x < -100);
    // 2b) Mon deck ÉPUISÉ (rien en réserve, rien en vol) → l'envahisseur DÉVERSE
    //     toute sa garnison restante d'un coup sur la porte (assaut final).
    if (deckEmpty && _myAtk.isEmpty && !_assault && _garrison > 0) {
      _assault = true;
      final n = _garrison;
      _garrison = 0;
      for (int i = 0; i < n; i++) {
        final ox = (_rng.nextDouble() - 0.5) * 1.2;
        final oy = (_rng.nextDouble() - 0.5) * 1.2;
        _sbires.add(_Sbire(_sbireSeq++, _invX + 0.3 + ox, _invY + oy, 1)
          ..wp = _gateApproachWaypoint(w));
      }
      _toast('⚔️ Ton deck est épuisé — l\'envahisseur jette toute sa garnison '
          'sur la porte !', _kEnemy);
    }
    // 3) Sbires ennemis : waypoint aléatoire D'ABORD, puis cap sur la porte (8,7) ;
    //    cassée → vers la GROTTE. MAIS si un de MES sbires est à portée, l'ennemi
    //    LUI FONCE DESSUS (charge) et le tue au contact, puis reprend sa route.
    final broken = _gateHp <= 0;
    final goal = broken ? _grotteTarget : const Offset(8, 7);
    const detect = 2.5; // rayon de détection d'un de mes sbires (charge)
    for (final s in _sbires) {
      if (s.hp <= 0) continue;
      // Charge : tant qu'il n'a pas encore tué, si un de MES sbires est à portée
      // il LUI FONCE DESSUS et le tue au contact — UN SEUL — puis file DROIT à la
      // porte (ne harcèle plus → garde l'effet de masse, évite les tourelles).
      if (!s.killed) {
        _Atk? prey;
        double preyD = detect;
        for (final a in _myAtk) {
          if (a.x < -100) continue;
          final d = sqrt(pow(a.x - s.x, 2) + pow(a.y - s.y, 2));
          if (d <= preyD) {
            preyD = d;
            prey = a;
          }
        }
        if (prey != null) {
          final dx = prey.x - s.x, dy = prey.y - s.y;
          final dist = sqrt(dx * dx + dy * dy);
          if (dist < 0.6) {
            prey.x = -999; // une seule victime…
            s.killed = true; // … puis cap DIRECT sur la porte
            s.wp = null;
          } else {
            const speed = 0.45; // charge un brin plus vive que la marche
            s.x += dx / dist * speed * dt;
            s.y += dy / dist * speed * dt;
          }
          continue;
        }
      }
      // PHASE 2 (porte cassée) : beeline DIRECT sur la grotte — pas de waypoint ni
      // d'ondulation → convergence garantie (plus de sbire qui orbite sans entrer).
      if (broken) {
        final dx = goal.dx - s.x, dy = goal.dy - s.y;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist > 0.45) {
          const speed = 0.32;
          s.x += dx / dist * speed * dt;
          s.y += dy / dist * speed * dt;
        } else if (_grotteTaken) {
          s.hp = 0; // capture finie → il entre dans la grotte
        } else if (!s.drained) {
          // Entame les PV une fois (plancher 30 % → l'araignée finit), puis attend.
          s.drained = true;
          final floorHp = (_grotteHpMax * 0.3).round();
          _grotteHp = (_grotteHp - 8).clamp(floorHp, _grotteHpMax);
        }
        continue;
      }
      // PHASE 1 (porte intacte) : waypoint aléatoire puis cap sur la porte (8,7),
      // avec ondulation + évitement des buissons.
      final tx = s.wp?.dx ?? goal.dx, ty = s.wp?.dy ?? goal.dy;
      final dx = tx - s.x, dy = ty - s.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist > 0.4) {
        const speed = 0.32; // ralenti (interception lisible)
        final ux = dx / dist, uy = dy / dist;
        // Ondulation amortie à l'approche (sinon le sbire orbite sans toucher).
        final wob =
            sin(_gameMs / 500.0 + s.phase) * 0.55 * (dist - 0.5).clamp(0.0, 1.0);
        var ny = s.y + (uy * speed + ux * wob) * dt;
        s.x += (ux * speed - uy * wob) * dt;
        if (w.hasBush(s.x.round(), ny.round())) {
          ny += (s.id.isEven ? -1 : 1) * 0.6 * dt;
        }
        s.y = ny.clamp(1.0, (w.rows - 2).toDouble());
      } else if (s.wp != null) {
        s.wp = null; // waypoint atteint → cap sur la porte
      } else {
        _gateHp = (_gateHp - 8).clamp(0, _gateHpMax); // touche la porte…
        s.hp = 0; // …et meurt
      }
    }
    _myAtk.removeWhere((a) => a.x < -100); // mes sbires tués par charge
    // 4) Tourelles : un tir = un mort (GRATUIT en Phase 1, pas de niveau).
    // Cadence lente (1 tir / 5 s) ; ne ciblent QUE les sbires déjà en chemin
    // (sortis de la zone garnison) → interception sur la lane, pas à la source.
    const range = _kTurretRange, cooldownMs = 5000, kGarrisonZone = 2.0;
    _turrets.forEach((tile, _) {
      if (_captureStartMs != null) return; // capture en cours → défenses muettes
      final p = tile.split('_');
      final tx = double.parse(p[0]), ty = double.parse(p[1]);
      if (_gameMs - (_turretLastFireMs[tile] ?? -99999) < cooldownMs) return;
      _Sbire? best;
      double bestD = range;
      for (final s in _sbires) {
        if (s.hp <= 0) continue;
        // Encore collé à l'envahisseur → pas encore ciblable (pas « la garnison »).
        if (sqrt(pow(s.x - _invX, 2) + pow(s.y - _invY, 2)) < kGarrisonZone) {
          continue;
        }
        final d = sqrt(pow(s.x - tx, 2) + pow(s.y - ty, 2));
        if (d <= bestD) {
          bestD = d;
          best = s;
        }
      }
      if (best != null) {
        if (broken) {
          if (_arrows <= 0) return; // Phase 2 : plus de flèches → tourelle muette
          _arrows--;
        }
        _turretLastFireMs[tile] = _gameMs;
        _shots.add(_Shot(Offset(tx, ty), Offset(best.x, best.y), _gameMs, 420));
        best.hp = 0; // one-shot
      }
    });
    // 4a) BÂTI — tourelles dérivées des STREAKS : un tir = un mort, GRATUIT, mais
    //     cadence ↑ avec le streak (constance forte = défense plus rapide : 5 s à
    //     streak 1 → ~1.2 s aux gros streaks). C'est ta vraie agency (hors-écran).
    _streakTurrets.forEach((tile, info) {
      if (_captureStartMs != null) return;
      final p = tile.split('_');
      final tx = double.parse(p[0]), ty = double.parse(p[1]);
      final cd = (5000 / (1 + info.streak / 5)).clamp(1200.0, 5000.0);
      if (_gameMs - (_streakTurretFireMs[tile] ?? -99999) < cd) return;
      _Sbire? best;
      double bestD = range;
      for (final s in _sbires) {
        if (s.hp <= 0) continue;
        if (sqrt(pow(s.x - _invX, 2) + pow(s.y - _invY, 2)) < kGarrisonZone) {
          continue;
        }
        final d = sqrt(pow(s.x - tx, 2) + pow(s.y - ty, 2));
        if (d <= bestD) {
          bestD = d;
          best = s;
        }
      }
      if (best != null) {
        _streakTurretFireMs[tile] = _gameMs;
        _shots.add(_Shot(Offset(tx, ty), Offset(best.x, best.y), _gameMs, 420));
        best.hp = 0;
      }
    });
    // 4b) Arcs fixes (8,1)/(8,13) : portée ~demi-map, one-shot GRATUIT, mais ne
    //     tirent QUE si l'avatar se tient sur une de leurs cases blanches.
    const bowCooldownMs = 1500;
    for (final bow in _bows) {
      if (_captureStartMs != null) break; // capture en cours → arcs muets
      if (!_bowManned(bow.pads)) continue; // personne sur la gâchette → muet
      final key = '${bow.at.x}_${bow.at.y}';
      if (_gameMs - (_bowLastFireMs[key] ?? -99999) < bowCooldownMs) continue;
      final bx = bow.at.x.toDouble(), by = bow.at.y.toDouble();
      _Sbire? best;
      double bestD = _kBowRange;
      for (final s in _sbires) {
        if (s.hp <= 0) continue;
        final d = sqrt(pow(s.x - bx, 2) + pow(s.y - by, 2));
        if (d <= bestD) {
          bestD = d;
          best = s;
        }
      }
      if (best != null) {
        if (broken) {
          if (_arrows <= 0) continue; // Phase 2 : plus de flèches → arc muet
          _arrows--;
        }
        _bowLastFireMs[key] = _gameMs;
        _shots.add(_Shot(Offset(bx, by), Offset(best.x, best.y), _gameMs, 360));
        best.hp = 0;
      }
    }
    _sbires.removeWhere((s) => s.hp <= 0);
    // 5) Conditions de fin de Phase 1. À l'INTÉRIEUR : rôles inversés — grotte
    //    prise = JE GAGNE (reprise), grotte sauvée/réserve épuisée = JE PERDS.
    if (_inInterior && _gateHp <= 0) _webBroken = true; // toiles tombées → passage
    if (_gateHp <= 0) {
      // Phase 2 : assaut sur la grotte. PV grotte à 0 → PRISE (rouge). Sinon, si
      // toute la vague est neutralisée → grotte SAUVÉE.
      if (_grotteTaken) {
        // Grotte prise : on laisse TOUTE la horde finir de rentrer dedans (vraie
        // invasion). Fin seulement quand le dernier sbire est entré.
        if (_sbires.isEmpty) {
          if (_inInterior) {
            _finishInteriorAssault(
                win: true, message: '🔵 Grotte reprise — l\'araignée est délogée !');
          } else {
            _phase1 = false;
            _toast('🔴 Grotte ENVAHIE — domaine perdu ! (Phase 2)', _kEnemy);
          }
        }
      } else if (_sbires.isEmpty) {
        if (_inInterior) {
          _finishInteriorAssault(
              win: false,
              message: '🛡️ L\'araignée a tenu sa grotte — refarme et relance ⚔️.');
        } else {
          _phase1 = false;
          _toast('🛡️ Grotte sauvée — assaut repoussé sur la grotte !', _kBlue);
        }
      }
    } else if (_garrison <= 0 && _sbires.isEmpty && _myAtk.isEmpty) {
      // Réserve d'assaut épuisée AVANT de casser la porte.
      if (_inInterior) {
        _finishInteriorAssault(
            win: false,
            message:
                '🛡️ Ton deck de reconquête s\'est épuisé avant la porte — refarme.');
      } else {
        _phase1 = false;
        _toast('🛡️ Invasion repoussée — garnison anéantie avant la porte !', _kBlue);
      }
    }
    // (Phase terminée : le défenseur rentre à pied chez lui — géré en tête de
    //  _simulate dans la branche !_phase1.)
  }

  // Point accessible aléatoire dans la chambre gauche (champ de bataille) : floor,
  // hors rocher → chaque sbire (ennemi ET à moi) y passe avant sa cible, donc ils
  // partent dans tous les sens au lieu de filer droit.
  Offset _randomWaypoint(UnifiedWorld w) {
    for (int tries = 0; tries < 24; tries++) {
      final x = 1 + _rng.nextInt(7); // 1..7 (chambre avant la porte x=9)
      final y = 2 + _rng.nextInt(11); // 2..12
      if (w.at(x, y) == UwTile.floor && !w.hasRock(x, y)) {
        return Offset(x.toDouble(), y.toDouble());
      }
    }
    return const Offset(4, 7); // fallback centre chambre
  }

  // Waypoint des sbires ENNEMIS : biaisé vers le couloir de la porte (x 3..7,
  // y 5..9) → un peu de dispersion mais ils convergent vers la porte et passent
  // dans la zone des tourelles (au lieu de filer aux bords haut/bas).
  Offset _gateApproachWaypoint(UnifiedWorld w) {
    for (int tries = 0; tries < 20; tries++) {
      final x = 3 + _rng.nextInt(5); // 3..7 (vers la porte)
      final y = 5 + _rng.nextInt(5); // 5..9 (couloir central)
      if (w.at(x, y) == UwTile.floor && !w.hasRock(x, y)) {
        return Offset(x.toDouble(), y.toDouble());
      }
    }
    return const Offset(6, 7);
  }

  // Case accessible aléatoire sur TOUTE la map (floor, hors rocher) — position de
  // mon attaquant rouge, qui émet mes sbires d'où il se trouve.
  Offset _randomMapTile(UnifiedWorld w) {
    for (int tries = 0; tries < 40; tries++) {
      final x = _rng.nextInt(w.cols), y = _rng.nextInt(w.rows);
      if (w.at(x, y) == UwTile.floor && !w.hasRock(x, y)) {
        return Offset(x.toDouble(), y.toDouble());
      }
    }
    return const Offset(8, 7);
  }

  // Dev : place l'envahisseur + mon attaquant au hasard et lance la Phase 1.
  void _startPhase1() {
    // TEST « deck égal » : mon deck forcé à masse 30 (= garnison ennemie 30) pour
    // voir qui gagne à armes égales. 🕷️5 + 🦂10 + 🐍15 = 30.
    var sp = 1, sc = 1, se = 1;
    setState(() {
      _tdMode = true;
      _phase1 = true;
      _sbires.clear();
      _myAtk.clear();
      _shots.clear();
      _myDeck
        ..clear()
        ..addAll({'spider': sp, 'scorpion': sc, 'snake': se});
      // Garnison de l'ENNEMI = TES RETARDS RÉELS : masse du backlog (routines sans
      // streak 🕷️ + activités-temps en retard 🦂 + tâches en retard 🐍). Plancher
      // 10 pour rester jouable même quand tu es à jour.
      final retards = logic
          .backlogEnemies()
          .fold(0, (s, e) => s + (_massByType[e.type] ?? 0));
      _garrison = retards < 10 ? 10 : retards;
      _enemyDeckPower = _garrison; // puissance du deck ennemi (affichée si prise)
      _assault = false;
      // Mon attaquant rouge + l'envahisseur : placés aléatoirement.
      final w = _w;
      // Mon 🦂 défenseur spawn en (16,6) ; mon avatar posté en (15,7).
      _redSpawn = const Offset(16, 6);
      _redHome = const Offset(16, 6);
      _redWander = null;
      _pos = const Point(15, 7);
      _revealAround(_pos);
      if (w != null) {
        // Envahisseur sur la COLONNE DE GAUCHE (x=0) : loin de la porte → long
        // trajet vers la grotte en Phase 2.
        int iy = 7;
        for (int tries = 0; tries < 30; tries++) {
          final y = _rng.nextInt(w.rows);
          if (w.at(0, y) == UwTile.floor) {
            iy = y;
            break;
          }
        }
        _invX = 0;
        _invY = iy.toDouble();
        // Grotte la plus proche de la porte = cible de l'assaut (Phase 2).
        String? nearId;
        Offset nearPt = const Offset(16, 7);
        double bestD = 1e9;
        for (final e in w.caves.entries) {
          final d = (pow(e.value.x - 8, 2) + pow(e.value.y - 7, 2)).toDouble();
          if (d < bestD) {
            bestD = d;
            nearId = e.key;
            nearPt = Offset(e.value.x.toDouble(), e.value.y.toDouble());
          }
        }
        _grotteTarget = nearPt;
        _grotteCaveId = nearId;
        final lvl =
            (nearId != null ? _t?.caveById(nearId)?.blueLevel : null) ?? 1;
        _grotteHpMax = (lvl * 25).clamp(40, 99999);
        _grotteHp = _grotteHpMax;
        _grotteTaken = false;
        _captureStartMs = null;
        _grotteHpAtCapture = 0;
        _invaderGone = false;
        _arrows = logic.weaponsAvailable('arc'); // pool de flèches du run
      }
      // Masse de MON deck = somme des masses des sbires à émettre (décrémentée à
      // chaque émission → atteint 0 pile quand le deck est vide).
      _myMass = sp * GoldEconomy.masseSpider +
          sc * GoldEconomy.masseScorpion +
          se * GoldEconomy.masseSerpent;
      _gateHp = _gateHpMax;
      // Émission par vagues : 1/10 du deck (au spawn) toutes les 10 s.
      _nextWaveMs = _gameMs;
      final total = sp + sc + se;
      _emitBatch = total <= 0 ? 1 : ((total + 9) ~/ 10);
    });
  }

  // Montre la composition du deck qui ATTAQUE (mon scorpion) : la masse décomposée
  // en 🐍15 / 🦂10 / 🕷️5. Pendant l'assaut = réserve restante (_garrison), sinon le
  // deck de reconquête amorcé (captures du domaine) + farming.
  void _showAttackDeck() {
    final mass = _tdMode ? _garrison : _reconquestDeck;
    var m = mass;
    final serp = m ~/ GoldEconomy.masseSerpent;
    m %= GoldEconomy.masseSerpent;
    final scor = m ~/ GoldEconomy.masseScorpion;
    m %= GoldEconomy.masseScorpion;
    final spid = m ~/ GoldEconomy.masseSpider;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kBg,
        title: Text('🃏 Deck d\'attaque — masse $mass',
            style: TextStyle(color: _interiorColor, fontSize: 16)),
        content: Text(
          '🐍 Serpents : $serp\n🦂 Scorpions : $scor\n🕷️ Araignées : $spid',
          style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.7),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer')),
        ],
      ),
    );
  }

  // SÉLECTEUR de domaine : liste les grottes (domaines) → l'user CHOISIT laquelle
  // entrer (plus de « grotte la plus proche » ambigu).
  void _quickEnter() {
    final t = _t;
    if (t == null) {
      _toast('Territoire pas encore chargé — réessaie dans un instant.',
          Colors.white60);
      return;
    }
    // Sur mobile on est toujours dans un domaine → le sélecteur sert à CHANGER.
    if (_inInterior && !widget.mobile) return;
    if (t.caves.isEmpty) {
      _toast('Aucune grotte dans le territoire (caves vides).', Colors.white60);
      return;
    }
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        backgroundColor: _kBg,
        title: const Text('Entrer dans quel domaine ?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        children: [
          for (final c in t.caves)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context);
                _enterInterior(c.id);
              },
              child: Row(children: [
                Icon(Icons.circle, size: 13, color: _caveColor(c)),
                const SizedBox(width: 10),
                Text(_domainName(c.domainId),
                    style: TextStyle(
                        color: _caveColor(c),
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
        ],
      ),
    );
  }

  // SIMULATION de défense (preview gratuit) : tes VRAIS nuisibles du domaine
  // (backlog) marchent vers le château, tes tours leur tirent dessus. Cliquer un
  // nuisible → sa carte de combat. Tout est RESTAURÉ à la fin (rien consommé).
  void _startSimDefense() {
    if (!_inInterior || _simDefense || _tdMode) return;
    if (_domTurrets.isEmpty) {
      _toast('Aucune tour de défense (tiens des routines la semaine passée).',
          _interiorColor);
      return;
    }
    setState(() {
      _simDefense = true;
      _simResult = null;
      _simEndMs = 0;
      _shots.clear();
      for (final tr in _domTurrets) {
        tr.ammo = tr.level;
      }
      // Attaquants = les VRAIS nuisibles du backlog de CE domaine, spawn bas-gauche.
      _defAttackers.clear();
      final dom = _interiorDomainId;
      var i = 0;
      for (final e in logic.backlogEnemies()) {
        if (dom != null && logic.enemyDomainId(e.type, e.id) != dom) continue;
        final sx = (i % 6).toDouble();
        final sy = (13 + (i ~/ 6) % 2).toDouble();
        _defAttackers.add(
            _DefAttacker(e.type, e.id, sx, sy, _massByType[e.type] ?? 5));
        if (++i >= 30) break;
      }
      if (_defAttackers.isEmpty) {
        _defAttackers.add(_DefAttacker('spider', '', 3, 14, 5)); // menace symbolique
      }
      _toast('🛡️ Simulation — tes retards attaquent. Clique un nuisible pour voir '
          'sa carte de combat.', _interiorColor);
    });
  }

  void _simulateDefense(double dt) {
    if (_simResult != null) {
      if (_gameMs - _simEndMs > 2500) {
        _simDefense = false;
        for (final tr in _domTurrets) {
          tr.ammo = tr.level;
        }
        _defAttackers.clear();
        _shots.clear();
      }
      return;
    }
    // 1) Marche de chaque nuisible le long du chemin (monte la lane → château).
    const speed = 2.5; // accéléré (preview) ; en vrai ce sera 1 pas/jour
    var anyReached = false;
    for (final a in _defAttackers) {
      final target = a.wpIdx < _defPath.length ? _defPath[a.wpIdx] : _defPath.last;
      final dx = target.dx - a.x, dy = target.dy - a.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist > 0.4) {
        a.x += dx / dist * speed * dt;
        a.y += dy / dist * speed * dt;
      } else if (a.wpIdx < _defPath.length - 1) {
        a.wpIdx++;
      } else {
        anyReached = true;
      }
    }
    // 2) Volée des tours : chaque tour tire sur le nuisible le plus proche à portée.
    const cd = 500, range = _kTurretRange;
    if (_gameMs - _simTurretFireMs >= cd) {
      _simTurretFireMs = _gameMs;
      for (final tr in _domTurrets) {
        if (tr.ammo <= 0) continue;
        _DefAttacker? best;
        double bestD = range;
        for (final a in _defAttackers) {
          if (a.hp <= 0) continue;
          final d = sqrt(pow(tr.x - a.x, 2) + pow(tr.y - a.y, 2));
          if (d <= bestD) {
            bestD = d;
            best = a;
          }
        }
        if (best != null) {
          tr.ammo--;
          best.hp--;
          _shots.add(_Shot(Offset(tr.x, tr.y), Offset(best.x, best.y), _gameMs, 320));
        }
      }
    }
    _defAttackers.removeWhere((a) => a.hp <= 0); // tués par les tours
    // 3) Verdict : un nuisible atteint le château → tomberait ; tous stoppés → tient.
    if (anyReached) {
      _simResult = 'fall';
      _simEndMs = _gameMs;
      _toast('❌ Un nuisible atteint le château → le domaine TOMBERAIT. Renforce '
          'tes tours ou clique les nuisibles pour faire le vrai travail.', _kEnemy);
    } else if (_defAttackers.isEmpty) {
      _simResult = 'hold';
      _simEndMs = _gameMs;
      _toast('✅ Tous les nuisibles stoppés — le domaine TIENDRAIT !', _kBlue);
    }
  }

  // Reconquête (tranche 1) : ENTRER dans la grotte = un CLONE de la map, gazon
  // teinté au domaine, avatar posé dans le gazon. On échange le monde actif
  // (_w/_pos/_revealed) et on le restaure en sortant (cf. _exitInterior).
  void _enterInterior(String caveId) {
    // Mobile : pas de map principale → _w peut être null (rien à sauver).
    final w = _w;
    if (w == null && !widget.mobile) return;
    final cave = _t?.caveById(caveId);
    // Backdrop intérieur MIROIR (même base que la map principale : château à
    // gauche). Le calendrier en overlay garde ses coords (déjà repère inversé).
    final interior = mirrorWorldX(generateUnifiedWorld(
        (_t?.seed ?? 1) ^ caveId.hashCode,
        caveIds: const ['coeur'])); // 17 cols (taille normale) ; noms en panneau latéral
    setState(() {
      _savedW = w;
      _savedPos = _pos;
      _savedRevealed = {..._revealed};
      _savedFarmPests = {..._farmPests};
      _interiorColor = cave != null ? _caveColor(cave) : _kBlue;
      _interiorCaveId = caveId;
      // Deck d'assaut du scorpion AMORCÉ par tes captures de CE domaine précis
      // (petit deck spécifique, dérivé de activity.domainId ; fallback fraction
      // globale si le domaine est vide) ; farmer les nuisibles l'AUGMENTE.
      _reconquestDeck = cave != null
          ? logic.reconquestDeckForDomain(cave.domainId)
          : logic.lifetimeBattleMasse;
      _webBroken = false; // toiles intactes jusqu'à l'assaut
      _inInterior = true;
      _tdMode = false; // pas de TD tant que l'assaut n'est pas lancé
      // Purge de tout combat de la MAP PRINCIPALE (sinon scorpion/sbires fantômes
      // restés à leur ancienne position fuient dans la grotte).
      _phase1 = false;
      _assault = false;
      _sbires.clear();
      _myAtk.clear();
      _shots.clear();
      _myDeck.clear();
      _garrison = 0;
      _grotteTaken = false;
      _invaderGone = false;
      _captureStartMs = null;
      _gateHp = _gateHpMax;
      _w = interior;
      _pos = interior.start; // avatar dans le gazon (entrée gauche)
      _revealed.clear();
      _farmPests.clear();
      _revealAround(_pos);
      _populateFarm(); // peuple le gazon avec les nuisibles de CE domaine
      // Défenses du domaine = ses routines à streak, posées en ZONE DE DÉPART
      // (0,0)→(7,1). L'user les drag où il veut. Niveau = streak = chargeur.
      _domTurrets.clear();
      final dom = cave?.domainId;
      _interiorDomainId = dom;
      if (dom != null) {
        final col = cave != null ? _caveColor(cave) : _kBlue;
        var idx = 0;
        for (final a in logic.state.activeActivities) {
          if (!a.isHabit || a.domainId != dom) continue;
          // Chargeur = complétions de la SEMAINE PASSÉE (0..7). Tour seulement si
          // tenue la semaine passée (>= 1) → ce que tu as bâti te défend.
          final charger = logic.routineDefenseCharger(a.id);
          if (charger < 1) continue;
          // Le STREAK actuel CLONE la tour : 1 base + 1 clone/jour de streak,
          // plafonné à 8. Streak cassé (0) → 1 tour de base (le coussin tient).
          final count = (1 + logic.habitCurrentStreak(a.id)).clamp(1, 8);
          for (var ci = 0; ci < count && idx < 40; ci++) {
            final key = '$dom~${a.id}~$ci';
            double px = (idx % 8).toDouble(), py = (idx ~/ 8).toDouble();
            final saved = logic.state.domTurretPos[key];
            if (saved != null && saved.contains('_')) {
              final s2 = saved.split('_');
              final sx = double.tryParse(s2[0]), sy = double.tryParse(s2[1]);
              if (sx != null && sy != null) {
                px = sx;
                py = sy;
              }
            }
            _domTurrets.add(_DomTurret(key, charger, col, a.name, px, py));
            idx++;
          }
        }
      }
      _toast(
          '🕳️ Tu entres dans ${cave != null ? _domainName(cave.domainId) : "la grotte"} '
          '— reconquiers-la !',
          _interiorColor);
    });
  }

  // Sortir de la grotte → restaure la map principale.
  void _exitInterior() {
    final saved = _savedW;
    if (saved == null) return;
    setState(() {
      _w = saved;
      _pos = _savedPos ?? saved.start;
      _revealed
        ..clear()
        ..addAll(_savedRevealed ?? const <String>{});
      _farmPests
        ..clear()
        ..addAll(_savedFarmPests ?? const {});
      _inInterior = false;
      _interiorCaveId = null;
      _savedW = null;
      _savedPos = null;
      _savedRevealed = null;
      _savedFarmPests = null;
      _tdMode = false;
      _webBroken = false;
    });
  }

  // Assaut INTÉRIEUR (reconquête) = MIROIR de _startPhase1, rôles inversés :
  // l'ARAIGNÉE défend (deck _myDeck émis en vagues, tient l'arc, possède les
  // tourelles/arcs déjà posés) ; MOI j'attaque — mon deck de reconquête farmé
  // joue la réserve d'assaut (= _garrison de l'« envahisseur » = mon scorpion 🦂).
  // Le moteur _simulate est réutilisé tel quel ; seules la résolution finale
  // (grotte prise = je GAGNE) et le visuel (🕷️↔🦂) sont inversés via _inInterior.
  void _startInteriorAssault() {
    final w = _w;
    if (w == null || !_inInterior) return;
    if (_reconquestDeck <= 0) {
      _toast('Deck vide — bats les nuisibles du domaine avant l\'assaut ⚔️.',
          _interiorColor);
      return;
    }
    setState(() {
      _tdMode = true;
      _phase1 = true;
      _assault = false;
      _webBroken = false;
      _sbires.clear();
      _myAtk.clear();
      _shots.clear();
      _grotteTaken = false;
      _invaderGone = false;
      _captureStartMs = null;
      _grotteHpAtCapture = 0;
      // Deck de l'ARAIGNÉE (défenseur) — fixe pour l'instant : masse 30.
      const sp = 4, sc = 1, se = 0;
      _myDeck
        ..clear()
        ..addAll({'spider': sp, 'scorpion': sc, 'snake': se});
      _myMass = sp * GoldEconomy.masseSpider +
          sc * GoldEconomy.masseScorpion +
          se * GoldEconomy.masseSerpent;
      // MA réserve d'assaut = le deck de reconquête farmé (= garnison invader).
      _garrison = _reconquestDeck;
      _enemyDeckPower = _garrison;
      // Araignée (défenseur) près de sa grotte 'coeur' ; mon scorpion (attaquant)
      // démarre LÀ OÙ EST L'AVATAR (il l'accompagne depuis l'entrée).
      _redSpawn = const Offset(11, 6);
      _redHome = const Offset(11, 6);
      _redWander = null;
      // Le scorpion est LANCÉ 2 cases sur la droite (charge vers la grotte) et
      // toute la map se révèle → l'assaut se joue en cinématique (déplacement
      // verrouillé tant que _tdMode est actif, cf. _onTap/_moveDir).
      _invX = (_pos.x + 2).clamp(0, w.cols - 1).toDouble();
      _invY = _pos.y.toDouble();
      for (var yy = 0; yy < w.rows; yy++) {
        for (var xx = 0; xx < w.cols; xx++) {
          _revealed.add('${xx}_$yy');
        }
      }
      _grotteTarget = const Offset(11, 7);
      _grotteCaveId = 'coeur';
      _grotteHpMax = 60;
      _grotteHp = _grotteHpMax;
      _arrows = logic.weaponsAvailable('arc');
      _gateHp = _gateHpMax;
      _nextWaveMs = _gameMs;
      final total = sp + sc + se;
      _emitBatch = total <= 0 ? 1 : ((total + 9) ~/ 10);
      _toast('⚔️ Assaut lancé — déloge l\'araignée !', _interiorColor);
    });
  }

  // Fin d'assaut intérieur (appelé par _simulate). win = grotte 'coeur' prise.
  void _finishInteriorAssault({required bool win, required String message}) {
    _tdMode = false;
    _phase1 = false;
    _toast(message, win ? _kBlue : _kEnemy);
    if (!win) return;
    // Victoire → reprendre la VRAIE grotte du domaine (territories/{uid}).
    final base = _t;
    final me = sync.uid;
    final id = _interiorCaveId;
    if (base != null && me != null && id != null && base.caveById(id) != null) {
      final caves = base.caves
          .map((c) => c.id == id
              ? c.copyWith(ownerUid: me, occupied: false, blueLevel: 1)
              : c)
          .toList();
      sync.saveTerritory(base.copyWith(caves: caves, mapTaken: false));
    }
    _exitInterior();
  }

  Future<void> _boot() async {
    final domainIds = logic.state.activeDomains.map((d) => d.id).toList();
    await sync.ensureTerritory('Toi', domainIds: domainIds);
    final me = sync.uid ?? '';
    _sub = sync.streamTerritory(me).listen((t) async {
      if (!mounted) return;
      // La map doit incarner exactement les domaines actifs (une grotte/domaine).
      // Migration des docs legacy (nw/ne/sw/se) + ajout/retrait au fil des domaines.
      if (t != null && _needsDomainReconcile(t)) {
        await _reconcileDomains(t); // le save re-déclenche le stream, bonnes grottes
        return;
      }
      setState(() {
        _t = t;
        _loading = false;
        // Génère la map principale (sauf sur MOBILE : on entre direct dans un
        // domaine — calendrier seul, pas d'overworld).
        if (_w == null && t != null && !widget.mobile) {
          // Miroir horizontal (preview) : château à gauche, farm à droite.
          final w = mirrorWorldX(generateUnifiedWorld(t.seed,
              caveIds: t.caves.map((c) => c.id).toList()));
          _w = w;
          final saved = logic.state.unifiedPos;
          if (saved != null && saved.contains('_')) {
            final s = saved.split('_');
            final px = int.tryParse(s[0]) ?? -1, py = int.tryParse(s[1]) ?? -1;
            _pos = w.inBounds(px, py) ? Point(px, py) : w.start;
          } else {
            _pos = w.start;
          }
          _revealed.addAll(logic.state.unifiedRevealed);
          // Arcs/cases blanches/ponts toujours visibles (postes de tir fixes).
          for (final p in [
            ..._bowTiles,
            ..._bowPads,
            ..._bowBridges,
            ..._greyTiles
          ]) {
            _revealed.add('${p.x}_${p.y}');
          }
          // Tours TD persistées (état perso de la grande map).
          for (final tile in logic.state.unifiedTurrets) {
            _turrets[tile] = 1;
          }
          _revealAround(_pos);
          _populateFarm(); // disperse le backlog sur toute la zone (caché par le fog)
        }
        _recomputeStreakTurrets(); // bâti = tourelles dérivées des streaks
      });
      // MOBILE : pas de map principale → on entre direct dans le 1er domaine
      // (calendrier). Une seule fois (puis _inInterior bloque la ré-entrée).
      if (widget.mobile &&
          !_inInterior &&
          t != null &&
          t.caves.isNotEmpty &&
          mounted) {
        _enterInterior(t.caves.first.id);
      }
      // À la 1ʳᵉ map chargée : auto-trigger hebdo (1×/sem) si la semaine a décliné.
      if (!_autoThreatChecked && t != null && !widget.mobile) {
        _autoThreatChecked = true;
        _maybeAutoThreat(t);
      }
    });
    // Pilote la marche de l'araignée (position dérivée du temps depuis le spawn).
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _gameTicker?.dispose();
    super.dispose();
  }

  // ── Grottes = domaines ────────────────────────────────────────────────────
  /// La map doit avoir une grotte par domaine actif (ni plus, ni moins).
  bool _needsDomainReconcile(Territory t) {
    final domains = logic.state.activeDomains;
    if (domains.isEmpty) return false; // domaines pas chargés → ne pas toucher
    final caveIds = t.caves.map((c) => c.id).toSet();
    final domIds = domains.map((d) => d.id).toSet();
    return caveIds.length != domIds.length || !caveIds.containsAll(domIds);
  }

  /// Reconstruit les grottes depuis les domaines actifs : conserve niveau/proprio
  /// d'une grotte existante au même id, crée les manquantes (niv 1), retire celles
  /// sans domaine (legacy nw/ne/…). Persiste (le stream se rafraîchit ensuite).
  Future<void> _reconcileDomains(Territory t) async {
    final me = sync.uid;
    final domains = logic.state.activeDomains;
    if (me == null || domains.isEmpty) return;
    final byId = {for (final c in t.caves) c.id: c};
    final caves = <TerritoryCave>[
      for (final d in domains)
        byId[d.id] != null
            ? (byId[d.id]!.domainId == d.id
                ? byId[d.id]!
                : byId[d.id]!.copyWith(domainId: d.id))
            : TerritoryCave(
                id: d.id,
                x: 0,
                y: 0,
                ownerUid: me,
                blueLevel: 1,
                occupied: false,
                domainId: d.id),
    ];
    // L'envahisseur ciblait une grotte disparue → on l'annule (évite un target mort).
    final keepIds = caves.map((c) => c.id).toSet();
    final inv = t.invader;
    final dropInvader = inv != null &&
        inv.targetCaveId != 'castle' &&
        !keepIds.contains(inv.targetCaveId);
    await sync.saveTerritory(
        t.copyWith(caves: caves, clearInvader: dropInvader));
  }

  /// Nom du domaine incarné par une grotte (pour titres/toasts/labels).
  String _domainName(String domainId) {
    for (final d in logic.state.activeDomains) {
      if (d.id == domainId) return d.name;
    }
    return 'grotte';
  }

  /// Couleur d'une grotte que JE possède = couleur de son domaine (la map se lit
  /// comme un dashboard d'équilibre). Le rouge reste réservé aux grottes prises.
  Color _caveColor(TerritoryCave c) =>
      domainColor(c.domainId.isEmpty ? c.id : c.domainId,
          logic.state.activeDomains) ??
      _kBlue;

  // Lève le brouillard autour de [p] ; retourne les cases NOUVELLEMENT révélées.
  List<String> _revealAround(Point<int> p) {
    final w = _w;
    if (w == null) return const [];
    final added = <String>[];
    for (var dy = -_kReveal; dy <= _kReveal; dy++) {
      for (var dx = -_kReveal; dx <= _kReveal; dx++) {
        final nx = p.x + dx, ny = p.y + dy;
        if (!w.inBounds(nx, ny)) continue;
        final id = '${nx}_$ny';
        if (_revealed.add(id)) added.add(id);
      }
    }
    // Intérieur : révéler la case (8,7) devant les TOILES 🕸️ lève TOUT le
    // brouillard → on voit le château (16,7) et toute la grotte derrière la porte.
    if (_inInterior && _revealed.contains('8_7')) {
      for (var y = 0; y < w.rows; y++) {
        for (var x = 0; x < w.cols; x++) {
          if (_revealed.add('${x}_$y')) added.add('${x}_$y');
        }
      }
    }
    return added;
  }

  List<Point<int>> _ortho(int x, int y) {
    return [
      Point(x + 1, y),
      Point(x - 1, y),
      Point(x, y + 1),
      Point(x, y - 1),
    ].where((p) => _passable(p.x, p.y)).toList();
  }

  // Franchissable = sol/arc, OU les TOILES 🕸️ une fois percées (intérieur).
  bool _passable(int x, int y) {
    final w = _w;
    if (w == null) return false;
    return w.walkable(x, y) ||
        _isBowWalkable(x, y) ||
        (_inInterior && _webBroken && w.isGate(x, y));
  }

  // BFS sur cases révélées + walkable (on ne traverse pas le brouillard).
  List<Point<int>> _bfsPath(Point<int> from, Point<int> to) {
    if (from == to) return const [];
    final startId = '${from.x}_${from.y}';
    final goalId = '${to.x}_${to.y}';
    final prev = <String, String?>{startId: null};
    final queue = <Point<int>>[from];
    var i = 0;
    while (i < queue.length) {
      final cur = queue[i++];
      if ('${cur.x}_${cur.y}' == goalId) break;
      for (final n in _ortho(cur.x, cur.y)) {
        final nid = '${n.x}_${n.y}';
        if (prev.containsKey(nid) || !_revealed.contains(nid)) continue;
        prev[nid] = '${cur.x}_${cur.y}';
        queue.add(n);
      }
    }
    if (!prev.containsKey(goalId)) return const [];
    final path = <Point<int>>[];
    var cur = goalId;
    while (cur != startId) {
      final s = cur.split('_');
      path.add(Point(int.parse(s[0]), int.parse(s[1])));
      cur = prev[cur]!;
    }
    return path.reversed.toList();
  }

  Future<void> _walkPath(List<Point<int>> path) async {
    setState(() => _busy = true);
    for (final p in path) {
      if (!mounted) break;
      _step(p);
      await Future.delayed(const Duration(milliseconds: 150));
    }
    if (mounted) setState(() => _busy = false);
  }

  void _step(Point<int> to) {
    _revealAround(to);
    _populateFarm();
    setState(() => _pos = to);
    _announce(to);
  }

  // Persiste position + brouillard de l'avatar (état perso → doc meta de l'user,
  // PAS le doc territoire spectatable). Appelé une fois après chaque déplacement.
  void _persistWalk() {
    if (_inInterior) return; // l'intérieur de grotte ne persiste pas la map principale
    final pos = '${_pos.x}_${_pos.y}';
    logic.state.unifiedPos = pos;
    logic.state.unifiedRevealed
      ..clear()
      ..addAll(_revealed);
    sync.setUnifiedWorldState(pos, _revealed.toList());
  }

  // Peuple la zone farm (gauche) avec tes VRAIS ennemis backlog (routines/activités/
  // tâches négligées) — pas des pests génériques. Placés à la révélation (faciles
  // d'abord), purgés quand l'item est rattrapé (PV 0). Cap visuel, repioche dans le
  // backlog restant.
  void _populateFarm() {
    final w = _w, t = _t;
    if (w == null || t == null) return;
    _farmPests.removeWhere((_, e) => logic.enemyHp(e.type, e.id) <= 0);
    const cap = 12;
    final room = cap - _farmPests.length;
    if (room <= 0) return;
    final placed = _farmPests.values.map((e) => e.id).toSet();
    var backlog = logic.backlogEnemies()
        .where((e) => !placed.contains(e.id))
        .toList();
    if (_inInterior) {
      // À l'intérieur d'une grotte : SEULEMENT les nuisibles de CE domaine.
      backlog = backlog
          .where((e) => logic.enemyDomainId(e.type, e.id) == _interiorCaveId)
          .toList();
    }
    if (backlog.isEmpty) return;
    // Toutes les cases farm libres, MÉLANGÉES (seed stable) → répartition sur TOUTE
    // la zone (pas un cluster à l'entrée). Le brouillard les révèle en explorant.
    final free = <String>[];
    for (int y = 0; y < w.rows; y++) {
      for (int x = 0; x < w.castle.x - 1; x++) {
        if (w.at(x, y) != UwTile.floor || w.hasBush(x, y)) continue;
        final id = '${x}_$y';
        if (_farmPests.containsKey(id)) continue;
        if (x == _pos.x && y == _pos.y) continue;
        free.add(id);
      }
    }
    free.shuffle(Random(t.seed));
    for (var i = 0; i < backlog.length && i < free.length && i < room; i++) {
      _farmPests[free[i]] = (type: backlog[i].type, id: backlog[i].id);
    }
  }

  // Combat backlog : aller au contact d'un ennemi (= un vrai item négligé) ouvre la
  // carte de combat en ENCART À DROITE (carte visible derrière). FAIRE LE TRAVAIL
  // fait fondre l'ennemi ; PV 0 → il disparaît de la map.
  Future<void> _backlogCombat(String tileId, String type, String id) async {
    setState(() => _combat = (type: type, id: id, tileId: tileId));
  }

  // Encart de combat (colonne droite) quand on attaque un nuisible.
  Widget _combatPanel() {
    final c = _combat!;
    return BacklogCombatPanel(
      key: ValueKey('${c.type}_${c.id}'),
      logic: logic,
      sync: sync,
      type: c.type,
      itemId: c.id,
      compact: true,
      rootContext: context,
      onChanged: () {
        if (!mounted) return;
        if (logic.enemyHp(c.type, c.id) <= 0) {
          // À l'intérieur : battre un nuisible du domaine gonfle ton deck de
          // reconquête (= la masse du nuisible : 🕷️5 / 🦂10 / 🐍15).
          if (_inInterior && _farmPests.containsKey(c.tileId)) {
            final gain = _massByType[c.type] ?? 0;
            _reconquestDeck += gain;
            _toast('+$gain deck de reconquête 🦂 (total $_reconquestDeck)',
                _interiorColor);
          }
          _farmPests.remove(c.tileId);
        }
        setState(() {});
      },
      onLaunchedTimer: () {
        // Minuteur lancé → on ferme l'encart et on quitte la map.
        if (mounted) Navigator.pop(context);
      },
      onClose: _closeCombat,
    );
  }

  // Ferme l'encart de combat (sans fermer la map) ; retire l'ennemi si vaincu.
  void _closeCombat() {
    final c = _combat;
    if (c == null || !mounted) return;
    if (logic.enemyHp(c.type, c.id) <= 0) _farmPests.remove(c.tileId);
    setState(() => _combat = null);
  }

  // Repère château au passage (les grottes, elles, déclenchent l'engagement).
  void _announce(Point<int> to) {
    final w = _w;
    if (w == null) return;
    if (to == w.castle) {
      _toast('🏰 Château — le cœur de ta map (à défendre).', _kGold);
    }
  }

  // ── Invasion spatiale (T2) : l'araignée marche du bord DROIT vers sa cible ──
  // RÈGLE : elle vise toujours la GROTTE la plus faible ; le château n'est ciblé
  // que s'il ne te reste AUCUNE grotte (les 4 prises) — c'est `spawnBotInvader`
  // qui pose ça. Sa position est DÉRIVÉE du temps écoulé depuis spawnAtMs le long
  // d'un chemin droite→cible : on ne persiste pas x/y sur la grille unifiée (donc
  // l'ancienne fiche 9×9 reste intacte). Seuls les états TERMINAUX (grotte/map
  // prise, repoussé) sont écrits dans le doc.

  Point<int>? _invaderTarget(UnifiedWorld w, Invader inv) =>
      inv.targetCaveId == 'castle' ? w.castle : w.caves[inv.targetCaveId];

  // Spawn = bord GAUCHE (ouest), rangée de la cible : l'araignée traverse alors
  // TOUTE la largeur jusqu'à sa cible (grottes à droite) → vraie fenêtre de défense
  // (et future « lane » de tower-defense). `_posAt` marche vers la cible → sens auto.
  Point<int> _invaderSpawn(UnifiedWorld w, Point<int> target) =>
      Point(0, target.y);

  int _pathLen(Point<int> s, Point<int> t) =>
      (s.x - t.x).abs() + (s.y - t.y).abs();

  // Avance Manhattan de [steps] depuis le spawn (ignore les murs : la friction
  // des murs est pour TOI, pas pour le maraudeur — comme advanceInvader).
  Point<int> _posAt(Point<int> s, Point<int> target, int steps) {
    var x = s.x, y = s.y, n = steps;
    while (n > 0 && (x != target.x || y != target.y)) {
      final dx = target.x - x, dy = target.y - y;
      if (dx != 0 && (dy == 0 || dx.abs() >= dy.abs())) {
        x += dx > 0 ? 1 : -1;
      } else {
        y += dy > 0 ? 1 : -1;
      }
      n--;
    }
    return Point(x, y);
  }

  // Position courante de l'araignée, ou null si pas d'invasion.
  Point<int>? _spiderPos() {
    final t = _t, w = _w;
    final inv = t?.invader;
    if (t == null || w == null || inv == null || t.mapTaken) return null;
    final target = _invaderTarget(w, inv);
    if (target == null) return null;
    final spawn = _invaderSpawn(w, target);
    final len = _pathLen(spawn, target);
    final steps =
        ((DateTime.now().millisecondsSinceEpoch - inv.spawnAtMs) ~/ _stepMs)
            .clamp(0, len);
    return _posAt(spawn, target, steps);
  }

  void _tick() {
    if (_paused) return;
    final t = _t, w = _w;
    final inv = t?.invader;
    if (t == null || w == null || inv == null || t.mapTaken) return;
    final target = _invaderTarget(w, inv);
    if (target == null) return;
    final spawn = _invaderSpawn(w, target);
    final len = _pathLen(spawn, target);
    final now = DateTime.now().millisecondsSinceEpoch;
    final steps = (now - inv.spawnAtMs) ~/ _stepMs;
    if (steps < len) {
      setState(() {}); // marche → re-render la position
      return;
    }
    // Arrivée : fenêtre d'interception puis résolution passive.
    final arrivalMs = inv.spawnAtMs + len * _stepMs;
    if (now - arrivalMs >= _caveWindowMs) {
      _resolveArrival(t, inv);
    } else {
      setState(() {});
    }
  }

  // Résolution passive (pas d'interception à temps) : château → map prise ;
  // grotte → menace vs niveau (bot gagne si level > blueLevel → grotte prise).
  void _resolveArrival(Territory t, Invader inv) {
    _paused = true;
    if (inv.targetCaveId == 'castle') {
      final next = t.copyWith(mapTaken: true, clearInvader: true);
      _t = next;
      sync.saveTerritory(next);
      if (mounted) setState(() {});
      _paused = false;
      _toast('💀 Ton château est tombé — MAP PRISE. Reconquiers tes grottes.',
          _kEnemy);
      return;
    }
    final cave = t.caveById(inv.targetCaveId);
    if (cave == null) {
      _paused = false;
      return;
    }
    final botWins = inv.level > cave.blueLevel;
    final Territory next;
    if (botWins) {
      final caves = t.caves
          .map((c) => c.id == cave.id
              ? c.copyWith(ownerUid: 'bot', occupied: true, blueLevel: inv.level)
              : c)
          .toList();
      next = t.copyWith(caves: caves, clearInvader: true);
    } else {
      next = t.copyWith(clearInvader: true);
    }
    _t = next;
    sync.saveTerritory(next);
    if (mounted) setState(() {});
    _paused = false;
    _toast(
        botWins
            ? '🟡 Le bot a PRIS ta grotte ${_domainName(cave.domainId)} ! Va la reprendre.'
            : '🛡️ Ta grotte ${_domainName(cave.domainId)} a tenu — le bot s\'est brisé dessus.',
        botWins ? _kEnemy : _kBlue);
  }

  // Interception : au contact de l'araignée → combat. Victoire = repoussée.
  Future<void> _intercept() async {
    final t = _t;
    final inv = t?.invader;
    if (t == null || inv == null) return;
    _paused = true;
    setState(() => _busy = true);
    final winner = await showCaveFight(context, logic, sync,
        blueLevel: inv.level, title: 'Interception — envahisseur');
    _paused = false;
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    final base = _t;
    if (winner == 'defender' && base != null) {
      final next = base.copyWith(clearInvader: true);
      _t = next;
      await sync.saveTerritory(next);
      if (mounted) setState(() {});
      _toast('🏹 Envahisseur repoussé — ta map est sauve.', _kBlue);
    } else {
      _toast('L\'envahisseur continue sa marche…', _kEnemy);
    }
  }

  // Courbe DOUCE chute de score hebdo → menace (idem territory_sheet).
  int _threatLevel(double drop) {
    if (drop <= 0) return 1;
    if (drop <= 0.25) return 2;
    if (drop <= 0.50) return 3;
    return 4;
  }

  // Dev : convoque un envahisseur scalé sur la vraie chute hebdo (planché à 2).
  Future<void> _summon() async {
    final t = _t;
    final me = sync.uid;
    if (t == null || me == null) return;
    if (t.invader != null) {
      _toast('Un envahisseur est déjà sur ta map (1 à la fois).', _kEnemy);
      return;
    }
    final sig = logic.territoryThreatSignal();
    final scaled = sig.hadData ? _threatLevel(sig.drop) : 1;
    final level = scaled < 2 ? 2 : scaled;
    final next = spawnBotInvader(
        t, me, DateTime.now().millisecondsSinceEpoch,
        botLevel: level);
    if (next.invader == null) {
      _toast(
          t.mapTaken
              ? 'Map déjà prise — reconquiers tes grottes.'
              : 'Plus de grotte à défendre.',
          _kEnemy);
      return;
    }
    _t = next;
    await sync.saveTerritory(next);
    if (!mounted) return;
    setState(() {});
    final cibleInv = next.invader!.targetCaveId;
    final cible = cibleInv == 'castle'
        ? 'ton CHÂTEAU ❤️'
        : 'ta grotte ${_domainName(cibleInv)}';
    _toast(
        '🕷️ Un envahisseur (niv $level) arrive par l\'ouest vers $cible !',
        _kEnemy);
  }

  // Auto-trigger d'accountability (porté de territory_sheet) : à l'ouverture, si la
  // dernière semaine complète a décliné (menace ≥ 2) et qu'aucune invasion n'est en
  // cours, spawn un bot scalé — 1×/semaine (clé `lastThreatWeek`). `force` (dev)
  // ignore la clé hebdo et ne consomme pas la semaine ; toaste la décision.
  void _maybeAutoThreat(Territory t, {bool force = false}) {
    final me = sync.uid;
    if (me == null) return;
    if (t.invader != null || t.mapTaken) {
      if (force) _toast('Déjà une invasion en cours / map prise.', _kEnemy);
      return;
    }
    final sig = logic.territoryThreatSignal();
    if (!force && t.lastThreatWeek == sig.weekKey) return;
    if (!sig.hadData) {
      if (force) {
        _toast('🐞 Moins de 2 semaines de score exploitables → aucun spawn.',
            Colors.white60);
      }
      return;
    }
    final level = _threatLevel(sig.drop);
    if (level < 2) {
      if (force) {
        _toast('🐞 Semaine stable ou en hausse → aucune menace (pas de spawn).',
            _kBlue);
      } else {
        final marked = t.copyWith(lastThreatWeek: sig.weekKey);
        _t = marked;
        sync.saveTerritory(marked);
      }
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final base = spawnBotInvader(t, me, now, botLevel: level);
    if (base.invader == null) {
      if (!force) {
        final marked = t.copyWith(lastThreatWeek: sig.weekKey);
        _t = marked;
        sync.saveTerritory(marked);
      }
      return;
    }
    final spawned = force ? base : base.copyWith(lastThreatWeek: sig.weekKey);
    _t = spawned;
    sync.saveTerritory(spawned);
    if (mounted) setState(() {});
    final pct = (sig.drop * 100).round();
    _toast(
        '${force ? '🐞 (forcé) ' : '🕷️ '}Ta semaine a chuté de $pct % → '
        'araignée niv $level (arrive par l\'ouest).',
        _kEnemy);
  }

  // Bascule la cadence ; rebase spawnAtMs pour garder l'araignée à sa position
  // courante (la position est dérivée de stepMs → sinon elle saute au changement).
  void _setCadence(bool real) {
    if (_realCadence == real) return;
    final t = _t;
    final inv = t?.invader;
    if (t != null && inv != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final oldSteps = (now - inv.spawnAtMs) ~/ _stepMs;
      setState(() => _realCadence = real);
      final rebased = now - oldSteps * _stepMs; // _stepMs reflète la NOUVELLE cadence
      final next = t.copyWith(invader: inv.copyWith(spawnAtMs: rebased));
      _t = next;
      sync.saveTerritory(next);
    } else {
      setState(() => _realCadence = real);
    }
  }

  // Persiste les tours posées (état perso, comme position/brouillard).
  void _persistTurrets() {
    final list = _turrets.keys.toList();
    logic.state.unifiedTurrets
      ..clear()
      ..addAll(list);
    sync.setUnifiedTurrets(list);
  }

  // Icône de tour selon la fréquence : routine hebdo/mensuelle = canon DCA
  // (anti-aircraft), sinon turret (quotidiennes + activités-temps).
  String _turretIcon(String id, String kind) {
    if (kind == 'spider') {
      for (final a in logic.state.activeActivities) {
        if (a.id == id) {
          if (a.isHabit && logic.effectiveHabitFreq(a).name != 'daily') {
            return 'assets/icons/anti-aircraft-gun.svg';
          }
          break;
        }
      }
    }
    return 'assets/icons/turret.svg';
  }

  // Barre de vie CONTINUE : remplissage `frac` (0..1), couleur = code santé.
  Widget _webLifeBar(double frac, double slot) {
    final col = _lifeColor(frac);
    return ClipRRect(
      borderRadius: BorderRadius.circular(slot * 0.03),
      child: Container(
        width: slot * 0.77,
        height: slot * 0.1,
        color: col.withOpacity(.18),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: frac.clamp(0.0, 1.0),
          child: Container(color: col),
        ),
      ),
    );
  }

  // Barre segmentée (7 cases) sous la tour, dimensionnée sur le `slot` de la grille.
  Widget _webSegBar(int filled, Color color, double slot) {
    final seg = slot * 0.09;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 7; i++)
          Container(
            width: seg,
            height: seg * 0.9,
            margin: EdgeInsets.only(right: slot * 0.02),
            decoration: BoxDecoration(
              color: i < filled ? color : Colors.white.withOpacity(.12),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    );
  }

  // CALENDRIER de domaine : les 10 routines les PLUS FAITES (tri par complétions
  // de la semaine passée) → 1 ligne chacune. charger = chargeur de la tour.
  List<({String id, String name, int charger, int active})> _domTopRoutines() {
    final dom = _interiorDomainId;
    if (dom == null) return const [];
    final list = <({String id, String name, int charger, int active})>[];
    for (final a in logic.state.activeActivities) {
      if (!a.isHabit || a.domainId != dom) continue;
      // Calendrier = routines QUOTIDIENNES seulement (tokens vides = non-daily).
      if (logic.routineWeekTokens(a.id).isEmpty) continue;
      list.add((
        id: a.id,
        name: a.name,
        charger: logic.routineDefenseCharger(a.id),
        active: logic.routine30dActive(a.id)
      ));
    }
    list.sort((a, b) => b.active.compareTo(a.active)); // les 5 plus actives /30j
    return list.take(5).toList();
  }

  // Les 5 activités-TEMPS (type=time) les plus actives sur 30j du domaine courant.
  List<({String id, String name, int charger, int active})>
      _domTopTimeActivities() {
    final dom = _interiorDomainId;
    if (dom == null) return const [];
    final list = <({String id, String name, int charger, int active})>[];
    for (final a in logic.state.activeActivities) {
      if (a.isHabit || a.domainId != dom) continue;
      final tok = logic.activityTimeTokens(a.id);
      if (tok.isEmpty) continue; // goalMin > 0
      list.add((
        id: a.id,
        name: a.name,
        // Chargeur = jours où l'objectif-temps a été atteint (7 glissants).
        charger:
            tok.where((t) => t.type == 'leaf' || t.type == 'flame').length,
        active: logic.activityTime30dMin(a.id)
      ));
    }
    list.sort((a, b) => b.active.compareTo(a.active));
    return list.take(5).toList();
  }

  // BÂTI — recalcule les tourelles dérivées des streaks : pour chaque routine
  // (habit) à streak ≥ 1, une tour dans la zone de SA grotte de domaine, niveau =
  // streak. C'est la constance réelle qui fortifie (pas une pose à la main).
  void _recomputeStreakTurrets() {
    _streakTurrets.clear();
    final w = _w, t = _t;
    if (w == null || t == null || _inInterior) return;
    final byDomain = <String, List<({String name, int streak})>>{};
    for (final a in logic.state.activeActivities) {
      if (!a.isHabit) continue;
      final s = logic.habitCurrentStreak(a.id);
      if (s < 1) continue;
      (byDomain[a.domainId] ??= []).add((name: a.name, streak: s));
    }
    byDomain.forEach((domainId, routines) {
      TerritoryCave? cave;
      for (final c in t.caves) {
        if (c.domainId == domainId) {
          cave = c;
          break;
        }
      }
      if (cave == null) return;
      final cp = w.caves[cave.id];
      if (cp == null) return;
      final color = _caveColor(cave);
      routines.sort((a, b) => b.streak.compareTo(a.streak)); // grosses au plus près
      final slots = _freeFloorNear(cp, routines.length);
      for (var i = 0; i < routines.length && i < slots.length; i++) {
        _streakTurrets['${slots[i].x}_${slots[i].y}'] = (
          streak: routines[i].streak,
          color: color,
          name: routines[i].name
        );
      }
    });
  }

  // Cases sol libres autour d'un centre (anneaux croissants, ordre déterministe),
  // hors grottes / rochers / buissons / tours déjà posées.
  List<Point<int>> _freeFloorNear(Point<int> center, int n) {
    final w = _w!;
    final out = <Point<int>>[];
    for (var r = 1; r <= 5 && out.length < n; r++) {
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (out.length >= n) break;
          if (dx.abs() != r && dy.abs() != r) continue; // périmètre de l'anneau
          final x = center.x + dx, y = center.y + dy;
          if (!w.inBounds(x, y) || w.at(x, y) != UwTile.floor) continue;
          if (w.hasRock(x, y) || w.hasBush(x, y) || w.caveIdAt(x, y) != null) {
            continue;
          }
          final tile = '${x}_$y';
          if (_streakTurrets.containsKey(tile) || _turrets.containsKey(tile)) {
            continue;
          }
          if (out.any((p) => p.x == x && p.y == y)) continue;
          out.add(Point(x, y));
        }
      }
    }
    return out;
  }

  // Maintien (TD) : retire la tour de cette case.
  void _onLongPress(int x, int y) {
    if (!_tdMode) return;
    final tile = '${x}_$y';
    if (_turrets.containsKey(tile)) {
      setState(() {
        _turrets.remove(tile);
        _turretLastFireMs.remove(tile);
        if (_selectedTurret == tile) _selectedTurret = null;
      });
      _persistTurrets();
    }
  }

  // Déplacement de l'avatar d'une case (flèches clavier).
  void _moveDir(int dx, int dy) {
    final w = _w;
    if (w == null || _busy) return;
    if (_inInterior && _tdMode) return; // assaut = cinématique, pas de déplacement
    final nx = _pos.x + dx, ny = _pos.y + dy;
    if (!_passable(nx, ny)) return;
    _step(Point(nx, ny));
    _persistWalk();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp) {
      _moveDir(0, -1);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _moveDir(0, 1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _moveDir(-1, 0);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _moveDir(1, 0);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> _onTap(int x, int y) async {
    final w = _w;
    if (_busy || w == null) return;
    // Assaut intérieur = cinématique : déplacement verrouillé (le scorpion charge
    // tout seul). On laisse passer uniquement pour la phase farm (!_tdMode).
    if (_inInterior && _tdMode) return;
    // Tap sur la grotte ROUGE (envahie) → ENTRER dans la grotte (niveau intérieur).
    if (_grotteTaken &&
        !_inInterior &&
        !_phase1 &&
        w.caveIdAt(x, y) == _grotteCaveId) {
      _enterInterior(_grotteCaveId!);
      return;
    }
    // Mode TD (dev) : tap = pose/retrait d'une tour sur une case sol marchable.
    // MAIS à l'INTÉRIEUR (assaut de reconquête) le tap doit DÉPLACER l'avatar
    // (sinon impossible de bouger pendant l'assaut) — tourelles intérieures = + tard.
    if (_tdMode && !_inInterior) {
      final tile = '${x}_$y';
      if (w.walkable(x, y) &&
          w.at(x, y) == UwTile.floor &&
          w.caveIdAt(x, y) == null &&
          !w.isSpawner(x, y)) {
        final placed = !_turrets.containsKey(tile);
        setState(() {
          if (placed) {
            // Pose sans sélectionner → pas de portée qui reste affichée.
            _turrets[tile] = 1;
            _selectedTurret = null;
          } else {
            // Tour existante : tap = bascule l'affichage de sa portée.
            _selectedTurret = _selectedTurret == tile ? null : tile;
          }
        });
        if (placed) _persistTurrets();
      } else {
        _toast('Pose la tour sur une case de sol libre.', Colors.white38);
      }
      return;
    }
    final p = _pos;
    final caveId = w.caveIdAt(x, y);
    final farmPest = _farmPests['${x}_$y'];
    final spider = _inInterior ? null : _spiderPos();
    final isSpider = spider != null && spider.x == x && spider.y == y;
    // Re-tap de la case courante : araignée > ennemi backlog > grotte.
    if (x == p.x && y == p.y) {
      if (isSpider) {
        await _intercept();
      } else if (farmPest != null) {
        await _backlogCombat('${x}_$y', farmPest.type, farmPest.id);
      } else if (caveId != null) {
        await _engageCave(caveId);
      }
      return;
    }
    if (!_passable(x, y)) {
      _toast('🧱 Un mur bloque ce passage.', Colors.white38);
      return;
    }
    final tileId = '${x}_$y';
    final adjacent = (x - p.x).abs() + (y - p.y).abs() == 1;
    if (!adjacent) {
      if (!_revealed.contains(tileId)) return;
      final path = _bfsPath(p, Point(x, y));
      if (path.isEmpty) {
        _toast('🌫️ Chemin bloqué par le brouillard.', Colors.white38);
        return;
      }
      await _walkPath(path);
    } else {
      _step(Point(x, y));
    }
    _persistWalk(); // position + brouillard (état perso, hors doc spectatable)
    // Arrivé sur la case visée → engage : araignée (interception) > ennemi backlog
    // (combat = faire le travail) > grotte (défendre / reprendre).
    if (_pos.x == x && _pos.y == y) {
      if (isSpider) {
        await _intercept();
      } else if (farmPest != null) {
        await _backlogCombat('${x}_$y', farmPest.type, farmPest.id);
      } else if (caveId != null) {
        await _engageCave(caveId);
      }
    }
  }

  // T1 — défense par avatar : entrer dans une grotte au contact ouvre l'ENCOUNTER
  // (board lanes `showCaveFight`). Grotte à moi → lever (+1 niveau) ; grotte prise
  // → reprendre (battre le boss installé). Effets persistés dans territories/{uid}
  // (identiques à la fiche god-view `territory_sheet`, mais pilotés par la position).
  Future<void> _engageCave(String id) async {
    final t = _t;
    final me = sync.uid;
    if (t == null || me == null) return;
    final cave = t.caveById(id);
    if (cave == null) return;
    setState(() => _busy = true);
    final reclaim = cave.ownerUid != me;
    final winner = await showCaveFight(context, logic, sync,
        blueLevel: cave.blueLevel,
        title: reclaim
            ? 'Reprendre ${_domainName(cave.domainId)}'
            : '${_domainName(cave.domainId)} — niv ${cave.blueLevel}');
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    final base = _t;
    if (base == null) return;
    if (winner != 'defender') {
      if (reclaim) {
        _toast('Le boss installé a tenu — la grotte reste prise.', _kEnemy);
      }
      return;
    }
    if (reclaim) {
      final caves = base.caves
          .map((c) => c.id == id
              ? c.copyWith(ownerUid: me, occupied: false, blueLevel: 1)
              : c)
          .toList();
      // Reconquérir une grotte ramène le château (la map n'est plus prise).
      await sync.saveTerritory(base.copyWith(caves: caves, mapTaken: false));
      _toast('🔵 Grotte ${_domainName(cave.domainId)} REPRISE ! Défense à re-monter (niv 1).',
          _kBlue);
    } else {
      final caves = base.caves
          .map((c) =>
              c.id == id ? c.copyWith(blueLevel: c.blueLevel + 1) : c)
          .toList();
      await sync.saveTerritory(base.copyWith(caves: caves));
      _toast('🕳️ Grotte ${_domainName(cave.domainId)} montée → niveau ${cave.blueLevel + 1}',
          _kBlue);
    }
  }

  void _toast(String m, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: c,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400)));
  }

  @override
  Widget build(BuildContext context) {
    final t = _t, w = _w;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
        child: Row(children: [
          if (widget.mobile) ...[
            Text(
                _interiorDomainId != null
                    ? '🏴 ${_domainName(_interiorDomainId!)}'
                    : '🏴 Domaine',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: _interiorColor)),
            const Spacer(),
            TextButton.icon(
              onPressed: _quickEnter,
              icon: const Icon(Icons.swap_horiz, size: 18, color: Colors.white70),
              label: const Text('Changer',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ),
          ] else ...[
            const Text('🗺️ Monde',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
            const SizedBox(width: 8),
            Text('farm · château · territoire',
                style:
                    TextStyle(color: Colors.white.withOpacity(.4), fontSize: 11)),
            const Spacer(),
          ],
          IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => Navigator.pop(context)),
        ]),
      ),
      Flexible(
        child: (_loading || t == null || w == null)
            ? const Center(
                child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: _kBlue)))
            : _content(t, w),
      ),
      if (!_loading && t != null && !widget.mobile) _siegeBar(t),
    ]),
    );
  }

  // Fine barre de statut du siège long-terme (épinglée en bas). En T2 elle
  // résumera l'envahisseur spatial en marche ; ici elle lit déjà l'état du doc.
  Widget _siegeBar(Territory t) {
    final inv = t.invader;
    final String msg;
    final Color col;
    if (t.mapTaken) {
      msg = '💀 Map prise — reconquiers tes grottes (rouges).';
      col = _kEnemy;
    } else if (inv != null) {
      final cible = inv.targetCaveId == 'castle'
          ? 'ton château'
          : 'grotte ${_domainName(inv.targetCaveId)}';
      msg = '🕷️ Siège en cours — un envahisseur marche vers $cible.';
      col = _kEnemy;
    } else {
      msg = '🛡️ Aucun siège en cours.';
      col = _kFarm;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: col.withOpacity(.10),
        border: Border(top: BorderSide(color: col.withOpacity(.35))),
      ),
      child: Text(msg,
          textAlign: TextAlign.center,
          style:
              TextStyle(color: col, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  Widget _content(Territory t, UnifiedWorld w) {
    // Panneau d'ACTIONS à GAUCHE (scroll indépendant → pas de scroll global),
    // plateau à DROITE (prend la place restante).
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Panneau d'actions à gauche — masqué quand le combat est ouvert (place)
        // ET sur mobile (calendrier seul, pas d'overworld/dev).
        if (_combat == null && !widget.mobile)
        SizedBox(
          width: 236,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
            children: [
              _zonesLegend(),
              if (t.invader == null && !t.mapTaken) ...[
                const SizedBox(height: 12),
                _threatReadout(),
              ],
              if (_kDev) ...[
                const SizedBox(height: 12),
                _cadenceToggle(),
                const SizedBox(height: 8),
                _coordsToggle(),
                const SizedBox(height: 8),
                _tdControls(),
                if (t.invader == null && !t.mapTaken) ...[
                  const SizedBox(height: 8),
                  _summonBtn(),
                  const SizedBox(height: 8),
                  _forceThreatBtn(),
                ],
              ],
              const SizedBox(height: 12),
              Text(
                'Avatar : touche une case éclairée. À GAUCHE rôdent tes '
                'routines/tâches NÉGLIGÉES (🕷️🦂🐍) : va à leur contact → '
                'combat = fais le vrai travail. À DROITE, défends tes grottes '
                '(bleue → +1 ; rouge → reprends-la).',
                style:
                    TextStyle(color: Colors.white.withOpacity(.4), fontSize: 10.5),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: _board(t, w),
          ),
        ),
        // Encart de COMBAT à droite (carte visible derrière) quand on attaque.
        if (_combat != null)
          Container(
            width: 318,
            decoration: BoxDecoration(
              border: Border(
                  left: BorderSide(color: Colors.white.withOpacity(.08))),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  child: _combatPanel(),
                ),
                // Croix : ferme le combat sans fermer la map.
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Fermer le combat',
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: _closeCombat,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Readout d'accountability : où en est ta semaine et quelle menace elle appelle.
  Widget _threatReadout() {
    final sig = logic.territoryThreatSignal();
    final String msg;
    final Color col;
    if (!sig.hadData) {
      msg = '📊 Pas encore assez d\'historique de score pour jauger la menace hebdo.';
      col = Colors.white54;
    } else {
      final level = _threatLevel(sig.drop);
      final pct = (sig.drop * 100).round();
      if (level < 2) {
        msg = '📈 Semaine stable ou en hausse — aucune menace hebdo.';
        col = _kBlue;
      } else {
        msg = '📉 Semaine en baisse de $pct % → menace niv $level '
            '(le bot vient seul, 1×/sem).';
        col = _kEnemy;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: col.withOpacity(.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.withOpacity(.35)),
      ),
      child: Text(msg,
          textAlign: TextAlign.center,
          style:
              TextStyle(color: col, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }

  // Dev : toggle de cadence Test 3 s/pas ⇄ Réel 1 h/pas.
  Widget _cadenceToggle() {
    Widget pill(String label, bool real) {
      final sel = _realCadence == real;
      return Expanded(
        child: GestureDetector(
          onTap: () => _setCadence(real),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? _kGold.withOpacity(.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                  color: sel ? _kGold.withOpacity(.6) : Colors.transparent),
            ),
            child: Text(label,
                style: TextStyle(
                    color: sel ? _kGold : Colors.white54,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF160C0C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Row(children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('Cadence (dev)',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        pill('Test · 3 s/pas', false),
        const SizedBox(width: 4),
        pill('Réel · 1 h/pas', true),
      ]),
    );
  }

  // Dev : rejoue la décision d'auto-trigger maintenant (sans clé hebdo, rejouable).
  Widget _forceThreatBtn() => Center(
        child: InkWell(
          onTap: () {
            final t = _t;
            if (t != null) _maybeAutoThreat(t, force: true);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(.14)),
            ),
            child: Text('🐞 Forcer l\'auto-trigger (dev)',
                style: TextStyle(
                    color: Colors.white.withOpacity(.55),
                    fontWeight: FontWeight.w700,
                    fontSize: 11)),
          ),
        ),
      );

  Widget _coordsToggle() => Center(
        child: InkWell(
          onTap: () => setState(() => _showCoords = !_showCoords),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(_showCoords ? .12 : .04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Colors.white.withOpacity(_showCoords ? .4 : .14)),
            ),
            child: Text(
                _showCoords ? '🧭 Coords ON (fog levé)' : '🧭 Afficher coords',
                style: TextStyle(
                    color: Colors.white.withOpacity(.7),
                    fontWeight: FontWeight.w700,
                    fontSize: 11)),
          ),
        ),
      );

  Widget _tdControls() {
    Widget pill(String label, Color c, VoidCallback onTap, {bool on = false}) =>
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: c.withOpacity(on ? .18 : .08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.withOpacity(on ? .6 : .35)),
            ),
            child: Text(label,
                style: TextStyle(
                    color: c.withOpacity(.9),
                    fontWeight: FontWeight.w700,
                    fontSize: 11)),
          ),
        );
    final arcs = logic.weaponsAvailable('arc');
    return Column(children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          if (_inInterior && widget.mobile) ...[
            // MOBILE : juste le calendrier — changer de domaine + fermer.
            pill('🔄 Changer de domaine', _interiorColor, _quickEnter),
            pill('✕ Fermer', Colors.white70,
                () => Navigator.of(context).maybePop()),
          ],
          if (_inInterior && !widget.mobile) ...[
            if (!_tdMode && !_simDefense)
              pill('🛡️ Simuler la défense', const Color(0xFF4FA3FF),
                  _startSimDefense),
            if (!_tdMode)
              pill('⚔️ Lancer l\'assaut', _interiorColor, _startInteriorAssault),
            pill('🃏 Deck', _interiorColor.withOpacity(.85), _showAttackDeck),
            pill('🚪 Sortir de la grotte', _interiorColor.withOpacity(.7),
                _tdMode ? () {} : _exitInterior),
          ],
          if (!_inInterior) ...[
            pill('🕳️ Entrer dans la grotte', const Color(0xFF1E8E7E),
                _quickEnter),
            pill(
                _tdMode ? '⚔️ TD ON — pose des tours' : '⚔️ Mode tower-defense',
                const Color(0xFFB07CF0),
                () => setState(() => _tdMode = !_tdMode),
                on: _tdMode),
            pill('🕷️ Convoquer (Phase 1)', _kEnemy, _startPhase1),
            if (_tdMode)
            pill('🧹 Vider', Colors.white70, () {
              setState(() {
                _phase1 = false;
                _sbires.clear();
                _myAtk.clear();
                _myDeck.clear();
                _garrison = 0;
                _turrets.clear();
                _turretLastFireMs.clear();
                _shots.clear();
                _selectedTurret = null;
                _gateHp = _gateHpMax;
              });
                _persistTurrets();
              }),
          ],
        ],
      ),
      if (_inInterior) ...[
        const SizedBox(height: 6),
        Text(
            '🏴 ${_interiorDomainId != null ? _domainName(_interiorDomainId!) : "Grotte"}'
            ' · ${_domTurrets.length} tour${_domTurrets.length > 1 ? "s" : ""} de défense',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _interiorColor,
                fontSize: 13,
                fontWeight: FontWeight.w900)),
      ],
      if (_inInterior && !_tdMode) ...[
        const SizedBox(height: 4),
        Text(
            '🦂 Deck de reconquête : $_reconquestDeck — bats les nuisibles du '
            'domaine pour le gonfler, puis ⚔️ lance l\'assaut',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _interiorColor, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
      if (_tdMode) ...[
        const SizedBox(height: 6),
        Text(
            _phase1
                ? (_gateHp <= 0
                    ? 'PHASE 2 🔴 — assaut sur la grotte · 🕳️ PV ${_grotteHp}/${_grotteHpMax} · 🏹 $_arrows flèches · sbires ${_sbires.length} · 🗼 ${_turrets.length} (chaque tir = 1 flèche)'
                    : 'PHASE 1 — mon attaquant 🦂 (deck $_myMass) · garnison ennemie $_garrison · mon deck 🕷️${_myDeck['spider'] ?? 0}/🦂${_myDeck['scorpion'] ?? 0}/🐍${_myDeck['snake'] ?? 0} · sbires lâchés ${_sbires.length} · 🚪 ${((_gateHp / _gateHpMax) * 100).round()}% · 🗼 ${_turrets.length} (1 tir = 1 mort, gratuit)')
                : '🏹 $arcs flèches · 🚪 ${((_gateHp / _gateHpMax) * 100).round()}% · 🗼 ${_turrets.length} tours · pose tes tours puis « Convoquer »',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withOpacity(.6), fontSize: 10.5)),
      ],
    ]);
  }

  Widget _summonBtn() => Center(
        child: InkWell(
          onTap: _summon,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: _kEnemy.withOpacity(.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kEnemy.withOpacity(.5)),
            ),
            child: const Text('🕷️ Convoquer un envahisseur (test)',
                style: TextStyle(
                    color: _kEnemy, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
        ),
      );

  Widget _zonesLegend() {
    Widget item(String emoji, String label, Color c) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: c, fontSize: 11)),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        item('🏹', 'Farm (gauche)', _kFarm),
        item('🏰', 'Château', _kGold),
        item('🕳️', 'Grottes = tes domaines', Colors.white70),
      ],
    );
  }

  Widget _board(Territory t, UnifiedWorld w) {
    final avatar = logic.state.activeAvatar ?? '🧍';
    final spider = _inInterior ? null : _spiderPos();
    return LayoutBuilder(builder: (context, c) {
      // Panneau latéral des noms de routines (intérieur) : réservé hors grille
      // pour ne pas rétrécir les cases.
      final nameW = _inInterior ? (widget.mobile ? 130.0 : 200.0) : 0.0;
      // Mobile : slot fixe (calendrier scrollable, pas écrasé à l'écran du tel).
      final slot = widget.mobile
          ? 36.0
          : ((c.maxWidth - nameW) / w.cols).clamp(22.0, 46.0);
      final inner = slot - 3;
      final topRoutines = _inInterior
          ? _domTopRoutines()
          : const <({String id, String name, int charger, int active})>[];
      // Labels = jour réel des 7 DERNIERS jours (aujourd'hui à droite, tourne seul).
      final calToday = () {
        final n = DateTime.now();
        return DateTime(n.year, n.month, n.day);
      }();
      const weekdayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
      final dayLabels = [
        for (var i = 0; i < 7; i++)
          weekdayLetters[
              calToday.subtract(Duration(days: 6 - i)).weekday - 1]
      ];
      // Tokens du tapis par ligne : 'spider'/'leaf'/'flame' pour chaque jour.
      final lanes = [for (final r in topRoutines) logic.routineWeekTokens(r.id)];
      // Remplissage du château par ligne (toiles/feuilles des jours passés).
      final fills = [for (final r in topRoutines) logic.routineChateauFill(r.id)];
      // Section ACTIVITÉS-TEMPS (bas, rows 8-12) : même tapis avec le temps.
      final topTime = _inInterior
          ? _domTopTimeActivities()
          : const <({String id, String name, int charger, int active})>[];
      final timeLanes = [for (final r in topTime) logic.activityTimeTokens(r.id)];
      final timeFills =
          [for (final r in topTime) logic.activityTimeChateauFill(r.id)];
      // Toutes les lignes (routines rows 2-6 + temps rows 8-12) en une liste pour
      // un rendu unifié.
      final allRows = [
        for (var i = 0; i < topRoutines.length; i++)
          (
            row: 2 + i,
            lane: lanes[i],
            fill: fills[i],
            r: topRoutines[i],
            kind: 'spider'
          ),
        for (var j = 0; j < topTime.length; j++)
          (
            row: 8 + j,
            lane: timeLanes[j],
            fill: timeFills[j],
            r: topTime[j],
            kind: 'scorpion'
          ),
      ];
      final grid = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int y = 0; y < w.rows; y++)
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (int x = 0; x < w.cols; x++)
                _cell(t, w, x, y, inner, avatar,
                    isSpider:
                        spider != null && spider.x == x && spider.y == y),
            ]),
        ],
      );
      // Centre pixel d'une tuile en coords continues (l'entité est au milieu).
      Offset centerD(double x, double y) =>
          Offset(x * slot + slot / 2, y * slot + slot / 2);
      final aw = slot * 0.85, ah = slot * 0.34;
      final board = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
          width: w.cols * slot,
          height: w.rows * slot,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              grid,
              // ── CALENDRIER de domaine : 1 ligne = 1 routine, 7 colonnes = jours,
              //    tour collée au château (gauche), nuisibles = jours manqués. ──
              if (_inInterior) ...[
                // Labels des jours (L M M J V S D) — uniquement en haut (row 1).
                for (var d = 0; d < 7; d++)
                  () {
                    final c0 = centerD(10.0 + d, 1);
                    return Positioned(
                      left: c0.dx - slot / 2,
                      top: c0.dy - slot / 2,
                      width: slot,
                      height: slot,
                      child: Center(
                        child: Text(dayLabels[d],
                            style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w900,
                                fontSize: slot * 0.42)),
                      ),
                    );
                  }(),
                // (Le nom de la routine est dans le PANNEAU LATÉRAL à droite,
                //  aligné à sa ligne — pas sur la grille.)
                // TOUR à COLONNE 9 — une par ligne (remplace l'ancienne porte).
                for (final e in allRows)
                  () {
                    final c0 = centerD(9, e.row.toDouble());
                    return Positioned(
                      left: c0.dx - slot / 2,
                      top: c0.dy - slot / 2,
                      width: slot,
                      height: slot,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Vie (jaune, continue) = jours faits (n) → pleine si tiré.
                          _webLifeBar(e.r.charger / 7, slot),
                          SizedBox(height: slot * 0.04),
                          // Chargeur (vert) = jours non faits (7-n) → vide si tout tiré.
                          _webSegBar(7 - e.r.charger, _kCharge, slot),
                          SizedBox(height: slot * 0.06),
                          // Turret (DCA si hebdo/mensuelle) → pointe vers les nuisibles.
                          SvgPicture.asset(_turretIcon(e.r.id, e.kind),
                              width: slot * 0.5,
                              height: slot * 0.5,
                              colorFilter: ColorFilter.mode(
                                  _interiorColor, BlendMode.srcIn)),
                        ],
                      ),
                    );
                  }(),
                // TOKENS du tapis : 🕷️ araignée (manqué, PV=cible de la routine) ·
                // 🔥 flemme (fait) · 🌿 buisson (placeholder). Araignée cliquable →
                // carte de combat (faire le vrai travail).
                for (final e in allRows)
                  for (var d = 0; d < e.lane.length; d++)
                    () {
                      final tok = e.lane[d];
                      if (tok.type == 'empty') return const SizedBox.shrink();
                      final c0 = centerD(10.0 + d, e.row.toDouble());
                      final spider = tok.type == 'spider';
                      final emoji = tok.type == 'flame'
                          ? '🔥'
                          : (spider
                              ? (e.kind == 'scorpion' ? '🦂' : '🕷️')
                              : '🍃');
                      return Positioned(
                        left: c0.dx - slot / 2,
                        top: c0.dy - slot / 2,
                        width: slot,
                        height: slot,
                        child: GestureDetector(
                          onTap: spider
                              ? () => showBacklogCombat(
                                  context, logic, sync, e.kind, e.r.id)
                              : null,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(emoji,
                                  style: TextStyle(fontSize: slot * 0.5)),
                              if (spider)
                                Text('${tok.hp}', // PV restants ce jour
                                    style: TextStyle(
                                        color: _kEnemy,
                                        fontWeight: FontWeight.w900,
                                        fontSize: slot * 0.2,
                                        height: 1)),
                            ],
                          ),
                        ),
                      );
                    }(),
                // (Portes retirées — la tour occupe désormais la col 9.)
                // CHÂTEAU (cols 8→0, à gauche de la tour) : se remplit des jours
                // PASSÉS — 🕸️ toiles (manques) ou 🍃 feuilles (en avance), de la
                // porte vers l'intérieur.
                for (final e in allRows)
                  for (var j = 0;
                      j <
                          (e.fill.webs > 0 ? e.fill.webs : e.fill.leaves);
                      j++)
                    () {
                      final web = e.fill.webs > 0;
                      final c0 =
                          centerD((8 - j).toDouble(), e.row.toDouble());
                      return Positioned(
                        left: c0.dx - slot / 2,
                        top: c0.dy - slot / 2,
                        width: slot,
                        height: slot,
                        child: Center(
                          child: Text(web ? '🕸️' : '🍃',
                              style: TextStyle(fontSize: slot * 0.5)),
                        ),
                      );
                    }(),
              ],
              // ── Couche TD : tours, sbires, flèches, PV porte ────────────────
              // Halo de portée d'un arc ACTIF (avatar sur une de ses cases blanches).
              for (final bow in _bows)
                if (_bowManned(bow.pads))
                  () {
                    final c0 =
                        centerD(bow.at.x.toDouble(), bow.at.y.toDouble());
                    final r = _kBowRange * slot;
                    return Positioned(
                      left: c0.dx - r,
                      top: c0.dy - r,
                      width: r * 2,
                      height: r * 2,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _kGold.withOpacity(.06),
                            border: Border.all(
                                color: _kGold.withOpacity(.4), width: 1),
                          ),
                        ),
                      ),
                    );
                  }(),
              // Halo de portée : tour SURVOLÉE (souris) ou sélectionnée (tap).
              if ((_hoveredTurret ?? _selectedTurret) != null &&
                  _turrets.containsKey(_hoveredTurret ?? _selectedTurret))
                () {
                  final pp = (_hoveredTurret ?? _selectedTurret)!.split('_');
                  final c0 =
                      centerD(double.parse(pp[0]), double.parse(pp[1]));
                  final r = _kTurretRange * slot;
                  return Positioned(
                    left: c0.dx - r,
                    top: c0.dy - r,
                    width: r * 2,
                    height: r * 2,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFB07CF0).withOpacity(.07),
                          border: Border.all(
                              color: const Color(0xFFB07CF0).withOpacity(.35),
                              width: 1),
                        ),
                      ),
                    ),
                  );
                }(),
              // BÂTI — tourelles dérivées des STREAKS de routines (map principale
              // SEULEMENT ; à l'intérieur ce sont les _domTurrets draggables).
              if (!_inInterior)
                for (final e in _streakTurrets.entries)
                  () {
                  // TOUJOURS visible (ton bâti, pas un ennemi caché par le fog).
                  final pp = e.key.split('_');
                  final c0 =
                      centerD(double.parse(pp[0]), double.parse(pp[1]));
                  final col = e.value.color;
                  return Positioned(
                    left: c0.dx - slot * 0.75,
                    top: c0.dy - slot * 0.6,
                    width: slot * 1.5,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Icône SVG game-icons.net (mono) TINTÉE à la couleur du
                        // domaine — test du nouveau langage visuel.
                        SvgPicture.asset('assets/icons/turret.svg',
                            width: slot * 0.6,
                            height: slot * 0.6,
                            colorFilter:
                                ColorFilter.mode(col, BlendMode.srcIn)),
                        Text('🔥${e.value.streak}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: col,
                                fontWeight: FontWeight.w900,
                                fontSize: slot * 0.22,
                                height: 1,
                                shadows: const [
                                  Shadow(color: Colors.black, blurRadius: 2)
                                ])),
                        if (slot >= 26)
                          Text(e.value.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: col.withOpacity(.95),
                                  fontWeight: FontWeight.w700,
                                  fontSize: slot * 0.16,
                                  height: 1.1,
                                  shadows: const [
                                    Shadow(color: Colors.black, blurRadius: 2)
                                  ])),
                      ],
                    ),
                  );
                }(),
              // (Anciennes tours draggables désactivées — remplacées par le
              // calendrier ci-dessus, 1 tour fixe par ligne de routine.)
              if (_legacyDragTurrets)
                for (var ti = 0; ti < _domTurrets.length; ti++)
                  () {
                    final tr = _domTurrets[ti];
                    final c0 = centerD(tr.x, tr.y);
                    return Positioned(
                      // Centré SUR la case (pas au-dessus) → pas coupé en y=0.
                      left: c0.dx - slot / 2,
                      top: c0.dy - slot / 2,
                      width: slot,
                      child: GestureDetector(
                        onPanUpdate: (d) => setState(() {
                          tr.x += d.delta.dx / slot;
                          tr.y += d.delta.dy / slot;
                        }),
                        onPanEnd: (_) {
                          setState(() {
                            final nx = tr.x.round(), ny = tr.y.round();
                            if (w.inBounds(nx, ny) &&
                                w.walkable(nx, ny) &&
                                !w.isGate(nx, ny)) {
                              tr.x = nx.toDouble();
                              tr.y = ny.toDouble();
                            }
                          });
                          // Persiste le placement (clé complète domainId~routineId~clone).
                          logic.state.domTurretPos[tr.posKey] =
                              '${tr.x.round()}_${tr.y.round()}';
                          sync.setDomTurretPos(logic.state.domTurretPos);
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SvgPicture.asset('assets/icons/turret.svg',
                                width: slot * 0.6,
                                height: slot * 0.6,
                                colorFilter: ColorFilter.mode(
                                    tr.ammo > 0
                                        ? tr.color
                                        : Colors.white24, // chargeur vide = éteinte
                                    BlendMode.srcIn)),
                            Text('🔋${tr.ammo}/${tr.level}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: tr.color,
                                    fontWeight: FontWeight.w900,
                                    fontSize: slot * 0.2,
                                    height: 1,
                                    shadows: const [
                                      Shadow(color: Colors.black, blurRadius: 2)
                                    ])),
                          ],
                        ),
                      ),
                    );
                  }(),
              // SIMULATION : les VRAIS nuisibles du domaine qui marchent vers le
              // château. CLIQUABLES → leur carte de combat (faire le vrai travail).
              if (_simDefense)
                for (final a in _defAttackers)
                  () {
                    final c0 = centerD(a.x, a.y);
                    return Positioned(
                      left: c0.dx - slot * 0.5,
                      top: c0.dy - slot * 0.7,
                      width: slot,
                      child: GestureDetector(
                        onTap: () {
                          if (a.id.isEmpty) return;
                          showBacklogCombat(context, logic, sync, a.type, a.id);
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(entityEmoji(a.type),
                                style: TextStyle(fontSize: slot * 0.6)),
                            Text('${a.hp}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: _kEnemy,
                                    fontWeight: FontWeight.w900,
                                    fontSize: slot * 0.2,
                                    height: 1,
                                    shadows: const [
                                      Shadow(color: Colors.black, blurRadius: 2)
                                    ])),
                          ],
                        ),
                      ),
                    );
                  }(),
              // Tours posées (fixes) — survol souris = montre la portée.
              for (final tile in _turrets.keys)
                () {
                  final pp = tile.split('_');
                  final c0 = centerD(
                      double.parse(pp[0]), double.parse(pp[1]));
                  final lit = (_hoveredTurret ?? _selectedTurret) == tile;
                  return Positioned(
                    left: c0.dx - slot / 2,
                    top: c0.dy - slot / 2,
                    width: slot,
                    height: slot,
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _hoveredTurret = tile),
                      onExit: (_) => setState(() {
                        if (_hoveredTurret == tile) _hoveredTurret = null;
                      }),
                      child: Center(
                        child: Container(
                          decoration: lit
                              ? BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFB07CF0).withOpacity(.25),
                                  border: Border.all(
                                      color: const Color(0xFFB07CF0), width: 1.5))
                              : null,
                          padding: const EdgeInsets.all(1),
                          child: Icon(Icons.cell_tower,
                              size: slot * 0.62,
                              color: const Color(0xFFC9B6F2)),
                        ),
                      ),
                    ),
                  );
                }(),
              // Sbires lâchés (one-shot, vers la porte). À l'intérieur = MES sbires
              // d'assaut 🦂 ; sur la map principale = les sbires ennemis 🕷️.
              for (final s in _sbires)
                () {
                  final c0 = centerD(s.x, s.y);
                  return Positioned(
                    left: c0.dx - slot * 0.25,
                    top: c0.dy - slot * 0.25,
                    child: Text(_inInterior ? '🦂' : '🕷️',
                        style: TextStyle(fontSize: slot * 0.42)),
                  );
                }(),
              // MES sbires d'attaque (cerclés de bleu) marchant vers l'envahisseur.
              for (final a in _myAtk)
                () {
                  final c0 = centerD(a.x, a.y);
                  return Positioned(
                    left: c0.dx - slot * 0.3,
                    top: c0.dy - slot * 0.3,
                    child: Container(
                      padding: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kBlue.withOpacity(.22),
                        border: Border.all(color: _kBlue.withOpacity(.8)),
                      ),
                      child: Text(entityEmoji(a.type),
                          style: TextStyle(fontSize: slot * 0.4)),
                    ),
                  );
                }(),
              // L'« ENVAHISSEUR » (Phase 1) — masqué une fois la capture terminée.
              // À l'intérieur = MON scorpion 🦂 (attaquant) ; sinon = l'ennemi 🕷️.
              if (_phase1 && !_invaderGone)
                () {
                  final c0 = centerD(_invX, _invY);
                  return Positioned(
                    left: c0.dx - slot * 0.7,
                    top: c0.dy - slot * 0.85,
                    width: slot * 1.4,
                    child: Column(
                      children: [
                        Text(_inInterior ? '🦂' : '🕷️',
                            style: TextStyle(fontSize: slot * 0.95)),
                        Text(_inInterior ? 'deck $_garrison' : 'garnison $_garrison',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: _inInterior ? _interiorColor : _kEnemy,
                                fontWeight: FontWeight.w900,
                                fontSize: slot * 0.26,
                                shadows: const [
                                  Shadow(color: Colors.black, blurRadius: 2)
                                ])),
                      ],
                    ),
                  );
                }(),
              // Le DÉFENSEUR au poste _redSpawn : sur la map principale = MON 🦂
              // (émet mon deck) ; à l'intérieur pendant l'assaut = l'ARAIGNÉE 🕷️
              // qui défend sa grotte (émet son deck _myMass).
              if (!_inInterior || _phase1)
                () {
                final c0 = centerD(_redSpawn.dx, _redSpawn.dy);
                return Positioned(
                  left: c0.dx - slot * 0.6,
                  top: c0.dy - slot * 1.05,
                  width: slot * 1.2,
                  child: Column(
                    children: [
                      // Deck (juste le nombre) AU-DESSUS : VERT au repos (deck vert
                      // dispo), ROUGE quand il défend (deck en cours de dépense).
                      Text(_inInterior
                          ? '$_myMass'
                          : '${_phase1 ? _myMass : logic.lifetimeBattleMasse}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: (_phase1 || _inInterior) ? _kEnemy : _kFarm,
                              fontWeight: FontWeight.w900,
                              fontSize: slot * 0.28,
                              shadows: const [
                                Shadow(color: Colors.black, blurRadius: 2)
                              ])),
                      Text(_inInterior ? '🕷️' : '🦂',
                          style: TextStyle(fontSize: slot * 0.85)),
                    ],
                  ),
                );
              }(),
              // Mon scorpion 🦂 ACCOMPAGNE l'avatar pendant la phase farm (posté à
              // côté de lui) → au lancement de l'assaut il combat depuis cette case.
              if (_inInterior && !_phase1)
                () {
                  final c0 = centerD(_pos.x.toDouble(), _pos.y.toDouble());
                  return Positioned(
                    left: c0.dx - slot * 0.85,
                    top: c0.dy + slot * 0.05,
                    child: Text('🦂', style: TextStyle(fontSize: slot * 0.6)),
                  );
                }(),
              // Araignée AU REPOS dans sa grotte (phase farm, avant l'assaut) → on
              // voit l'ennemi à déloger dès que le brouillard se lève.
              if (_inInterior && !_phase1)
                () {
                  final c = _w?.caves['coeur'];
                  if (c == null || !_revealed.contains('${c.x}_${c.y}')) {
                    return const SizedBox.shrink();
                  }
                  final c0 = centerD(c.x.toDouble(), c.y.toDouble());
                  return Positioned(
                    left: c0.dx - slot * 0.35,
                    top: c0.dy - slot * 0.55,
                    child: Text('🕷️', style: TextStyle(fontSize: slot * 0.7)),
                  );
                }(),
              // Barre de vie de la grotte CIBLÉE (Phase 2 : porte cassée).
              if (_phase1 && _gateHp <= 0 && _grotteHpMax > 0)
                () {
                  final c0 = centerD(_grotteTarget.dx, _grotteTarget.dy);
                  final frac = (_grotteHp / _grotteHpMax).clamp(0.0, 1.0);
                  final bw = slot * 1.2;
                  return Positioned(
                    left: c0.dx - bw / 2,
                    top: c0.dy - slot * 0.85,
                    width: bw,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // PV au-dessus de la barre (lisibilité).
                        Text('🕳️ $_grotteHp/$_grotteHpMax',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: slot * 0.22,
                                shadows: const [
                                  Shadow(color: Colors.black, blurRadius: 2)
                                ])),
                        const SizedBox(height: 1),
                        Container(
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(.55),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                                color: Colors.white.withOpacity(.4), width: .5),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: frac,
                            child: Container(
                              decoration: BoxDecoration(
                                color: frac > .35 ? _kBlue : _kEnemy,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }(),
              // Flèches en vol (marron, dérivées du temps).
              for (final s in _shots)
                () {
                  final p = ((_gameMs - s.startMs) / s.durMs).clamp(0.0, 1.0);
                  final from = centerD(s.from.dx, s.from.dy);
                  final to = centerD(s.to.dx, s.to.dy);
                  final pos = Offset.lerp(from, to, p)!;
                  final ang = (to - from).direction;
                  return Positioned(
                    left: pos.dx - aw / 2,
                    top: pos.dy - ah / 2,
                    child: Transform.rotate(
                      angle: ang,
                      child: CustomPaint(
                          size: Size(aw, ah),
                          painter: const _ArrowPainter()),
                    ),
                  );
                }(),
              // Barre de PV de la porte (au-dessus du chokepoint).
              if (_tdMode)
                () {
                  final c0 = centerD(9, 4.1);
                  final bw = slot * 2.6;
                  return Positioned(
                    left: c0.dx - bw / 2,
                    top: c0.dy - 4,
                    child: Column(children: [
                      Text('🚪 ${(_gateHp).round()}',
                          style: TextStyle(
                              color: const Color(0xFFC8924A),
                              fontSize: slot * 0.28,
                              fontWeight: FontWeight.w800,
                              shadows: const [
                                Shadow(color: Colors.black, blurRadius: 2)
                              ])),
                      Container(
                        width: bw,
                        height: 5,
                        decoration: BoxDecoration(
                            color: Colors.black.withOpacity(.55),
                            borderRadius: BorderRadius.circular(3)),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (_gateHp / _gateHpMax).clamp(0.0, 1.0),
                          child: Container(
                              decoration: BoxDecoration(
                                  color: const Color(0xFF8B5A2B),
                                  borderRadius: BorderRadius.circular(3))),
                        ),
                      ),
                    ]),
                  );
                }(),
            ],
          ),
            ),
            // Panneau latéral : noms des routines, ALIGNÉS à leur ligne (row 3+i).
            if (_inInterior)
              SizedBox(
                width: nameW,
                height: w.rows * slot,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final e in allRows)
                      Positioned(
                        top: e.row * slot,
                        left: 6,
                        width: nameW - 12,
                        height: slot,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(e.r.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: _interiorColor.withOpacity(.95),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      // Mobile : plateau pannable/zoomable (calendrier plus grand que l'écran).
      return widget.mobile
          ? InteractiveViewer(
              constrained: false,
              boundaryMargin: const EdgeInsets.all(140),
              minScale: 0.4,
              maxScale: 2.5,
              child: board)
          : Center(child: board);
    });
  }

  Widget _cell(
      Territory t, UnifiedWorld w, int x, int y, double inner, String avatar,
      {bool isSpider = false}) {
    final id = '${x}_$y';
    final revealed = _revealed.contains(id) || _showCoords;
    final isAvatar = _pos.x == x && _pos.y == y;

    // Hors vision : brouillard noir, non tappable.
    if (!revealed) {
      return Container(
        width: inner,
        height: inner,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.55),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.white.withOpacity(.04)),
        ),
      );
    }

    final kind = w.at(x, y);
    Color bg = Colors.white.withOpacity(.03);
    Color border = Colors.white.withOpacity(.05);
    Widget? child;

    if (kind == UwTile.wall) {
      // Mur = terrain rocheux SOMBRE (infranchissable) ; certains portent 🪨.
      bg = const Color(0xFF1A120C).withOpacity(.82);
      border = Colors.black.withOpacity(.5);
      if (w.hasRock(x, y) && !_inInterior) {
        child = Text('🪨', style: TextStyle(fontSize: inner * 0.5));
      }
    } else if (kind == UwTile.floor) {
      // Sol praticable = CLAIR (contraste net avec les murs). À l'intérieur d'une
      // grotte : gazon teinté à la couleur du domaine ; sinon farm vert.
      final farmSide = x < w.castle.x - 1;
      final base =
          _inInterior ? _interiorColor : (farmSide ? _kFarm : Colors.white);
      bg = base.withOpacity(.18);
      border = base.withOpacity(.40);
      // Décor buisson 🌿 SEULEMENT sur la map principale — retiré à l'intérieur
      // (calendrier) pour ne pas faire doublon avec les tokens 🌿.
      if (w.hasBush(x, y) && !_inInterior) {
        child = Text('🌿', style: TextStyle(fontSize: inner * 0.5));
      }
    } else if (kind == UwTile.castle) {
      bg = _kGold.withOpacity(.22);
      border = _kGold.withOpacity(.7);
      child = Text('🏰', style: TextStyle(fontSize: inner * 0.5));
    }

    // Arcs fixes 🏹, leurs cases blanches (gâchette) et la tuile-pont d'accès.
    final bp = Point(x, y);
    if (_bowTiles.contains(bp)) {
      final active = _bows.any((b) => b.at == bp && _bowManned(b.pads));
      bg = (active ? _kGold : Colors.white).withOpacity(active ? .26 : .12);
      border = (active ? _kGold : Colors.white).withOpacity(active ? .9 : .5);
      child = Text('🏹', style: TextStyle(fontSize: inner * 0.5));
    } else if (_bowPads.contains(bp)) {
      bg = Colors.white.withOpacity(.7); // case blanche = poste de tir
      border = Colors.white;
      child = null;
    } else if (_bowBridges.contains(bp)) {
      bg = Colors.white.withOpacity(.32); // pont (blanc atténué) vers le sol farm
      border = Colors.white.withOpacity(.6);
      child = null;
    } else if (_greyTiles.contains(bp)) {
      bg = Colors.grey.withOpacity(.45); // case d'accès grise aux tourelles
      border = Colors.grey.withOpacity(.75);
      child = null;
    }

    // Chokepoint x9 : à l'INTÉRIEUR = TOILES 🕸️ (percées en dépensant le deck) ;
    // sur la map principale = porte en bois (cassée par l'envahisseur, PV ≤ 0).
    if (w.isGate(x, y)) {
      if (_inInterior) {
        bg = _interiorColor.withOpacity(_webBroken ? .14 : .55);
        border = _interiorColor.withOpacity(_webBroken ? .35 : .9);
        child = Text(_webBroken ? '💥' : '🕸️',
            style: TextStyle(fontSize: inner * 0.5));
      } else {
        final broken = _gateHp <= 0;
        bg = const Color(0xFF6B4423).withOpacity(broken ? .22 : .7);
        border = const Color(0xFF3E2A18).withOpacity(broken ? .4 : 1);
        child = Text(broken ? '💥' : '🚪',
            style: TextStyle(fontSize: inner * 0.5));
      }
    }
    // (Le spawner n'est plus dessiné case par case : l'envahisseur est rendu en
    // overlay à sa position pendant la Phase 1.)

    // Grotte (overlay depuis le doc territoire).
    final caveId = w.caveIdAt(x, y);
    if (caveId != null) {
      final cave = t.caveById(caveId);
      // Prise ce run (Phase 2, visuel) → rouge, même si elle est encore à moi en base.
      final taken = _grotteTaken && caveId == _grotteCaveId;
      final mine = !taken && cave != null && cave.ownerUid == t.uid;
      // Grotte à moi = couleur de son domaine (dashboard d'équilibre) ;
      // grotte prise = rouge (réservé à l'ennemi).
      final col = mine ? _caveColor(cave) : _kEnemy;
      bg = col.withOpacity(.22);
      border = col.withOpacity(.7);
      final name = cave != null ? _domainName(cave.domainId) : '';
      child = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Grotte envahie → araignée 🕷️ + puissance du deck ennemi (au lieu du
          // trou 🕳️ + niveau bleu).
          Text(taken ? '🕷️' : '🕳️', style: TextStyle(fontSize: inner * 0.32)),
          Text('${taken ? _enemyDeckPower : (cave?.blueLevel ?? 0)}',
              style: TextStyle(
                  color: col,
                  fontSize: inner * 0.24,
                  fontWeight: FontWeight.w900,
                  height: 1)),
          if (inner >= 30 && name.isNotEmpty)
            SizedBox(
              width: inner,
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: col.withOpacity(.9),
                      fontSize: inner * 0.16,
                      fontWeight: FontWeight.w700,
                      height: 1.1)),
            ),
        ],
      );
    }

    // L'araignée d'invasion se superpose à la case (sauf si l'avatar y est =
    // interception) ; un ennemi backlog (zone farm) s'affiche à combattre.
    final spiderHere = isSpider && !isAvatar;
    final farmPest = _inInterior ? null : _farmPests['${x}_$y'];
    final farmHere = farmPest != null && !isAvatar && !spiderHere;
    final tile = Container(
      width: inner,
      height: inner,
      margin: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: isAvatar
            ? Colors.white.withOpacity(.16)
            : spiderHere
                ? _kEnemy.withOpacity(.25)
                : farmHere
                    ? _kFarm.withOpacity(.18)
                    : bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
            color: isAvatar
                ? Colors.white
                : spiderHere
                    ? _kEnemy
                    : farmHere
                        ? _kFarm.withOpacity(.7)
                        : border,
            width: isAvatar || spiderHere || farmHere ? 2 : 1),
      ),
      alignment: Alignment.center,
      child: isAvatar
          ? Text(avatar, style: TextStyle(fontSize: inner * 0.55))
          : spiderHere
              ? Text('🕷️', style: TextStyle(fontSize: inner * 0.55))
              : farmHere
                  ? Text(entityEmoji(farmPest.type),
                      style: TextStyle(fontSize: inner * 0.5))
                  : child,
    );

    final shown = _showCoords
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              tile,
              Positioned(
                left: 3,
                top: 2,
                child: Text('$x,$y',
                    style: TextStyle(
                        fontSize: (inner * 0.26).clamp(7.0, 11.0),
                        height: 1,
                        color: Colors.white.withOpacity(.75),
                        fontWeight: FontWeight.w700,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 2)
                        ])),
              ),
            ],
          )
        : tile;
    return GestureDetector(
        onTap: () => _onTap(x, y),
        onLongPress: () => _onLongPress(x, y),
        child: shown);
  }
}

/// Flèche dessinée pointant vers +x (la droite) : hampe + pointe (réaliste, sans
/// empennage). Marron. Orientée vers la cible par le `Transform.rotate` parent.
/// Socle réutilisable pour « tourelle tire sur la grotte/le sbire ».
const _kArrowWood = Color(0xFF6B4423); // marron hampe
const _kArrowHead = Color(0xFF3E2A18); // pointe (plus sombre)

/// Sbire ENNEMI (éphémère) : position continue en coords de tuiles, PV, assaut.
class _Sbire {
  final int id;
  double x, y, hp;
  final double maxHp;
  bool atGate = false;
  bool killed = false; // a déjà tué un de mes sbires → file droit à la porte
  bool drained = false; // a déjà entamé les PV de la grotte (une seule fois)
  Offset? wp; // point de déviation aléatoire (avant d'aller à la porte)
  _Sbire(this.id, this.x, this.y, this.hp) : maxHp = hp;
  // Déphasage propre (chemin ondulant non synchronisé entre sbires).
  double get phase => id * 1.7;
}

/// MON sbire d'attaque (Phase 1) : passe par un point de déviation puis fonce
/// SUR L'ENVAHISSEUR (ne chasse jamais les sbires ennemis).
class _Atk {
  final int id;
  final String type; // spider | scorpion | snake
  double x, y;
  Offset? wp; // point de déviation aléatoire (avant d'aller à l'envahisseur)
  _Atk(this.id, this.type, this.x, this.y);
  double get phase => id * 1.7;
}

/// Nuisible ATTAQUANT d'un domaine (défense) = un vrai item de backlog (routine
/// lâchée / temps ou tâche en retard) qui marche vers le château. Cliquable → sa
/// carte de combat (faire le vrai travail) → il disparaît de l'attaque.
class _DefAttacker {
  final String type, id; // identité backlog
  double x, y;
  int hp; // = masse (5/10/15) ; tombé à 0 par les tours
  int wpIdx = 0;
  _DefAttacker(this.type, this.id, this.x, this.y, this.hp);
}

/// Tourelle de DÉFENSE d'un domaine (intérieur de grotte). Posée par l'user en
/// drag & drop selon sa stratégie ; niveau = streak de la routine = CHARGEUR
/// initial (`ammo`) qui diminue à chaque tir. Puissance = constance réelle ;
/// agency = le placement. Niveau du domaine = Σ des niveaux de ses tourelles.
class _DomTurret {
  final String posKey; // clé de persistance "domainId~routineId~cloneIdx"
  final int level; // = chargeur (complétions de la routine la semaine passée)
  final Color color; // couleur du domaine
  final String name; // nom de la routine
  double x, y; // position en cases (fractionnaire pendant le drag)
  int ammo; // tirs restants
  int lastFireMs = -99999;
  _DomTurret(this.posKey, this.level, this.color, this.name, this.x, this.y)
      : ammo = level;
}

/// Flèche en vol : from/to en coords de tuiles, animée par le temps (startMs+durMs).
class _Shot {
  final Offset from, to;
  final int startMs, durMs;
  const _Shot(this.from, this.to, this.startMs, this.durMs);
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, cy = h / 2;
    final sw = (h * 0.22).clamp(1.2, 2.6);
    final shaft = Paint()
      ..color = _kArrowWood
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final tipX = w;
    // Hampe (du talon jusqu'au début de la pointe).
    canvas.drawLine(Offset(w * 0.05, cy), Offset(w * 0.78, cy), shaft);
    // Pointe (triangle plein, sombre).
    final headLen = w * 0.26, headHalf = h * 0.42;
    final head = Path()
      ..moveTo(tipX, cy)
      ..lineTo(tipX - headLen, cy - headHalf)
      ..lineTo(tipX - headLen, cy + headHalf)
      ..close();
    canvas.drawPath(head, Paint()..color = _kArrowHead);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => false;
}
