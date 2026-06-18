import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart'
    show KeyEvent, KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/territory.dart';
import 'package:productivitwo_v1/unified_world.dart';
import 'package:productivitwo_v1/world_layout.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/widgets/backlog_combat.dart';
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart';
import 'package:productivitwo_v1/widgets/activity_detail_sheet.dart';
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
// Map en PLEIN ÉCRAN : masque le panneau d'actions/dev à gauche (sera supprimé) →
// toutes les interactions se font directement dans le jeu (taps sur la carte).
const bool _kMapFullscreen = true;
// MONDE V2 (data‑driven, grandit avec l'utilisateur) — derrière un flag le temps
// de la construction. true → grande map V2 (world_layout) ; false → ancien overworld.
const bool _kWorldV2 = true;
const double _kV2Slot = 48; // taille de case FIXE de la grande map V2
// ≥ N araignées (jours manqués) dans la semaine = INVASION ; il faut redescendre
// sous N (valider ses routines) pour pouvoir déloger l'araignée.
const int _kInvasionN = 10;

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

/// Carte cinématique web rendue comme onglet embarqué du hub gamification —
/// pas de Dialog. `embedded:true` neutralise les fermetures globales. Supprime
/// l'overlay assistant tant que l'onglet est monté (comme showUnifiedWorldSheet).
class UnifiedWorldScreen extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const UnifiedWorldScreen({required this.logic, required this.sync, super.key});
  @override
  State<UnifiedWorldScreen> createState() => _UnifiedWorldScreenState();
}

class _UnifiedWorldScreenState extends State<UnifiedWorldScreen> {
  late final bool _prevSuppressed;
  @override
  void initState() {
    super.initState();
    _prevSuppressed = assistantOverlaySuppressed.value;
    assistantOverlaySuppressed.value = true;
  }

  @override
  void dispose() {
    assistantOverlaySuppressed.value = _prevSuppressed;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _kBg,
        body: SafeArea(
          child: _UnifiedWorldView(
              logic: widget.logic,
              sync: widget.sync,
              mobile: true,
              embedded: true),
        ),
      );
}

class _UnifiedWorldView extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  // Mobile : pas de map principale, on affiche direct le calendrier par domaine.
  final bool mobile;
  // Embarqué (onglet du hub) : pas de Dialog → neutralise les fermetures globales
  // (croix X, pill « ✕ Fermer », pop après lancement de minuteur).
  final bool embedded;
  const _UnifiedWorldView(
      {required this.logic,
      required this.sync,
      this.mobile = false,
      this.embedded = false});

  @override
  State<_UnifiedWorldView> createState() => _UnifiedWorldViewState();
}

