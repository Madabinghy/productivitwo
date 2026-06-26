// Prototype « Fluo Adventure — navigation » : les 3 échelles reliées par la fusée.
//
//   🌌 COSMOS    planètes = domaines de vie. 🚀 → entrer dans un domaine.
//   🏠 MAP       1 map / domaine ; pièces = activités. 🚀 (case Entrée) → cosmos.
//                chaque pièce a un terminal ⌗ cliquable → la carte à nœuds.
//   🗺 NODE-MAP  la « grille » à nœuds, INFINIE : on monte de nœud en nœud
//                (combat ⚔ / trésor ◆ / planète 🪐 / boss ☠), de plus en plus
//                loin ; trésors & boss débloquent un item. 🚀 → map.
//
// Données : FluoNavScreen accepte une liste de FluoDomain (vrais domaines +
// activités). Sans données → jeu de démo. lib/web/fluo_data_screen.dart le
// branche sur AppState (?proto=fluo, après auth).
// Dessiné en code. Accès démo standalone : ?proto=fluo (sans données).

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:productivitwo_v1/prototypes/orbit_prototype.dart';
import 'package:productivitwo_v1/prototypes/td_prototype.dart';

void main() => runApp(const FluoNavApp());

class FluoNavApp extends StatelessWidget {
  const FluoNavApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: FluoNavScreen(),
      );
}

// ── Données injectables (vrais domaines / activités) ────────────────────────
// Une activité du domaine. energy = carburant gagné par tes VRAIES séances
// (≈ nombre de séances/coches sur 30 j) ; avancer d'un nœud en consomme.
class FluoActivity {
  const FluoActivity(this.name, {this.energy = 0});
  final String name;
  final int energy;
}

class FluoDomain {
  const FluoDomain(
      {required this.name,
      required this.color,
      required this.activities,
      this.mass = 0.6});
  final String name;
  final Color color;
  final List<FluoActivity> activities;
  final double mass; // 0..1 → taille de la planète (temps, réf. p90)
}

const _demoDoms = <FluoDomain>[
  FluoDomain(name: 'Santé', color: Color(0xFF5BD0A0), mass: 1.0, activities: [
    FluoActivity('Course', energy: 7),
    FluoActivity('Muscu', energy: 4),
    FluoActivity('Sommeil', energy: 9),
    FluoActivity('Repas', energy: 2),
    FluoActivity('Étirement', energy: 1),
  ]),
  FluoDomain(name: 'Travail', color: Color(0xFF35E0FF), mass: 0.8, activities: [
    FluoActivity('Focus', energy: 6),
    FluoActivity('Réunions', energy: 3),
    FluoActivity('Mails', energy: 5),
    FluoActivity('Projets', energy: 4),
    FluoActivity('Veille', energy: 1),
  ]),
  FluoDomain(name: 'Perso', color: Color(0xFFFF5A8A), mass: 0.45, activities: [
    FluoActivity('Lecture', energy: 3),
    FluoActivity('Musique', energy: 2),
    FluoActivity('Amis', energy: 1),
    FluoActivity('Jeux', energy: 0),
    FluoActivity('Sorties', energy: 1),
  ]),
  FluoDomain(name: 'Esprit', color: Color(0xFFA86BFF), mass: 0.6, activities: [
    FluoActivity('Médit.', energy: 5),
    FluoActivity('Journal', energy: 2),
    FluoActivity('Respire', energy: 3),
    FluoActivity('Gratitude', energy: 1),
    FluoActivity('Pause', energy: 2),
  ]),
];

enum _View { cosmos, map, run, room }

// bougie dans une pièce d'étage
class _Candle {
  _Candle(this.pos);
  final Offset pos;
  bool lit = false;
}

// Comportements du boss (couche 1 = aggro selon la distance ; couche 3 = la
// lumière le domine → defense puis dizzy). Un état = une planche d'animation.
enum _BossState { idle, walk, run, attack, defense, dizzy }

// Descripteur d'une planche : asset + grille (colonnes/total) + cadence.
class _BossAnim {
  const _BossAnim(this.asset, this.cols, this.frames, {this.fps = 10});
  final String asset;
  final int cols; // colonnes de la grille (frames de 256 px)
  final int frames; // nombre total de frames
  final double fps;
}

enum NodeKind { start, combat, treasure, planet, boss }

class _MNode {
  _MNode(this.row, this.xFrac, this.kind);
  final int row;
  final double xFrac;
  final NodeKind kind;
  final List<int> links = [];
  bool visited = false;
  bool unlocked = false;
  double worldY = 0;
  double pulse = 0;
}

class FluoNavScreen extends StatefulWidget {
  const FluoNavScreen(
      {super.key, this.data, this.bodies, this.sunFill = 1.0, this.sunLabel});
  final List<FluoDomain>? data; // null → démo
  // Galaxie (niveau 0) = la vraie vue orbit. bodies[i] ↔ data[i] (même ordre).
  final List<OrbitBody>? bodies;
  final double sunFill;
  final String? sunLabel;
  @override
  State<FluoNavScreen> createState() => _FluoNavScreenState();
}

class _FluoNavScreenState extends State<FluoNavScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _t = 0;
  Size _size = Size.zero;
  bool _setup = false;

  late final List<FluoDomain> _doms;
  late final List<OrbitBody> _bodies; // galaxie (niveau 0)

  _View _view = _View.cosmos;
  double _trans = 1.0;
  int _domain = 0;
  int _activity = 0;
  int _itemsUnlocked = 0;
  String? _flash;
  double _flashT = 0;
  // jauge de TEST : luminosité globale 0..1 (simule des « lumens » collectés
  // pour éclairer la map). À retirer/relier à la vraie monnaie plus tard.
  double _lumens = 0;

  // étages : index 0 = cage d'escalier, 1 = entrée, 2+ = activités
  static const int _maxActivityRooms = 5;

  late List<Rect> _px;
  late List<Offset> _planetPx;
  late List<double> _planetR;

  // héros (vue map)
  Offset _hero = Offset.zero;
  Offset _target = Offset.zero;
  Offset _joy = Offset.zero; // direction joystick (-1..1)
  Offset _knob = Offset.zero; // position visuelle du pouce
  static const double _kJoyFactor = 0.6; // joystick un peu plus lent
  static const double _heroR = 13;
  static const double _speed = 240;
  static const double _heroLight = 130;
  // torches allumées dans la map du domaine (indices de pièces 2..6)
  final Set<int> _lit = {};
  // enquête noire : indices trouvés (1 par étage éclairé), verdict
  final List<String> _clues = [];
  bool _carnetOpen = false;
  bool _solved = false;
  String? _verdict;

  // intérieur d'étage : une petite MAP à explorer — plusieurs salles reliées
  // par un mini couloir, le boss au fond. La caméra suit l'avatar (coords monde,
  // map plus grande que l'écran).
  List<Rect> _rooms = [];
  List<Rect> _corridors = [];
  double _roomWorldW = 0;
  double _roomWorldH = 0;
  Offset _roomCam = Offset.zero;
  static const double _roomCorridorOverlap = 18; // couloir mord sur les salles
  Offset _rHero = Offset.zero;
  final List<_Candle> _candles = [];
  Offset _cluePos = Offset.zero;
  bool _clueTaken = false;
  String _clueText = '';
  Offset _guardPos = Offset.zero;
  bool _guardAlive = true;
  bool _inGuardFight = false;
  // Boss (araignée) animé : une planche par état, frames de 256 px.
  // Ajouter un autre boss = un autre jeu de planches sur ce même schéma.
  static const double _bossFrameSize = 256;
  static const double _bossSpeed = 72;
  static const Map<_BossState, _BossAnim> _bossAnims = {
    _BossState.idle: _BossAnim('assets/sprites/boss_spider_idle.png', 6, 24),
    _BossState.walk:
        _BossAnim('assets/sprites/boss_spider_walk.png', 4, 16, fps: 12),
    _BossState.run:
        _BossAnim('assets/sprites/boss_spider_run.png', 4, 16, fps: 16),
    _BossState.attack:
        _BossAnim('assets/sprites/boss_spider_attack.png', 5, 20, fps: 18),
    _BossState.defense:
        _BossAnim('assets/sprites/boss_spider_defense.png', 4, 16),
    _BossState.dizzy:
        _BossAnim('assets/sprites/boss_spider_dizzy.png', 4, 16, fps: 8),
  };
  final Map<_BossState, ui.Image> _bossSheets = {};
  _BossState _bossState = _BossState.idle;
  double _bossAttackT = 0; // wind-up de morsure avant le combat TD

  // node-map (vue run) — carte infinie
  static const double _rowGap = 120;
  final List<_MNode> _nodes = [];
  int _rowCount = 0;
  int _cur = 0;
  int? _movingTo;
  double _moveT = 0;
  double _camY = 0;
  Offset _heroW = Offset.zero;
  int _depth = 0;
  int _energy = 0; // carburant restant (gagné par les vraies séances)
  final Set<int> _wonNodes = {}; // nœuds combat gagnés (✓)
  // butin posé dans les pièces : clé 'domaine:activité' → kinds d'items
  final Map<String, List<int>> _roomItems = {};
  static const int _kItemKinds = 6;
  static const _itemNames = [
    'Trophée',
    'Plante',
    'Cristal',
    'Lampe',
    'Étoile',
    'Fanion'
  ];
  String _actKey(int dom, int act) => '$dom:$act';
  math.Random _runRng = math.Random(1);

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _doms = (d == null || d.isEmpty) ? _demoDoms : d;
    _bodies = widget.bodies ?? _synthBodies(_doms);
    _ticker = createTicker(_tick)..start();
    _loadBossSprite();
  }

  Future<void> _loadBossSprite() async {
    for (final e in _bossAnims.entries) {
      try {
        final img = await _decodeAsset(e.value.asset);
        if (!mounted) return;
        _bossSheets[e.key] = img;
      } catch (_) {
        // planche manquante → fallback cercle pour cet état, jamais bloquant
      }
    }
    if (mounted) setState(() {});
  }

  Future<ui.Image> _decodeAsset(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  // Galaxie de démo (si aucune donnée fournie).
  List<OrbitBody> _synthBodies(List<FluoDomain> ds) => [
        for (var i = 0; i < ds.length; i++)
          OrbitBody(
            name: ds[i].name,
            hot: ds[i].color,
            cold: Color.lerp(ds[i].color, const Color(0xFF6A749A), 0.72)!,
            mass: ds[i].mass,
            angle: i * 1.7,
            days: (i * 3.0).clamp(0.0, OrbitBody.maxDays).toDouble(),
            streak: 0,
          ),
      ];

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  int _activityCount(int domain) =>
      math.min(_maxActivityRooms, _doms[domain].activities.length);

  // une pièce est-elle active pour le domaine courant ?
  bool _roomActive(int i) {
    if (i < 2) return true; // couloir + Entrée
    return (i - 2) < _activityCount(_domain);
  }

  void _build(Size s) {
    _size = s;
    // Manoir vertical : cage d'escalier à gauche (index 0), entrée en bas
    // (index 1), puis 1 étage par activité (index 2+, de bas en haut).
    final nAct = _activityCount(_domain);
    const topPad = 96.0, botPad = 64.0;
    final usableH = math.max(140.0, s.height - topPad - botPad);
    final bands = nAct + 1; // entrée + étages activités
    final bandH = usableH / bands;
    final shaftLeft = s.width * 0.04;
    final shaftW = s.width * 0.12;
    final floorLeft = shaftLeft + shaftW - 8; // chevauche la cage → connexe
    final floorRight = s.width * 0.96;
    _px = [Rect.fromLTWH(shaftLeft, topPad, shaftW, usableH)]; // 0 = escalier
    for (var k = 0; k <= nAct; k++) {
      final top = topPad + usableH - (k + 1) * bandH + 4;
      _px.add(Rect.fromLTWH(floorLeft, top, floorRight - floorLeft, bandH - 8));
    }
    // planètes : anneau autour du centre, taille selon le nb d'activités
    final n = _doms.length;
    final cx = s.width * 0.5, cy = s.height * 0.46;
    final rx = s.width * 0.30, ry = s.height * 0.30;
    _planetPx = [];
    _planetR = [];
    for (var i = 0; i < n; i++) {
      if (n == 1) {
        _planetPx.add(Offset(cx, cy));
      } else {
        final ang = -math.pi / 2 + i * 2 * math.pi / n;
        _planetPx.add(Offset(cx + math.cos(ang) * rx, cy + math.sin(ang) * ry));
      }
      // taille = temps (mass, réf. p90 comme les heatmaps) ; plancher visible
      _planetR.add(18 + _doms[i].mass.clamp(0.0, 1.0) * 30);
    }
    _hero = _px[1].center;
    _target = _hero;
    _setup = true;
  }

  // ── node-map ────────────────────────────────────────────────────────────
  NodeKind _pickKind() {
    final r = _runRng.nextDouble();
    if (r < 0.5) return NodeKind.combat;
    if (r < 0.8) return NodeKind.treasure;
    return NodeKind.planet;
  }

  void _genRow() {
    final r = _rowCount;
    final newIdx = <int>[];
    if (r == 0) {
      _nodes.add(_MNode(0, 0.5, NodeKind.start)..worldY = 0);
      newIdx.add(_nodes.length - 1);
    } else {
      final two = _runRng.nextDouble() < 0.5;
      final xs = two
          ? [0.26 + _runRng.nextDouble() * 0.12, 0.60 + _runRng.nextDouble() * 0.12]
          : [0.36 + _runRng.nextDouble() * 0.28];
      for (final x in xs) {
        final kind = (r % 6 == 0) ? NodeKind.boss : _pickKind();
        _nodes.add(_MNode(r, x, kind)..worldY = -r * _rowGap);
        newIdx.add(_nodes.length - 1);
      }
      final prev = <int>[];
      for (var i = 0; i < _nodes.length; i++) {
        if (_nodes[i].row == r - 1) prev.add(i);
      }
      for (final ni in newIdx) {
        prev.sort((a, b) => (_nodes[a].xFrac - _nodes[ni].xFrac)
            .abs()
            .compareTo((_nodes[b].xFrac - _nodes[ni].xFrac).abs()));
        _nodes[prev.first].links.add(ni);
      }
      for (final pi in prev) {
        if (!_nodes[pi].links.any((l) => _nodes[l].row == r)) {
          newIdx.sort((a, b) => (_nodes[a].xFrac - _nodes[pi].xFrac)
              .abs()
              .compareTo((_nodes[b].xFrac - _nodes[pi].xFrac).abs()));
          _nodes[pi].links.add(newIdx.first);
        }
      }
    }
    _rowCount++;
  }

  // Carte à nœuds (legacy) — conservée mais hors flux actuel (manoir → pièce →
  // gardien). Réintégrable plus tard.
  // ignore: unused_element
  void _initRun() {
    _runRng = math.Random(_domain * 97 + _activity * 31 + 7);
    _nodes.clear();
    _rowCount = 0;
    for (var i = 0; i < 8; i++) {
      _genRow();
    }
    _nodes[0].visited = true;
    _nodes[0].unlocked = true;
    for (final l in _nodes[0].links) {
      _nodes[l].unlocked = true;
    }
    _cur = 0;
    _movingTo = null;
    _moveT = 0;
    _camY = 0;
    _depth = 0;
    _wonNodes.clear();
    final acts = _doms[_domain].activities;
    _energy = _activity < acts.length ? acts[_activity].energy : 0;
    _flash = '⚡ $_energy énergie · ${_curActivity} (tes vraies séances)';
    _flashT = 2.2;
    _heroW = Offset(0.5 * _size.width, 0);
  }

  Offset _nodeWorld(int i) =>
      Offset(_nodes[i].xFrac * _size.width, _nodes[i].worldY);

  Offset _project(Offset world) =>
      Offset(world.dx, _size.height * 0.62 + (world.dy - _camY));

  String get _curActivity {
    final acts = _doms[_domain].activities;
    return _activity < acts.length ? acts[_activity].name : 'Activité';
  }

  void _arrive(int i) {
    final n = _nodes[i];
    n.visited = true;
    _cur = i;
    _depth = math.max(_depth, n.row);
    for (final l in n.links) {
      _nodes[l].unlocked = true;
    }
    switch (n.kind) {
      case NodeKind.treasure:
        _itemsUnlocked++;
        _flash = 'Item débloqué ◆ ($_curActivity)';
        _flashT = 2.2;
        break;
      case NodeKind.boss:
        _itemsUnlocked++;
        _flash = 'Boss vaincu ☠ — item rare débloqué !';
        _flashT = 2.4;
        break;
      case NodeKind.combat:
        _flash = 'Combat ⚔';
        _flashT = 1.2;
        _launchCombat(n.row, i);
        break;
      case NodeKind.planet:
        _flash = 'Planète 🪐 — domaine nourri';
        _flashT = 1.6;
        break;
      case NodeKind.start:
        break;
    }
    while (_rowCount < n.row + 6) {
      _genRow();
    }
  }

  // Ouvre le vrai tower-defense pour un nœud combat. Carburant initial = ta
  // régularité réelle sur l'activité ; objectif (vagues) = profondeur du nœud ;
  // gagner rapporte un item + de l'énergie.
  void _launchCombat(int row, int nodeIndex) {
    final acts = _doms[_domain].activities;
    final e = _activity < acts.length ? acts[_activity].energy : 0;
    final fuel = (e / 10).clamp(0.2, 1.0).toDouble();
    final target = (1 + row ~/ 2).clamp(1, 6);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context)
          .push<bool>(MaterialPageRoute(
            builder: (_) => TdGameScreen(
              initialFuel: fuel,
              combatLabel: 'Combat · ${_curActivity}',
              targetWave: target,
            ),
          ))
          .then((won) {
        if (!mounted) return;
        setState(() {
          if (won == true) {
            final kind = _runRng.nextInt(_kItemKinds);
            (_roomItems[_actKey(_domain, _activity)] ??= []).add(kind);
            _wonNodes.add(nodeIndex);
            _itemsUnlocked++;
            _energy += 2;
            _flash =
                'Combat gagné ⚔ — ${_itemNames[kind]} posé dans ${_curActivity}  +2⚡';
            _flashT = 2.8;
          } else if (won == false) {
            _flash = 'Combat perdu… retente un nœud ⚔';
            _flashT = 2.0;
          }
        });
      });
    });
  }

  // ── enquête noire ─────────────────────────────────────────────────────────
  static const _noirLines = [
    'Une tasse encore tiède traîne près de « {A} »…',
    'Des papiers froissés, planqués sous « {A} ».',
    'Une ombre a rôdé du côté de « {A} » cette semaine.',
    'Trop de silence autour de « {A} ». Suspect.',
    'On a négligé « {A} »… volontairement ?',
    'Une porte de « {A} » fermée à double tour.',
  ];
  String _noirClue(String a) =>
      _noirLines[_clues.length % _noirLines.length].replaceAll('{A}', a);

  void _solveCase() {
    final acts = _doms[_domain].activities;
    if (acts.isEmpty) return;
    var culprit = acts.first;
    for (final a in acts) {
      if (a.energy < culprit.energy) culprit = a;
    }
    setState(() {
      _solved = true;
      _carnetOpen = false;
      _verdict =
          'Le saboteur de ${_doms[_domain].name.toUpperCase()} :\n« ${culprit.name} ».\n\n'
          'Négligée (⚡${culprit.energy}), elle a laissé l\'ombre gagner.\n'
          'Ravive-la pour rallumer le manoir.';
      _flash = 'Enquête résolue 🕵️';
      _flashT = 2.6;
    });
  }

  // ── intérieur d'étage : une MAP à explorer (salles + couloir + boss au fond) ─
  // L'étage n'est plus une seule pièce : c'est une enfilade de salles séparées
  // par un mini couloir. On entre par la 1ʳᵉ salle, on fouille (bougies, indice),
  // et le boss garde la salle du fond. La caméra suit l'avatar.
  void _initRoom(int act) {
    _activity = act;
    _lit.add(act + 2); // l'étage devient « visité » dans le manoir
    final w = _size.width, h = _size.height;
    final rng = math.Random(_domain * 131 + act * 17 + 5);

    const nRooms = 3; // salle d'entrée + salle(s) + salle du boss
    final roomW = w * 0.80;
    final roomH = h * 0.60;
    final corridorW = w * 0.34;
    final corridorH = h * 0.22;
    const topPad = 100.0;
    final cy = topPad + roomH / 2; // axe vertical des couloirs

    _rooms = [];
    _corridors = [];
    for (var k = 0; k < nRooms; k++) {
      final left = k * (roomW + corridorW);
      _rooms.add(Rect.fromLTWH(left, topPad, roomW, roomH));
      if (k < nRooms - 1) {
        // le couloir chevauche les deux salles voisines → passage connexe
        final cLeft = left + roomW - _roomCorridorOverlap;
        final cRight = left + roomW + corridorW + _roomCorridorOverlap;
        _corridors.add(Rect.fromLTWH(
            cLeft, cy - corridorH / 2, cRight - cLeft, corridorH));
      }
    }
    _roomWorldW = (nRooms - 1) * (roomW + corridorW) + roomW;
    _roomWorldH = topPad + roomH + 80;

    Offset rp(Rect room) {
      final r = room.deflate(40);
      return Offset(r.left + rng.nextDouble() * r.width,
          r.top + rng.nextDouble() * r.height);
    }

    // bougies réparties dans toutes les salles (l'entrée en a deux)
    _candles
      ..clear()
      ..addAll([
        for (var k = 0; k < nRooms; k++) _Candle(rp(_rooms[k])),
        _Candle(rp(_rooms.first)),
      ]);
    // indice dans une salle intermédiaire
    _cluePos = rp(_rooms[nRooms ~/ 2]);
    _clueTaken = false;
    _clueText = _noirClue(_doms[_domain].activities[act].name);
    // boss au fond (dernière salle), héros à l'entrée (première salle)
    final boss = _rooms.last;
    _guardPos = Offset(boss.center.dx, boss.top + 64);
    _guardAlive = true;
    _inGuardFight = false;
    _bossState = _BossState.idle;
    _bossAttackT = 0;
    _rHero = Offset(_rooms.first.center.dx, _rooms.first.bottom - 44);
    _roomCam = _clampRoomCam(_rHero - Offset(w / 2, h / 2));
  }

  // borne la caméra de la pièce à l'intérieur du monde (pas de hors-map)
  Offset _clampRoomCam(Offset c) {
    final maxX = math.max(0.0, _roomWorldW - _size.width);
    final maxY = math.max(0.0, _roomWorldH - _size.height);
    return Offset(c.dx.clamp(0.0, maxX), c.dy.clamp(0.0, maxY));
  }

  // marchable dans la map d'étage = à l'intérieur d'une salle OU d'un couloir
  bool _roomWalkable(Offset p) {
    for (final r in _rooms) {
      if (r.inflate(-_heroR * 0.4).contains(p)) return true;
    }
    for (final c in _corridors) {
      if (c.inflate(-_heroR * 0.3).contains(p)) return true;
    }
    return false;
  }

  void _fightGuardian() {
    if (_inGuardFight) return;
    _inGuardFight = true;
    final acts = _doms[_domain].activities;
    final e = _activity < acts.length ? acts[_activity].energy : 0;
    final fuel = (e / 10).clamp(0.2, 1.0).toDouble();
    final target = 2 + (_activity % 3);
    final name = acts[_activity].name;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context)
          .push<bool>(MaterialPageRoute(
            builder: (_) => TdGameScreen(
                initialFuel: fuel,
                combatLabel: 'Gardien · $name',
                targetWave: target),
          ))
          .then((won) {
        _inGuardFight = false;
        if (!mounted) return;
        setState(() {
          // éloigne le héros du boss (bas de la salle du fond), boss au repos
          _rHero = Offset(_rooms.last.center.dx, _rooms.last.bottom - 44);
          _bossState = _BossState.idle;
          _bossAttackT = 0;
          if (won == true) {
            _guardAlive = false;
            _itemsUnlocked++;
            (_roomItems[_actKey(_domain, _activity)] ??= [])
                .add(_itemsUnlocked % _kItemKinds);
            _flash = 'Boss vaincu ⚔ — étage nettoyé, butin ◆';
            _flashT = 2.6;
          } else if (won == false) {
            _flash = 'Le boss tient bon… reviens plus fort';
            _flashT = 2.0;
          }
        });
      });
    });
  }

  // ── comportements du boss (couche 1 distance + couche 3 lumière) ──────────
  // Le boss garde la salle du fond. Peu de lumière → il chasse le héros
  // (idle → walk → run → morsure = combat TD). On monte les lumens → il se
  // protège (defense) puis se fait éblouir (dizzy = fenêtre sûre).
  void _updateBoss(double dt) {
    if (!_guardAlive || _inGuardFight || _rooms.isEmpty) return;
    final bossRoom = _rooms.last;
    final toHero = _rHero - _guardPos;
    final d = toHero.distance;
    final dir = d > 0.001 ? toHero / d : const Offset(0, 1);

    // couche 3 : la lumière domine l'araignée
    if (_lumens >= 0.80) {
      _bossState = _BossState.dizzy; // ébloui → ne bouge plus, n'attaque pas
      _bossAttackT = 0;
      return;
    }
    if (_lumens >= 0.50) {
      _bossState = _BossState.defense; // se protège et recule vers le fond
      _bossAttackT = 0;
      _moveBoss(-dir * _bossSpeed * 0.5 * dt, bossRoom);
      return;
    }

    // couche 1 : aggro selon la distance (peu de lumière)
    if (_bossAttackT > 0) {
      _bossState = _BossState.attack;
      _bossAttackT -= dt;
      if (_bossAttackT <= 0) _fightGuardian(); // la morsure ouvre le combat TD
      return;
    }
    const aggroR = 240.0, runR = 130.0, biteR = 56.0;
    if (d <= biteR) {
      _bossState = _BossState.attack;
      _bossAttackT = 0.45; // wind-up visible avant le TD
    } else if (d <= runR) {
      _bossState = _BossState.run;
      _moveBoss(dir * _bossSpeed * 1.7 * dt, bossRoom);
    } else if (d <= aggroR) {
      _bossState = _BossState.walk;
      _moveBoss(dir * _bossSpeed * dt, bossRoom);
    } else {
      _bossState = _BossState.idle;
    }
  }

  void _moveBoss(Offset step, Rect room) {
    final r = room.deflate(46);
    final n = _guardPos + step;
    _guardPos =
        Offset(n.dx.clamp(r.left, r.right), n.dy.clamp(r.top, r.bottom));
  }

  void _go(_View v) {
    setState(() {
      _view = v;
      _trans = 0;
    });
  }

  bool _walkable(Offset p) {
    for (var i = 0; i < _px.length; i++) {
      if (!_roomActive(i)) continue;
      if (_px[i].inflate(-_heroR * 0.4).contains(p)) return true;
    }
    return false;
  }

  void _tick(Duration e) {
    final dt = (e - _last).inMicroseconds / 1e6;
    _last = e;
    if (!_setup || dt <= 0 || dt > 0.08) {
      setState(() {});
      return;
    }
    _t += dt;
    if (_flashT > 0) _flashT -= dt;
    if (_trans < 1) _trans = (_trans + dt * 2.4).clamp(0.0, 1.0);

    if (_view == _View.map) {
      // joystick prioritaire ; sinon tap-to-move
      if (_joy.distance > 0.08) {
        _target = _hero; // coupe le tap-to-move
        final step = _joy * _speed * _kJoyFactor * dt;
        if (_walkable(_hero + step)) {
          _hero += step;
        } else if (_walkable(_hero + Offset(step.dx, 0))) {
          _hero += Offset(step.dx, 0);
        } else if (_walkable(_hero + Offset(0, step.dy))) {
          _hero += Offset(0, step.dy);
        }
      } else {
        final to = _target - _hero;
        final dist = to.distance;
        if (dist > 1) {
          final dir = to / dist;
          final step = dir * math.min(_speed * dt, dist);
          if (_walkable(_hero + step)) {
            _hero += step;
          } else if (_walkable(_hero + Offset(step.dx, 0))) {
            _hero += Offset(step.dx, 0);
          } else if (_walkable(_hero + Offset(0, step.dy))) {
            _hero += Offset(0, step.dy);
          } else {
            _target = _hero;
          }
        }
      }
      // révèle un étage en s'en approchant (le nom sort de l'ombre)
      final n = _activityCount(_domain);
      for (var i = 2; i < 2 + n; i++) {
        if (_lit.contains(i)) continue;
        if ((_px[i].center - _hero).distance < 34) {
          _lit.add(i);
          _flash = 'Étage trouvé — touche-le pour y entrer';
          _flashT = 1.6;
        }
      }
    } else if (_view == _View.room) {
      // déplacement joystick : libre tant qu'on reste sur une salle ou un couloir
      if (_joy.distance > 0.08) {
        final step = _joy * _speed * _kJoyFactor * dt;
        if (_roomWalkable(_rHero + step)) {
          _rHero += step;
        } else if (_roomWalkable(_rHero + Offset(step.dx, 0))) {
          _rHero += Offset(step.dx, 0);
        } else if (_roomWalkable(_rHero + Offset(0, step.dy))) {
          _rHero += Offset(0, step.dy);
        }
      }
      // la caméra suit l'avatar (map d'étage plus grande que l'écran)
      final tc =
          _clampRoomCam(_rHero - Offset(_size.width / 2, _size.height / 2));
      _roomCam += (tc - _roomCam) * math.min(1.0, dt * 6);
      for (final c in _candles) {
        if (!c.lit && (c.pos - _rHero).distance < 30) {
          c.lit = true;
          _flash = 'Bougie allumée';
          _flashT = 0.9;
        }
      }
      if (!_clueTaken && (_cluePos - _rHero).distance < 28) {
        _clueTaken = true;
        _clues.add(_clueText);
        _flash = 'Indice ramassé 🔍 (${_clues.length})';
        _flashT = 1.8;
      }
      _updateBoss(dt);
    } else if (_view == _View.run && _nodes.isNotEmpty) {
      for (final n in _nodes) {
        n.pulse += dt;
      }
      _camY += (_nodes[_cur].worldY - _camY) * math.min(1.0, dt * 4);
      final mt = _movingTo;
      if (mt != null) {
        _moveT = (_moveT + dt * 1.8).clamp(0.0, 1.0);
        _heroW = Offset.lerp(_nodeWorld(_cur), _nodeWorld(mt),
            Curves.easeInOut.transform(_moveT))!;
        if (_moveT >= 1) {
          _arrive(mt);
          _movingTo = null;
        }
      } else {
        _heroW = _nodeWorld(_cur).translate(0, math.sin(_t * 2.2) * 2);
      }
    }
    setState(() {});
  }

  void _onTapCanvas(Offset p) {
    if (_trans < 0.6) return;
    switch (_view) {
      case _View.cosmos:
        for (var i = 0; i < _planetPx.length; i++) {
          if ((_planetPx[i] - p).distance <= _planetR[i] + 16) {
            _domain = i;
            _go(_View.map);
            return;
          }
        }
        break;
      case _View.map:
        // tape un étage révélé → entre dans sa pièce
        for (var i = 2; i < _px.length; i++) {
          if (!_roomActive(i) || !_lit.contains(i)) continue;
          if (_px[i].contains(p)) {
            _initRoom(i - 2);
            _go(_View.room);
            return;
          }
        }
        if (_walkable(p)) {
          _target = p;
        } else {
          Offset? best;
          double bd = double.infinity;
          for (var i = 0; i < _px.length; i++) {
            if (!_roomActive(i)) continue;
            final r = _px[i];
            final c = Offset(p.dx.clamp(r.left + _heroR, r.right - _heroR),
                p.dy.clamp(r.top + _heroR, r.bottom - _heroR));
            final d = (c - p).distance;
            if (d < bd) {
              bd = d;
              best = c;
            }
          }
          if (best != null) _target = best;
        }
        break;
      case _View.run:
        if (_movingTo != null) return;
        for (var i = 0; i < _nodes.length; i++) {
          final n = _nodes[i];
          if (!n.unlocked || n.visited) continue;
          if (!_nodes[_cur].links.contains(i)) continue;
          if ((_project(_nodeWorld(i)) - p).distance <= 28) {
            if (_energy <= 0) {
              _flash = 'Plus d\'énergie — fais une séance de ${_curActivity}';
              _flashT = 2.2;
              return;
            }
            _energy -= 1; // avancer coûte du carburant réel
            _movingTo = i;
            _moveT = 0;
            return;
          }
        }
        break;
      case _View.room:
        break; // déplacement au joystick
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070F),
      body: LayoutBuilder(builder: (context, c) {
        final s = Size(c.maxWidth, c.maxHeight);
        if (!_setup || s != _size) _build(s);
        final Widget content;
        if (_view == _View.cosmos) {
          // niveau 0 = la vraie galaxie orbit (planètes autour d'Aujourd'hui)
          content = OrbitView(
            bodies: _bodies,
            interactive: false,
            sunFill: widget.sunFill,
            sunLabel: widget.sunLabel,
            onTapBody: (b) {
              final i = _bodies.indexOf(b);
              if (i >= 0) {
                setState(() {
                  _domain = i;
                  _lit.clear();
                  _clues.clear();
                  _solved = false;
                  _verdict = null;
                  _carnetOpen = false;
                  _build(_size); // recalcule les étages pour ce domaine
                  _hero = _px[1].center;
                  _target = _hero;
                  _view = _View.map;
                  _trans = 0;
                });
              }
            },
          );
        } else {
          content = GestureDetector(
            onTapDown: (d) => _onTapCanvas(d.localPosition),
            child: CustomPaint(size: s, painter: _NavPainter(this)),
          );
        }
        return Stack(children: [
          Positioned.fill(child: content),
          if (_view != _View.cosmos)
            Positioned(
              left: 14,
              top: 14,
              child: _backBtn(
                  () => _go(_view == _View.map ? _View.cosmos : _View.map)),
            ),
          // bouton de test : simule une vraie séance (recharge le carburant)
          if (_view == _View.run)
            Positioned(
              right: 14,
              bottom: 18,
              child: _energyBtn(),
            ),
          // manoir-enquête : carnet d'indices + résoudre
          if (_view == _View.map && _activityCount(_domain) > 0) ...[
            Positioned(
              left: 14,
              bottom: 18,
              child: _pill('🔍 Carnet ${_clues.length}', const Color(0xFFFFB35A),
                  () => setState(() => _carnetOpen = !_carnetOpen)),
            ),
            if (_clues.length >= _activityCount(_domain) && !_solved)
              Positioned(
                right: 14,
                bottom: 18,
                child: _pill('🕵️ Résoudre', const Color(0xFFB6FF3C), _solveCase),
              ),
          ],
          if (_view == _View.map && _carnetOpen) _carnetPanel(),
          if (_view == _View.map && _solved && _verdict != null) _verdictPanel(),
          // joystick de déplacement (à droite) — manoir + pièce d'étage
          if (_view == _View.map || _view == _View.room)
            Positioned(right: 18, bottom: 32, child: _joystick()),
          // jauge de TEST : règle la luminosité globale (simule des lumens)
          if (_view == _View.map || _view == _View.room)
            Positioned(top: 50, right: 12, child: _lumensSlider()),
        ]);
      }),
    );
  }

  void _updateJoy(Offset local, double r) {
    var d = local - Offset(r, r);
    final len = d.distance;
    final maxR = r * 0.66;
    if (len > maxR) d = d / len * maxR;
    setState(() {
      _knob = d;
      _joy = Offset(d.dx / maxR, d.dy / maxR);
    });
  }

  Widget _joystick() {
    const sz = 116.0;
    const r = sz / 2;
    return GestureDetector(
      onPanStart: (e) => _updateJoy(e.localPosition, r),
      onPanUpdate: (e) => _updateJoy(e.localPosition, r),
      onPanEnd: (_) => setState(() {
        _joy = Offset.zero;
        _knob = Offset.zero;
      }),
      child: Container(
        width: sz,
        height: sz,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.04),
          border: Border.all(
              color: const Color(0xFF35E0FF).withOpacity(0.35), width: 1.5),
        ),
        child: Center(
          child: Transform.translate(
            offset: _knob,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF35E0FF).withOpacity(0.22),
                border:
                    Border.all(color: const Color(0xFF35E0FF), width: 2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // jauge de test : glisser pour éclairer toute la map (lumens simulés)
  Widget _lumensSlider() => Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1422).withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFE08A).withOpacity(0.7)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('💡 Lumens (test) ${(_lumens * 100).round()}%',
              style: const TextStyle(
                  color: Color(0xFFFFE08A),
                  fontWeight: FontWeight.w800,
                  fontSize: 11)),
          SizedBox(
            width: 150,
            height: 26,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: const Color(0xFFFFE08A),
                inactiveTrackColor: Colors.white24,
                thumbColor: const Color(0xFFFFE08A),
              ),
              child: Slider(
                value: _lumens,
                onChanged: (v) => setState(() => _lumens = v),
              ),
            ),
          ),
        ]),
      );

  Widget _pill(String label, Color c, VoidCallback onTap) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.withOpacity(0.8)),
            ),
            child: Text(label,
                style: TextStyle(
                    color: c, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ),
      );

  Widget _carnetPanel() => Positioned.fill(
        child: GestureDetector(
          onTap: () => setState(() => _carnetOpen = false),
          child: Container(
            color: Colors.black.withOpacity(0.6),
            alignment: Alignment.center,
            child: Container(
              margin: const EdgeInsets.all(28),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0D12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFB35A).withOpacity(0.5)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('🔍 Carnet d\'enquête',
                    style: TextStyle(
                        color: Color(0xFFFFB35A),
                        fontWeight: FontWeight.w900,
                        fontSize: 18)),
                const SizedBox(height: 12),
                if (_clues.isEmpty)
                  const Text('Aucun indice. Explore les étages dans le noir.',
                      style: TextStyle(color: Colors.white70))
                else
                  ..._clues.map((c) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ',
                                  style: TextStyle(color: Color(0xFFFFB35A))),
                              Expanded(
                                  child: Text(c,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 13))),
                            ]),
                      )),
                const SizedBox(height: 12),
                Text('Touche pour fermer',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.4), fontSize: 11)),
              ]),
            ),
          ),
        ),
      );

  Widget _verdictPanel() => Positioned.fill(
        child: GestureDetector(
          onTap: () => setState(() => _verdict = null),
          child: Container(
            color: Colors.black.withOpacity(0.72),
            alignment: Alignment.center,
            child: Container(
              margin: const EdgeInsets.all(28),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0D12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFB6FF3C).withOpacity(0.6)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('🕵️ Verdict',
                    style: TextStyle(
                        color: Color(0xFFB6FF3C),
                        fontWeight: FontWeight.w900,
                        fontSize: 20)),
                const SizedBox(height: 14),
                Text(_verdict ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14, height: 1.4)),
                const SizedBox(height: 16),
                Text('Touche pour fermer',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.4), fontSize: 11)),
              ]),
            ),
          ),
        ),
      );

  Widget _energyBtn() => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() {
            _energy += 1;
            _flash = '⚡ +1 énergie (séance simulée)';
            _flashT = 1.4;
          }),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE08A).withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFE08A).withOpacity(0.8)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('⚡', style: TextStyle(fontSize: 15)),
              SizedBox(width: 6),
              Text('+séance (test)',
                  style: TextStyle(
                      color: Color(0xFFFFE08A),
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
            ]),
          ),
        ),
      );

  Widget _backBtn(VoidCallback onTap) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF35E0FF).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF35E0FF).withOpacity(0.8)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.arrow_back, color: Color(0xFF35E0FF), size: 16),
              SizedBox(width: 6),
              Text('Retour',
                  style: TextStyle(
                      color: Color(0xFF35E0FF),
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
            ]),
          ),
        ),
      );
}