class _UnifiedWorldViewState extends State<_UnifiedWorldView>
    with TickerProviderStateMixin {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => widget.sync;

  Territory? _t;
  UnifiedWorld? _w;
  // ── MONDE V2 (data‑driven) ─────────────────────────────────────────────────
  WorldLayout? _wv2;
  Point<int> _posV2 = const Point(0, 0);
  final Map<String, Color> _v2Tint = {}; // "x_y" → couleur domaine (château)
  final Map<String, Color> _v2WallTint = {}; // "x_y" → accent domaine (murs déco)
  // "x_y" → serpent (tâche en retard) à farmer dans le jardin du domaine.
  final Map<String, ({String type, String id, Color color})> _v2Pests = {};
  // Calendrier inline projeté (réutilise routineWeekTokens/activityTimeTokens).
  final Map<String, String> _v2DayTok = {}; // tileId → emoji du jour
  final Map<String, int> _v2DayCount = {}; // tileId → PV nuisible (compteur)
  // tileId tourelle → chargeur (0..7) + routine/activité (couleur 🕷️/🦂).
  final Map<String, ({int charger, bool isRoutine})> _v2Turret = {};
  final Map<String, String> _v2TurretRoutineId = {}; // tileId tourelle → routineId (lanes routine)
  final Set<String> _v2LaunchPads = {}; // tileIds de la case de tir (gauche de chaque tourelle)
  final Set<String> _v2Sep = {}; // tileIds de la ligne séparatrice routines/activités
  final Map<String, int> _v2DayTurretX = {}; // tileId jour → X de la tourelle de sa lane
  final Map<String, String> _v2DayLabel = {}; // tileId entête → lettre du jour
  // INVASION : case araignée‑boss (≥ 10 araignées accumulées) → clic = combat.
  final Map<String, String> _v2Araignee = {}; // tileId → domainId en invasion
  final Map<String, String> _v2Toiles = {}; // tileId (jardin) → domainId (marqueur)
  final Set<String> _v2Invaded = {}; // domaines envahis (collant : reste tant que pas délogé)
  final Set<String> _v2Dislodged = {}; // domaines délogés (réduits < N) → ne reviennent pas
  final Map<String, String> _v2LaneName = {}; // tileId → nom routine/activité
  // Cinématique V2 : volée de boulets (tourelle → jour) + flashs d'impact.
  final List<_CineFb> _v2Fbs = [];
  final List<({Offset at, int untilMs})> _v2Flashes = [];
  // ARAIGNÉES D'ÉCART HEBDO : petites entités MOBILES (position continue) qui errent
  // CONFINÉES au village+jardin de LEUR domaine (jamais les murs/passages).
  // Nombre cible par domaine = Σ routines max(0, valeur(j‑7) − valeur(aujourd'hui)).
  final List<_GardenSpider> _gardenSpiders = [];
  // Shurikens STOCKÉS PAR DOMAINE (gagnés en réduisant l'écart depuis le dernier
  // passage) : l'avatar en tire un sur l'araignée la plus proche À PORTÉE
  // (_kNinjaRange) DONT le domaine a du stock. 1 shuriken touché = 1 araignée tuée.
  // → « nettoyer » un domaine ne dépend que de SES propres complétions.
  final Map<String, int> _gardenShurikensByDomain = {};
  final List<_GardenShk> _gardenShk = []; // shurikens d'araignée en vol
  int _lastGardenShkMs = 0; // cadence de tir (anti‑rafale)
  static const String _kSpiderGapKey = 'v2_spider_gap';
  String _spiderGapYmd = ''; // jour de référence de l'écart persisté
  final Map<String, int> _spiderGapSeenByDomain = {}; // écart « réglé » par domaine
  bool _spiderGapLoaded = false;
  String? _v2ActiveDomain; // domaine où se trouve l'avatar (révélé à l'entrée)
  bool _v2Walking = false; // marche en cours (évite les clics concurrents)
  bool _v2Spawned = false; // 1ᵉʳ spawn posé (bas‑gauche)
  // Tick d'animation ISOLÉ : la cinématique repeint SEULEMENT son overlay
  // (via AnimatedBuilder), pas toute la grille de cases → pas de surcharge.
  final ValueNotifier<int> _v2CineTick = ValueNotifier(0);
  final ScrollController _v2HCtrl = ScrollController();
  final ScrollController _v2VCtrl = ScrollController();
  // PERF — cache de la grille V2 : la fenêtre de cases visibles ne change qu'au
  // franchissement d'une case ; sans ça l'AnimatedBuilder de scroll reconstruirait
  // des centaines de widgets à chaque sous‑pixel de drag/molette. Invalidé à chaque
  // build() (un setState a pu changer l'état d'une case).
  ({int x0, int y0, int x1, int y1})? _cellWindow;
  List<Widget>? _cachedCells;
  // PERF — calque statique de la mini‑carte (cases du monde) enregistré en Picture :
  // ne se redessine qu'au (re)build du monde, pas à chaque frame de scroll (seuls
  // l'avatar + le cadre viewport sont repeints par‑dessus). Versionné par _rebuildWv2.
  int _wv2Version = 0;
  ui.Picture? _miniBasePic; // calque cases mini‑carte (recordé une fois par monde)
  int _miniBaseKey = -1; // = _wv2Version du calque enregistré
  bool _loading = true;
  bool _busy = false;
  bool _paused = false; // gelé pendant un combat (pas d'avance/résolution)
  StreamSubscription<Territory?>? _sub;
  StreamSubscription<List<Project>>? _projSub;
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

  // Un arc tire si l'AVATAR se tient sur une de ses cases.
  bool _bowManned(Set<Point<int>> pads) => pads.contains(_pos);
  // Combat de nuisible affiché en ENCART à droite (carte visible derrière).
  ({String type, String id, String tileId})? _combat;
  // Panneau JARDIN in‑place : le jardin (cases vertes) d'un domaine est remplacé par
  // une mini‑app. `mode` ∈ {combat, routineDash}. null = jardin normal. Un tap sur
  // une case de la map le referme.
  ({String domainId, String mode})? _gardenPanel;
  Point<int>? _cannonSpinAt; // case rampe en cours de spin (null = repos)
  int _cannonSpinStartMs = 0;
  final Map<String, double> _cannonRaise = {}; // tileId tourelle → lever 0..1 (animé)
  final List<_Sbire> _sbires = []; // sbires lâchés (marchent vers la porte)
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
  Offset _grotteTarget = const Offset(16, 7); // grotte visée une fois la porte cassée
  // Phase 2 : la grotte ciblée a des PV (= niveau bleu) ; les sbires les drainent.
  String? _grotteCaveId; // id de la grotte assaillie
  int _grotteHp = 0, _grotteHpMax = 0;
  bool _grotteTaken = false; // capture finie → grotte prise (rouge, visuel ce run)
  int? _captureStartMs; // ms où l'araignée a touché la grotte (anim de capture 5 s)
  int _grotteHpAtCapture = 0; // PV restants quand l'araignée commence à finir
  bool _invaderGone = false; // araignée disparue (fin de l'anim) → la horde rentre
  static const int _kCaptureMs = 5000; // durée de l'anim de capture
  int _arrows = 0; // pool de flèches du run (chaque tir tourelle/arc en coûte 1 en P2)
  // ── Intérieur de grotte (reconquête) : on entre dans un CLONE de la map, gazon
  //    teinté au domaine, avatar dans le gazon. On échange le monde actif
  //    (_w/_pos/_revealed) et on restaure en sortant.
  bool _inInterior = false;
  bool _interiorPeaceful = true; // grotte NON occupée → pas de cadre d'assaut
  // ── Cinématique de reprise (Mise à jour 3) — phase PRÉPARATION des tours :
  //    les flammes chargent chaque tourelle SÉQUENTIELLEMENT (tour 0, puis 1…).
  bool _cineActive = false; // une cinématique de prépa est en cours
  int _cinePrepIndex = 0; // tour en cours de charge (index dans allRows)
  double _cinePrepCharge = 0; // 0..1 progression de la tour courante
  int _cineRowCount = 0; // nb de tours à charger (figé au lancement)
  static const double _kCinePrepPerTurret = 1.8; // secondes / tour (ralenti)
  // Phase NETTOYAGE : CHAQUE tour tire SON nombre de flammes (munitions), sur la
  // cible la PLUS PROCHE (toiles du château prioritaires sur le jardin). Liste
  // de tirs pré-calculée : chacun = tour d'origine + cible (clé + position).
  bool _cineClearing = false;
  List<({int turretRow, String key, double tx, double ty})> _cineShots = const [];
  int _cineClearIndex = 0; // tir en cours
  double _cineClearT = 0; // 0..1 vol du projectile vers la cible courante
  static const double _kCineClearPerTarget = 0.6; // secondes / tir (ralenti)
  // Visée du canon : on incline la TÊTE (aa-head) autour de la monture. Pivot en
  // coords du widget (avant le flipX), angle naturel du barillet (~45°). Réglables.
  static const Alignment _kBarrelPivot = Alignment(-0.32, 0.25);
  static const double _kBarrelNatural = 0.78; // rad (~45°) = relevé d'origine
  // Phase ATTAQUE (étapes 6-8) : le ninja se déplace en continu sur la carte et
  // a une jauge de vie de 10 PV (les shurikens sur les « biens » : à brancher).
  bool _cineAttack = false;
  double _ninjaX = 0, _ninjaY = 0; // position lisse du ninja
  double _ninjaTX = 0, _ninjaTY = 0; // cible de déplacement courante
  int _ninjaHp = 10;
  double _bossAttackT = 0; // s écoulées → l'araignée frappe le ninja chaque minute
  // ARC : quand activé, le ninja s'arrête 5 s et tire 3 flèches/s (gratuit).
  bool _ninjaBow = false;
  double _bowDur = 0;
  double _bowArrowT = 0;
  static const double _kBowDuration = 5.0; // s d'immobilité / tir à l'arc
  static const double _kBowEvery = 1 / 3; // 3 flèches / s
  static const double _kArrowSpeed = 4.0; // flèches rapides
  final Random _cineRng = Random();
  static const double _kNinjaSpeed = 0.75; // cases / s
  List<int> _cineRowFlames = const []; // nb de flammes par ligne (ordre allRows)
  // Sbires de l'attaque : chaque toile SURVIVANTE lâche un sbire (spawn 1/s,
  // cyclique), qui erre aléatoirement ; le ninja leur tire dessus (-1 PV si touché).
  final List<_Sbire> _cineSbires = [];
  int _cineSbireSeq = 0;
  int _ninjaShurikens = 0; // deck de shurikens = budget du jour (munitions)
  int _battleShkStart = 0; // shurikens au DÉBUT du combat (pour calculer le dépensé)
  // Toiles SURVIVANTES (avec clé + position) : sources de spawn ET cibles que
  // les tours continuent de détruire en SUPPORT. Quand toutes sont détruites →
  // victoire.
  List<({String key, double col, double row})> _cineToileSpawns = const [];
  final Set<String> _cineKilledToiles = {}; // détruites pendant l'attaque
  // Toiles-château détruites, PERSISTÉES la journée → 💥 affichée même hors combat
  // (incite à avoir un max de flammes). Non vidé en ré-entrant (clés = routine+sem).
  final Set<String> _dayKilledToiles = {};
  int _cineSpawnIdx = 0; // toile suivante à faire spawn (cyclique)
  double _cineSpawnT = 0;
  final List<_CineFb> _supportFbs = []; // boules de feu de support en vol
  // Tours en mode SUPPORT (attaque) : seules celles ayant des flammes tirent,
  // 1 boule / 10 s (coûte 1 flamme), rechargées par leurs flammes-source / 30 s.
  final List<_CineTurret> _cineTurrets = [];
  final Map<int, _CineTurret> _cineTurretByRow = {};
  final Set<String> _inFlightKeys = {}; // toiles déjà visées par un boulet en vol
  static const double _kSbireSpawnEvery = 1.0; // 1 sbire / s (cyclique)
  static const double _kSbireSpeed = 0.4; // cases / s (lent → esquivable)
  static const double _kTurretFireEvery = 10.0; // s entre 2 tirs d'une tour
  static const double _kTurretAimDur = 2.0; // s d'animation de visée (canon)
  static const double _kFlameRegrow = 45.0; // s (base) pour recharger les flammes
  static const double _kBarrelAimDip = 0.7; // amplitude du mouvement de visée
  static const double _kSupportFbDur = 10.0; // s de vol cannon→cible (accéléré un peu)
  static const double _kLiveFbDur = 2.4; // s de vol pour le tir d'arrivée (S3)
  // L'icône fireball « pointe » sa tête dense vers le BAS (+y) ; -pi/2 aligne
  // cette tête sur la direction du vol, +pi/6 = +30° horaire (calage demandé).
  static const double _kFbIconOffset = -pi / 2 + pi / 6;
  final List<_CineShk> _shurikens = []; // shurikens en vol
  double _shkThrowT = 0; // cadence de lancer
  double _attackElapsed = 0; // temps écoulé → accélère les shurikens
  static const double _kShkEvery = 0.5; // 2 shurikens / s
  static const double _kShkSpeedBase = 1.1; // vitesse initiale (esquivable)
  static const double _kShkAccel = 0.12; // +cases/s par s (finit par gagner)
  static const double _kShkSpeedMax = 3.5; // plafond (sinon invisible + tunneling)
  static const double _kNinjaRange = 4.5; // portée de tir (sinon gaspille le deck)

  void _pickNinjaTarget() {
    final w = _w;
    _ninjaTX = _cineRng.nextInt(w?.cols ?? 20).toDouble();
    _ninjaTY = _cineRng.nextInt(w?.rows ?? 15).toDouble();
  }

  // Toutes les toiles (🕸️ semaines à 0) du domaine avec leur position grille.
  List<({String key, double col, double row})> _cineAllToiles() {
    final w = _w;
    if (w == null) return const [];
    final mid = w.rows ~/ 2;
    final routines = _domTopRoutines();
    final times = _domTopTimeActivities();
    final r0 = mid - routines.length;
    final out = <({String key, double col, double row})>[];
    for (var i = 0; i < routines.length; i++) {
      final heat = logic.routineWeeklyHeatmap(routines[i].id);
      for (var k = 0; k < heat.length; k++) {
        if (heat[k] == 0) {
          out.add((
            key: 'toile:${routines[i].id}:$k',
            col: k.toDouble(),
            row: (r0 + i).toDouble()
          ));
        }
      }
    }
    for (var j = 0; j < times.length; j++) {
      final heat = logic.activityTimeWeeklyHeatmap(times[j].id);
      for (var k = 0; k < heat.length; k++) {
        if (heat[k] == 0) {
          out.add((
            key: 'toile:${times[j].id}:$k',
            col: k.toDouble(),
            row: (mid + 1 + j).toDouble()
          ));
        }
      }
    }
    return out;
  }

  // Shurikens dépensés AUJOURD'HUI (budget journalier = lifetime − dépensé).
  String get _todayYmd {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  int _shurikenSpentToday() =>
      logic.state.battleShurikensByDay[_todayYmd] ?? 0;

  void _consumeShurikens(int n) {
    if (n <= 0) return;
    logic.state.battleShurikensByDay[_todayYmd] = _shurikenSpentToday() + n;
    sync.pushAll(logic.state); // persiste (j'ai payé pour cette déloge)
  }

  void _startAttack() {
    _cineAttack = true;
    _ninjaHp = 10;
    _bossAttackT = 0;
    // Budget du JOUR : lifetime − déjà dépensé aujourd'hui (≥ 0). À 0 → tu tombes
    // vite à court → défaite : farme/attends demain pour reconstituer le deck.
    _ninjaShurikens =
        (logic.lifetimeBattleMasse - _shurikenSpentToday()).clamp(0, 1 << 30);
    _battleShkStart = _ninjaShurikens;
    _ninjaX = _pos.x.toDouble();
    _ninjaY = _pos.y.toDouble();
    _shurikens.clear();
    _shkThrowT = 0;
    _attackElapsed = 0;
    _cineSpawnT = 0;
    _cineSpawnIdx = 0;
    _supportFbs.clear();
    _inFlightKeys.clear();
    _cineKilledToiles.clear();
    _cineSbires.clear();
    _cineSbireSeq = 0;
    // Tours de support : UNE par ligne ayant ≥1 flamme cette semaine (les autres
    // ne tirent pas). Décompte d'amorce échelonné pour ne pas tirer en rafale.
    _cineTurrets.clear();
    _cineTurretByRow.clear();
    final wt = _w;
    if (wt != null) {
      final mid = wt.rows ~/ 2;
      final routines = _domTopRoutines();
      final times = _domTopTimeActivities();
      final r0 = mid - routines.length;
      void addTurret(int row, int flames) {
        if (flames <= 0) return;
        // Recharge ≈45 s ± aléatoire + phase initiale aléatoire → les canons ne
        // rechargent pas tous en même temps.
        final reloadEvery = _kFlameRegrow * (0.8 + _cineRng.nextDouble() * 0.4);
        final tu = _CineTurret(
            row,
            flames,
            flames,
            _cineRng.nextDouble() * _kTurretFireEvery,
            reloadEvery,
            _cineRng.nextDouble() * reloadEvery);
        _cineTurrets.add(tu);
        _cineTurretByRow[row] = tu;
      }
      for (var i = 0; i < routines.length; i++) {
        addTurret(
            r0 + i,
            logic
                .routineWeekTokens(routines[i].id)
                .where((t) => t.type == 'flame')
                .length);
      }
      for (var j = 0; j < times.length; j++) {
        addTurret(
            mid + 1 + j,
            logic
                .activityTimeTokens(times[j].id)
                .where((t) => t.type == 'flame')
                .length);
      }
    }
    // Toiles SURVIVANTES (non nettoyées) : sources de spawn ET cibles que les
    // tours continuent de détruire en support.
    final shot = _cineShots.map((s) => s.key).toSet();
    _cineToileSpawns = [
      for (final t in _cineAllToiles())
        if (!shot.contains(t.key)) (key: t.key, col: t.col, row: t.row)
    ];
    _pickNinjaTarget();
  }

  // Pré-calcule la séquence de tirs : pour chaque tour (dans l'ordre), elle tire
  // `flammes` projectiles, chacun sur la cible RESTANTE la plus proche — une
  // toile (château) battant tout nuisible (jardin), sinon par distance.
  List<({int turretRow, String key, double tx, double ty})> _cineBuildShots() {
    final w = _w;
    if (w == null) return const [];
    final mid = w.rows ~/ 2;
    final routines = _domTopRoutines();
    final times = _domTopTimeActivities();
    final r0 = mid - routines.length;
    final rowsInfo = <({String id, String kind, int gridRow, int flames})>[
      for (var i = 0; i < routines.length; i++)
        (
          id: routines[i].id,
          kind: 'spider',
          gridRow: r0 + i,
          flames: logic
              .routineWeekTokens(routines[i].id)
              .where((t) => t.type == 'flame')
              .length
        ),
      for (var j = 0; j < times.length; j++)
        (
          id: times[j].id,
          kind: 'scorpion',
          gridRow: mid + 1 + j,
          flames: logic
              .activityTimeTokens(times[j].id)
              .where((t) => t.type == 'flame')
              .length
        ),
    ];
    final remaining = <String, ({double col, double row, bool toile})>{};
    for (final ri in rowsInfo) {
      final heat = ri.kind == 'spider'
          ? logic.routineWeeklyHeatmap(ri.id)
          : logic.activityTimeWeeklyHeatmap(ri.id);
      for (var i = 0; i < heat.length; i++) {
        if (heat[i] == 0) {
          remaining['toile:${ri.id}:$i'] =
              (col: i.toDouble(), row: ri.gridRow.toDouble(), toile: true);
        }
      }
      final lane = ri.kind == 'spider'
          ? logic.routineWeekTokens(ri.id)
          : logic.activityTimeTokens(ri.id);
      for (var d = 0; d < lane.length; d++) {
        if (lane[d].type == 'spider') {
          remaining['nuis:${ri.id}:$d'] =
              (col: 13.0 + d, row: ri.gridRow.toDouble(), toile: false);
        }
      }
    }
    final shots = <({int turretRow, String key, double tx, double ty})>[];
    for (final ri in rowsInfo) {
      var ammo = ri.flames;
      final tr = ri.gridRow;
      while (ammo > 0 && remaining.isNotEmpty) {
        String? bestKey;
        double bestD = double.infinity;
        bool bestToile = false;
        remaining.forEach((k, v) {
          final d =
              (v.col - 12) * (v.col - 12) + (v.row - tr) * (v.row - tr);
          final better = bestKey == null
              ? true
              : (v.toile != bestToile ? v.toile : d < bestD);
          if (better) {
            bestKey = k;
            bestD = d;
            bestToile = v.toile;
          }
        });
        if (bestKey == null) break;
        final v = remaining[bestKey]!;
        shots.add((turretRow: tr, key: bestKey!, tx: v.col, ty: v.row));
        remaining.remove(bestKey);
        ammo--;
      }
    }
    return shots;
  }
  String? _interiorCaveId; // domaine de la grotte intérieure (= filtre nuisibles)
  String? _interiorDomainId; // domainId courant (clé de persistance des tours)
  // MODE TEMPS RÉEL (S1) : cases FORCÉES praticables dans l'intérieur (col 11 à
  // gauche des tours + col 12 + couloir vertical + porte de sortie) pour garantir
  // que l'avatar atteint toujours sa cible (cf. « cases accessibles »).
  final Set<String> _interiorWalk = {};
  Point<int>? _exitDoor; // porte de sortie intérieur → map principale
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
  static const Map<String, int> _massByType = {
    'spider': GoldEconomy.masseSpider,
    'scorpion': GoldEconomy.masseScorpion,
    'snake': GoldEconomy.masseSerpent,
  };
  int _nextWaveMs = 0; // prochaine vague d'émission
  int _emitBatch = 1; // sbires émis par vague = 1/10 de la garnison au spawn

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
    // Reprise des cinématiques mobiles mises en file après la fin d'un combat.
    if (!_combatBusy && !_traveling && _travelQueue.isNotEmpty) {
      _pumpTravelQueue();
    }
    if (_v2Fbs.isNotEmpty || _v2Flashes.isNotEmpty) {
      _simulateV2Cine(dt / 1000.0);
      _v2CineTick.value++; // repeint l'overlay seul (pas la grille)
    }
    // Araignées d'écart hebdo : errance + tir auto des shurikens stockés. Suspendu
    // en combat / à l'intérieur (elles vivent sur la grande map seulement).
    if (!_inInterior &&
        !_combatBusy &&
        (_gardenSpiders.isNotEmpty || _gardenShk.isNotEmpty)) {
      _simulateGardenSpiders(dt / 1000.0);
      _v2CineTick.value++; // repeint l'overlay seul (pas la grille)
    }
    if (_cannonSpinAt != null) _v2CineTick.value++; // anim spin de la rampe ☢️
    if (_liveFiring) {
      _simulateLive(dt / 1000.0);
      if (mounted) setState(() {});
    } else if (_battleActive) {
      _simulateBattle(dt / 1000.0);
      if (mounted) setState(() {});
    } else if (_cineActive) {
      _simulateCine(dt / 1000.0);
      if (mounted) setState(() {});
    } else if (_tdMode) {
      _simulate(dt / 1000.0);
      if (mounted) setState(() {});
    } else if (_simDefense) {
      _simulateDefense(dt / 1000.0);
      if (mounted) setState(() {});
    } else if (hadShots && mounted) {
      setState(() {});
    }
  }

  // Cinématique — PHASE PRÉPARATION : charge la jauge de flammes de la tour
  // courante, puis passe à la suivante. Quand toutes sont chargées → la prépa
  // est finie (slice suivant : nettoyage du terrain).
  void _simulateCine(double dt) {
    // PHASE ATTAQUE (étapes 7-8) : le ninja se déplace en continu sur la carte.
    if (_cineAttack) {
      final w = _w;
      final cols = w?.cols ?? 20, rows = w?.rows ?? 15;
      _attackElapsed += dt;
      // Spawn 1 sbire / s, en CYCLANT les toiles survivantes (pas tout d'un coup ;
      // après la dernière, on recommence à la première).
      if (_cineToileSpawns.isNotEmpty) {
        _cineSpawnT += dt;
        if (_cineSpawnT >= _kSbireSpawnEvery) {
          _cineSpawnT -= _kSbireSpawnEvery;
          final t = _cineToileSpawns[_cineSpawnIdx % _cineToileSpawns.length];
          _cineSpawnIdx++;
          _cineSbires.add(_Sbire(_cineSbireSeq++, t.col, t.row, 1));
        }
      }
      // SUPPORT des tours : chaque tour AYANT des flammes tire 1 boule / 10 s
      // (après une animation de visée), coûte 1 flamme ; ses flammes-source la
      // rechargent toutes les 30 s. Une toile déjà visée par un boulet en vol
      // n'est pas reciblée (1 flamme = 1 toile, pas de gaspillage).
      if (_cineToileSpawns.isNotEmpty) {
        for (final tu in _cineTurrets) {
          // Recharge : les flammes regarnissent la tour ≈toutes les 45 s (aléatoire
          // par tour → désynchronisé).
          tu.reload += dt;
          if (tu.reload >= tu.reloadEvery) {
            tu.reload -= tu.reloadEvery;
            tu.ammo = tu.maxFlames;
          }
          if (tu.aim < 0) {
            if (tu.ammo <= 0) continue;
            tu.cd -= dt;
            if (tu.cd <= 0) {
              final hasTarget =
                  _cineToileSpawns.any((t) => !_inFlightKeys.contains(t.key));
              if (hasTarget) {
                tu.aim = 0; // démarre la visée
              } else {
                tu.cd = 1.0; // rien à viser : réessaie bientôt
              }
            }
          } else {
            // Visée lente : le canon plonge (0→0.5) puis se relève (0.5→1) ; tir
            // à la fin de l'animation.
            tu.aim += dt / _kTurretAimDur;
            if (tu.aim >= 1.0) {
              tu.aim = -1;
              // Cadence rendue ALÉATOIRE (≈7–13 s) → les canons se désynchronisent.
              tu.cd = _kTurretFireEvery * (0.7 + _cineRng.nextDouble() * 0.6);
              final avail = [
                for (final t in _cineToileSpawns)
                  if (!_inFlightKeys.contains(t.key)) t
              ];
              if (avail.isNotEmpty && tu.ammo > 0) {
                tu.ammo--;
                final t = avail[_cineRng.nextInt(avail.length)];
                _inFlightKeys.add(t.key);
                // Arc d'autant plus haut que la cible est loin (lobe de mortier).
                final arc = ((12 - t.col).abs() * 0.4).clamp(1.2, 5.0).toDouble();
                // Départ au BOUT du canon (décalé vers la cible), pas au centre.
                final sx = 12 + 0.5 * (t.col > 12 ? 1 : -1);
                _supportFbs.add(_CineFb(_kSupportFbDur, sx, tu.row - 0.25, t.col,
                    t.row, arc, t.key));
              }
            }
          }
        }
      }
      // Avance les boules de feu de support (paramétrique) ; à t≥1, détruit la toile.
      for (final fb in _supportFbs) {
        fb.t += dt / fb.dur;
        if (fb.t >= 1.0) {
          fb.dead = true;
          _cineKilledToiles.add(fb.key);
          if (fb.key.startsWith('toile:')) _dayKilledToiles.add(fb.key);
          _cineToileSpawns.removeWhere((t) => t.key == fb.key);
          _inFlightKeys.remove(fb.key);
        }
      }
      _supportFbs.removeWhere((fb) => fb.dead);
      // VICTOIRE : toutes les toiles détruites → l'araignée est DÉLOGÉE (définitif)
      // et on PAIE les shurikens dépensés (budget du jour décrémenté & persisté).
      if (_cineToileSpawns.isEmpty && _supportFbs.isEmpty) {
        _cineAttack = false;
        _cineActive = false;
        _consumeShurikens(_battleShkStart - _ninjaShurikens);
        final dom = _interiorDomainId;
        if (dom != null) _v2Dislodged.add(dom); // ne reviendra pas
        _toast('🏰 Araignée délogée ! (toiles détruites)', _kBlue);
        return;
      }
      // ARC actif : le ninja S'ARRÊTE 5 s et tire 3 flèches/s (sans consommer ses
      // shurikens), puis reprend sa route.
      if (_ninjaBow) {
        _bowDur += dt;
        _bowArrowT += dt;
        if (_bowArrowT >= _kBowEvery && _cineSbires.isNotEmpty) {
          _bowArrowT -= _kBowEvery;
          _Sbire? near;
          var nd = double.infinity;
          for (final s in _cineSbires) {
            final d = (s.x - _ninjaX) * (s.x - _ninjaX) +
                (s.y - _ninjaY) * (s.y - _ninjaY);
            if (d < nd) {
              nd = d;
              near = s;
            }
          }
          if (near != null) {
            final ddx = near.x - _ninjaX, ddy = near.y - _ninjaY;
            final dd = sqrt(ddx * ddx + ddy * ddy);
            if (dd > 0.01) {
              _shurikens.add(_CineShk(_ninjaX, _ninjaY, ddx / dd * _kArrowSpeed,
                  ddy / dd * _kArrowSpeed,
                  arrow: true)); // gratuit : pas de _ninjaShurikens--
            }
          }
        }
        if (_bowDur >= _kBowDuration) _ninjaBow = false;
      } else {
        // Ninja : déplacement ALÉATOIRE perpétuel.
        final dx = _ninjaTX - _ninjaX, dy = _ninjaTY - _ninjaY;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist < 0.35) {
          _pickNinjaTarget();
        } else {
          final step = _kNinjaSpeed * dt;
          _ninjaX += dx / dist * step;
          _ninjaY += dy / dist * step;
        }
      }
      _pos = Point(_ninjaX.round().clamp(0, cols - 1),
          _ninjaY.round().clamp(0, rows - 1));
      // Sbires : déplacement ALÉATOIRE (chacun erre vers un point au hasard ;
      // en repique un à l'arrivée). Lents → esquivables.
      for (final s in _cineSbires) {
        if (s.wp == null ||
            ((s.wp!.dx - s.x).abs() < 0.4 && (s.wp!.dy - s.y).abs() < 0.4)) {
          s.wp = Offset(_cineRng.nextInt(cols).toDouble(),
              _cineRng.nextInt(rows).toDouble());
        }
        final sdx = s.wp!.dx - s.x, sdy = s.wp!.dy - s.y;
        final sd = sqrt(sdx * sdx + sdy * sdy);
        if (sd > 0.05) {
          s.x += sdx / sd * _kSbireSpeed * dt;
          s.y += sdy / sd * _kSbireSpeed * dt;
        }
      }
      // Ninja LANCE un shuriken (2/s) sur le sbire le plus proche (ligne droite ;
      // le sbire peut l'esquiver). Consomme une munition du deck.
      _shkThrowT += dt;
      if (!_ninjaBow &&
          _shkThrowT >= _kShkEvery &&
          _ninjaShurikens > 0 &&
          _cineSbires.isNotEmpty) {
        _shkThrowT = 0;
        _Sbire? near;
        var nd = double.infinity;
        for (final s in _cineSbires) {
          final d = (s.x - _ninjaX) * (s.x - _ninjaX) +
              (s.y - _ninjaY) * (s.y - _ninjaY);
          if (d < nd) {
            nd = d;
            near = s;
          }
        }
        // Ne tire QUE si le sbire le plus proche est À PORTÉE (sinon gaspille).
        if (near != null && nd <= _kNinjaRange * _kNinjaRange) {
          final ddx = near.x - _ninjaX, ddy = near.y - _ninjaY;
          final dd = sqrt(ddx * ddx + ddy * ddy);
          if (dd > 0.01) {
            // Vitesse qui AUGMENTE avec le temps → finit par toucher (le ninja
            // tire 2/s vs 1/s de spawn) : pas de boucle infinie.
            final shkSpeed = (_kShkSpeedBase + _attackElapsed * _kShkAccel)
                .clamp(0.0, _kShkSpeedMax);
            _shurikens.add(_CineShk(_ninjaX, _ninjaY,
                ddx / dd * shkSpeed, ddy / dd * shkSpeed));
            _ninjaShurikens--;
          }
        }
      }
      // Avance les shurikens + collision avec les sbires.
      for (final shk in _shurikens) {
        shk.x += shk.vx * dt;
        shk.y += shk.vy * dt;
        if (shk.x < -1 || shk.x > cols + 1 || shk.y < -1 || shk.y > rows + 1) {
          shk.dead = true;
          continue;
        }
        for (final s in _cineSbires) {
          if ((shk.x - s.x).abs() < 0.5 && (shk.y - s.y).abs() < 0.5) {
            s.hp = 0;
            shk.dead = true;
            break;
          }
        }
      }
      _shurikens.removeWhere((shk) => shk.dead);
      _cineSbires.removeWhere((s) => s.hp <= 0);
      // Un sbire TOUCHE le ninja → -1 PV (le sbire disparaît). 0 PV → échec.
      _cineSbires.removeWhere((s) {
        if ((s.x - _ninjaX).abs() < 0.55 && (s.y - _ninjaY).abs() < 0.55) {
          _ninjaHp--;
          return true;
        }
        return false;
      });
      // L'ARAIGNÉE-BOSS frappe le ninja chaque minute d'assaut → -1 PV.
      _bossAttackT += dt;
      if (_bossAttackT >= 60.0) {
        _bossAttackT -= 60.0;
        _ninjaHp--;
        _toast('🕷️ L\'araignée frappe le ninja — -1 PV !', _kEnemy);
      }
      if (_ninjaHp <= 0) {
        // DÉFAITE : on NE consomme PAS les shurikens (rien persisté) → tu peux
        // refarmer ton deck et réessayer ; l'araignée n'est PAS délogée.
        _cineAttack = false;
        _cineActive = false;
        _toast('💀 Le ninja est tombé — l\'araignée tient. Farme et réessaie.',
            _kEnemy);
      }
      return;
    }
    // PHASE NETTOYAGE (après la prépa) : les tours tirent sur les cibles.
    if (_cineClearing) {
      if (_cineClearIndex >= _cineShots.length) {
        _cineClearing = false;
        _startAttack(); // → phase attaque (ninja)
        return;
      }
      _cineClearT += dt / _kCineClearPerTarget;
      while (_cineClearT >= 1.0 && _cineClearIndex < _cineShots.length) {
        _cineClearT -= 1.0;
        // Toile-château détruite → 💥 PERSISTÉE la journée.
        final key = _cineShots[_cineClearIndex].key;
        if (key.startsWith('toile:')) _dayKilledToiles.add(key);
        _cineClearIndex++;
      }
      return;
    }
    // PHASE PRÉPARATION : charge séquentielle. Les tours SANS flamme ne
    // participent pas → on les saute INSTANTANÉMENT (pas de temps d'attente).
    while (_cinePrepIndex < _cineRowCount &&
        (_cinePrepIndex >= _cineRowFlames.length ||
            _cineRowFlames[_cinePrepIndex] == 0)) {
      _cinePrepIndex++;
      _cinePrepCharge = 0;
    }
    if (_cinePrepIndex >= _cineRowCount) {
      // → passe au NETTOYAGE.
      _cineClearing = true;
      _cineShots = _cineBuildShots();
      _cineClearIndex = 0;
      _cineClearT = 0;
      return;
    }
    _cinePrepCharge += dt / _kCinePrepPerTurret;
    if (_cinePrepCharge >= 1.0) {
      _cinePrepCharge = 0;
      _cinePrepIndex++;
    }
  }

  // Démarre la cinématique de reprise (prépa des tours). rowCount = nb de tours.
  void _startCine() {
    // Flammes par ligne (ordre allRows = routines puis activités-temps).
    _cineRowFlames = [
      for (final r in _domTopRoutines())
        logic.routineWeekTokens(r.id).where((t) => t.type == 'flame').length,
      for (final r in _domTopTimeActivities())
        logic.activityTimeTokens(r.id).where((t) => t.type == 'flame').length,
    ];
    setState(() {
      _cineActive = true;
      _cinePrepIndex = 0;
      _cinePrepCharge = 0;
      _cineRowCount = _cineRowFlames.length;
      _cineClearing = false;
      _cineShots = const [];
      _cineClearIndex = 0;
      _cineClearT = 0;
      _cineAttack = false;
    });
  }

  // Charge de flammes (0..1) de la tour d'index i pendant la cinématique :
  // pleine si déjà passée, en cours si courante, vide sinon.
  double _cineCharge(int i) {
    if (i < _cinePrepIndex) return 1.0;
    if (i == _cinePrepIndex && _cineActive) return _cinePrepCharge;
    return 0.0;
  }

  void _simulate(double dt) {
    final w = _w;
    if (w == null) return;
    if (!_phase1) return;
    // L'attaquant 🕷️ reste FIXE tant que la porte tient, puis avance sur la grotte.
    const wanderSpeed = 0.45; // vitesse de l'envahisseur (avance vers la grotte)
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
    // 1) CONVOCATION DE MONSTRES : l'envahisseur 🕷️ déverse sa garnison vers la
    //    porte, ~1/10 par vague toutes les 10 s, depuis sa propre case (x=0). Plus
    //    de duel : la défense, c'est la porte + les tourelles/arcs posés.
    if (_garrison > 0 && _gameMs >= _nextWaveMs) {
      final n = _emitBatch.clamp(0, _garrison);
      _garrison -= n;
      for (int i = 0; i < n; i++) {
        final ox = (_rng.nextDouble() - 0.5) * 0.9;
        final oy = (_rng.nextDouble() - 0.5) * 0.9;
        _sbires.add(_Sbire(_sbireSeq++, _invX + 0.3 + ox, _invY + oy, 1)
          ..wp = _gateApproachWaypoint(w));
      }
      _nextWaveMs += 10000;
    }
    // 3) Sbires ennemis : waypoint aléatoire D'ABORD, puis cap sur la porte (8,7) ;
    //    cassée → vers la GROTTE.
    final broken = _gateHp <= 0;
    final goal = broken ? _grotteTarget : const Offset(8, 7);
    for (final s in _sbires) {
      if (s.hp <= 0) continue;
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
    } else if (_garrison <= 0 && _sbires.isEmpty) {
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

  // Dev : place l'envahisseur 🕷️ à gauche et lance la Phase 1 (convocation).
  void _startPhase1() {
    setState(() {
      _tdMode = true;
      _phase1 = true;
      _sbires.clear();
      _shots.clear();
      // Garnison de l'ENNEMI = TES RETARDS RÉELS : masse du backlog (routines sans
      // streak 🕷️ + activités-temps en retard 🦂 + tâches en retard 🐍). Plancher
      // 10 pour rester jouable même quand tu es à jour.
      final retards = logic
          .backlogEnemies()
          .fold(0, (s, e) => s + (_massByType[e.type] ?? 0));
      _garrison = retards < 10 ? 10 : retards;
      _enemyDeckPower = _garrison; // puissance du deck ennemi (affichée si prise)
      final w = _w;
      // Avatar posté côté château (15,7), face à l'invasion qui vient de gauche.
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
      _gateHp = _gateHpMax;
      // Convocation par vagues : ~1/10 de la garnison toutes les 10 s.
      _nextWaveMs = _gameMs;
      _emitBatch = ((_garrison + 9) ~/ 10).clamp(1, _garrison);
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
  void _quickEnter({bool forceOccupied = false}) {
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
                _enterInterior(c.id, forceOccupied: forceOccupied);
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
      if (_defAttackers.isEmpty && !_interiorPeaceful) {
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
  void _enterInterior(String caveId, {bool forceOccupied = false}) {
    // Mobile : pas de map principale → _w peut être null (rien à sauver).
    final w = _w;
    if (w == null && !widget.mobile) return;
    final cave = _t?.caveById(caveId);
    // Grille assez HAUTE pour TOUTES les routines + activités-temps du domaine
    // (placement dynamique, plus de cap). rows = labels + routines + écart +
    // temps + marge ; le plateau défile verticalement si plus grand que l'écran.
    final dom0 = cave?.domainId;
    var nr = 0, nt = 0;
    for (final a in logic.state.activeActivities) {
      if (dom0 == null || a.domainId != dom0) continue;
      if (a.isHabit) {
        if (logic.routineWeekTokens(a.id).isNotEmpty) nr++;
      } else {
        if (logic.activityTimeTokens(a.id).isNotEmpty) nt++;
      }
    }
    // Grille CENTRÉE sur midY (= rows~/2 = ligne de spawn château/araignée/avatar).
    // Routines AU-DESSUS de midY, activités EN DESSOUS → la ligne vide du milieu
    // (midY) porte naturellement le château/l'araignée/l'avatar.
    final m = nr > nt ? nr : nt;
    final calRows = 2 * m + 3;
    // Backdrop intérieur MIROIR (même base que la map principale : château à
    // gauche). Le calendrier en overlay garde ses coords (déjà repère inversé).
    final interior = mirrorWorldX(generateUnifiedWorld(
        (_t?.seed ?? 1) ^ caveId.hashCode,
        caveIds: const ['coeur'],
        cols: 20, // château heatmap 12 sem (0→11) + tour (12) + 7 jours (13→19)
        rows: calRows < 9 ? 9 : calRows));
    setState(() {
      _savedW = w;
      _savedPos = _pos;
      _savedRevealed = {..._revealed};
      _savedFarmPests = {..._farmPests};
      _interiorColor = cave != null ? _caveColor(cave) : _kBlue;
      // Cadre d'assaut SEULEMENT si la grotte est réellement OCCUPÉE (état
      // territoire), pas si simplement négligée.
      _interiorPeaceful = forceOccupied ? false : (cave == null || !cave.occupied);
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
      // Reset cinématique (sinon une grotte ré-entrée garde l'état DCA/attaque).
      _cineActive = false;
      _cineClearing = false;
      _cineAttack = false;
      _cinePrepIndex = 0;
      _cineClearIndex = 0;
      // Purge de tout combat de la MAP PRINCIPALE (sinon scorpion/sbires fantômes
      // restés à leur ancienne position fuient dans la grotte).
      _phase1 = false;
      _sbires.clear();
      _shots.clear();
      _garrison = 0;
      _grotteTaken = false;
      _invaderGone = false;
      _captureStartMs = null;
      _gateHp = _gateHpMax;
      _w = interior;
      _pos = interior.start; // avatar dans le gazon (entrée gauche)
      _revealed.clear();
      _farmPests.clear();
      // Intérieur = plateau calendrier/combat (pas un donjon à explorer) → on
      // révèle TOUT à l'entrée. L'ancien déclencheur de case (8,7) ne tient plus
      // depuis l'élargissement de la grille (20 cols) → le brouillard restait.
      for (var y = 0; y < interior.rows; y++) {
        for (var x = 0; x < interior.cols; x++) {
          _revealed.add('${x}_$y');
        }
      }
      _populateFarm(); // peuple le gazon avec les nuisibles de CE domaine
      // Défenses du domaine = ses routines à streak, posées en ZONE DE DÉPART
      // (0,0)→(7,1). L'user les drag où il veut. Niveau = streak = chargeur.
      _domTurrets.clear();
      final dom = cave?.domainId;
      _interiorDomainId = dom;
      // ACCESSIBILITÉ (S1) : force praticables la case à gauche de chaque tour
      // (col 11), la tour (col 12), un couloir vertical col 11 qui les relie, et
      // pose une PORTE DE SORTIE en haut du couloir. La ligne médiane (sol) relie
      // le couloir au spawn de l'avatar → BFS toujours résoluble.
      _interiorWalk.clear();
      _exitDoor = null;
      {
        final midI = interior.rows ~/ 2;
        final nRout = _domTopRoutines().length;
        final nTime = _domTopTimeActivities().length;
        final trows = <int>[
          for (var i = 0; i < nRout; i++) midI - nRout + i,
          for (var j = 0; j < nTime; j++) midI + 1 + j,
        ];
        if (trows.isNotEmpty) {
          final lo = (trows.reduce(min) - 1).clamp(0, interior.rows - 1);
          final hi = trows.reduce(max).clamp(0, interior.rows - 1);
          for (var y = lo; y <= hi; y++) _interiorWalk.add('11_$y');
          _interiorWalk.add('11_$midI'); // jonction avec la ligne médiane (spawn)
          for (final y in trows) {
            _interiorWalk.add('11_$y');
            _interiorWalk.add('12_$y');
          }
          _exitDoor = Point(11, lo); // haut du couloir = sortie
        }
      }
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
      final dname =
          cave != null ? _domainName(cave.domainId) : "la grotte";
      _toast(
          _interiorPeaceful
              ? '🏡 Tu entres dans $dname — domaine tenu, grotte en paix.'
              : '🕳️ Tu entres dans $dname — grotte occupée, reconquiers-la !',
          _interiorColor);
    });
  }

  // Sortir de la grotte → restaure la map principale.
  // Web : restaure l'overworld V1 sauvegardé (_savedW). Mobile V2 : pas
  // d'overworld V1 → on revient simplement à la carte V2 (état _wv2/_posV2
  // conservé pendant l'intérieur).
  void _exitInterior() {
    final saved = _savedW;
    if (saved == null && !widget.mobile) return;
    setState(() {
      if (saved != null) {
        _w = saved;
        _pos = _savedPos ?? saved.start;
        _revealed
          ..clear()
          ..addAll(_savedRevealed ?? const <String>{});
        _farmPests
          ..clear()
          ..addAll(_savedFarmPests ?? const {});
      } else {
        // Mobile V2 : on quitte l'intérieur sans restaurer d'overworld V1.
        _w = null;
      }
      _inInterior = false;
      _interiorCaveId = null;
      _interiorWalk.clear();
      _exitDoor = null;
      // Coupe un éventuel tir d'arrivée / bataille en cours.
      _liveFiring = false;
      _liveFb = null;
      _liveDone?.complete();
      _liveDone = null;
      _battleActive = false;
      _battleBeams.clear();
      _battleDone?.complete();
      _battleDone = null;
      _savedW = null;
      _savedPos = null;
      _savedRevealed = null;
      _savedFarmPests = null;
      _tdMode = false;
      _webBroken = false;
    });
  }

  // Assaut INTÉRIEUR (reconquête) = MIROIR de _startPhase1, rôles inversés :
  // MOI j'attaque (mon scorpion 🦂) — mon deck de reconquête farmé joue la
  // réserve d'assaut (= _garrison de l'« envahisseur »), qui se déverse en vagues
  // vers la grotte 'coeur'. Le moteur _simulate est réutilisé tel quel ; seules la
  // résolution finale (grotte prise = je GAGNE) et le visuel (🕷️↔🦂) sont inversés
  // via _inInterior. Bouton retiré ; conservé pour un éventuel re-câblage.
  // ignore: unused_element
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
      _webBroken = false;
      _sbires.clear();
      _shots.clear();
      _grotteTaken = false;
      _invaderGone = false;
      _captureStartMs = null;
      _grotteHpAtCapture = 0;
      // MA réserve d'assaut = le deck de reconquête farmé (= garnison invader).
      _garrison = _reconquestDeck;
      _enemyDeckPower = _garrison;
      // Mon scorpion 🦂 (attaquant) démarre LÀ OÙ EST L'AVATAR (il l'accompagne
      // depuis l'entrée). Le scorpion est LANCÉ 2 cases sur la droite (charge vers
      // la grotte) et toute la map se révèle → l'assaut se joue en cinématique
      // (déplacement verrouillé tant que _tdMode est actif, cf. _onTap/_moveDir).
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
      _emitBatch = ((_garrison + 9) ~/ 10).clamp(1, _garrison);
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
    _loadAnimatedHits(); // persistance : hits déjà animés aujourd'hui (anti‑rejeu)
    _loadSpiderGap(); // persistance : écart hebdo réglé au dernier passage
    _subscribeHits(); // temps réel : valider une routine → l'avatar voyage
    _subscribeSessions(); // temps réel : minuteur d'activité → assaut live
    // Projets Gantt → logic.currentProjects (sinon backlogEnemies() ne voit aucune
    // tâche → aucun serpent dans le jardin). Le web_home ne le faisait pas pour la map.
    _projSub = sync.streamProjects().listen((projects) {
      if (!mounted) return;
      logic.updateGanttCounts(projects);
      _populateFarm(); // repeuple le jardin avec les tâches en retard fraîches
      setState(() {
        if (_kWorldV2) _rebuildWv2(); // la map V2 grandit avec les données
      });
    });
    if (_kWorldV2) setState(_rebuildWv2); // 1ère construction du monde V2
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
              caveIds: t.caves.map((c) => c.id).toList(),
              withDistricts: true));
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
        if (_kWorldV2) _rebuildWv2(); // domaines dispo (grottes) → (re)pose la map V2
      });
      // MOBILE : on reste sur la carte V2 explorable (overworld). L'entrée dans
      // l'intérieur d'un domaine se fait en jeu (clic du boss du domaine).
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
    _projSub?.cancel();
    _hitSub?.cancel();
    _sessionSub?.cancel();
    _v2PrimeTimer?.cancel();
    _v2IdleTimer?.cancel();
    for (final t in _actFireTimers.values) {
      t.cancel();
    }
    _timer?.cancel();
    _gameTicker?.dispose();
    _v2HCtrl.dispose();
    _v2VCtrl.dispose();
    _v2CineTick.dispose();
    _miniBasePic?.dispose();
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

  // Couleur du domaine où le PLUS de temps a été loggué AUJOURD'HUI (somme des
  // sessions du jour, comme _loggedMinutesOnDay). null si rien aujourd'hui.
  Color? _topTimeDomainColorToday() {
    final now = DateTime.now();
    final perDomain = <String, int>{};
    for (final s in logic.state.sessions) {
      if (s.startAt.year != now.year ||
          s.startAt.month != now.month ||
          s.startAt.day != now.day) continue;
      final mins = s.duration.inMinutes;
      if (mins <= 0) continue;
      String? dom;
      for (final a in logic.state.activities) {
        if (a.id == s.activityId) {
          dom = a.domainId;
          break;
        }
      }
      if (dom == null || dom.isEmpty) continue;
      perDomain[dom] = (perDomain[dom] ?? 0) + mins;
    }
    if (perDomain.isEmpty) return null;
    var topDom = '';
    var best = -1;
    perDomain.forEach((d, m) {
      if (m > best) {
        best = m;
        topDom = d;
      }
    });
    return domainColor(topDom, logic.state.activeDomains);
  }

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
        // Grande map : la PORTE est franchissable par l'avatar (déplacement libre
        // château ↔ jardin) — elle ne reste un chokepoint que pour l'invasion.
        (!_inInterior && w.isGate(x, y)) ||
        (_inInterior && _interiorWalk.contains('${x}_$y')) ||
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
        // Sur la grande map (pas de fog) toute case walkable passe ; le brouillard
        // ne bloque le chemin qu'à l'intérieur d'un domaine.
        if (prev.containsKey(nid) || (_inInterior && !_revealed.contains(nid))) {
          continue;
        }
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

  Future<void> _walkPath(List<Point<int>> path, {int stepMs = 150}) async {
    setState(() => _busy = true);
    for (final p in path) {
      if (!mounted) break;
      _step(p);
      await Future.delayed(Duration(milliseconds: stepMs));
    }
    if (mounted) setState(() => _busy = false);
  }

  void _step(Point<int> to) {
    _revealAround(to);
    _populateFarm();
    setState(() => _pos = to);
    _announce(to);
  }

  // ── MODE TEMPS RÉEL (S2) : voyage automatique de l'avatar vers une routine ──
  // Praticabilité d'AUTO-VOYAGE : plus permissive que `_passable` — l'avatar
  // franchit la PORTE (x9), peut marcher sur une grotte, et ignore le brouillard
  // (BFS dédié). Garantit qu'un domaine est TOUJOURS atteignable (cases accessibles).
  bool _autoPassable(int x, int y) {
    final w = _w;
    if (w == null || !w.inBounds(x, y)) return false;
    return w.walkable(x, y) ||
        _isBowWalkable(x, y) ||
        w.isGate(x, y) ||
        w.caveIdAt(x, y) != null ||
        (_inInterior && _interiorWalk.contains('${x}_$y'));
  }

  List<Point<int>> _orthoAuto(int x, int y) => [
        Point(x + 1, y),
        Point(x - 1, y),
        Point(x, y + 1),
        Point(x, y - 1),
      ].where((p) => _autoPassable(p.x, p.y)).toList();

  // BFS d'auto-voyage : ignore le brouillard (révèle en marchant).
  List<Point<int>> _bfsPathAuto(Point<int> from, Point<int> to) {
    if (from == to) return const [];
    final startId = '${from.x}_${from.y}';
    final goalId = '${to.x}_${to.y}';
    final prev = <String, String?>{startId: null};
    final queue = <Point<int>>[from];
    var i = 0;
    while (i < queue.length) {
      final cur = queue[i++];
      if ('${cur.x}_${cur.y}' == goalId) break;
      for (final n in _orthoAuto(cur.x, cur.y)) {
        final nid = '${n.x}_${n.y}';
        if (prev.containsKey(nid)) continue;
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

  // Ligne-tourelle d'une routine/activité DANS le domaine courant (col 12 ; case
  // gauche = col 11). Routines au-dessus de la médiane, activités-temps en dessous.
  int? _routineTurretRow(String id) {
    final w = _w;
    if (w == null) return null;
    final mid = w.rows ~/ 2;
    final routines = _domTopRoutines();
    final idx = routines.indexWhere((r) => r.id == id);
    if (idx >= 0) return mid - routines.length + idx;
    final times = _domTopTimeActivities();
    final j = times.indexWhere((r) => r.id == id);
    if (j >= 0) return mid + 1 + j;
    return null;
  }

  bool _traveling = false;

  // Voyage complet : (sortir du mauvais domaine →) map principale → bon domaine →
  // case à GAUCHE de la tourelle (col 11). Réutilise enter/exit + marche animée.
  Future<void> _travelToRoutine(String routineId, {bool blank = false}) async {
    if (_traveling || widget.mobile) return;
    // Domaine de la routine/activité.
    String? domId;
    for (final a in logic.state.activeActivities) {
      if (a.id == routineId) {
        domId = a.domainId;
        break;
      }
    }
    final t = _t;
    if (domId == null || t == null) return;
    // Grotte de ce domaine.
    String? caveId;
    for (final c in t.caves) {
      if (c.domainId == domId) {
        caveId = c.id;
        break;
      }
    }
    if (caveId == null) return;
    // Déjà dans CE domaine → on ne rejoue PAS la bataille (juste le tir) : ça
    // favorise de rester sur un seul domaine à la fois.
    final alreadyHere = _inInterior && _interiorCaveId == caveId;
    _traveling = true;
    try {
      // 1. Mauvais domaine ouvert → marcher vers la porte de sortie, sortir.
      if (_inInterior && _interiorCaveId != caveId) {
        final ex = _exitDoor;
        if (ex != null) {
          final path = _bfsPathAuto(_pos, ex);
          if (path.isNotEmpty) await _walkPath(path);
        }
        _exitInterior();
        await Future.delayed(const Duration(milliseconds: 140));
      }
      // 2. Sur la map principale → marcher jusqu'à la grotte, entrer.
      if (!_inInterior) {
        final w = _w;
        final cp = w?.caves[caveId];
        if (w != null && cp != null) {
          final path = _bfsPathAuto(_pos, cp);
          if (path.isNotEmpty) await _walkPath(path);
        }
        _enterInterior(caveId);
        await Future.delayed(const Duration(milliseconds: 140));
      }
      // 3. Dans le bon domaine → case à gauche de la tourelle (col 11).
      final row = _routineTurretRow(routineId);
      if (row != null) {
        final path = _bfsPathAuto(_pos, Point(11, row));
        if (path.isNotEmpty) await _walkPath(path, stepMs: 230); // un peu plus lent
        // 4. On ne (re)joue la cinématique QUE s'il reste des toiles à détruire
        //    (les détruites portent une 💥 persistante → pas de rejeu inutile).
        if (_domainRemainingToiles(domId) > 0) {
          // Bataille du jardin (sauf si déjà sur place) : SEMAINE (toggle, 1×/jour)
          // ou AUJOURD'HUI (défaut), puis tir final transformé sur la routine.
          if (!alreadyHere) {
            if (_replayWeek && !_weeklyPlayedToday) {
              _weeklyBattleAt = DateTime.now();
              await _runGardenBattle(weekly: true);
            } else {
              await _runGardenBattle(weekly: false);
            }
          }
          await _fireArrival(routineId, row, blank: blank);
        }
      }
    } finally {
      _traveling = false;
    }
  }

  // Routine de TEST pour le voyage (S2) : 1ʳᵉ routine quotidienne active.
  String? _firstTravelRoutineId() {
    for (final a in logic.state.activeActivities) {
      if (a.isHabit && logic.routineWeekTokens(a.id).isNotEmpty) return a.id;
    }
    return null;
  }

  // routines/activités à visiter, dans l'ordre. blank = 1ᵉʳ tir cinématique (sans PV).
  final List<({String id, bool blank})> _travelQueue = [];

  // ── TEMPS RÉEL : hits de routine animés UNE seule fois (exploration semi‑auto) ──
  // Chaque HabitHit du jour est animé exactement une fois (dédup par id, persisté).
  // BACKLOG (à l'ouverture, hits faits hors‑web) → l'avatar voyage bas→haut pour les
  // décharger. LIVE (web déjà ouvert) → la tour tire SUR PLACE.
  StreamSubscription<List<HabitHit>>? _hitSub;
  static const String _kAnimatedKey = 'v2_animated_hits';
  final Set<String> _animatedHitIds = {}; // ids de HabitHit déjà animés aujourd'hui
  bool _animatedLoaded = false;
  String _animatedYmd = '';
  List<HabitHit> _lastHits = const []; // dernière salve (réévaluée après chargement)
  bool _hitStreamSeen = false; // 1ʳᵉ salve Firestore reçue (= snapshot d'ouverture)
  bool _backlogProcessed = false; // backlog d'ouverture traité → tout hit suivant = LIVE
  Timer? _v2PrimeTimer;
  final Map<String, List<String>> _pendingByRoutine = {}; // routineId → ids à animer (flammes)
  bool _v2AutoExploring = false;
  bool _v2UserControl = false; // l'utilisateur a repris la main (stoppe l'auto)
  Timer? _v2IdleTimer; // 1 min sans interaction → l'avatar reprend

  Future<void> _loadAnimatedHits() async {
    _animatedYmd = yyyymmdd(DateTime.now());
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kAnimatedKey);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        if (m['ymd'] == _animatedYmd) {
          _animatedHitIds.addAll((m['ids'] as List).cast<String>());
        }
      }
    } catch (_) {}
    _animatedLoaded = true;
    _evaluateHits(_lastHits); // rejoue la dernière salve arrivée avant le chargement
  }

  Future<void> _persistAnimated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAnimatedKey,
          jsonEncode({'ymd': _animatedYmd, 'ids': _animatedHitIds.toList()}));
    } catch (_) {}
  }

  // ── ARAIGNÉES D'ÉCART HEBDO (par domaine) ──────────────────────────────────
  Future<void> _loadSpiderGap() async {
    _spiderGapYmd = yyyymmdd(DateTime.now());
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSpiderGapKey);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        if (m['ymd'] == _spiderGapYmd) {
          final seen = (m['seen'] as Map<String, dynamic>?) ?? const {};
          seen.forEach((k, v) => _spiderGapSeenByDomain[k] = (v as num).toInt());
        }
      }
    } catch (_) {}
    _spiderGapLoaded = true;
    if (mounted && _wv2 != null) setState(_populateV2Spiders);
  }

  Future<void> _persistSpiderGap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSpiderGapKey,
          jsonEncode({'ymd': _spiderGapYmd, 'seen': _spiderGapSeenByDomain}));
    } catch (_) {}
  }

  // Écart hebdo d'une routine : max(0, valeur(même jour la semaine dernière) −
  // valeur(aujourd'hui)). Combien de complétions il reste à faire pour égaler S‑7.
  int _routineWeekGap(String routineId, DateTime today) {
    final lastWeek = today.subtract(const Duration(days: 7));
    final gap = logic.habitValueOn(routineId, lastWeek) -
        logic.habitValueOn(routineId, today);
    return gap > 0 ? gap : 0;
  }

  // Écart d'un domaine = Σ sur ses routines.
  int _domainWeekGap(CastleBlock c, DateTime today) {
    var total = 0;
    for (final lane in c.lanes) {
      if (!lane.isRoutine) continue;
      total += _routineWeekGap(lane.id, today);
    }
    return total;
  }

  // Pose / réconcilie les araignées d'écart, PAR DOMAINE. INVARIANT par domaine :
  // araignées vivantes(D) = écart(D) + shurikens(D). Chaque shuriken touché
  // décrémente LES DEUX → on converge vers l'écart courant du domaine. Les shurikens
  // « gagnés » = la réduction de l'écart de CE domaine depuis le dernier passage.
  void _populateV2Spiders() {
    final w = _wv2;
    if (w == null || !_spiderGapLoaded || widget.mobile) return;
    final today = yyyymmdd(DateTime.now());
    final now = DateTime.now();
    final todayD = DateTime(now.year, now.month, now.day);
    if (_spiderGapYmd != today) {
      // Nouveau jour → reset complet (par domaine).
      _spiderGapYmd = today;
      _spiderGapSeenByDomain.clear();
      _gardenShurikensByDomain.clear();
      _gardenSpiders.clear();
      _gardenShk.clear();
    }
    for (final c in w.castles) {
      final dom = c.domainId;
      final gap = _domainWeekGap(c, todayD);
      // 1er passage du jour pour ce domaine → seen = gap (aucun shuriken, on montre l'écart).
      final seen = _spiderGapSeenByDomain[dom] ?? gap;
      final earned = seen - gap; // ≥ 0 (l'écart ne fait que baisser le jour J)
      if (earned > 0) {
        _gardenShurikensByDomain[dom] = (_gardenShurikensByDomain[dom] ?? 0) + earned;
      }
      _spiderGapSeenByDomain[dom] = gap;
      final shur = _gardenShurikensByDomain[dom] ?? 0;
      final desired = gap + shur;
      final mineCount = _gardenSpiders.where((s) => s.domainId == dom).length;
      if (mineCount > desired) {
        var toRemove = mineCount - desired;
        _gardenSpiders.removeWhere((s) => s.domainId == dom && toRemove-- > 0);
      } else {
        for (var i = mineCount; i < desired; i++) {
          final s = _spawnGardenSpider(w, c);
          if (s == null) break;
          _gardenSpiders.add(s);
        }
      }
    }
    _persistSpiderGap();
  }

  // Fait apparaître une araignée sur une case PRATICABLE au hasard, CONFINÉE au
  // village+jardin de son domaine (château/calendrier exclu). Mémorise ses bornes.
  _GardenSpider? _spawnGardenSpider(WorldLayout w, CastleBlock c) {
    final bx0 = c.villageRect.left;
    final by0 = c.villageRect.top;
    final bx1 = c.gardenRect.left + c.gardenRect.width - 1;
    final by1 = c.villageRect.top + c.villageRect.height - 1;
    final rng = _rng;
    for (var t = 0; t < 40; t++) {
      final x = bx0 + rng.nextInt(bx1 - bx0 + 1);
      final y = by0 + rng.nextInt(by1 - by0 + 1);
      if (w.walkable(x, y)) {
        return _GardenSpider(x + 0.5, y + 0.5, rng.nextDouble() * 2 * pi,
            c.domainId, bx0, by0, bx1, by1);
      }
    }
    return null;
  }

  void _subscribeHits() {
    if (widget.mobile) return; // mode spectateur = web
    _hitSub = sync.streamHabitHits().listen((hits) {
      _lastHits = hits;
      _hitStreamSeen = true;
      _evaluateHits(hits);
    });
  }

  // (CastleBlock, LaneRow) d'une routine/activité présente dans le monde V2, ou null.
  (CastleBlock, LaneRow)? _v2LaneOf(String id) {
    final w = _wv2;
    if (w == null) return null;
    String? dom;
    for (final a in logic.state.activeActivities) {
      if (a.id == id) {
        dom = a.domainId;
        break;
      }
    }
    if (dom == null) return null;
    final c = w.byDomain[dom];
    if (c == null) return null;
    for (final l in c.lanes) {
      if (l.id == id) return (c, l);
    }
    return null;
  }

  bool _hasPending() => _pendingByRoutine.values.any((l) => l.isNotEmpty);

  void _evaluateHits(List<HabitHit> hits) {
    if (!_animatedLoaded || !_hitStreamSeen || widget.mobile) return;
    final today = yyyymmdd(DateTime.now());
    if (_animatedYmd != today) {
      // Changement de jour → on repart à zéro (les tours ne tirent que le jour courant).
      _animatedYmd = today;
      _animatedHitIds.clear();
      _pendingByRoutine.clear();
      _backlogProcessed = false;
    }
    // Hits du jour pas encore animés ni déjà en file.
    final fresh = <HabitHit>[];
    for (final h in hits) {
      if (yyyymmdd(h.ts) != today) continue;
      if (_animatedHitIds.contains(h.id)) continue;
      final q = _pendingByRoutine[h.habitId];
      if (q != null && q.contains(h.id)) continue;
      fresh.add(h);
    }

    if (!_backlogProcessed) {
      // Snapshot d'OUVERTURE : on accumule le BACKLOG (fenêtre 800 ms pour coalescer
      // un éventuel cache offline), puis on déclenche l'exploration auto.
      var added = false;
      for (final h in fresh) {
        final lane = _v2LaneOf(h.habitId);
        if (lane == null || !lane.$2.isRoutine) {
          _animatedHitIds.add(h.id); // non animable → marqué pour ne pas y revenir
          continue;
        }
        (_pendingByRoutine[h.habitId] ??= []).add(h.id);
        added = true;
      }
      if (added) _persistAnimated();
      if (added && mounted) setState(() {});
      _v2PrimeTimer?.cancel();
      _v2PrimeTimer = Timer(const Duration(milliseconds: 800), () {
        _backlogProcessed = true;
        if (_hasPending()) _v2DischargeBacklog();
      });
      return;
    }

    // LIVE (web ouvert) : tir SUR PLACE immédiat, une animation par hit.
    var fired = false;
    for (final h in fresh) {
      final lane = _v2LaneOf(h.habitId);
      _animatedHitIds.add(h.id);
      if (lane != null && lane.$2.isRoutine) {
        _v2OnRoutineValidated(h.habitId);
        fired = true;
      }
    }
    if (fired) _persistAnimated();
  }

  // Routine flammée la plus proche de _posV2.y dans la direction `dir`
  // (-1 = vers le haut / y décroissant, +1 = vers le bas), ou null.
  LaneRow? _nextPendingLane(int dir) {
    final w = _wv2;
    if (w == null) return null;
    LaneRow? best;
    var bestDist = 1 << 30;
    final curY = _posV2.y;
    for (final c in w.castles) {
      for (final l in c.lanes) {
        if (!l.isRoutine) continue;
        final q = _pendingByRoutine[l.id];
        if (q == null || q.isEmpty) continue;
        final dy = l.y - curY;
        if (dir < 0 && dy > 0) continue; // on monte : ignore ce qui est en dessous
        if (dir > 0 && dy < 0) continue; // on descend : ignore ce qui est au‑dessus
        final dist = dy.abs();
        if (dist < bestDist) {
          bestDist = dist;
          best = l;
        }
      }
    }
    return best;
  }

  // Centre la caméra sur la case `p` (suivi de l'avatar — AUTO uniquement).
  void _v2CenterOn(Point<int> p) {
    if (!_v2HCtrl.hasClients || !_v2VCtrl.hasClients) return;
    const slot = _kV2Slot;
    final tx = (p.x * slot + slot / 2 - _v2HCtrl.position.viewportDimension / 2)
        .clamp(0.0, _v2HCtrl.position.maxScrollExtent);
    final ty = (p.y * slot + slot / 2 - _v2VCtrl.position.viewportDimension / 2)
        .clamp(0.0, _v2VCtrl.position.maxScrollExtent);
    _v2HCtrl.animateTo(tx,
        duration: const Duration(milliseconds: 120), curve: Curves.linear);
    _v2VCtrl.animateTo(ty,
        duration: const Duration(milliseconds: 120), curve: Curves.linear);
  }

  // Marche l'avatar jusqu'à `target` (BFS), révèle le brouillard et suit la caméra.
  // Interruptible : sort tôt si l'utilisateur reprend la main (_v2UserControl).
  Future<void> _v2WalkTo(Point<int> target) async {
    final path = _bfsV2(_posV2, target);
    for (final step in path) {
      if (!mounted || _v2UserControl) return;
      setState(() {
        _posV2 = step;
        _revealAroundV2(step);
      });
      _v2CheckDomainEntry();
      _v2CenterOn(step);
      await Future.delayed(const Duration(milliseconds: 75));
    }
  }

  // EXPLORATION AUTO : décharge le backlog de flammes par balayage de proximité.
  // Monte d'abord (bas→haut), inverse en bout, fini quand plus aucune flamme.
  // Durée du boulet de tir en exploration auto (cinématique ralentie ; l'avatar
  // attend que le boulet ait atteint la routine avant d'enchaîner / de repartir).
  static const double _kV2ExploreBoltDur = 3.6; // s

  Future<void> _v2DischargeBacklog() async {
    if (_v2AutoExploring || _combatBusy || _v2Walking || widget.mobile) return;
    _v2AutoExploring = true;
    _v2UserControl = false;
    try {
      var dir = -1; // vers le haut d'abord
      var flips = 0;
      while (mounted && !_v2UserControl && _hasPending()) {
        final lane = _nextPendingLane(dir);
        if (lane == null) {
          if (++flips > 2) break; // plus rien d'atteignable dans les 2 sens
          dir = -dir;
          continue;
        }
        flips = 0;
        await _v2WalkTo(Point(lane.turretX - 1, lane.y));
        if (_v2UserControl || !mounted) break;
        final ids = _pendingByRoutine[lane.id];
        while (ids != null && ids.isNotEmpty && mounted && !_v2UserControl) {
          _fireV2Bolt(lane.dayX0 + 6, lane.y, lane.turretX,
              dur: _kV2ExploreBoltDur);
          _animatedHitIds.add(ids.removeAt(0));
          _persistAnimated();
          if (mounted) setState(() {}); // met à jour les flammes
          // Attend la fin de l'animation (boulet arrivé) avant le tir suivant
          // ou de repartir vers la prochaine routine.
          await Future.delayed(Duration(
              milliseconds: (_kV2ExploreBoltDur * 1000).round() + 300));
        }
      }
    } finally {
      _v2AutoExploring = false;
    }
  }

  // ── TEMPS RÉEL : minuteur d'activité (session ouverte) → assaut live ──
  StreamSubscription<List<Session>>? _sessionSub;
  bool _sessionsPrimed = false;
  final Set<String> _runningActs = {}; // activités dont le minuteur tourne
  // Tir périodique pendant qu'un minuteur tourne : -1 PV / 5 min (1 PV = 5 min de
  // retard sur le scorpion, cf. gold_engine.enemyHp). 1ᵉʳ tir = cinématique (blank).
  final Map<String, Timer> _actFireTimers = {};
  static const Duration _kActFireEvery = Duration(minutes: 5);

  void _subscribeSessions() {
    if (widget.mobile) return; // mode spectateur = web
    _sessionSub = sync.streamSessions().listen((sessions) {
      final running = <String>{
        for (final s in sessions)
          if (s.endAt == null) s.activityId
      };
      if (!_sessionsPrimed) {
        // Amorçage : un minuteur déjà en cours à l'ouverture → on lance l'assaut.
        _sessionsPrimed = true;
        for (final id in running) {
          _onTimerStart(id);
        }
        _runningActs
          ..clear()
          ..addAll(running);
        return;
      }
      // Démarrages frais → assaut ; arrêts → on coupe le tir périodique.
      for (final id in running.difference(_runningActs)) {
        _onTimerStart(id);
      }
      for (final id in _runningActs.difference(running)) {
        _onTimerStop(id);
      }
      _runningActs
        ..clear()
        ..addAll(running);
    });
  }

  void _onTimerStart(String activityId) {
    // 1ᵉʳ tir = cinématique (n'enlève rien), puis -1 PV toutes les 5 min.
    _enqueueTravel(activityId, blank: true);
    _actFireTimers[activityId]?.cancel();
    _actFireTimers[activityId] = Timer.periodic(_kActFireEvery, (_) {
      if (!mounted || !_runningActs.contains(activityId)) return;
      _enqueueTravel(activityId, blank: false); // tir -1 PV
    });
  }

  void _onTimerStop(String activityId) {
    _actFireTimers.remove(activityId)?.cancel();
  }

  void _enqueueTravel(String id, {bool blank = false}) {
    _travelQueue.add((id: id, blank: blank));
    _pumpTravelQueue();
  }

  // Un COMBAT (assaut/bataille/tir d'arrivée) est en cours → on ne joue PAS les
  // cinématiques déclenchées par le mobile (elles swappent _w/_pos et cassent tout).
  bool get _combatBusy =>
      _cineActive || _battleActive || _liveFiring || _simDefense;

  Future<void> _pumpTravelQueue() async {
    if (_traveling || _combatBusy) return; // combat en cours → la file attend
    if (_kWorldV2) {
      // Cinématique mobile sur la NOUVELLE map V2 (l'ancienne sert d'arène).
      _traveling = true;
      while (_travelQueue.isNotEmpty && mounted && !_combatBusy) {
        _v2OnRoutineValidated(_travelQueue.removeAt(0).id);
        await Future.delayed(const Duration(milliseconds: 450));
      }
      _traveling = false;
    } else {
      while (_travelQueue.isNotEmpty && mounted && !_combatBusy) {
        final next = _travelQueue.removeAt(0);
        await _travelToRoutine(next.id, blank: next.blank);
      }
    }
  }

  // Action mobile (routine validée / minuteur) → tir célébratoire de SA tourelle
  // sur la map V2 : on révèle le domaine et le canon de la ligne fait feu.
  void _v2OnRoutineValidated(String id) {
    final w = _wv2;
    if (w == null) return;
    String? dom;
    for (final a in logic.state.activeActivities) {
      if (a.id == id) {
        dom = a.domainId;
        break;
      }
    }
    if (dom == null) return;
    final c = w.byDomain[dom];
    if (c == null) return;
    LaneRow? lane;
    for (final l in c.lanes) {
      if (l.id == id) {
        lane = l;
        break;
      }
    }
    if (lane == null) return;
    // Révèle le domaine (pour voir le tir) sans bouger la caméra.
    final b = c.bounds;
    setState(() {
      for (var yy = b.top; yy < b.top + b.height; yy++) {
        for (var xx = b.left; xx < b.left + b.width; xx++) {
          _revealed.add('${xx}_$yy');
        }
      }
    });
    _fireV2Bolt(lane.dayX0 + 6, lane.y, lane.turretX);
  }

  // ── CINÉMATIQUE D'ARRIVÉE (S3) : la tour charge 1 flamme, vise, tire, −1 ──
  bool _liveFiring = false;
  int _liveRow = 0;
  int _liveFlames = 1; // flamme(s) chargée(s) = nb de validations du jour
  double _liveAim = 0; // 0..1 : charge + visée
  _CineFb? _liveFb; // boulet du tir d'arrivée
  Offset? _liveFlashAt; // case d'impact (flash)
  int _liveFlashUntilMs = 0;
  Completer<void>? _liveDone;

  // Cible du tir : la COLONNE 19 (jour courant) de la ligne de la routine — vers
  // le jardin (droite), PAS le château (gauche) où se tient l'avatar (col 11).
  Offset _liveTarget(int row) => Offset(19, row.toDouble());

  void _simulateLive(double dt) {
    if (_liveFb == null) {
      _liveAim += dt / _kTurretAimDur; // charge + visée
      if (_liveAim >= 1.0) {
        _liveAim = 1.0;
        final tgt = _liveTarget(_liveRow);
        final arc = ((12 - tgt.dx).abs() * 0.4).clamp(1.2, 5.0).toDouble();
        // Départ au BOUT du canon (décalé vers la cible = droite), pas au centre.
        final sx = 12 + 0.5 * (tgt.dx > 12 ? 1 : -1);
        _liveFb = _CineFb(
            _kLiveFbDur, sx, _liveRow - 0.25, tgt.dx, tgt.dy, arc, 'live');
      }
    } else {
      _liveFb!.t += dt / _liveFb!.dur;
      if (_liveFb!.t >= 1.0) {
        _liveFlashAt = Offset(_liveFb!.tx, _liveFb!.ty);
        _liveFlashUntilMs = _gameMs + 5000; // 💥 reste 5 s puis disparaît
        // Impact : -1 sur l'araignée du jour (col 19). Le rendu affiche 💥 si elle
        // tombe à 0, sinon le nombre décrémenté. Tir CINÉMATIQUE (_liveBlank) → on
        // ne retire RIEN (1ᵉʳ tir d'une session-minuteur d'activité).
        if (_liveDecKey != null && !_liveBlank) {
          _toileDec[_liveDecKey!] = (_toileDec[_liveDecKey!] ?? 0) + 1;
        }
        _liveBlank = false;
        _liveDecKey = null;
        _liveFb = null;
        _liveFiring = false;
        _liveDone?.complete();
        _liveDone = null;
      }
    }
  }

  // Décréments visuels du tir d'arrivée par case ('routineId_colIndex' → -N).
  // Quand le nombre tombe à 0, l'araignée meurt (💥 persistante la journée).
  final Map<String, int> _toileDec = {};
  String? _liveDecKey; // case (col 19) visée par le tir d'arrivée en cours
  bool _liveBlank = false; // tir purement cinématique (ne retire aucun PV)

  // Nb de toiles NON détruites (restantes) d'un domaine → gate la cinématique :
  // on ne (re)joue que tant qu'il reste des toiles.
  int _domainRemainingToiles(String domId) {
    var rem = 0;
    for (final a in logic.state.activeActivities) {
      if (a.domainId != domId) continue;
      final lane = a.isHabit
          ? logic.routineWeekTokens(a.id)
          : logic.activityTimeTokens(a.id);
      if (lane.isEmpty) continue;
      final toiles = lane.where((t) => t.type == 'spider').length;
      final flames = lane.where((t) => t.type == 'flame').length;
      rem += (toiles - flames).clamp(0, toiles).toInt();
    }
    return rem;
  }

  // ── BATAILLE HEBDO (jardin) : vagues colonne par colonne sur 7 jours glissants ──
  bool _battleActive = false;
  int _battleCol = 0; // colonne-jour en cours (0..6)
  double _battleColT = 0;
  bool _battleVolleyDone = false;
  final Set<int> _battleFaded = {}; // colonnes déjà nettoyées (estompées)
  final List<_Beam> _battleBeams = []; // traits en vol
  List<({int row, List tokens})> _battleRows = const [];
  Completer<void>? _battleDone;
  static const double _kBattleColDur = 1.0; // s par colonne (vague)
  // Toggle « à l'arrivée » : rejouer la SEMAINE (7 colonnes, lourd, 1×/jour) ou
  // seulement AUJOURD'HUI (dernière colonne). Défaut = aujourd'hui.
  bool _replayWeek = false;
  DateTime? _weeklyBattleAt; // dernier jour où la bataille HEBDO a été jouée
  bool get _weeklyPlayedToday {
    final a = _weeklyBattleAt;
    if (a == null) return false;
    final n = DateTime.now();
    return a.year == n.year && a.month == n.month && a.day == n.day;
  }

  // weekly=true → 7 colonnes (jours glissants) ; false → seulement aujourd'hui
  // (dernière colonne, index 6).
  Future<void> _runGardenBattle({required bool weekly}) async {
    final w = _w;
    if (!mounted || w == null) return;
    final mid = w.rows ~/ 2;
    final routines = _domTopRoutines();
    final times = _domTopTimeActivities();
    final rows = <({int row, List tokens})>[];
    for (var i = 0; i < routines.length; i++) {
      rows.add((
        row: mid - routines.length + i,
        tokens: logic.routineWeekTokens(routines[i].id)
      ));
    }
    for (var j = 0; j < times.length; j++) {
      rows.add(
          (row: mid + 1 + j, tokens: logic.activityTimeTokens(times[j].id)));
    }
    if (rows.isEmpty) return;
    _battleRows = rows;
    _battleCol = weekly ? 0 : 6; // aujourd'hui = dernière colonne-jour
    _battleColT = 0;
    _battleVolleyDone = false;
    _battleFaded.clear();
    _battleBeams.clear();
    _battleDone = Completer<void>();
    setState(() => _battleActive = true);
    await _battleDone!.future;
  }

  void _simulateBattle(double dt) {
    _battleBeams.removeWhere((b) => _gameMs - b.bornMs > 240);
    // Volée au début de chaque colonne : un trait par ligne ayant un token là.
    if (!_battleVolleyDone && _battleColT > 0.12) {
      for (final r in _battleRows) {
        if (_battleCol < r.tokens.length &&
            r.tokens[_battleCol].type != 'empty') {
          _battleBeams.add(_Beam(12, r.row.toDouble(),
              (13 + _battleCol).toDouble(), r.row.toDouble(), _gameMs));
        }
      }
      _battleVolleyDone = true;
    }
    _battleColT += dt;
    if (_battleColT >= _kBattleColDur) {
      _battleFaded.add(_battleCol); // colonne nettoyée → s'estompe
      _battleCol++;
      _battleColT = 0;
      _battleVolleyDone = false;
      if (_battleCol >= 7) {
        _battleActive = false;
        _battleDone?.complete();
        _battleDone = null;
      }
    }
  }

  // Joue le tir d'arrivée et attend sa fin (avatar déjà posé en col 11).
  // [blank] = tir purement cinématique (ne retire aucun PV) — utilisé pour le
  // 1ᵉʳ tir d'une session-minuteur d'activité.
  Future<void> _fireArrival(String routineId, int row, {bool blank = false}) async {
    if (!mounted) return;
    _liveRow = row;
    _liveFlames = 1; // une seule flamme au-dessus du canon pour cette cinématique
    _liveDecKey = '${routineId}_6'; // col 19 = index 6 (jour courant)
    _liveBlank = blank;
    _liveAim = 0;
    _liveFb = null;
    _liveDone = Completer<void>();
    setState(() => _liveFiring = true);
    await _liveDone!.future;
    if (mounted && !blank) _toast('✅ −1 — frappée !', _interiorColor);
  }

  // Copies orientées d'un boulet (tête + traînée) — partagé tir support/arrivée.
  // `centerD` (closure locale du board) projette une case en pixels.
  List<Widget> _fbWidgets(
      _CineFb fb, double slot, Offset Function(double, double) centerD) {
    final widgets = <Widget>[];
    for (int i = 6; i >= 0; i--) {
      final u = i == 0 ? fb.t : fb.t - i * 0.05;
      if (u <= 0) continue;
      final ct = centerD(fb.xAt(u), fb.yAt(u));
      final f = 1 - i / 7.0;
      final sz = slot * (0.10 + 0.20 * f);
      final col = i == 0
          ? const Color(0xFFFF8A3D)
          : Color.lerp(const Color(0xFFFFE08A), const Color(0xFFFF5A2A), 1 - f)!
              .withOpacity(0.22 + 0.45 * f);
      widgets.add(Positioned(
        left: ct.dx - slot / 2,
        top: ct.dy - slot / 2,
        width: slot,
        height: slot,
        child: Center(
          child: Transform.rotate(
            angle: fb.angleAt(u) + _kFbIconOffset,
            child: SvgPicture.asset('assets/icons/fireball.svg',
                width: sz,
                height: sz,
                colorFilter: ColorFilter.mode(col, BlendMode.srcIn)),
          ),
        ),
      ));
    }
    return widgets;
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

  // Peuple la zone farm avec tes VRAIS ennemis backlog (routines/activités/tâches
  // négligées) — pas des pests génériques. WYSIWYG : PAS de cap, on affiche TOUT le
  // backlog (1 case = 1 nuisible), purgé quand l'item est rattrapé (PV 0).
  // Côté JARDIN (farm) = côté de la PORTE opposé au château. Robuste au miroir :
  // la grande map est mirrorWorldX (château à GAUCHE, jardin à DROITE), donc on
  // ne peut pas se fier à `x < castle.x`.
  bool _isFarmX(UnifiedWorld w, int x) {
    final gateX = w.gate.isEmpty
        ? w.cols ~/ 2
        : int.parse(w.gate.first.split('_')[0]);
    return w.castle.x < gateX ? x > gateX : x < gateX;
  }

  void _populateFarm() {
    final w = _w, t = _t;
    if (w == null || t == null) return;
    _farmPests.removeWhere((_, e) => logic.enemyHp(e.type, e.id) <= 0);
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
    // la zone (pas un cluster à l'entrée).
    final free = <String>[];
    for (int y = 0; y < w.rows; y++) {
      for (int x = 0; x < w.cols; x++) {
        if (!_isFarmX(w, x)) continue;
        if (w.at(x, y) != UwTile.floor || w.hasBush(x, y)) continue;
        final id = '${x}_$y';
        if (_farmPests.containsKey(id)) continue;
        if (x == _pos.x && y == _pos.y) continue;
        free.add(id);
      }
    }
    free.shuffle(Random(t.seed));
    // WYSIWYG : tout le backlog (borné seulement par le nb de cases libres).
    for (var i = 0; i < backlog.length && i < free.length; i++) {
      _farmPests[free[i]] = (type: backlog[i].type, id: backlog[i].id);
    }
  }

  // Combat backlog : aller au contact d'un ennemi (= un vrai item négligé) ouvre la
  // carte de combat en ENCART À DROITE (carte visible derrière). FAIRE LE TRAVAIL
  // fait fondre l'ennemi ; PV 0 → il disparaît de la map.
  Future<void> _backlogCombat(String tileId, String type, String id) async {
    // MONDE V2 desktop : le combat s'affiche DANS le jardin du domaine (in‑place),
    // plus en colonne à droite. Mobile garde l'écran plein (cf. rendu).
    final p = tileId.split('_');
    final dom = (_kWorldV2 && !widget.mobile && p.length == 2)
        ? _domainAtTileV2(int.tryParse(p[0]) ?? -1, int.tryParse(p[1]) ?? -1)
        : null;
    setState(() {
      _combat = (type: type, id: id, tileId: tileId);
      if (dom != null) _gardenPanel = (domainId: dom, mode: 'combat');
    });
  }

  // Domaine dont la bande contient la case (x,y), ou null.
  String? _domainAtTileV2(int x, int y) {
    final w = _wv2;
    if (w == null) return null;
    for (final c in w.castles) {
      final b = c.bounds;
      if (x >= b.left && x < b.left + b.width && y >= b.top && y < b.top + b.height) {
        return c.domainId;
      }
    }
    return null;
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
          // MONDE V2 : retirer le serpent du jardin + rafraîchir le calendrier.
          if (_kWorldV2 && _v2Pests.containsKey(c.tileId)) {
            _v2Pests.remove(c.tileId);
            _populateV2Calendar();
          }
        }
        setState(() {});
      },
      onLaunchedTimer: () {
        // Minuteur lancé → on ferme l'encart et on quitte la map.
        // Embarqué (onglet du hub) : pas de pop (fermerait tout le bottom sheet).
        if (!widget.embedded && mounted) Navigator.pop(context);
      },
      onClose: _closeCombat,
    );
  }

  // Ferme l'encart de combat (sans fermer la map) ; retire l'ennemi si vaincu.
  void _closeCombat() {
    final c = _combat;
    if (c == null || !mounted) return;
    if (logic.enemyHp(c.type, c.id) <= 0) _farmPests.remove(c.tileId);
    setState(() {
      _combat = null;
      if (_gardenPanel?.mode == 'combat') _gardenPanel = null;
    });
  }

  // ── Panneau JARDIN in‑place ────────────────────────────────────────────────
  // Recouvre la bande `gardenRect` du domaine de l'avatar : combat (BacklogCombatPanel)
  // ou mini‑app dashboard des routines/activités du domaine.
  Widget _gardenPanelV2(WorldLayout w) {
    final gp = _gardenPanel!;
    final c = w.byDomain[gp.domainId];
    if (c == null) return const SizedBox.shrink();
    final g = c.gardenRect;
    final col = domainColor(gp.domainId, logic.state.activeDomains) ?? _kGold;
    return Positioned(
      left: g.left * _kV2Slot,
      top: g.top * _kV2Slot,
      width: g.width * _kV2Slot,
      height: g.height * _kV2Slot,
      child: Material(
        color: const Color(0xFF0E1714),
        elevation: 10,
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: (gp.mode == 'combat' && _combat != null)
              ? _combatPanel()
              : _routineDashV2(c, col),
        ),
      ),
    );
  }

  Widget _routineDashV2(CastleBlock c, Color col) {
    final acts = logic.activitiesOfDomain(c.domainId);
    final shur = _gardenShurikensByDomain[c.domainId] ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        color: col.withOpacity(.22),
        child: Row(children: [
          Expanded(
            child: Text(_domainName(c.domainId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13)),
          ),
          if (shur > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('🗡️ $shur',
                  style: const TextStyle(
                      color: Color(0xFFFFC83D),
                      fontWeight: FontWeight.w900,
                      fontSize: 12)),
            ),
          InkWell(
            onTap: () => setState(() {
              _gardenPanel = null;
              _combat = null;
            }),
            child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, color: Colors.white60, size: 18)),
          ),
        ]),
      ),
      Expanded(
        child: acts.isEmpty
            ? const Center(
                child: Text('Aucune routine ici',
                    style: TextStyle(color: Colors.white38, fontSize: 12)))
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [for (final a in acts) _dashRowV2(a, col)],
              ),
      ),
    ]);
  }

  Widget _dashRowV2(Activity a, Color col) {
    final isRoutine = a.isHabit;
    final pc = logic.habitPeriod(a);
    final streak = isRoutine ? logic.habitCurrentStreak(a.id) : 0;
    return InkWell(
      onTap: () async {
        if (isRoutine) {
          await showRoutineSheet(context,
              logic: logic, habitId: a.id, day: DateTime.now());
        } else {
          await showActivitySheet(context, logic, a.id);
        }
        if (mounted) setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(children: [
          Text(isRoutine ? '🕷️' : '🦂', style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12.5)),
                  Text(
                      '${pc.done}/${pc.target}'
                      '${isRoutine && streak > 0 ? '  ·  🔥$streak' : ''}',
                      style: TextStyle(
                          color: Colors.white.withOpacity(.55), fontSize: 11)),
                ]),
          ),
          // CTA : routine → +1 (incHabit) ; activité‑temps → minuteur (start).
          if (isRoutine)
            _dashCta(Icons.add, col, () {
              logic.incHabit(a.id, 1, DateTime.now());
              if (mounted) setState(() {});
            })
          else
            _dashCta(Icons.play_arrow_rounded, col, () {
              // Le onChange du web ne pushe PAS → on persiste la session à la main
              // dans Firestore pour que le téléphone la voie (→ Live Activity).
              final openBefore =
                  logic.state.sessions.where((s) => s.endAt == null).toList();
              logic.start(a.id);
              for (final s in openBefore) {
                sync.saveSession(s); // elles viennent de recevoir endAt
              }
              if (logic.state.sessions.isNotEmpty) {
                sync.saveSession(logic.state.sessions.last); // nouvelle session ouverte
              }
              _toast('⏱️ Chrono lancé — ${a.name}', col);
              if (mounted) setState(() {});
            }),
        ]),
      ),
    );
  }

  Widget _dashCta(IconData icon, Color col, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: col.withOpacity(.25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: col.withOpacity(.6)),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      );

  // ── Séquence CANON (clic sur rampe ☢️) ─────────────────────────────────────
  // marche sur la rampe → spin ☢️ 2 s + lève le canon → tire si flammes (sinon
  // monte/descend) → bascule le jardin en dashboard de la lane.
  // Marche pas à pas vers `target` (sans bail sur le contrôle user — séquence pilotée).
  Future<void> _v2StepTo(Point<int> target) async {
    final path = _bfsV2(_posV2, target);
    for (final step in path) {
      if (!mounted) return;
      setState(() {
        _posV2 = step;
        _revealAroundV2(step);
      });
      _v2CheckDomainEntry();
      await Future.delayed(const Duration(milliseconds: 75));
    }
  }

  // Anime le lever du canon `id` de `from`→`to` (0..1) sur `ms` (~25 fps).
  Future<void> _animateCannonRaise(
      String id, double from, double to, int ms) async {
    const fps = 25;
    final steps = (ms * fps ~/ 1000).clamp(1, 1000);
    for (var i = 0; i <= steps; i++) {
      if (!mounted) return;
      final t = i / steps;
      setState(() => _cannonRaise[id] = from + (to - from) * t);
      await Future.delayed(Duration(milliseconds: ms ~/ steps));
    }
  }

  // Séquence CANON en 3 phases (tap sur la rampe ☢️ en `x,y` ; canon en `x+1,y`) :
  //  1) l'avatar arrive 2 cases à GAUCHE du canon (= 1 case à gauche de la rampe),
  //     PAS dessus → la rampe tourne sur elle‑même et le canon se LÈVE (opérationnel).
  //  2) l'avatar MONTE sur la rampe.
  //  3) la cinématique de chargement/tir se lance « comme en mode combat ».
  Future<void> _onCannonRamp(int x, int y) async {
    final w = _wv2;
    if (w == null || _v2Walking) return;
    _v2Walking = true;
    try {
      final dom = _domainAtTileV2(x, y);
      final turretId = '${x + 1}_$y';
      // — Phase 1 : arriver 2 cases à gauche du canon (1 à gauche de la rampe).
      await _v2StepTo(Point(x - 1, y));
      if (!mounted) return;
      // la rampe TOURNE et le canon se LÈVE progressivement, synchronisés (~2 s).
      setState(() {
        _cannonSpinAt = Point(x, y);
        _cannonSpinStartMs = _gameMs;
        _cannonRaise[turretId] = 0;
      });
      await _animateCannonRaise(turretId, 0.0, 1.0, 2000);
      if (!mounted) return;
      // La rotation de la rampe s'arrête, puis on laisse 0,5 s avant que l'avatar
      // ne monte dessus (le canon reste relevé).
      setState(() => _cannonSpinAt = null);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      // — Phase 2 : l'avatar monte sur la rampe.
      await _v2StepTo(Point(x, y));
      if (!mounted) return;
      // — Phase 3 : chargement/visée puis tir « mode combat » (volée vers le jour).
      final tur = _v2Turret[turretId];
      final rid = _v2TurretRoutineId[turretId];
      final flames = (tur?.charger ?? 0) > 0
          ? (tur?.charger ?? 0)
          : (rid != null ? (_pendingByRoutine[rid]?.length ?? 0) : 0);
      if (flames > 0) {
        await Future.delayed(const Duration(milliseconds: 600)); // charge/visée
        final n = flames.clamp(1, 5);
        for (var i = 0; i < n; i++) {
          if (!mounted) return;
          _fireV2Bolt(x + 8, y, x + 1, dur: 2.2); // boulet en arc + 💥 à l'impact
          await Future.delayed(const Duration(milliseconds: 320));
        }
        await Future.delayed(const Duration(milliseconds: 900));
      }
      if (!mounted) return;
      // — Fin : le canon redescend (animé) + le jardin bascule en dashboard.
      await _animateCannonRaise(turretId, 1.0, 0.0, 450);
      if (!mounted) return;
      setState(() {
        _cannonRaise.remove(turretId);
        if (dom != null) _gardenPanel = (domainId: dom, mode: 'routineDash');
      });
    } finally {
      _v2Walking = false;
    }
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

  // Tap sur une tour → ouvre le sheet de la routine ou de l'activité. La heatmap
  // du sheet (détail par jour) est gardée : complémentaire du château (qui résume
  // par semaine).
  Future<void> _openRowSheet(String id, String kind) async {
    if (kind == 'spider') {
      await showRoutineSheet(context,
          logic: logic, habitId: id, day: DateTime.now());
    } else {
      await showActivitySheet(context, logic, id);
    }
    if (mounted) setState(() {});
  }

  // Aspect des tours. SEULEMENT pendant la cinématique/combat : toutes prennent
  // le canon DCA (anti-aircraft). Sinon : hebdo/mensuelle = DCA, quotidienne +
  // activités-temps = turret.
  String _turretIcon(String id, String kind) {
    if (_tdMode) return 'assets/icons/anti-aircraft-gun.svg';
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

  // Rangée de jusqu'à `maxFlames` petites flammes (= jours-flammes de la semaine)
  // au-dessus de la tour pendant la cinématique : les `charge` premières (0..1)
  // sont allumées, le reste est en attente (éteint). Remplace le chargeur.
  Widget _cineFlameRow(int maxFlames, int lit, double slot) {
    if (maxFlames <= 0) return SizedBox(height: slot * 0.18);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < maxFlames; i++)
          Opacity(
            opacity: i < lit ? 1.0 : 0.22,
            child: Text('🔥', style: TextStyle(fontSize: slot * 0.2)),
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
    list.sort((a, b) => b.active.compareTo(a.active)); // tri par activité /30j
    return list; // TOUTES les routines du domaine (plus de cap)
  }

  // TOUTES les activités-TEMPS (type=time) du domaine courant (tri par activité).
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
    return list; // TOUTES les activités-temps du domaine (plus de cap)
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
    // Re-tap de la case courante : porte de sortie > araignée > backlog > grotte.
    if (x == p.x && y == p.y) {
      if (_inInterior && _exitDoor != null && _exitDoor!.x == x && _exitDoor!.y == y) {
        _exitInterior();
      } else if (isSpider) {
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
      if (_inInterior && !_revealed.contains(tileId)) return;
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
      if (_inInterior && _exitDoor != null && _exitDoor!.x == x && _exitDoor!.y == y) {
        _exitInterior();
      } else if (isSpider) {
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
          if (widget.mobile && _inInterior) ...[
            // Intérieur d'un domaine : bouton retour vers la carte + nom + changer.
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              onPressed: _exitInterior,
            ),
            const SizedBox(width: 8),
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
          ] else if (widget.mobile) ...[
            // Carte explorable (overworld) : marche jusqu'au boss d'un domaine
            // pour entrer dans son intérieur (calendrier).
            const Text('🌍 Monde',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
            const SizedBox(width: 8),
            Text('explore · combats · domaines',
                style:
                    TextStyle(color: Colors.white.withOpacity(.4), fontSize: 11)),
            const Spacer(),
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
          // Embarqué (onglet) : pas de croix (rien à fermer dans un onglet).
          if (!widget.embedded)
            IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context)),
        ]),
      ),
      Flexible(
        child: (_kWorldV2 && !_inInterior)
            ? (_wv2 == null
                ? const Center(
                    child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(color: _kBlue)))
                : Stack(children: [
                    Positioned.fill(child: _contentV2()),
                    Positioned(
                        top: 10,
                        right: 10,
                        child: _miniMapV2(maxSide: widget.mobile ? 120 : 160)),
                    if (_combat != null)
                      // Écran étroit : le combat occupe tout l'écran. Desktop : il
                      // s'affiche IN‑PLACE dans le jardin (cf. _contentV2) ; on ne
                      // garde la colonne 340px qu'en repli (domaine introuvable).
                      widget.mobile
                          ? Positioned.fill(
                              child: Material(
                                color: const Color(0xFF0E1714),
                                child: SafeArea(child: _combatPanel()),
                              ),
                            )
                          : (_gardenPanel?.mode == 'combat'
                              ? const SizedBox.shrink()
                              : Positioned(
                                  top: 0,
                                  bottom: 0,
                                  right: 0,
                                  width: 340,
                                  child: Material(
                                    color: const Color(0xFF0E1714),
                                    child: _combatPanel(),
                                  ),
                                )),
                  ]))
            : ((_loading || t == null || w == null)
                ? const Center(
                    child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(color: _kBlue)))
                : _content(t, w)),
      ),
      if (!_kWorldV2 && !_loading && t != null && !widget.mobile) _siegeBar(t),
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
        // Panneau d'actions à gauche — masqué en plein écran (_kMapFullscreen),
        // quand le combat est ouvert (place), ET sur mobile (calendrier seul).
        if (!_kMapFullscreen && _combat == null && !widget.mobile)
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
          // Grande map : plein espace (hauteur bornée → le board se dimensionne
          // pour remplir). Mobile/intérieur : scroll vertical (calendrier).
          child: (widget.mobile || _inInterior)
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: _board(t, w),
                )
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Center(child: _board(t, w)),
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
            // Embarqué (onglet) : pas de « ✕ Fermer » (fermerait le bottom sheet).
            if (!widget.embedded)
              pill('✕ Fermer', Colors.white70,
                  () => Navigator.of(context).maybePop()),
          ],
          if (_inInterior && !widget.mobile) ...[
            if (!_tdMode && !_simDefense)
              pill('🛡️ Simuler la défense', const Color(0xFF4FA3FF),
                  _startSimDefense),
            // Rejoue la cinématique complète d'assaut (prépa → nettoyage → attaque).
            if (!_tdMode && !_cineActive)
              pill('⚔️ Lancer l\'assaut', const Color(0xFFFF8A3D), _startCine),
            // ARC : pendant l'attaque, le ninja s'arrête 5 s et tire 3 flèches/s.
            if (_cineAttack)
              pill(_ninjaBow ? '🏹 Arc en cours…' : '🏹 Tirer à l\'arc', _kGold,
                  () {
                if (!_ninjaBow) {
                  setState(() {
                    _ninjaBow = true;
                    _bowDur = 0;
                    _bowArrowT = 0;
                  });
                }
              }, on: _ninjaBow),
            pill('🃏 Deck', _interiorColor.withOpacity(.85), _showAttackDeck),
            pill('🚪 Sortir de la grotte', _interiorColor.withOpacity(.7),
                _tdMode ? () {} : _exitInterior),
          ],
          // Toggle « à l'arrivée » : revoir la semaine (1×/jour) ou aujourd'hui.
          if (!widget.mobile)
            pill(
                _replayWeek ? '🔁 Revoir : semaine' : '🔁 Revoir : aujourd\'hui',
                const Color(0xFF8E7CC3),
                () => setState(() => _replayWeek = !_replayWeek),
                on: _replayWeek),
          // TEST (S2) : simule une validation → l'avatar voyage vers la routine.
          if (!widget.mobile)
            pill('🤖 Voyage test', const Color(0xFF66BB6A), () {
              final id = _firstTravelRoutineId();
              if (id != null) {
                _travelToRoutine(id);
              } else {
                _toast('Aucune routine quotidienne à viser.', Colors.white54);
              }
            }),
          if (!_inInterior) ...[
            pill('🕳️ Entrer dans la grotte', const Color(0xFF1E8E7E),
                _quickEnter),
            // TEST : force la grotte « occupée » → cadre d'assaut/cinématique.
            pill('🕳️🕷️ Entrer (grotte occupée)', _kEnemy,
                () => _quickEnter(forceOccupied: true)),
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
                    : 'PHASE 1 — 🕷️ garnison ennemie $_garrison · sbires lâchés ${_sbires.length} · 🚪 ${((_gateHp / _gateHpMax) * 100).round()}% · 🗼 ${_turrets.length} (1 tir = 1 mort, gratuit)')
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
      // Grande map (overworld) : on REMPLIT l'espace dispo (largeur ET hauteur),
      // cases carrées, pour une carte la plus grande possible. Intérieur : largeur.
      final slot = widget.mobile
          ? 36.0
          : _inInterior
              // -2 px de marge : évite le débordement sous‑pixel de la Row
              // [grille + panneau de noms] (RenderFlex « RIGHT OVERFLOWED »).
              ? ((c.maxWidth - nameW - 2) / w.cols).clamp(22.0, 46.0)
              : (() {
                  final byW = c.maxWidth / w.cols;
                  // Hauteur non bornée (rare) → on retombe sur la largeur.
                  final byH = c.maxHeight.isFinite ? c.maxHeight / w.rows : byW;
                  return (byW < byH ? byW : byH).clamp(22.0, 200.0);
                })();
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
      // Calendrier CENTRÉ sur midY (ligne de spawn château/araignée/avatar) :
      // routines au-dessus (finissent à midY-1), activités en dessous (à partir
      // de midY+1). La ligne midY reste vide = la ligne de combat.
      final mid = w.rows ~/ 2;
      final routineRow0 = mid - topRoutines.length; // 1ère routine
      final timeRow0 = mid + 1;
      final allRows = [
        for (var i = 0; i < topRoutines.length; i++)
          (
            row: routineRow0 + i,
            lane: lanes[i],
            fill: fills[i],
            r: topRoutines[i],
            kind: 'spider',
            heat: logic.routineWeeklyHeatmap(topRoutines[i].id)
          ),
        for (var j = 0; j < topTime.length; j++)
          (
            row: timeRow0 + j,
            lane: timeLanes[j],
            fill: timeFills[j],
            r: topTime[j],
            kind: 'scorpion',
            heat: logic.activityTimeWeeklyHeatmap(topTime[j].id)
          ),
      ];
      // Cibles déjà éliminées (clés) + tir courant (tour → cible).
      // Toiles/nuisibles déjà nettoyés : pendant le nettoyage = ceux déjà tirés ;
      // pendant l'attaque = TOUS (ils restent supprimés, ne réapparaissent pas).
      final cineCleared = _cineActive
          ? _cineShots
              .take(_cineClearing ? _cineClearIndex : _cineShots.length)
              .map((s) => s.key)
              .toSet()
          : const <String>{};
      final cineCurShot =
          _cineClearing && _cineClearIndex < _cineShots.length
              ? _cineShots[_cineClearIndex]
              : null;
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
                // Labels des jours (L M M J V S D) — masqués en mode combat
                // (visibilité : seules toiles + tours restent).
                if (!_cineAttack)
                  for (var d = 0; d < 7; d++)
                    () {
                    final c0 = centerD(13.0 + d, (routineRow0 - 1).toDouble());
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
                // TOUR à COLONNE 12 — une par ligne (entre château et jours).
                for (var ei = 0; ei < allRows.length; ei++)
                  () {
                    final e = allRows[ei];
                    final charge = _cineCharge(ei); // 0..1 charge cinématique
                    final flameMax =
                        e.lane.where((t) => t.type == 'flame').length;
                    // SEULES les tours ayant ≥1 flamme sur leur ligne se
                    // transforment (DCA) et combattent. Les autres restent
                    // normales (vie + chargeur, icône turret) pendant la ciné.
                    // Tir d'ARRIVÉE (S3) : la tour de la routine validée se
                    // TRANSFORME aussi en canon (DCA) pour lancer le boulet.
                    final liveHere = _liveFiring && e.row == _liveRow;
                    final cineTurret = (_cineActive && flameMax > 0) || liveHere;
                    // Une flamme « touche » la tour à des paliers réguliers :
                    // la tour ne change QU'À l'arrivée de chaque flamme.
                    final arrived = flameMax > 0
                        ? (charge * flameMax).floor().clamp(0, flameMax)
                        : 0;
                    final cineFlame = liveHere
                        ? 1.0
                        : (cineTurret && flameMax > 0 ? arrived / flameMax : 0.0);
                    // État de tir (phase attaque) : flammes restantes + visée.
                    final tu = _cineAttack ? _cineTurretByRow[e.row] : null;
                    // Flammes affichées : arrivée = flamme(s) du jour ; attaque =
                    // munitions restantes ; sinon = charge ciné.
                    final flameRowMax = liveHere ? _liveFlames : flameMax;
                    final lit = liveHere
                        ? _liveFlames
                        : (tu != null ? tu.ammo.clamp(0, flameMax) : arrived);
                    // Visée du barillet :
                    //  - attaque : le canon PLONGE puis se RELÈVE (animation lente)
                    //    avant chaque tir ;
                    //  - nettoyage : inclinaison vers la toile-château ciblée.
                    final double headAngle;
                    if (tu != null && tu.aim >= 0) {
                      headAngle = -sin(pi * tu.aim) * _kBarrelAimDip;
                    } else if (liveHere) {
                      headAngle =
                          -sin(pi * _liveAim.clamp(0.0, 1.0)) * _kBarrelAimDip;
                    } else if (cineCurShot != null &&
                        cineCurShot.turretRow == e.row &&
                        cineCurShot.tx < 12) {
                      headAngle =
                          _kBarrelNatural * (cineCurShot.tx / 11).clamp(0.0, 1.0);
                    } else {
                      headAngle = 0.0;
                    }
                    final c0 = centerD(12, e.row.toDouble());
                    return Positioned(
                      left: c0.dx - slot / 2,
                      top: c0.dy - slot / 2,
                      width: slot,
                      height: slot,
                      // Tap (barres + icône) → ouvre le sheet routine / activité.
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _openRowSheet(e.r.id, e.kind),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Cinématique : jusqu'à N petites flammes (= jours-
                            // flammes de la semaine) s'allument à mesure que la
                            // tour charge → REMPLACENT le chargeur ; la jauge de
                            // vie DISPARAÎT. Hors cinématique : vie + chargeur.
                            if (cineTurret)
                              _cineFlameRow(flameRowMax, lit, slot)
                            else ...[
                              _webLifeBar(e.r.charger / 7, slot),
                              SizedBox(height: slot * 0.04),
                              _webSegBar(7 - e.r.charger, _kCharge, slot),
                            ],
                            SizedBox(height: slot * 0.04),
                            // Turret — s'embrase (orange + glow) en chargeant.
                            Container(
                              decoration: cineFlame > 0
                                  ? BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                            color: const Color(0xFFFF8A3D)
                                                .withOpacity(.7 * cineFlame),
                                            blurRadius: slot * 0.5 * cineFlame,
                                            spreadRadius:
                                                slot * 0.08 * cineFlame),
                                      ])
                                  : null,
                              // Se RETOURNE vers le château (gauche) seulement au
                              // moment du NETTOYAGE (après que toutes les tours
                              // ont été renforcées). En prépa : sens naturel.
                              child: Transform.flip(
                                // Tir d'arrivée = vers le jardin (droite) → PAS de
                                // retournement (sinon le canon vise l'avatar à gauche).
                                flipX: cineTurret &&
                                    !liveHere &&
                                    (_cineClearing || _cineAttack),
                                child: () {
                                  final tint = ColorFilter.mode(
                                      Color.lerp(
                                          e.r.charger == 0
                                              ? _kEnemy
                                              : _interiorColor,
                                          const Color(0xFFFF8A3D),
                                          cineFlame)!,
                                      BlendMode.srcIn);
                                  if (!cineTurret) {
                                    return SvgPicture.asset(
                                        _turretIcon(e.r.id, e.kind),
                                        width: slot * 0.5,
                                        height: slot * 0.5,
                                        colorFilter: tint);
                                  }
                                  // DCA en 2 morceaux : base FIXE + tête
                                  // (barillet + monture) — superposées (visée à
                                  // venir : on incline la tête autour de la
                                  // monture).
                                  return SizedBox(
                                    width: slot * 0.5,
                                    height: slot * 0.5,
                                    child: Stack(children: [
                                      SvgPicture.asset(
                                          'assets/icons/aa-base.svg',
                                          width: slot * 0.5,
                                          height: slot * 0.5,
                                          colorFilter: tint),
                                      Transform.rotate(
                                        angle: headAngle,
                                        alignment: _kBarrelPivot,
                                        child: SvgPicture.asset(
                                            'assets/icons/aa-head.svg',
                                            width: slot * 0.5,
                                            height: slot * 0.5,
                                            colorFilter: tint),
                                      ),
                                    ]),
                                  );
                                }(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }(),
                // TOKENS du tapis : 🕷️ araignée (manqué, PV=cible de la routine) ·
                // 🔥 flemme (fait) · 🌿 buisson (placeholder). Araignée cliquable →
                // carte de combat (faire le vrai travail).
                for (var ei = 0; ei < allRows.length; ei++)
                  for (var d = 0; d < allRows[ei].lane.length; d++)
                    () {
                      final e = allRows[ei];
                      final tok = e.lane[d];
                      if (tok.type == 'empty') return const SizedBox.shrink();
                      // Combat : on cache le jardin (cases vides), MAIS on garde les
                      // flammes-source — elles rechargent la tour et « regrandissent »
                      // sur le cycle de recharge (30 s).
                      if (_cineAttack) {
                        if (tok.type != 'flame') return const SizedBox.shrink();
                        final tu = _cineTurretByRow[e.row];
                        if (tu == null) return const SizedBox.shrink();
                        final g = (tu.reload / tu.reloadEvery).clamp(0.0, 1.0);
                        final c0 = centerD(13.0 + d, e.row.toDouble());
                        return Positioned(
                          left: c0.dx - slot / 2,
                          top: c0.dy - slot / 2,
                          width: slot,
                          height: slot,
                          child: Center(
                            child: Opacity(
                              opacity: 0.35 + 0.65 * g,
                              child: Text('🔥',
                                  style: TextStyle(
                                      fontSize: slot * (0.30 + 0.25 * g))),
                            ),
                          ),
                        );
                      }
                      // Nuisible du jardin déjà nettoyé par une tour → vide.
                      if (tok.type == 'spider' &&
                          cineCleared.contains('nuis:${e.r.id}:$d')) {
                        return const SizedBox.shrink();
                      }
                      // Cinématique : une flamme quitte sa case quand elle vole.
                      // Ligne déjà chargée → toutes parties ; ligne en cours →
                      // seules celles déjà parties/en vol disparaissent ; les
                      // suivantes restent en case jusqu'à leur tour.
                      if (_cineActive && tok.type == 'flame') {
                        if (ei < _cinePrepIndex) {
                          return const SizedBox.shrink();
                        }
                        if (ei == _cinePrepIndex) {
                          final order = [
                            for (var dd = 0; dd < d; dd++)
                              if (e.lane[dd].type == 'flame') dd
                          ].length;
                          final count =
                              e.lane.where((t) => t.type == 'flame').length;
                          final arrived = (_cinePrepCharge * count).floor();
                          if (order <= arrived) return const SizedBox.shrink();
                        }
                      }
                      final c0 = centerD(13.0 + d, e.row.toDouble());
                      // Décrément du tir d'arrivée : -1 sur le nombre sous l'araignée.
                      // Tombe à 0 → MORTE → 💥 persistante ; sinon nombre décrémenté.
                      final dec = _toileDec['${e.r.id}_$d'] ?? 0;
                      final shownHp =
                          tok.type == 'spider' ? tok.hp - dec : 0;
                      final killed = tok.type == 'spider' && shownHp <= 0;
                      final spider = tok.type == 'spider' && !killed;
                      final emoji = killed
                          ? '💥'
                          : (tok.type == 'flame'
                              ? '🔥'
                              : (tok.type == 'spider'
                                  ? (e.kind == 'scorpion' ? '🦂' : '🕷️')
                                  : '')); // 'leaf' (fait) → case vide, plus clean
                      // Bataille : colonne déjà nettoyée → estompée (laisse voir
                      // la colonne suivante).
                      final battleFade =
                          _battleActive && _battleFaded.contains(d) ? 0.18 : 1.0;
                      return Positioned(
                        left: c0.dx - slot / 2,
                        top: c0.dy - slot / 2,
                        width: slot,
                        height: slot,
                        child: Opacity(
                          opacity: battleFade,
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
                                  Text('$shownHp', // PV restants (après décréments)
                                      style: TextStyle(
                                          color: _kEnemy,
                                          fontWeight: FontWeight.w900,
                                          fontSize: slot * 0.2,
                                          height: 1)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }(),
                // FLAMME EN VOL (cinématique) : pour la tour EN COURS de charge,
                // ses flammes partent UNE PAR UNE de leur case (col 13+d) et
                // rejoignent la tour (col 12). La tour ne change qu'à l'arrivée.
                if (_cineActive && _cinePrepIndex < allRows.length)
                  () {
                    final e = allRows[_cinePrepIndex];
                    final flameDays = [
                      for (var d = 0; d < e.lane.length; d++)
                        if (e.lane[d].type == 'flame') d
                    ];
                    final count = flameDays.length;
                    if (count == 0) return const SizedBox.shrink();
                    final prog = _cinePrepCharge * count;
                    final arrived = prog.floor();
                    if (arrived >= count) return const SizedBox.shrink();
                    final sub = (prog - arrived).clamp(0.0, 1.0);
                    final flyD = flameDays[arrived];
                    final from = centerD(13.0 + flyD, e.row.toDouble());
                    final to = centerD(12, e.row.toDouble());
                    final pos =
                        Offset.lerp(from, to, Curves.easeIn.transform(sub))!;
                    return Positioned(
                      left: pos.dx - slot / 2,
                      top: pos.dy - slot / 2,
                      width: slot,
                      height: slot,
                      child: Center(
                        child:
                            Text('🔥', style: TextStyle(fontSize: slot * 0.5)),
                      ),
                    );
                  }(),
                // CHÂTEAU (cols 11→0) : HEATMAP des 12 dernières semaines. Case =
                // nb de jours tenus (flammes) cette semaine, ou 🕸️ si semaine
                // perdue (0). Récente près de la tour (col 11), ancienne à gauche.
                // MASQUÉE quand l'avatar entre dans le château (col ≤ 12) → on
                // voit alors le contenu/combat (araignée, etc.).
                if (_pos.x > 12 || _cineActive)
                  for (final e in allRows)
                    for (var i = 0; i < e.heat.length; i++)
                      () {
                      final n = e.heat[i];
                      // Combat : on ne garde QUE les toiles (🕸️ = semaine à 0) ;
                      // les cases chiffrées (n>0) sont cachées.
                      if (_cineAttack && n > 0) {
                        return const SizedBox.shrink();
                      }
                      // Toile détruite (prépa/support OU jours précédents) → 💥
                      // PERSISTÉE la journée (au lieu de disparaître).
                      final toileKey = 'toile:${e.r.id}:$i';
                      final killedToile = n == 0 &&
                          (cineCleared.contains(toileKey) ||
                              _cineKilledToiles.contains(toileKey) ||
                              _dayKilledToiles.contains(toileKey));
                      final c0 = centerD(i.toDouble(), e.row.toDouble());
                      return Positioned(
                        left: c0.dx - slot / 2,
                        top: c0.dy - slot / 2,
                        width: slot,
                        height: slot,
                        child: Container(
                          margin: EdgeInsets.all(slot * 0.07),
                          decoration: BoxDecoration(
                            color: n > 0
                                ? _kCharge.withOpacity(
                                    0.2 + 0.8 * (n / 7).clamp(0.0, 1.0))
                                : Colors.white.withOpacity(.04),
                            borderRadius: BorderRadius.circular(slot * 0.12),
                            border: Border.all(
                                color: Colors.white.withOpacity(.06)),
                          ),
                          alignment: Alignment.center,
                          child: n > 0
                              ? Text('$n',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: slot * 0.34))
                              : Text(killedToile ? '💥' : '🕸️',
                                  style: TextStyle(fontSize: slot * 0.4)),
                        ),
                      );
                    }(),
                // PROJECTILE de nettoyage : la tour tire une BOULE DE FEU vers sa
                // cible (de la tour, col 12, vers la cible) puis elle disparaît.
                if (cineCurShot != null)
                  () {
                    final from = centerD(12, cineCurShot.turretRow.toDouble());
                    final to = centerD(cineCurShot.tx, cineCurShot.ty);
                    final pos = Offset.lerp(from, to,
                        Curves.easeOut.transform(_cineClearT.clamp(0.0, 1.0)))!;
                    return Positioned(
                      left: pos.dx - slot / 2,
                      top: pos.dy - slot / 2,
                      width: slot,
                      height: slot,
                      child: Center(
                        child: SvgPicture.asset('assets/icons/fireball.svg',
                            width: slot * 0.42,
                            height: slot * 0.42,
                            colorFilter: const ColorFilter.mode(
                                Color(0xFFFF8A3D), BlendMode.srcIn)),
                      ),
                    );
                  }(),
                // SBIRES lâchés par l'araignée → foncent (sinusoïde) sur le ninja.
                if (_cineAttack)
                  for (final s in _cineSbires)
                    () {
                      final c0 = centerD(s.x, s.y);
                      return Positioned(
                        left: c0.dx - slot / 2,
                        top: c0.dy - slot / 2,
                        width: slot,
                        height: slot,
                        child: Center(
                          child: Text('🕷️',
                              style: TextStyle(fontSize: slot * 0.42)),
                        ),
                      );
                    }(),
                // BOULES DE FEU de support (tours → toiles restantes) : tête orientée
                // dans le sens du vol + traînée de flamme qui s'estompe vers la queue.
                if (_cineAttack)
                  for (final fb in _supportFbs) ..._fbWidgets(fb, slot, centerD),
                // Boulet du tir d'ARRIVÉE (S3, hors cinématique d'assaut).
                if (_liveFb != null) ..._fbWidgets(_liveFb!, slot, centerD),
                // Traits de la BATAILLE HEBDO (couleur du domaine, placeholder).
                if (_battleActive)
                  for (final b in _battleBeams)
                    () {
                      final p1 = centerD(b.fx, b.fy);
                      final p2 = centerD(b.tx, b.ty);
                      final dxx = p2.dx - p1.dx, dyy = p2.dy - p1.dy;
                      final len = sqrt(dxx * dxx + dyy * dyy);
                      return Positioned(
                        left: p1.dx,
                        top: p1.dy,
                        child: Transform.rotate(
                          angle: atan2(dyy, dxx),
                          alignment: Alignment.topLeft,
                          child: Container(
                            width: len,
                            height: 3,
                            decoration: BoxDecoration(
                              color: _interiorColor,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                    color: _interiorColor.withOpacity(.6),
                                    blurRadius: 4)
                              ],
                            ),
                          ),
                        ),
                      );
                    }(),
                // Flash d'impact du tir d'arrivée.
                if (_liveFlashAt != null && _gameMs < _liveFlashUntilMs)
                  () {
                    final c0 = centerD(_liveFlashAt!.dx, _liveFlashAt!.dy);
                    return Positioned(
                      left: c0.dx - slot / 2,
                      top: c0.dy - slot / 2,
                      width: slot,
                      height: slot,
                      child: Center(
                        child: Text('💥',
                            style: TextStyle(fontSize: slot * 0.6)),
                      ),
                    );
                  }(),
                // SHURIKENS / FLÈCHES en vol (lancés par le ninja sur les sbires).
                if (_cineAttack)
                  for (final shk in _shurikens)
                    () {
                      final c0 = centerD(shk.x, shk.y);
                      // Flèche d'arc : dard orienté dans le sens du vol (pas de spin).
                      final child = shk.arrow
                          ? Transform.rotate(
                              angle: atan2(shk.vy, shk.vx),
                              child: Text('➤',
                                  style: TextStyle(
                                      color: _kGold, fontSize: slot * 0.42)),
                            )
                          : Transform.rotate(
                              angle: _gameMs * 0.018, // shuriken : spin continu
                              child: SvgPicture.asset(
                                  'assets/icons/shuriken.svg',
                                  width: slot * 0.34,
                                  height: slot * 0.34,
                                  colorFilter: ColorFilter.mode(
                                      Colors.white.withOpacity(.92),
                                      BlendMode.srcIn)),
                            );
                      return Positioned(
                        left: c0.dx - slot / 2,
                        top: c0.dy - slot / 2,
                        width: slot,
                        height: slot,
                        child: Center(child: child),
                      );
                    }(),
                // NINJA (phase attaque) : déplacement perpétuel sur la carte +
                // jauge de vie 10 PV au-dessus + tire sur les sbires.
                if (_cineAttack)
                  () {
                    final c0 = centerD(_ninjaX, _ninjaY);
                    return Positioned(
                      left: c0.dx - slot / 2,
                      top: c0.dy - slot * 0.7,
                      width: slot,
                      height: slot * 1.8,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < 10; i++)
                                Container(
                                  width: slot * 0.05,
                                  height: slot * 0.11,
                                  margin: EdgeInsets.symmetric(
                                      horizontal: slot * 0.006),
                                  decoration: BoxDecoration(
                                    color: i < _ninjaHp
                                        ? const Color(0xFF4FC26B)
                                        : Colors.white24,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: slot * 0.04),
                          Text(avatar, style: TextStyle(fontSize: slot * 0.6)),
                          SizedBox(height: slot * 0.02),
                          // Compteur de shurikens (deck lifetime).
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SvgPicture.asset('assets/icons/shuriken.svg',
                                  width: slot * 0.18,
                                  height: slot * 0.18,
                                  colorFilter: const ColorFilter.mode(
                                      Colors.white70, BlendMode.srcIn)),
                              SizedBox(width: slot * 0.03),
                              Text('$_ninjaShurikens',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: slot * 0.22,
                                      shadows: const [
                                        Shadow(
                                            color: Colors.black, blurRadius: 2)
                                      ])),
                            ],
                          ),
                        ],
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
              // Mon scorpion 🦂 ACCOMPAGNE l'avatar (phase farm). Masqué pendant
              // la cinématique (sinon il suit le ninja partout).
              if (_inInterior && !_phase1 && !_cineActive)
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
      // Web : scroll horizontal → absorbe tout débordement sous‑pixel de la Row
      // [grille + noms] (plus de « RIGHT OVERFLOWED »).
      return widget.mobile
          ? InteractiveViewer(
              constrained: false,
              boundaryMargin: const EdgeInsets.all(140),
              minScale: 0.4,
              maxScale: 2.5,
              child: board)
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal, child: board);
    });
  }

  Widget _cell(
      Territory t, UnifiedWorld w, int x, int y, double inner, String avatar,
      {bool isSpider = false}) {
    final id = '${x}_$y';
    // Pas de brouillard sur la GRANDE MAP : tout visible. Le fog ne subsiste qu'à
    // l'intérieur d'un domaine (exploration du calendrier/plateau).
    final revealed = !_inInterior || _revealed.contains(id) || _showCoords;
    // En phase attaque, le ninja est rendu en overlay lisse → pas d'avatar de
    // case (sinon doublon).
    final isAvatar = _pos.x == x && _pos.y == y && !_cineAttack;

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
      // grotte : gazon teinté au domaine ; sinon farm vert.
      final farmSide = _isFarmX(w, x);
      // QUARTIER : si la case appartient à la parcelle d'un domaine, gazon teinté
      // à SA couleur → petit voisinage coloré sur la map principale.
      final distId = _inInterior ? null : w.districtIdAt(x, y);
      Color base;
      if (_inInterior) {
        base = _interiorColor;
      } else if (distId != null) {
        final dc = t.caveById(distId);
        base = dc != null ? _caveColor(dc) : _kBlue;
      } else {
        base = farmSide ? _kFarm : Colors.white;
      }
      bg = base.withOpacity(distId != null ? .16 : .18);
      border = base.withOpacity(distId != null ? .45 : .40);
      // Maison 🏠 du quartier (devant la parcelle) + décor d'univers déterministe
      // (arbres/fleurs) sur le reste de la parcelle, hors grotte.
      final houseId = _inInterior ? null : w.houseIdAt(x, y);
      if (houseId != null) {
        child = Text('🏠', style: TextStyle(fontSize: inner * 0.55));
      } else if (distId != null && w.caveIdAt(x, y) == null) {
        final h = (x * 7 + y * 13) % 7;
        final deco = h == 0
            ? '🌲'
            : h == 1
                ? '🌳'
                : h == 2
                    ? '🌸'
                    : null;
        if (deco != null) {
          child = Text(deco, style: TextStyle(fontSize: inner * 0.42));
        }
      } else if (w.hasBush(x, y) && !_inInterior) {
        child = Text('🌿', style: TextStyle(fontSize: inner * 0.5));
      }
    } else if (kind == UwTile.castle) {
      // Teinte = domaine où tu as passé le PLUS de temps aujourd'hui (défaut : or).
      final cc = _topTimeDomainColorToday() ?? _kGold;
      bg = cc.withOpacity(.22);
      border = cc.withOpacity(.7);
      child = SvgPicture.asset('assets/icons/justice.svg',
          width: inner * 0.62,
          height: inner * 0.62,
          colorFilter: ColorFilter.mode(cc, BlendMode.srcIn));
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

    // ACCESSIBILITÉ (S1) : couloir d'accès forcé (cases murs rendues praticables)
    // teinté discrètement + PORTE DE SORTIE en haut du couloir.
    if (_inInterior && _interiorWalk.contains(id) && kind == UwTile.wall) {
      bg = _interiorColor.withOpacity(.10);
      border = _interiorColor.withOpacity(.30);
    }
    if (_inInterior && _exitDoor != null && _exitDoor!.x == x && _exitDoor!.y == y) {
      bg = _kFarm.withOpacity(.30);
      border = _kFarm.withOpacity(.9);
      child = Text('🚪', style: TextStyle(fontSize: inner * 0.5));
    }

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
    // Nuisible : couleur de SON domaine + fraction de PV (la case se remplit au %).
    Color pestColor = _kFarm;
    double pestHpFrac = 0;
    if (farmHere) {
      final dom = logic.enemyDomainId(farmPest.type, farmPest.id);
      pestColor =
          (dom != null ? domainColor(dom, logic.state.activeDomains) : null) ??
              _kFarm;
      final mx = logic.enemyMaxHp(farmPest.type, farmPest.id);
      pestHpFrac = (logic.enemyHp(farmPest.type, farmPest.id) / (mx <= 0 ? 1 : mx))
          .clamp(0.0, 1.0);
    }
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
                    ? pestColor.withOpacity(.15)
                    : bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
            color: isAvatar
                ? Colors.white
                : spiderHere
                    ? _kEnemy
                    : farmHere
                        ? pestColor.withOpacity(.85)
                        : border,
            width: isAvatar || spiderHere || farmHere ? 2 : 1),
      ),
      alignment: Alignment.center,
      child: isAvatar
          ? Text(avatar, style: TextStyle(fontSize: inner * 0.55))
          : spiderHere
              ? Text('🕷️', style: TextStyle(fontSize: inner * 0.55))
              : farmHere
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        // Remplissage couleur du domaine, du bas vers le haut, au
                        // prorata des PV restants du nuisible.
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: pestHpFrac,
                              child: Container(color: pestColor.withOpacity(.55)),
                            ),
                          ),
                        ),
                        Center(
                          child: Text(entityEmoji(farmPest.type),
                              style: TextStyle(fontSize: inner * 0.5)),
                        ),
                      ],
                    )
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
    final cell = GestureDetector(
        onTap: () => _onTap(x, y),
        onLongPress: () => _onLongPress(x, y),
        child: shown);
    // Survol souris (web) : titre de l'item + PV du nuisible du jardin.
    if (farmHere) {
      final hp = logic.enemyHp(farmPest.type, farmPest.id);
      final maxHp = logic.enemyMaxHp(farmPest.type, farmPest.id);
      return Tooltip(
        message: '${logic.enemyItemName(farmPest.type, farmPest.id)}\n'
            'PV $hp/$maxHp',
        waitDuration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: const Color(0xF21A1A1A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: pestColor.withOpacity(.7)),
        ),
        textStyle: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
        child: cell,
      );
    }
    return cell;
  }

  // ══ MONDE V2 (data‑driven) ════════════════════════════════════════════════
  // Domaines + leurs lignes (routines daily / activités‑temps) → spécif de monde.
  List<DomainSpec> _domainSpecs() {
    // Source des domaines = les GROTTES de la territoire (streamée + réconciliée
    // = 1 grotte/domaine actif), fiable même si logic.state n'est pas encore chargé.
    final t = _t;
    final domIds = <String>[];
    if (t != null) {
      for (final c in t.caves) {
        if (c.domainId.isNotEmpty && !domIds.contains(c.domainId)) {
          domIds.add(c.domainId);
        }
      }
    }
    // Repli : si pas de territoire, on tente l'état applicatif.
    if (domIds.isEmpty) {
      for (final d in logic.state.activeDomains) {
        domIds.add(d.id);
      }
    }
    final out = <DomainSpec>[];
    for (final domId in domIds) {
      int? color;
      for (final d in logic.state.activeDomains) {
        if (d.id == domId) {
          color = d.colorValue;
          break;
        }
      }
      final routines = <String>[];
      final acts = <String>[];
      for (final a in logic.state.activeActivities) {
        if (a.domainId != domId) continue;
        if (a.isHabit) {
          if (logic.routineWeekTokens(a.id).isEmpty) continue;
          routines.add(a.id);
        } else {
          if (logic.activityTimeTokens(a.id).isEmpty) continue;
          acts.add(a.id);
        }
      }
      out.add(DomainSpec(
          domainId: domId,
          colorValue: color,
          routineIds: routines,
          activityIds: acts));
    }
    // Le domaine où l'on passe le PLUS DE TEMPS (minutes 30 j de ses activités) est
    // placé TOUT EN BAS = près du spawn → accès rapide à ce sur quoi on bosse le
    // plus, cinématiques plus vite, sans traverser toute la map.
    int timeOf(DomainSpec d) {
      var m = 0;
      for (final aid in d.activityIds) {
        m += logic.activityTime30dMin(aid);
      }
      return m;
    }

    out.sort((a, b) => timeOf(a).compareTo(timeOf(b))); // croissant → max en bas
    return out;
  }

  // (Re)construit la grande map V2 depuis l'état → elle GRANDIT avec les données.
  void _rebuildWv2() {
    final layout = buildWorld(_domainSpecs());
    _wv2 = layout;
    _wv2Version++; // structure/teintes changées → invalide le calque mini‑carte
    _cellWindow = null; // et la grille cullée
    _cachedCells = null;
    _v2Tint.clear();
    _v2WallTint.clear();
    for (final c in layout.castles) {
      final col = domainColor(c.domainId, logic.state.activeDomains) ?? _kGold;
      // Château ET village teintés de la couleur du domaine.
      for (final r in [c.castleRect, c.villageRect]) {
        for (var y = r.top; y < r.top + r.height; y++) {
          for (var x = r.left; x < r.left + r.width; x++) {
            _v2Tint['${x}_$y'] = col;
          }
        }
      }
      // Murs intérieurs déco : accent de la couleur du domaine (halo discret).
      for (final p in c.decoWalls) {
        _v2WallTint['${p.x}_${p.y}'] = col;
      }
    }
    final firstSpawn = !_v2Spawned;
    if (!_v2Spawned) {
      _posV2 = layout.start; // 1ᵉʳ spawn = bas‑gauche (dernier domaine)
      _v2Spawned = true;
    } else if (!layout.inBounds(_posV2.x, _posV2.y) ||
        !layout.walkable(_posV2.x, _posV2.y)) {
      _posV2 = layout.start;
    }
    _populateV2Gardens();
    _populateV2Calendar();
    _populateV2Araignees();
    _populateV2Spiders(); // araignées d'écart hebdo (mobiles) + shurikens stockés
    _revealAroundV2(_posV2); // nuage de guerre : on révèle autour de l'avatar
    // Caméra cadrée sur le spawn UNE seule fois (plus d'auto‑centrage ensuite).
    if (firstSpawn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToAvatarV2());
    }
  }

  // Peuple les jardins, PAR DOMAINE, avec les nuisibles backlog du domaine :
  // 🐍 serpents (tâches en retard) + 🦂 scorpions (activités‑temps en retard).
  // GARDIENS DE PASSAGE : les 2 portes du mur partagé sont bouchées par les nuisibles
  // du domaine au plus petit PV (peu importe le type → 2 serpents OU 2 scorpions
  // possibles). AUCUN nuisible ne se pose sur une case interactive (rampe de tir).
  void _populateV2Gardens() {
    _v2Pests.clear();
    final w = _wv2;
    if (w == null) return;
    final byDom = <String, List<({String type, String id, int hp})>>{};
    for (final e in logic.backlogEnemies()) {
      if (e.type != 'snake' && e.type != 'scorpion') continue;
      final dom = logic.enemyDomainId(e.type, e.id);
      if (dom == null) continue;
      byDom.putIfAbsent(dom, () => []).add(e);
    }
    for (final c in w.castles) {
      final pests = [...?byDom[c.domainId]];
      if (pests.isEmpty) continue;
      final color =
          domainColor(c.domainId, logic.state.activeDomains) ?? _kFarm;
      final g = c.gardenRect;
      pests.sort((a, b) => a.hp.compareTo(b.hp)); // plus petit PV d'abord
      // Cases INTERACTIVES (rampes de tir = dernière colonne du jardin, sur chaque
      // lane) → jamais de nuisible dessus.
      final interactive = <String>{
        for (final lane in c.lanes) '${g.left + g.width - 1}_${lane.y}',
      };
      // GARDIENS : boucher les 2 portes praticables avec les plus petits PV dispos.
      final pr = g.top - 1; // rangée du mur partagé (portes percées dans buildWorld)
      for (final dx in [g.width ~/ 3, (2 * g.width) ~/ 3]) {
        if (pests.isEmpty) break;
        final px = g.left + dx;
        if (w.inBounds(px, pr) && w.at(px, pr) == WtTile.garden) {
          final e = pests.removeAt(0);
          _v2Pests['${px}_$pr'] = (type: e.type, id: e.id, color: color);
        }
      }
      // RESTE : dispersé dans le jardin (hors cases interactives, mélange déterministe).
      final free = <String>[];
      for (var y = g.top; y < g.top + g.height; y++) {
        for (var x = g.left; x < g.left + g.width; x++) {
          final id = '${x}_$y';
          if (w.at(x, y) != WtTile.garden) continue; // skip murs déco
          if (interactive.contains(id)) continue; // case interactive protégée
          free.add(id);
        }
      }
      free.shuffle(Random(c.domainId.hashCode));
      for (var i = 0; i < pests.length && i < free.length; i++) {
        _v2Pests[free[i]] = (type: pests[i].type, id: pests[i].id, color: color);
      }
    }
  }

  // Le type 'spider' = jour manqué = NUISIBLE : 🕷️ pour une routine, 🦂 pour une
  // activité‑temps (le type de token est générique, la lane décide).
  static String _tokEmoji(String type, bool isRoutine) {
    switch (type) {
      case 'leaf':
        return ''; // jour fait (1er jour) → case vide, plus clean
      case 'flame':
        return '🔥';
      case 'spider':
        return isRoutine ? '🕷️' : '🦂';
      default:
        return '';
    }
  }

  // Projette le CALENDRIER de chaque domaine inline : tourelle + 7 tokens‑jours
  // (+ compteur PV), séparateur routines/activités. Réutilise les mêmes helpers
  // que le rendu intérieur (routineWeekTokens / activityTimeTokens).
  void _populateV2Calendar() {
    _v2DayTok.clear();
    _v2DayCount.clear();
    _v2Turret.clear();
    _v2TurretRoutineId.clear();
    _v2LaunchPads.clear();
    _v2Sep.clear();
    _v2DayTurretX.clear();
    _v2DayLabel.clear();
    _v2LaneName.clear();
    final w = _wv2;
    if (w == null) return;
    const wd = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final c in w.castles) {
      for (var j = 0; j < 7; j++) {
        final d = today.subtract(Duration(days: 6 - j));
        _v2DayLabel['${c.dayX0 + j}_${c.headerY}'] = wd[d.weekday - 1];
      }
    }
    for (final c in w.castles) {
      for (final lane in c.lanes) {
        final name = _activityName(lane.id);
        final toks = lane.isRoutine
            ? logic.routineWeekTokens(lane.id)
            : logic.activityTimeTokens(lane.id);
        final charger =
            toks.where((t) => t.type == 'leaf' || t.type == 'flame').length;
        _v2Turret['${lane.turretX}_${lane.y}'] =
            (charger: charger, isRoutine: lane.isRoutine);
        if (lane.isRoutine) {
          _v2TurretRoutineId['${lane.turretX}_${lane.y}'] = lane.id;
        }
        // Case de tir = juste à GAUCHE de la tourelle (dernière colonne du jardin) :
        // marqueur « rampe de lancement » (là où l'avatar se poste pour tirer).
        _v2LaunchPads.add('${lane.turretX - 1}_${lane.y}');
        _v2LaneName['${lane.turretX}_${lane.y}'] = name;
        for (var j = 0; j < 7 && j < toks.length; j++) {
          final id = '${lane.dayX0 + j}_${lane.y}';
          final t = toks[j];
          final e = _tokEmoji(t.type, lane.isRoutine);
          if (e.isNotEmpty) _v2DayTok[id] = e;
          if (t.type == 'spider' && t.hp > 0) _v2DayCount[id] = t.hp;
          _v2DayTurretX[id] = lane.turretX;
          _v2LaneName[id] = name;
        }
      }
      if (c.sepY >= 0) {
        final r = c.castleRect;
        for (var x = r.left; x < r.left + r.width; x++) {
          _v2Sep.add('${x}_${c.sepY}');
        }
      }
    }
  }

  String _activityName(String id) {
    for (final a in logic.state.activeActivities) {
      if (a.id == id) return a.name;
    }
    return '';
  }

  // Araignées d'un domaine = jours manqués (🕷️/🦂) sur les 7 jours (AUJOURD'HUI
  // inclus → valider une routine du jour fait baisser le compte) de toutes ses
  // lignes. À ≥ N → invasion.
  int _v2InvasionCount(CastleBlock c) {
    var n = 0;
    for (final lane in c.lanes) {
      final toks = lane.isRoutine
          ? logic.routineWeekTokens(lane.id)
          : logic.activityTimeTokens(lane.id);
      for (var j = 0; j < 7 && j < toks.length; j++) {
        if (toks[j].type == 'spider') n++;
      }
    }
    return n;
  }

  void _populateV2Araignees() {
    _v2Araignee.clear();
    _v2Toiles.clear();
    final w = _wv2;
    if (w == null) return;
    for (final c in w.castles) {
      if (_v2Dislodged.contains(c.domainId)) continue; // délogée → ne revient pas
      // Invasion COLLANTE : dès qu'on atteint N, le domaine reste envahi jusqu'à
      // ce qu'on l'ait DÉLOGÉE (réduit < N + affrontée).
      if (_v2InvasionCount(c) >= _kInvasionN) _v2Invaded.add(c.domainId);
      if (!_v2Invaded.contains(c.domainId)) continue;
      // Case‑séparateur (entre tourelles routines et activités), colonne tourelles.
      final y = c.sepY >= 0
          ? c.sepY
          : (c.lanes.isNotEmpty
              ? c.lanes[c.lanes.length ~/ 2].y
              : c.castleRect.top);
      _v2Araignee['${c.castleRect.left}_$y'] = c.domainId;
      // Une toile dans le jardin (marqueur : valide tes routines pour la déloger).
      final g = c.gardenRect;
      _v2Toiles['${g.left + g.width ~/ 2}_${g.top + g.height ~/ 2}'] = c.domainId;
    }
  }

  void _revealAroundV2(Point<int> p) {
    final w = _wv2;
    if (w == null) return;
    for (var dy = -_kReveal; dy <= _kReveal; dy++) {
      for (var dx = -_kReveal; dx <= _kReveal; dx++) {
        final nx = p.x + dx, ny = p.y + dy;
        if (w.inBounds(nx, ny)) _revealed.add('${nx}_$ny');
      }
    }
  }

  // Clic sur la grande map = TÉLÉPORTATION directe du ninja sur la case (pas de
  // marche). Puis combat si serpent, ou coffre.
  // Clic sur la grande map = le ninja MARCHE jusqu'à la case (BFS, case par case,
  // révèle le brouillard en chemin). Case‑jour = cinématique. Arrivée = combat/coffre.
  // L'utilisateur interagit → il reprend la main (stoppe l'auto) + (ré)arme le
  // timer d'inactivité : 1 min sans interaction → l'avatar reprend son travail.
  void _v2TakeControl() {
    _v2UserControl = true;
    _v2ArmIdle();
  }

  void _v2ArmIdle() {
    _v2IdleTimer?.cancel();
    _v2IdleTimer = Timer(const Duration(minutes: 1), () {
      if (!mounted) return;
      if (_hasPending() && !_combatBusy && !_v2AutoExploring) {
        _v2DischargeBacklog();
      }
    });
  }

  Future<void> _onTapV2(int x, int y) async {
    final w = _wv2;
    if (w == null || _v2Walking) return;
    _v2TakeControl(); // clic = reprise de la main (interrompt l'exploration auto)
    final id = '${x}_$y';
    // Un tap sur la map referme le dashboard jardin (le jardin réapparaît).
    if (_gardenPanel != null) {
      setState(() {
        _gardenPanel = null;
        _combat = null;
      });
      return;
    }
    // Rampe de tir ☢️ → séquence canon (marche, spin, lève, tire si flammes) puis
    // dashboard de la lane.
    if (_v2LaunchPads.contains(id)) {
      await _onCannonRamp(x, y);
      return;
    }
    // Araignée‑boss : clic → shuriken → on change de map (combat dans l'intérieur).
    final araDom = _v2Araignee[id] ?? _v2Toiles[id];
    if (araDom != null) {
      final castle = w.byDomain[araDom];
      final n = castle == null ? 0 : _v2InvasionCount(castle);
      // ≥ N araignées cette semaine → trop tôt : il faut valider ses routines pour
      // redescendre sous N avant de pouvoir la déloger.
      if (castle == null || n >= _kInvasionN) {
        _toast(
            '🕸️ ${_domainName(araDom)} : $n araignées cette semaine. Valide tes '
            'routines pour descendre sous $_kInvasionN, puis déloge‑la.',
            _kEnemy);
        return;
      }
      // < N → on peut TENTER de l'affronter. La déloge (et la conso de shurikens)
      // n'a lieu qu'en cas de VICTOIRE du combat (cf. _simulateCine), pas au clic.
      _launchV2Cine(x, y, _posV2.x); // shuriken/jet vers l'araignée
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      _enterDomainFromV2(araDom);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _inInterior) _startCine();
      });
      return;
    }
    if (_v2DayTok.containsKey(id) && _v2DayTurretX.containsKey(id)) {
      _launchV2Cine(x, y, _v2DayTurretX[id]!);
      return;
    }
    if (!w.walkable(x, y)) {
      _toast('🧱 Un mur bloque le passage.', Colors.white38);
      return;
    }
    final path = _bfsV2(_posV2, Point(x, y));
    if (path.isEmpty) return;
    _v2Walking = true;
    for (final step in path) {
      if (!mounted) break;
      setState(() {
        _posV2 = step;
        _revealAroundV2(step);
      });
      _v2CheckDomainEntry();
      await Future.delayed(const Duration(milliseconds: 75));
    }
    _v2Walking = false;
    if (!mounted) return;
    final pest = _v2Pests['${_posV2.x}_${_posV2.y}'];
    if (pest != null) {
      await _backlogCombat('${_posV2.x}_${_posV2.y}', pest.type, pest.id);
    } else if (w.at(_posV2.x, _posV2.y) == WtTile.chest) {
      _toast('🎁 Coffre ! (récompense à venir)', _kGold);
    } else {
      // Posé à GAUCHE d'une tour flammée → reprise immédiate de l'exploration auto
      // depuis cette routine (monte, puis redescend pour les restes).
      final rid = _v2TurretRoutineId['${_posV2.x + 1}_${_posV2.y}'];
      if (rid != null && (_pendingByRoutine[rid]?.isNotEmpty ?? false)) {
        _v2DischargeBacklog();
      }
    }
  }

  // Entre dans l'intérieur EXISTANT d'un domaine (la « map de combat ») → la
  // cinématique d'assaut s'y joue ; en ressortant on revient sur la map V2.
  void _enterDomainFromV2(String domainId) {
    final t = _t;
    if (t == null) return;
    String? caveId;
    for (final c in t.caves) {
      if (c.domainId == domainId) {
        caveId = c.id;
        break;
      }
    }
    // Repli : certaines grottes ont id == domainId (legacy/réconcilié).
    caveId ??= t.caveById(domainId) != null ? domainId : null;
    if (caveId == null) {
      _toast('🕸️ Grotte introuvable pour ${_domainName(domainId)}.', _kEnemy);
      return;
    }
    _enterInterior(caveId);
  }

  List<Point<int>> _bfsV2(Point<int> from, Point<int> to) {
    final w = _wv2;
    if (w == null || from == to || !w.walkable(to.x, to.y)) return const [];
    final prev = <String, Point<int>?>{'${from.x}_${from.y}': null};
    final q = <Point<int>>[from];
    var i = 0;
    while (i < q.length) {
      final cur = q[i++];
      if (cur == to) break;
      for (final n in [
        Point(cur.x + 1, cur.y),
        Point(cur.x - 1, cur.y),
        Point(cur.x, cur.y + 1),
        Point(cur.x, cur.y - 1),
      ]) {
        final nid = '${n.x}_${n.y}';
        if (prev.containsKey(nid) || !w.walkable(n.x, n.y)) continue;
        // Un serpent bloque le passage (impossible d'enjamber) → l'avatar doit
        // faire le tour. Exception : la case CIBLE, pour aller la combattre.
        if (n != to && _v2Pests.containsKey(nid)) continue;
        prev[nid] = cur;
        q.add(n);
      }
    }
    if (!prev.containsKey('${to.x}_${to.y}')) return const [];
    final path = <Point<int>>[];
    Point<int>? cur = to;
    while (cur != null && cur != from) {
      path.add(cur);
      cur = prev['${cur.x}_${cur.y}'];
    }
    return path.reversed.toList();
  }

  // Cinématique du jour : la tourelle de la lane tire un boulet sur la case‑jour.
  // Un boulet tourelle → case (delay = échelonnement de la volée).
  void _fireV2Bolt(int dayX, int dayY, int turretX,
      {double delay = 0, double dur = 2.2}) {
    final arc = ((dayX - turretX).abs() * 0.28).clamp(0.8, 3.0).toDouble();
    // Durée par défaut 2,2 s ; l'exploration auto passe une durée plus longue.
    final fb = _CineFb(dur, turretX + 0.5, dayY.toDouble(), dayX.toDouble(),
        dayY.toDouble(), arc, 'v2');
    fb.t = -delay; // tir différé (volée)
    _v2Fbs.add(fb);
    _v2CineTick.value++;
  }

  void _launchV2Cine(int dayX, int dayY, int turretX) =>
      _fireV2Bolt(dayX, dayY, turretX);

  // Détecte l'entrée dans un nouveau domaine (bande contenant l'avatar) → volée.
  void _v2CheckDomainEntry() {
    final w = _wv2;
    if (w == null) return;
    CastleBlock? here;
    for (final c in w.castles) {
      final b = c.bounds;
      if (_posV2.x >= b.left &&
          _posV2.x < b.left + b.width &&
          _posV2.y >= b.top &&
          _posV2.y < b.top + b.height) {
        here = c;
        break;
      }
    }
    if (here == null) {
      _v2ActiveDomain = null;
      return;
    }
    // Entrée dans un nouveau domaine → on l'ÉCLAIRE en entier (le tir des tourelles
    // n'est déclenché que par les boules réellement provisionnées, cf.
    // _pendingByRoutine / _v2DischargeBacklog).
    if (here.domainId != _v2ActiveDomain) {
      _v2ActiveDomain = here.domainId;
      final b = here.bounds;
      setState(() {
        for (var yy = b.top; yy < b.top + b.height; yy++) {
          for (var xx = b.left; xx < b.left + b.width; xx++) {
            _revealed.add('${xx}_$yy');
          }
        }
      });
    }
  }

  void _simulateV2Cine(double dt) {
    for (final fb in _v2Fbs) {
      fb.t += dt / fb.dur;
      if (fb.t >= 1.0 && !fb.dead) {
        fb.dead = true;
        _v2Flashes.add((at: Offset(fb.tx, fb.ty), untilMs: _gameMs + 1400));
      }
    }
    _v2Fbs.removeWhere((fb) => fb.dead);
    _v2Flashes.removeWhere((f) => _gameMs >= f.untilMs);
  }

  // Vitesses des araignées / shurikens d'écart (en cases par seconde).
  static const double _kSpiderSpeed = 0.7;
  static const double _kSpiderShkSpeed = 11.0;
  static const int _kSpiderShkCooldownMs = 220; // anti‑rafale entre deux tirs

  // Une case est‑elle dans les bornes de confinement d'une araignée ET praticable ?
  bool _spiderCanStep(WorldLayout w, _GardenSpider s, int tx, int ty) =>
      tx >= s.bx0 && tx <= s.bx1 && ty >= s.by0 && ty <= s.by1 && w.walkable(tx, ty);

  // Errance des araignées CONFINÉES au village+jardin de leur domaine + tir auto des
  // shurikens stockés (par domaine) sur l'araignée la plus proche À PORTÉE.
  void _simulateGardenSpiders(double dt) {
    final w = _wv2;
    if (w == null) return;
    // 1) Errance bornée : rebond sur les murs ET la frontière du domaine.
    for (final s in _gardenSpiders) {
      // Hors de ses bornes ou dans un mur (layout changé) → relocalise chez elle.
      if (!_spiderCanStep(w, s, s.x.floor(), s.y.floor())) {
        for (var t = 0; t < 30; t++) {
          final rx = s.bx0 + _rng.nextInt(s.bx1 - s.bx0 + 1);
          final ry = s.by0 + _rng.nextInt(s.by1 - s.by0 + 1);
          if (w.walkable(rx, ry)) {
            s.x = rx + 0.5;
            s.y = ry + 0.5;
            s.dir = _rng.nextDouble() * 2 * pi;
            break;
          }
        }
        continue;
      }
      s.dir += (_rng.nextDouble() - 0.5) * 1.4 * dt; // dérive douce du cap
      final nx = s.x + cos(s.dir) * _kSpiderSpeed * dt;
      final ny = s.y + sin(s.dir) * _kSpiderSpeed * dt;
      if (_spiderCanStep(w, s, nx.floor(), ny.floor())) {
        s.x = nx;
        s.y = ny;
      } else {
        s.dir = _rng.nextDouble() * 2 * pi; // bloquée → nouveau cap
      }
    }
    // 2) Tir auto PAR DOMAINE : l'avatar vise l'araignée la plus proche à portée DONT
    //    le domaine a encore du stock (au‑delà des shurikens déjà en vol vers lui).
    if (_gameMs - _lastGardenShkMs >= _kSpiderShkCooldownMs) {
      final ax = _posV2.x + 0.5, ay = _posV2.y + 0.5;
      final inFlight = <String, int>{};
      for (final k in _gardenShk) {
        inFlight[k.domainId] = (inFlight[k.domainId] ?? 0) + 1;
      }
      _GardenSpider? target;
      var bestD = _kNinjaRange * _kNinjaRange;
      for (final s in _gardenSpiders) {
        if (s.dead) continue;
        final stock = _gardenShurikensByDomain[s.domainId] ?? 0;
        if (stock - (inFlight[s.domainId] ?? 0) <= 0) continue; // plus de shuriken dispo
        final d = (s.x - ax) * (s.x - ax) + (s.y - ay) * (s.y - ay);
        if (d <= bestD) {
          bestD = d;
          target = s;
        }
      }
      if (target != null) {
        final ddx = target.x - ax, ddy = target.y - ay;
        final dd = sqrt(ddx * ddx + ddy * ddy);
        if (dd > 0.01) {
          _gardenShk.add(_GardenShk(ax, ay, ddx / dd * _kSpiderShkSpeed,
              ddy / dd * _kSpiderShkSpeed, _gameMs, target.domainId));
          _lastGardenShkMs = _gameMs;
        }
      }
    }
    // 3) Avance les shurikens + collision (tue l'araignée, consomme un shuriken du
    //    domaine de l'araignée TOUCHÉE → invariant per‑domaine préservé).
    for (final shk in _gardenShk) {
      shk.x += shk.vx * dt;
      shk.y += shk.vy * dt;
      // Hors map ou trop vieux (cible esquivée) → disparaît SANS consommer le stock.
      if (shk.x < -1 ||
          shk.x > w.cols + 1 ||
          shk.y < -1 ||
          shk.y > w.rows + 1 ||
          _gameMs - shk.bornMs > 1500) {
        shk.dead = true;
        continue;
      }
      for (final s in _gardenSpiders) {
        if (s.dead) continue;
        if ((shk.x - s.x).abs() < 0.5 && (shk.y - s.y).abs() < 0.5) {
          s.dead = true;
          shk.dead = true;
          final st = _gardenShurikensByDomain[s.domainId] ?? 0;
          if (st > 0) _gardenShurikensByDomain[s.domainId] = st - 1;
          _v2Flashes.add((at: Offset(s.x - 0.5, s.y - 0.5), untilMs: _gameMs + 700));
          break;
        }
      }
    }
    _gardenShk.removeWhere((shk) => shk.dead);
    _gardenSpiders.removeWhere((s) => s.dead);
  }

  Offset _v2CenterD(double x, double y) =>
      Offset(x * _kV2Slot + _kV2Slot / 2, y * _kV2Slot + _kV2Slot / 2);

  void _scrollToAvatarV2() {
    if (!_v2HCtrl.hasClients || !_v2VCtrl.hasClients) return;
    final vpW = _v2HCtrl.position.viewportDimension;
    final vpH = _v2VCtrl.position.viewportDimension;
    final tx = (_posV2.x * _kV2Slot + _kV2Slot / 2 - vpW / 2)
        .clamp(0.0, _v2HCtrl.position.maxScrollExtent);
    final ty = (_posV2.y * _kV2Slot + _kV2Slot / 2 - vpH / 2)
        .clamp(0.0, _v2VCtrl.position.maxScrollExtent);
    _v2HCtrl.animateTo(tx,
        duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    _v2VCtrl.animateTo(ty,
        duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }

  Widget _contentV2() {
    final w = _wv2;
    if (w == null) {
      return const Center(child: CircularProgressIndicator(color: _kBlue));
    }
    // On arrive ici via build() → l'état a pu changer : on force un recalcul des
    // cases au prochain frame, puis le cache reprend pendant le scroll pur.
    _cachedCells = null;
    // Exploration : DEUX navigations cohabitent. Drag‑pan au DOIGT (un doigt) via
    // GestureDetector.onPanUpdate, ET scroll 2 doigts / molette via
    // Listener.onPointerSignal (déplace la carte en 2D). Les physics des scrolls
    // restent désactivées (on pilote tout à la main). Le tap sur une case marche
    // toujours l'avatar (un drag ≠ un tap).
    return Listener(
      onPointerSignal: (e) {
        if (e is! PointerScrollEvent) return;
        if (!_v2HCtrl.hasClients || !_v2VCtrl.hasClients) return;
        _v2TakeControl();
        _v2HCtrl.jumpTo((_v2HCtrl.offset + e.scrollDelta.dx)
            .clamp(0.0, _v2HCtrl.position.maxScrollExtent));
        _v2VCtrl.jumpTo((_v2VCtrl.offset + e.scrollDelta.dy)
            .clamp(0.0, _v2VCtrl.position.maxScrollExtent));
      },
      child: GestureDetector(
      onPanDown: (_) => _v2TakeControl(), // déplacer la carte = reprendre la main
      onPanUpdate: (d) {
        if (!_v2HCtrl.hasClients || !_v2VCtrl.hasClients) return;
        _v2HCtrl.jumpTo((_v2HCtrl.offset - d.delta.dx)
            .clamp(0.0, _v2HCtrl.position.maxScrollExtent));
        _v2VCtrl.jumpTo((_v2VCtrl.offset - d.delta.dy)
            .clamp(0.0, _v2VCtrl.position.maxScrollExtent));
      },
      child: SingleChildScrollView(
        controller: _v2VCtrl,
        scrollDirection: Axis.vertical,
        physics: const NeverScrollableScrollPhysics(),
        child: SingleChildScrollView(
          controller: _v2HCtrl,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: w.cols * _kV2Slot,
            height: w.rows * _kV2Slot,
          child: Stack(
            children: [
              // GRILLE CULLÉE : seules les cases VISIBLES sont construites
              // (recalculé au scroll) → coût borné quel que soit le monde.
              // RepaintBoundary : isole les repeints de la grille du reste du Stack.
              Positioned.fill(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_v2HCtrl, _v2VCtrl]),
                    builder: (_, __) => Stack(children: _visibleCellsV2(w)),
                  ),
                ),
              ),
              // Noms des lignes (routines/activités) à droite, comme dans la grotte.
              ..._v2LaneLabels(w),
              ..._v2ShurikenBadges(w),
              // Overlay cinématique : repeint SEUL (grille statique en dessous).
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _v2CineTick,
                    builder: (_, __) => Stack(children: [
                      for (final fb in _v2Fbs)
                        ..._fbWidgets(fb, _kV2Slot, _v2CenterD),
                      for (final f in _v2Flashes)
                        if (_gameMs < f.untilMs)
                          Positioned(
                            left: f.at.dx * _kV2Slot,
                            top: f.at.dy * _kV2Slot,
                            width: _kV2Slot,
                            height: _kV2Slot,
                            child: Center(
                                child: Text('💥',
                                    style:
                                        TextStyle(fontSize: _kV2Slot * 0.6))),
                          ),
                      // Petites araignées d'écart hebdo (mobiles) — visibles dans le
                      // brouillard découvert seulement.
                      for (final s in _gardenSpiders)
                        if (_revealed.contains('${s.x.floor()}_${s.y.floor()}') ||
                            _showCoords)
                          Positioned(
                            left: (s.x - 0.5) * _kV2Slot,
                            top: (s.y - 0.5) * _kV2Slot,
                            width: _kV2Slot,
                            height: _kV2Slot,
                            child: Center(
                                child: Text('🕷️',
                                    style: TextStyle(
                                        fontSize: _kV2Slot * 0.42))),
                          ),
                      // Shurikens d'araignée en vol (spin continu).
                      for (final shk in _gardenShk)
                        Positioned(
                          left: (shk.x - 0.5) * _kV2Slot,
                          top: (shk.y - 0.5) * _kV2Slot,
                          width: _kV2Slot,
                          height: _kV2Slot,
                          child: Center(
                            child: Transform.rotate(
                              angle: _gameMs * 0.018,
                              child: SvgPicture.asset(
                                  'assets/icons/shuriken.svg',
                                  width: _kV2Slot * 0.34,
                                  height: _kV2Slot * 0.34,
                                  colorFilter: ColorFilter.mode(
                                      Colors.white.withOpacity(.92),
                                      BlendMode.srcIn)),
                            ),
                          ),
                        ),
                      // Rampe ☢️ : tour sur elle‑même (2 s) pendant la séquence canon.
                      if (_cannonSpinAt != null)
                        Positioned(
                          left: _cannonSpinAt!.x * _kV2Slot,
                          top: _cannonSpinAt!.y * _kV2Slot,
                          width: _kV2Slot,
                          height: _kV2Slot,
                          child: Center(
                            child: Transform.rotate(
                              angle: (_gameMs - _cannonSpinStartMs) / 2000 * 2 * pi,
                              child: Text('☢️',
                                  style: TextStyle(fontSize: _kV2Slot * 0.5)),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
              // Panneau JARDIN in‑place (combat ou dashboard routines) — INTERACTIF.
              if (_gardenPanel != null) _gardenPanelV2(w),
            ],
          ),
        ),
        ),
      ),
      ),
    );
  }

  // Noms des lignes (routine/activité) à DROITE du calendrier (extérieur), teintés
  // de la couleur du domaine — visibles seulement si le domaine est éclairé.
  List<Widget> _v2LaneLabels(WorldLayout w) {
    final out = <Widget>[];
    for (final c in w.castles) {
      final col = domainColor(c.domainId, logic.state.activeDomains) ?? _kGold;
      for (final lane in c.lanes) {
        if (!_revealed.contains('${lane.turretX}_${lane.y}') && !_showCoords) {
          continue;
        }
        final name = _activityName(lane.id);
        if (name.isEmpty) continue;
        out.add(Positioned(
          left: (c.dayX0 + 7) * _kV2Slot + 4,
          top: lane.y * _kV2Slot,
          height: _kV2Slot,
          width: 6 * _kV2Slot,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: col,
                    fontSize: _kV2Slot * 0.3,
                    fontWeight: FontWeight.w800)),
          ),
        ));
      }
    }
    return out;
  }

  // Badge « 🗡️ N » du stock de shurikens par domaine (coin haut‑gauche du jardin),
  // visible si le domaine est découvert et a du stock.
  List<Widget> _v2ShurikenBadges(WorldLayout w) {
    final out = <Widget>[];
    for (final c in w.castles) {
      final n = _gardenShurikensByDomain[c.domainId] ?? 0;
      if (n <= 0) continue;
      final g = c.gardenRect;
      if (!_revealed.contains('${g.left}_${g.top}') && !_showCoords) continue;
      out.add(Positioned(
        left: g.left * _kV2Slot + 2,
        top: g.top * _kV2Slot + 2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.55),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('🗡️ $n',
              style: const TextStyle(
                  color: Color(0xFFFFC83D),
                  fontWeight: FontWeight.w900,
                  fontSize: 11)),
        ),
      ));
    }
    return out;
  }

  // Cases visibles (fenêtre de scroll + marge) → Positioned.
  List<Widget> _visibleCellsV2(WorldLayout w) {
    const slot = _kV2Slot, margin = 2;
    // Au 1ᵉʳ frame le viewport n'existe pas encore → on cadre une FENÊTRE autour de
    // l'avatar (et pas TOUTES les cases, qui ferait une frame énorme au spawn).
    final hasC = _v2HCtrl.hasClients && _v2VCtrl.hasClients;
    final vpW = hasC ? _v2HCtrl.position.viewportDimension : 1000.0;
    final vpH = hasC ? _v2VCtrl.position.viewportDimension : 800.0;
    final offX = hasC ? _v2HCtrl.offset : (_posV2.x * slot - vpW / 2);
    final offY = hasC ? _v2VCtrl.offset : (_posV2.y * slot - vpH / 2);
    final x0 = ((offX / slot).floor() - margin).clamp(0, w.cols - 1);
    final x1 = (((offX + vpW) / slot).ceil() + margin).clamp(0, w.cols - 1);
    final y0 = ((offY / slot).floor() - margin).clamp(0, w.rows - 1);
    final y1 = (((offY + vpH) / slot).ceil() + margin).clamp(0, w.rows - 1);
    // Tant que la FENÊTRE de tuiles ne change pas (scroll sous‑pixel), on réutilise
    // les widgets déjà construits → zéro rebuild de case pendant un drag fluide.
    final win = (x0: x0, y0: y0, x1: x1, y1: y1);
    final cached = _cachedCells;
    if (cached != null && _cellWindow == win) return cached;
    final cells = <Widget>[];
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        cells.add(Positioned(
            left: x * slot,
            top: y * slot,
            width: slot,
            height: slot,
            child: _cellV2(x, y)));
      }
    }
    _cellWindow = win;
    return _cachedCells = cells;
  }

  // Décor cosmétique (game-icon teintée, faible opacité) posé par world_layout.
  Widget? _v2DecorWidget(String id, double inner) {
    final d = _wv2?.decor[id];
    if (d == null) return null;
    final (String asset, Color color, double scale) = switch (d) {
      WtDecor.rock => ('assets/icons/rock.svg', const Color(0xFF8A8A8A), 0.62),
      WtDecor.tree =>
        ('assets/icons/pine-tree.svg', const Color(0xFF4E7A48), 0.84),
      WtDecor.bush =>
        ('assets/icons/berry-bush.svg', const Color(0xFF5E8A4A), 0.66),
      WtDecor.house =>
        ('assets/icons/house.svg', const Color(0xFFB58C5A), 0.70),
      WtDecor.torch =>
        ('assets/icons/torch.svg', const Color(0xFFE8A33D), 0.55),
    };
    return SvgPicture.asset(asset,
        width: inner * scale,
        height: inner * scale,
        colorFilter: ColorFilter.mode(color.withOpacity(.82), BlendMode.srcIn));
  }

  Widget _cellV2(int x, int y) {
    final w = _wv2!;
    final id = '${x}_$y';
    final revealed = _revealed.contains(id) || _showCoords;
    final isAvatar = _posV2.x == x && _posV2.y == y;
    const slot = _kV2Slot, inner = slot - 3;
    if (!revealed) {
      return SizedBox(
        width: slot,
        height: slot,
        child: GestureDetector(
          onTap: () => _onTapV2(x, y),
          child: Container(color: const Color(0xFF0A0A0A)),
        ),
      );
    }
    Color bg;
    Widget? child;
    final pest = _v2Pests[id];
    final tile = w.at(x, y);
    switch (tile) {
      case WtTile.wall:
        // Pierre (brique) partout = « vrai monde » ; les murs INTÉRIEURS d'un
        // domaine reçoivent en plus un halo discret de la couleur du domaine.
        final accent = _v2WallTint[id];
        bg = accent != null
            ? Color.alphaBlend(
                accent.withOpacity(.16), const Color(0xFF3A3A3A))
            : const Color(0xFF2C2C2C);
        child = SvgPicture.asset('assets/icons/brick-wall.svg',
            width: inner * 0.8,
            height: inner * 0.8,
            colorFilter: const ColorFilter.mode(
                Color(0xFFB8B0A4), BlendMode.srcIn));
        break;
      case WtTile.terrain:
        // Extérieur SOMBRE, comme le fond sous les nuisibles → ils semblent
        // surgir du noir (côté droit ouvert notamment). Décor cosmétique éventuel.
        bg = Colors.black.withOpacity(.28);
        child = _v2DecorWidget(id, inner);
        break;
      case WtTile.garden:
        bg = _kFarm.withOpacity(.22);
        // Rampe de lancement (case de tir à gauche de la tourelle) : marqueur ☢️
        // sur fond ambré (zone de tir / danger).
        if (_v2LaunchPads.contains(id)) {
          bg = const Color(0xFFE8C13D).withOpacity(.16);
          child = Text('☢️', style: TextStyle(fontSize: inner * 0.5));
        }
        break;
      case WtTile.village:
        // Village teinté de la couleur du domaine (plus doux que le château).
        bg = (_v2Tint[id] ?? const Color(0xFF3A2E1E)).withOpacity(.20);
        child = _v2DecorWidget(id, inner);
        break;
      case WtTile.bridge:
        bg = const Color(0xFF6B4A2A).withOpacity(.55); // pont en bois
        break;
      case WtTile.castle:
        // Calendrier inline : séparateur, tourelle (défense), token‑jour, sinon mur.
        final tColor = _v2Tint[id] ?? _kGold;
        final tur = _v2Turret[id];
        final tok = _v2DayTok[id];
        final lbl = _v2DayLabel[id];
        if (lbl != null) {
          bg = tColor.withOpacity(.20);
          child = Text(lbl,
              style: TextStyle(
                  fontSize: inner * 0.34,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withOpacity(.85)));
        } else if (_v2Sep.contains(id)) {
          bg = tColor.withOpacity(.65); // ligne séparatrice (rempart)
        } else if (tur != null) {
          bg = tColor.withOpacity(.18);
          // Flammes chargées = tirs dus (hits faits hors‑web) que l'avatar viendra
          // décharger pendant l'exploration auto.
          final rid = _v2TurretRoutineId[id];
          final pending = rid == null ? 0 : (_pendingByRoutine[rid]?.length ?? 0);
          // Pieds DROITS (fixes) : seule la tête du canon se relève (cf. _v2TurretWidget).
          final raise = _cannonRaise[id] ?? 0.0;
          final turret = _v2TurretWidget(tur.charger, tur.isRoutine, inner,
              raise: raise);
          child = pending <= 0
              ? turret
              : Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    turret,
                    Positioned(
                      right: -1,
                      top: -1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 3, vertical: 0.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('🔥$pending',
                            style: TextStyle(
                                fontSize: inner * 0.26,
                                height: 1,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFFFFC83D))),
                      ),
                    ),
                  ],
                );
        } else if (tok != null) {
          bg = Colors.black.withOpacity(.28);
          final cnt = _v2DayCount[id] ?? 0;
          child = cnt > 0
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(tok, style: TextStyle(fontSize: inner * 0.4)),
                    Text('$cnt',
                        style: TextStyle(
                            fontSize: inner * 0.22,
                            height: 1,
                            color: const Color(0xFFE05858),
                            fontWeight: FontWeight.w900)),
                  ])
              : Text(tok, style: TextStyle(fontSize: inner * 0.46));
        } else {
          bg = tColor.withOpacity(.10); // château vide
        }
        break;
      case WtTile.chest:
        bg = const Color(0xFF13211A);
        child = Text('🎁', style: const TextStyle(fontSize: inner * 0.5));
        break;
    }
    // Nuisible du jardin (🐍 serpent / 🦂 scorpion) : case remplie au % PV (couleur
    // domaine) + emoji ; sur une case‑passage = gardien qui bloque le raccourci.
    if (pest != null && tile == WtTile.garden) {
      final hp = logic.enemyHp(pest.type, pest.id);
      final mx = logic.enemyMaxHp(pest.type, pest.id);
      final frac = (hp / (mx <= 0 ? 1 : mx)).clamp(0.0, 1.0);
      bg = pest.color.withOpacity(.15);
      child = Stack(fit: StackFit.expand, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: frac,
              child: Container(color: pest.color.withOpacity(.55)),
            ),
          ),
        ),
        Center(
            child: Text(entityEmoji(pest.type),
                style: const TextStyle(fontSize: inner * 0.5))),
      ]);
    }
    // Toile d'invasion dans le jardin (marqueur : valide tes routines pour déloger).
    if (_v2Toiles.containsKey(id)) {
      child = Text('🕸️', style: TextStyle(fontSize: inner * 0.6));
    }
    // Araignée‑boss d'invasion (clic = combat si semaine propre).
    if (_v2Araignee.containsKey(id)) {
      bg = _kEnemy.withOpacity(.32);
      child = Text('🕷️', style: TextStyle(fontSize: inner * 0.75));
    }
    if (isAvatar) {
      bg = Colors.white.withOpacity(.18);
      child = Text(logic.state.activeAvatar ?? '🧍',
          style: const TextStyle(fontSize: inner * 0.6));
    }
    final cell = SizedBox(
      width: slot,
      height: slot,
      child: GestureDetector(
        onTap: () => _onTapV2(x, y),
        child: Container(
          margin: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white.withOpacity(.05)),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
    // Tooltips : serpent (titre + PV) / ligne de calendrier (nom).
    String? tip;
    if (pest != null && tile == WtTile.garden) {
      tip = '${logic.enemyItemName(pest.type, pest.id)}\n'
          'PV ${logic.enemyHp(pest.type, pest.id)}/${logic.enemyMaxHp(pest.type, pest.id)}';
    } else if (_v2LaneName[id]?.isNotEmpty ?? false) {
      tip = _v2LaneName[id];
    }
    if (tip != null) {
      return Tooltip(
        message: tip,
        waitDuration: const Duration(milliseconds: 250),
        child: cell,
      );
    }
    return cell;
  }

  // Mini‑carte (coin haut‑droit) : monde entier à l'échelle + avatar + cadre du
  // viewport (suit le scroll). Tap → recentre la caméra sur ce point.
  Widget _miniMapV2({double maxSide = 160.0}) {
    final w = _wv2;
    if (w == null) return const SizedBox.shrink();
    final cell = maxSide / max(w.cols, w.rows);
    final mw = w.cols * cell, mh = w.rows * cell;
    // (Re)enregistre le calque de cases une seule fois par monde → les frames de
    // scroll ne repeignent plus que l'avatar + le cadre viewport par‑dessus.
    if (_miniBasePic == null || _miniBaseKey != _wv2Version) {
      _miniBasePic?.dispose();
      _miniBasePic = _recordMiniBase(w, cell);
      _miniBaseKey = _wv2Version;
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xCC0A0A0A),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(3),
      child: GestureDetector(
        onTapDown: (d) => _miniMapTap(d.localPosition, cell),
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_v2HCtrl, _v2VCtrl]),
            builder: (_, __) {
              Rect? vp;
              if (_v2HCtrl.hasClients &&
                  _v2VCtrl.hasClients &&
                  _v2HCtrl.position.hasViewportDimension) {
                vp = Rect.fromLTWH(
                  _v2HCtrl.offset / _kV2Slot * cell,
                  _v2VCtrl.offset / _kV2Slot * cell,
                  _v2HCtrl.position.viewportDimension / _kV2Slot * cell,
                  _v2VCtrl.position.viewportDimension / _kV2Slot * cell,
                );
              }
              return CustomPaint(
                size: Size(mw, mh),
                painter: _MiniMapPainter(_miniBasePic!, _posV2, cell, vp),
              );
            },
          ),
        ),
      ),
    );
  }

  // Enregistre les cases du monde dans un Picture réutilisable (couleur par type
  // de tuile ; château teinté du domaine). Recordé une fois par version de monde.
  ui.Picture _recordMiniBase(WorldLayout w, double cell) {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final p = Paint()..style = PaintingStyle.fill;
    for (var y = 0; y < w.rows; y++) {
      for (var x = 0; x < w.cols; x++) {
        switch (w.at(x, y)) {
          case WtTile.wall:
            p.color = const Color(0xFF333333);
            break;
          case WtTile.terrain:
            p.color = const Color(0xFF0F1A14);
            break;
          case WtTile.garden:
            p.color = const Color(0xFF1E6B3A);
            break;
          case WtTile.village:
            p.color = const Color(0xFF5A4630);
            break;
          case WtTile.bridge:
            p.color = const Color(0xFF8A5E33);
            break;
          case WtTile.castle:
            p.color = _v2Tint['${x}_$y'] ?? const Color(0xFFD4A017);
            break;
          case WtTile.chest:
            p.color = const Color(0xFFE0B84A);
            break;
        }
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), p);
      }
    }
    return rec.endRecording();
  }

  // Tap mini‑carte → PAN la caméra vers ce point (regarder ailleurs sans bouger
  // l'avatar) ; pas d'auto‑centrage.
  void _miniMapTap(Offset local, double cell) {
    final w = _wv2;
    if (w == null || !_v2HCtrl.hasClients || !_v2VCtrl.hasClients) return;
    final cx = (local.dx / cell).floor().clamp(0, w.cols - 1);
    final cy = (local.dy / cell).floor().clamp(0, w.rows - 1);
    final vpW = _v2HCtrl.position.viewportDimension;
    final vpH = _v2VCtrl.position.viewportDimension;
    final tx = (cx * _kV2Slot + _kV2Slot / 2 - vpW / 2)
        .clamp(0.0, _v2HCtrl.position.maxScrollExtent);
    final ty = (cy * _kV2Slot + _kV2Slot / 2 - vpH / 2)
        .clamp(0.0, _v2VCtrl.position.maxScrollExtent);
    _v2HCtrl.animateTo(tx,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    _v2VCtrl.animateTo(ty,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  Widget _v2TurretWidget(int charger, bool isRoutine, double inner,
      {double raise = 0}) {
    final col = isRoutine ? _kEnemy : const Color(0xFFFF8A3D);
    final r = raise.clamp(0.0, 1.0);
    final gun = inner * 0.58;
    // Tête baissée au repos (0.5 rad) → relevée (0 = opérationnel) avec le lever.
    final headAngle = 0.5 * (1 - r);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 7; i++)
            Container(
              width: inner * 0.045,
              height: inner * 0.08,
              margin: EdgeInsets.symmetric(horizontal: inner * 0.006),
              color: i < charger
                  ? const Color(0xFF3CCB6E)
                  : Colors.white24,
            ),
        ]),
        SizedBox(height: inner * 0.04),
        // DCA en 2 morceaux (comme la carte de combat) : BASE fixe = pieds droits ;
        // seule la TÊTE (aa-head) pivote autour de la monture. + FLAMME au‑dessus
        // pendant la charge (comme en mode combat).
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            SizedBox(
              width: gun,
              height: gun,
              child: Stack(children: [
                SvgPicture.asset('assets/icons/aa-base.svg',
                    width: gun,
                    height: gun,
                    colorFilter: ColorFilter.mode(col, BlendMode.srcIn)),
                Transform.rotate(
                  angle: headAngle,
                  alignment: _kBarrelPivot,
                  child: SvgPicture.asset('assets/icons/aa-head.svg',
                      width: gun,
                      height: gun,
                      colorFilter: ColorFilter.mode(col, BlendMode.srcIn)),
                ),
              ]),
            ),
            if (r > 0.25)
              Positioned(
                top: -gun * 0.34,
                child: Opacity(
                  opacity: r,
                  child: SvgPicture.asset('assets/icons/fireball.svg',
                      width: gun * 0.5,
                      height: gun * 0.5,
                      colorFilter: const ColorFilter.mode(
                          Color(0xFFFFB23D), BlendMode.srcIn)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Peintre de la mini‑carte du monde V2 (cases à l'échelle + avatar + viewport).
class _MiniMapPainter extends CustomPainter {
  final ui.Picture base; // calque cases pré‑enregistré (cf. _recordMiniBase)
  final Point<int> avatar;
  final double cell;
  final Rect? viewport;
  _MiniMapPainter(this.base, this.avatar, this.cell, this.viewport);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPicture(base);
    if (viewport != null) {
      canvas.drawRect(
          viewport!,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = Colors.white70);
    }
    canvas.drawCircle(
        Offset((avatar.x + 0.5) * cell, (avatar.y + 0.5) * cell),
        cell.clamp(1.6, 3.2),
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter old) =>
      old.avatar != avatar ||
      old.viewport != viewport ||
      old.cell != cell ||
      !identical(old.base, base);
}

/// Flèche dessinée pointant vers +x (la droite) : hampe + pointe (réaliste, sans
/// empennage). Marron. Orientée vers la cible par le `Transform.rotate` parent.
/// Socle réutilisable pour « tourelle tire sur la grotte/le sbire ».
const _kArrowWood = Color(0xFF6B4423); // marron hampe
const _kArrowHead = Color(0xFF3E2A18); // pointe (plus sombre)

/// Sbire ENNEMI (éphémère) : position continue en coords de tuiles, PV, assaut.
// Shuriken lancé par le ninja : ligne droite (direction figée au lancer).
class _CineShk {
  double x, y;
  final double vx, vy;
  final bool arrow; // true = flèche d'arc (rendu différent, ne consomme pas le deck)
  bool dead = false;
  _CineShk(this.x, this.y, this.vx, this.vy, {this.arrow = false});
}

/// Petite araignée d'ÉCART HEBDO : position continue (coords de tuiles), CONFINÉE
/// au village+jardin de son domaine (`bx0..bx1`, `by0..by1` inclusifs), bloquée par
/// les murs. `dir` = cap courant (radians). `domainId` = stock de shurikens associé.
class _GardenSpider {
  double x, y, dir;
  final String domainId;
  final int bx0, by0, bx1, by1;
  bool dead = false;
  _GardenSpider(
      this.x, this.y, this.dir, this.domainId, this.bx0, this.by0, this.bx1, this.by1);
}

/// Shuriken d'araignée en vol : ligne droite, tué l'araignée à l'impact.
/// `domainId` = domaine visé (limite le tir au stock de ce domaine).
class _GardenShk {
  double x, y;
  final double vx, vy;
  final int bornMs;
  final String domainId;
  bool dead = false;
  _GardenShk(this.x, this.y, this.vx, this.vy, this.bornMs, this.domainId);
}

// Tour en mode support pendant l'attaque : tire 1/10 s (coûte 1 flamme), se
// recharge via ses flammes-source toutes les 30 s. `aim` = animation de visée.
class _CineTurret {
  final int row;
  final int maxFlames;
  int ammo;
  double cd; // s avant le prochain tir
  double aim = -1; // -1 = repos ; 0..1 = visée en cours (canon plonge/relève)
  double reload; // 0..reloadEvery : cycle de recharge des flammes
  final double reloadEvery; // ≈45 s ± aléatoire (désynchronise les recharges)
  _CineTurret(
      this.row, this.maxFlames, this.ammo, this.cd, this.reloadEvery, this.reload);
}

// Trait de tir de la bataille hebdo (tour → token d'une colonne-jour) ; placeholder
// visuel (couleur du domaine) avant polish.
class _Beam {
  final double fx, fy, tx, ty;
  final int bornMs;
  _Beam(this.fx, this.fy, this.tx, this.ty, this.bornMs);
}

// Boule de feu de SUPPORT : tirée par une tour vers une toile, en ARC (parabole),
// lente, orientée dans le sens du vol. À l'impact (t≥1) → la toile (clé) détruite.
class _CineFb {
  double t = 0; // progression 0..1
  final double dur, fx, fy, tx, ty, arc;
  final String key;
  bool dead = false;
  _CineFb(this.dur, this.fx, this.fy, this.tx, this.ty, this.arc, this.key);
  // Position à un temps donné (lobe vers le HAUT = -y).
  double xAt(double u) => fx + (tx - fx) * u;
  double yAt(double u) => fy + (ty - fy) * u - arc * sin(pi * u);
  double get x => xAt(t);
  double get y => yAt(t);
  // Orientation à un temps u : en MONTÉE (u<0.5) la boule vise le SOMMET de la
  // trajectoire ; en DESCENTE (u≥0.5) elle se réoriente vers la CIBLE.
  double angleAt(double u) {
    final ax = u < 0.5 ? xAt(0.5) : tx;
    final ay = u < 0.5 ? yAt(0.5) : ty;
    final ddx = ax - xAt(u), ddy = ay - yAt(u);
    if (ddx.abs() < 1e-4 && ddy.abs() < 1e-4) {
      return atan2(ty - yAt(u), tx - xAt(u)); // au sommet : bascule vers la cible
    }
    return atan2(ddy, ddx);
  }

  double get angle => angleAt(t);
}

class _Sbire {
  final int id;
  String? src; // toile d'origine (cinématique) : tué → la toile est détruite
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