class _NavPainter extends CustomPainter {
  _NavPainter(this.g);
  final _FluoNavScreenState g;

  static const _kindColor = {
    NodeKind.start: Color(0xFF7DFFCE),
    NodeKind.combat: Color(0xFFFF3DDA),
    NodeKind.treasure: Color(0xFFFFD36B),
    NodeKind.planet: Color(0xFFA86BFF),
    NodeKind.boss: Color(0xFFFF4D5E),
  };
  static const _kindIcon = {
    NodeKind.start: '⌂',
    NodeKind.combat: '⚔',
    NodeKind.treasure: '◆',
    NodeKind.planet: '🪐',
    NodeKind.boss: '☠',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ease = Curves.easeOut.transform(g._trans);
    canvas.saveLayer(rect, Paint()..color = Colors.white.withOpacity(ease));
    final sc = 1.06 - 0.06 * ease;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(sc);
    canvas.translate(-size.width / 2, -size.height / 2);

    switch (g._view) {
      case _View.cosmos:
        _paintCosmos(canvas, size);
        break;
      case _View.map:
        _paintMap(canvas, size);
        break;
      case _View.run:
        _paintRun(canvas, size);
        break;
      case _View.room:
        _paintRoom(canvas, size);
        break;
    }
    canvas.restore();
    canvas.restore();
    _paintFlash(canvas, size);
  }

  // ── COSMOS ────────────────────────────────────────────────────────────────
  void _paintCosmos(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.2,
            colors: [Color(0xFF231C52), Color(0xFF120F35), Color(0xFF07061A)],
          ).createShader(rect));
    final rnd = math.Random(3);
    for (var i = 0; i < 80; i++) {
      final x = rnd.nextDouble() * size.width, y = rnd.nextDouble() * size.height;
      final tw = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(g._t * 1.5 + i));
      canvas.drawCircle(Offset(x, y), rnd.nextDouble() * 1.4 + 0.4,
          Paint()..color = Colors.white.withOpacity(0.5 * tw));
    }
    for (var i = 0; i < g._planetPx.length; i++) {
      final p = g._planetPx[i];
      final pr = g._planetR[i];
      final dom = g._doms[i];
      final pulse = 1 + 0.03 * math.sin(g._t * 2 + i);
      _glow(canvas, p, pr * 1.7, dom.color.withOpacity(0.35));
      canvas.drawCircle(
          p,
          pr * pulse,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.4, -0.4),
              colors: [Colors.white.withOpacity(0.9), dom.color, dom.color],
              stops: const [0.0, 0.4, 1.0],
            ).createShader(Rect.fromCircle(center: p, radius: pr)));
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(-0.4);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: pr * 3, height: pr),
          _stroke(dom.color.withOpacity(0.5), 2));
      canvas.restore();
      _text(canvas, dom.name, p.translate(0, pr + 18), Colors.white, 15,
          weight: FontWeight.w800);
      _text(canvas, '${dom.activities.length} act.', p.translate(0, pr + 36),
          Colors.white.withOpacity(0.45), 11);
      _text(canvas, '🚀', p.translate(pr * 0.7, -pr * 0.7), Colors.white, 16);
    }
    _text(canvas, 'COSMOS', Offset(size.width / 2, 30), const Color(0xFFB6FF3C),
        22, weight: FontWeight.w900);
    _text(canvas, 'Tes domaines de vie · touche une planète pour y voyager 🚀',
        Offset(size.width / 2, 54), const Color(0xFF8FA0C8), 12);
    _text(canvas, 'Items débloqués : ${g._itemsUnlocked}',
        Offset(size.width / 2, size.height - 24), const Color(0xFFFFD36B), 12,
        weight: FontWeight.w700);
  }

  // ── MANOIR NOIR (domaine) : 1 étage par activité, plongé dans l'ombre ──────
  void _paintMap(Canvas canvas, Size size) {
    final dom = g._doms[g._domain];
    final rect = Offset.zero & size;
    final accent = Color.lerp(dom.color, const Color(0xFF8090A0), 0.45)!; // désaturé noir
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.3,
            colors: [Color(0xFF12151C), Color(0xFF0A0B10), Color(0xFF050608)],
          ).createShader(rect));
    final nAct = g._activityCount(g._domain);

    // 1. structure du manoir (sol/murs) — révélée par la lumière
    // cage d'escalier (index 0)
    final shaft = g._px[0];
    canvas.drawRRect(RRect.fromRectAndRadius(shaft, const Radius.circular(4)),
        Paint()..color = const Color(0xFF0C0E14));
    canvas.drawRRect(RRect.fromRectAndRadius(shaft, const Radius.circular(4)),
        _stroke(accent.withOpacity(0.3), 1.4));
    for (double y = shaft.top + 14; y < shaft.bottom; y += 18) {
      canvas.drawLine(Offset(shaft.left + 4, y), Offset(shaft.right - 4, y),
          _stroke(const Color(0xFF1A1E28), 1.2));
    }
    // étages (entrée index 1 + activités 2+)
    for (var i = 1; i < g._px.length; i++) {
      if (!g._roomActive(i)) continue;
      final px = g._px[i];
      final rr = RRect.fromRectAndRadius(px, const Radius.circular(5));
      final lit = i == 1 || g._lit.contains(i);
      canvas.drawRRect(rr, Paint()..color = const Color(0xFF0B0D12));
      if (lit && i >= 2) {
        canvas.drawRRect(rr, Paint()..color = accent.withOpacity(0.10));
      }
      canvas.drawRRect(rr, _stroke(accent.withOpacity(lit ? 0.6 : 0.22), 1.6));
    }
    // torches éteintes (révélées quand la lampe du héros passe)
    for (var i = 2; i < 2 + nAct; i++) {
      if (!g._lit.contains(i)) {
        _drawTorch(canvas, Offset(g._px[i].left + 26, g._px[i].center.dy), false);
      }
    }

    // 2. voile d'ombre noir, percé par la lampe du héros + les étages fouillés
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(
        rect,
        Paint()
          ..color = const Color(0xFF05060B)
              .withOpacity((0.90 - 0.82 * g._lumens).clamp(0.0, 1.0)));
    _punch(canvas, g._hero,
        _FluoNavScreenState._heroLight * (1 + g._lumens));
    for (final i in g._lit) {
      _punch(canvas, g._px[i].center,
          math.min(g._px[i].width, g._px[i].height) * 1.1);
    }
    canvas.restore();

    // 3. au-dessus du voile : étages éclairés (lampe + nom + ⚡ + indice + ⌗)
    _text(canvas, 'Entrée', Offset(g._px[1].center.dx, g._px[1].center.dy),
        Colors.white.withOpacity(0.6), 12, weight: FontWeight.w700);
    for (var i = 2; i < 2 + nAct; i++) {
      if (!g._lit.contains(i)) continue;
      final px = g._px[i];
      final act = dom.activities[i - 2];
      final cy = px.center.dy;
      _drawTorch(canvas, Offset(px.left + 26, cy + 4), true);
      _text(canvas, act.name, Offset(px.center.dx, cy - 7),
          Colors.white.withOpacity(0.92), 13, weight: FontWeight.w700);
      _text(canvas, '⚡${act.energy} · ▸ entrer', Offset(px.center.dx, cy + 9),
          const Color(0xFFFFB35A).withOpacity(0.8), 10, weight: FontWeight.w700);
      // butin posé (items gagnés en combat)
      final items = g._roomItems[g._actKey(g._domain, i - 2)] ?? const [];
      for (var k = 0; k < items.length && k < 6; k++) {
        _drawItem(canvas, Offset(px.left + 70 + k * 18, cy), items[k]);
      }
    }

    _drawHero(canvas, g._hero, const Color(0xFFB6FF3C));

    // HUD
    _text(canvas, 'MANOIR · ${dom.name.toUpperCase()}',
        Offset(size.width / 2, 30), accent, 20, weight: FontWeight.w900);
    if (nAct == 0) {
      _text(canvas, 'Aucune activité dans ce domaine',
          Offset(size.width / 2, size.height / 2),
          Colors.white.withOpacity(0.5), 14);
    } else {
      _text(
          canvas,
          g._solved
              ? 'Enquête résolue 🕵️'
              : 'Explore les étages dans le noir · 1 indice par étage',
          Offset(size.width / 2, 52),
          const Color(0xFF8FA0C8),
          12);
      _text(canvas, '🔍 Indices ${g._clues.length}/$nAct',
          Offset(size.width / 2, size.height - 24),
          const Color(0xFFFFB35A), 13, weight: FontWeight.w700);
    }
  }

  // ── MAP D'ÉTAGE : salles séparées par un mini couloir, le boss au fond ─────
  // Le monde est plus grand que l'écran : la caméra (g._roomCam) suit l'avatar.
  void _paintRoom(Canvas canvas, Size size) {
    final dom = g._doms[g._domain];
    final act = dom.activities[g._activity];
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF050608));

    final cam = g._roomCam;
    canvas.save();
    canvas.translate(-cam.dx, -cam.dy);

    // Sol continu : salles + couloirs partagent la même couleur de sol, puis on
    // ne trace les murs QUE là où il n'y a pas d'ouverture → aucun mur entre un
    // couloir et la salle qu'il dessert.
    const floor = Color(0xFF0B0D12);
    final grid = _stroke(const Color(0xFF161A22), 1);
    final wallN = _stroke(const Color(0xFF7C8AA0).withOpacity(0.5), 2);

    void fillAndGrid(Rect r) {
      canvas.drawRect(r, Paint()..color = floor);
      canvas.save();
      canvas.clipRect(r);
      for (double x = r.left; x < r.right; x += 30) {
        canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), grid);
      }
      for (double y = r.top; y < r.bottom; y += 30) {
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
      }
      canvas.restore();
    }

    for (final c in g._corridors) {
      fillAndGrid(c);
    }
    for (final room in g._rooms) {
      fillAndGrid(room);
    }

    // murs des couloirs : uniquement entre deux salles (le reste = ouverture)
    for (var k = 0; k < g._corridors.length; k++) {
      final c = g._corridors[k];
      final a = g._rooms[k], b = g._rooms[k + 1];
      canvas.drawLine(Offset(a.right, c.top), Offset(b.left, c.top), wallN);
      canvas.drawLine(Offset(a.right, c.bottom), Offset(b.left, c.bottom), wallN);
    }

    // murs des salles : pleins, sauf l'ouverture vers le(s) couloir(s)
    for (var ri = 0; ri < g._rooms.length; ri++) {
      final room = g._rooms[ri];
      final isBoss = ri == g._rooms.length - 1;
      final wall = isBoss
          ? _stroke(const Color(0xFFFF4D5E).withOpacity(0.5), 2)
          : wallN;
      canvas.drawLine(room.topLeft, room.topRight, wall);
      canvas.drawLine(room.bottomLeft, room.bottomRight, wall);
      // gauche : ouverture si un couloir arrive de la gauche
      final leftGap = ri > 0 ? g._corridors[ri - 1] : null;
      if (leftGap == null) {
        canvas.drawLine(room.topLeft, room.bottomLeft, wall);
      } else {
        canvas.drawLine(room.topLeft, Offset(room.left, leftGap.top), wall);
        canvas.drawLine(
            Offset(room.left, leftGap.bottom), room.bottomLeft, wall);
      }
      // droite : ouverture si un couloir part vers la droite
      final rightGap = ri < g._corridors.length ? g._corridors[ri] : null;
      if (rightGap == null) {
        canvas.drawLine(room.topRight, room.bottomRight, wall);
      } else {
        canvas.drawLine(room.topRight, Offset(room.right, rightGap.top), wall);
        canvas.drawLine(
            Offset(room.right, rightGap.bottom), room.bottomRight, wall);
      }
    }

    // contenu (indice, boss, bougies) — voilé puis révélé par la lumière
    if (!g._clueTaken) {
      final pz = 0.6 + 0.4 * math.sin(g._t * 4);
      _glow(canvas, g._cluePos, 14 * pz, const Color(0xFFFFD36B).withOpacity(0.5));
      _text(canvas, '🔍', g._cluePos, const Color(0xFFFFE08A), 18);
    }
    if (g._guardAlive) _drawBoss(canvas, g._guardPos);
    for (final c in g._candles) {
      _drawTorch(canvas, c.pos, c.lit);
    }

    // voile d'ombre sur la zone visible, percé par la lampe + bougies allumées
    final visible = Rect.fromLTWH(cam.dx, cam.dy, size.width, size.height);
    canvas.saveLayer(visible, Paint());
    canvas.drawRect(
        visible,
        Paint()
          ..color = const Color(0xFF05060B)
              .withOpacity((0.92 - 0.84 * g._lumens).clamp(0.0, 1.0)));
    _punch(canvas, g._rHero, 120 * (1 + g._lumens));
    for (final c in g._candles) {
      if (c.lit) _punch(canvas, c.pos, 90);
    }
    canvas.restore();

    _drawHero(canvas, g._rHero, const Color(0xFFB6FF3C));
    canvas.restore();

    // HUD (espace écran, hors caméra)
    _text(canvas, 'ÉTAGE · ${act.name.toUpperCase()}',
        Offset(size.width / 2, 30), const Color(0xFF7C8AA0), 18,
        weight: FontWeight.w900);
    final litN = g._candles.where((c) => c.lit).length;
    _text(
        canvas,
        g._guardAlive
            ? 'Explore · ramasse l\'indice · monte les 💡 lumens pour éblouir le boss'
            : 'Étage nettoyé ✓ — reviens au manoir',
        Offset(size.width / 2, 52),
        const Color(0xFF8FA0C8),
        11);
    _text(
        canvas,
        '🕯 $litN/${g._candles.length}   ·   🔍 ${g._clueTaken ? "indice ✓" : "indice ?"}',
        Offset(size.width / 2, size.height - 24),
        const Color(0xFFFFB35A),
        12,
        weight: FontWeight.w700);
    // boussole : le boss est hors-champ à droite → indique la direction
    if (g._guardAlive && g._guardPos.dx - cam.dx > size.width - 8) {
      _text(canvas, 'Boss →', Offset(size.width - 48, size.height / 2),
          const Color(0xFFFF4D5E).withOpacity(0.85), 13,
          weight: FontWeight.w800);
    }
  }

  void _drawTorch(Canvas canvas, Offset p, bool lit) {
    canvas.drawLine(p.translate(0, 2), p.translate(0, 13),
        _stroke(const Color(0xFF6A5A40), 2.4));
    if (lit) {
      final f = 0.8 + 0.2 * math.sin(g._t * 9 + p.dx);
      _glow(canvas, p.translate(0, -4), 18 * f, const Color(0xFFFFB35A));
      final flame = Path()
        ..moveTo(p.dx - 5, p.dy)
        ..quadraticBezierTo(p.dx - 4, p.dy - 12 * f, p.dx, p.dy - 16 * f)
        ..quadraticBezierTo(p.dx + 4, p.dy - 12 * f, p.dx + 5, p.dy)
        ..close();
      canvas.drawPath(flame, Paint()..color = const Color(0xFFFF8A2B));
      canvas.drawPath(
          Path()
            ..moveTo(p.dx - 2.5, p.dy - 1)
            ..quadraticBezierTo(p.dx, p.dy - 9 * f, p.dx + 2.5, p.dy - 1)
            ..close(),
          Paint()..color = const Color(0xFFFFE08A));
    } else {
      canvas.drawCircle(p.translate(0, -3), 5,
          Paint()..color = const Color(0xFF2A2230));
      canvas.drawCircle(p.translate(0, -3), 5,
          _stroke(const Color(0xFFFFB35A).withOpacity(0.5), 1.4));
    }
  }

  // ── NODE-MAP (carte infinie) ───────────────────────────────────────────────
  void _paintRun(Canvas canvas, Size size) {
    final dom = g._doms[g._domain];
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(0, -0.1),
            radius: 1.2,
            colors: [Color(0xFF1A1440), Color(0xFF0B0A22), Color(0xFF05070F)],
          ).createShader(rect));
    final rnd = math.Random(5);
    for (var i = 0; i < 70; i++) {
      final sx = rnd.nextDouble() * size.width;
      final sy = (rnd.nextDouble() * size.height - g._camY * 0.2) % size.height;
      canvas.drawCircle(Offset(sx, sy < 0 ? sy + size.height : sy),
          rnd.nextDouble() * 1.3 + 0.3, Paint()..color = Colors.white.withOpacity(0.4));
    }

    if (g._nodes.isEmpty) return;

    for (var i = 0; i < g._nodes.length; i++) {
      final n = g._nodes[i];
      final a = g._project(g._nodeWorld(i));
      if (a.dy < -60 || a.dy > size.height + 60) continue;
      for (final l in n.links) {
        final b = g._project(g._nodeWorld(l));
        final live = n.visited || (n.unlocked && g._nodes[l].unlocked);
        canvas.drawLine(
            a,
            b,
            Paint()
              ..strokeWidth = live ? 3 : 1.5
              ..color = (live
                      ? const Color(0xFF8FE9FF)
                      : const Color(0xFF3A4570))
                  .withOpacity(live ? 0.5 : 0.25));
      }
    }
    for (var i = 0; i < g._nodes.length; i++) {
      final n = g._nodes[i];
      final pos = g._project(g._nodeWorld(i));
      if (pos.dy < -40 || pos.dy > size.height + 40) continue;
      final c = _kindColor[n.kind]!;
      final reachable = !n.visited &&
          n.unlocked &&
          g._nodes[g._cur].links.contains(i) &&
          g._movingTo == null &&
          g._energy > 0;
      final op = n.unlocked ? 1.0 : 0.4;
      _glow(canvas, pos, 22, c.withOpacity(n.unlocked ? 0.4 : 0.12));
      if (reachable) {
        final pr = 17 + (0.5 + 0.5 * math.sin(n.pulse * 4)) * 8;
        canvas.drawCircle(pos, pr, _stroke(c.withOpacity(0.7), 2));
      }
      canvas.drawCircle(
          pos, 17, Paint()..color = const Color(0xFF120F30).withOpacity(op));
      canvas.drawCircle(pos, 17, _stroke(c.withOpacity(op), 2.4));
      if (n.visited) {
        canvas.drawCircle(pos, 17, Paint()..color = c.withOpacity(0.18));
      }
      _text(canvas, _kindIcon[n.kind]!, pos, c.withOpacity(op), 15);
      if (g._wonNodes.contains(i)) {
        _text(canvas, '✓', pos.translate(13, -13), const Color(0xFFB6FF3C), 13,
            weight: FontWeight.w900);
      }
    }
    _drawHero(canvas, g._project(g._heroW), const Color(0xFFB6FF3C));

    _text(canvas, '${dom.name} · ${g._curActivity}'.toUpperCase(),
        Offset(size.width / 2, 28), dom.color, 19, weight: FontWeight.w900);
    _text(
        canvas,
        g._energy > 0
            ? 'Avancer coûte 1 ⚡ (gagnée par tes vraies séances)'
            : 'Plus d\'énergie — fais une séance de ${g._curActivity} pour avancer',
        Offset(size.width / 2, 52),
        g._energy > 0 ? const Color(0xFF8FA0C8) : const Color(0xFFFFB35A),
        12);
    _text(
        canvas,
        '⚡ Énergie ${g._energy}   ·   ✦ Profondeur ${g._depth}   ·   ◆ Items ${g._itemsUnlocked}',
        Offset(size.width / 2, size.height - 24),
        const Color(0xFFB6FF3C),
        13,
        weight: FontWeight.w700);
  }

  void _paintFlash(Canvas canvas, Size size) {
    if (g._flashT <= 0 || g._flash == null) return;
    final a = (g._flashT / 2.2).clamp(0.0, 1.0);
    final box = Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.18),
        width: 360,
        height: 42);
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(12)),
        Paint()..color = const Color(0xFF0B1422).withOpacity(0.92 * a));
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(12)),
        _stroke(const Color(0xFFFFD36B).withOpacity(a), 1.5));
    _text(canvas, g._flash!, box.center, const Color(0xFFFFE08A).withOpacity(a),
        14, weight: FontWeight.w800);
  }

  // ── helpers ────────────────────────────────────────────────────────────────
  void _punch(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..shader = RadialGradient(
            colors: const [Colors.white, Colors.white, Color(0x00FFFFFF)],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(Rect.fromCircle(center: c, radius: r)));
  }

  // butin posé dans une pièce (dessiné en code ; assets possibles plus tard)
  void _drawItem(Canvas canvas, Offset p, int kind) {
    switch (kind) {
      case 0: // trophée
        const c = Color(0xFFFFD36B);
        _glow(canvas, p, 10, c.withOpacity(0.5));
        canvas.drawArc(Rect.fromCenter(center: p.translate(0, -2), width: 12, height: 12),
            0, math.pi, false, _stroke(c, 2.2));
        canvas.drawLine(p.translate(0, 4), p.translate(0, 7), _stroke(c, 2));
        canvas.drawLine(p.translate(-4, 7), p.translate(4, 7), _stroke(c, 2));
        break;
      case 1: // plante
        const c = Color(0xFFB6FF3C);
        _glow(canvas, p.translate(0, -4), 9, c.withOpacity(0.4));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: p.translate(0, 4), width: 8, height: 6),
                const Radius.circular(2)),
            Paint()..color = const Color(0xFF3A2A1A));
        for (final a in [-0.6, 0.0, 0.6]) {
          canvas.drawLine(p.translate(0, 1),
              p.translate(math.sin(a) * 7, -8 - math.cos(a) * 2), _stroke(c, 2));
        }
        break;
      case 2: // cristal (losange)
        const c = Color(0xFF35E0FF);
        _glow(canvas, p, 10, c.withOpacity(0.5));
        canvas.drawPath(
            Path()
              ..moveTo(p.dx, p.dy - 7)
              ..lineTo(p.dx + 5, p.dy)
              ..lineTo(p.dx, p.dy + 7)
              ..lineTo(p.dx - 5, p.dy)
              ..close(),
            Paint()..color = c);
        break;
      case 3: // lampe
        const c = Color(0xFFFFE08A);
        _glow(canvas, p, 11, c.withOpacity(0.5));
        canvas.drawCircle(p, 5, Paint()..color = c);
        canvas.drawLine(p.translate(0, 5), p.translate(0, 9),
            _stroke(const Color(0xFF6A7A90), 2));
        break;
      case 4: // étoile
        const c = Color(0xFFFF9EC4);
        _glow(canvas, p, 10, c.withOpacity(0.5));
        final star = Path();
        for (var s = 0; s < 10; s++) {
          final a = -math.pi / 2 + s * math.pi / 5;
          final r = s.isEven ? 6.5 : 2.6;
          final pt = p.translate(math.cos(a) * r, math.sin(a) * r);
          s == 0 ? star.moveTo(pt.dx, pt.dy) : star.lineTo(pt.dx, pt.dy);
        }
        star.close();
        canvas.drawPath(star, Paint()..color = c);
        break;
      default: // fanion
        const c = Color(0xFFA86BFF);
        _glow(canvas, p, 9, c.withOpacity(0.45));
        canvas.drawLine(p.translate(-5, -7), p.translate(-5, 7), _stroke(c, 2));
        canvas.drawPath(
            Path()
              ..moveTo(p.dx - 5, p.dy - 7)
              ..lineTo(p.dx + 6, p.dy - 3)
              ..lineTo(p.dx - 5, p.dy + 1)
              ..close(),
            Paint()..color = c);
    }
  }

  // Boss = sprite araignée animé : la planche dépend de l'état (idle/walk/run/
  // attack/defense/dizzy). Halo rouge en chasse, bleu quand la lumière le domine.
  void _drawBoss(Canvas canvas, Offset p) {
    final state = g._bossState;
    final dominated =
        state == _BossState.dizzy || state == _BossState.defense;
    final halo = dominated ? const Color(0xFF8FE9FF) : const Color(0xFFFF4D5E);
    final gp = 0.5 + 0.5 * math.sin(g._t * 3);
    _glow(canvas, p, 34, halo.withOpacity(0.26 + gp * 0.14));
    // ombre portée (dessinée en code, commune à tous les états)
    canvas.drawOval(
        Rect.fromCenter(center: p.translate(0, 42), width: 92, height: 26),
        Paint()..color = Colors.black.withOpacity(0.35));

    final anim = _FluoNavScreenState._bossAnims[state]!;
    final img = g._bossSheets[state];
    if (img == null) {
      canvas.drawCircle(p, 22, Paint()..color = const Color(0xFF2A0F14));
      canvas.drawCircle(p, 22, _stroke(halo, 2.4));
    } else {
      const fs = _FluoNavScreenState._bossFrameSize;
      final f = (g._t * anim.fps).floor() % anim.frames;
      final src = Rect.fromLTWH(
          (f % anim.cols) * fs, (f ~/ anim.cols) * fs, fs, fs);
      const sz = 150.0;
      canvas.drawImageRect(
          img, src, Rect.fromCenter(center: p, width: sz, height: sz), Paint());
    }
    final label = state == _BossState.dizzy
        ? '✦ ébloui'
        : state == _BossState.defense
            ? '☠ se protège'
            : '☠ BOSS';
    _text(canvas, label, p.translate(0, 58), halo.withOpacity(0.9), 12,
        weight: FontWeight.w800);
  }

  void _drawHero(Canvas canvas, Offset p, Color c) {
    _glow(canvas, p, 22, c.withOpacity(0.5));
    canvas.drawLine(p.translate(0, -11), p.translate(0, -19), _stroke(c, 2.4));
    canvas.drawCircle(p.translate(0, -20), 2.4, Paint()..color = Colors.white);
    canvas.drawCircle(
        p,
        12,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            colors: [Colors.white, c],
          ).createShader(Rect.fromCircle(center: p, radius: 12)));
    canvas.drawCircle(p, 12, _stroke(Colors.white.withOpacity(0.6), 1.4));
    canvas.drawCircle(p.translate(-4, -2), 2.6, Paint()..color = Colors.white);
    canvas.drawCircle(p.translate(4, -2), 2.6, Paint()..color = Colors.white);
    canvas.drawCircle(
        p.translate(-3.6, -2), 1.3, Paint()..color = const Color(0xFF12211F));
    canvas.drawCircle(
        p.translate(4.4, -2), 1.3, Paint()..color = const Color(0xFF12211F));
    final smile = Path()
      ..moveTo(p.dx - 4, p.dy + 4)
      ..quadraticBezierTo(p.dx, p.dy + 8, p.dx + 4, p.dy + 4);
    canvas.drawPath(smile, _stroke(const Color(0xFF12211F), 1.8));
  }

  void _glow(Canvas c, Offset o, double r, Color col) {
    c.drawCircle(
        o,
        r,
        Paint()
          ..color = col
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
  }

  Paint _stroke(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..color = c;

  void _text(Canvas c, String s, Offset at, Color color, double size,
      {FontWeight weight = FontWeight.w600}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(color: color, fontSize: size, fontWeight: weight)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _NavPainter old) => true;
}
