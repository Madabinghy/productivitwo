import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
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

const int _kReveal = 2; // rayon de brouillard levé autour de l'avatar (Chebyshev)

// Outils dev (convocation manuelle, forcer l'auto-trigger, toggle de cadence) :
// affichés tant que true. ⚠️ à passer à false avant une vraie prod (comme pour
// territory_sheet). kDebugMode ne convient pas : le build web release le met à
// false → on ne pourrait plus tester en ligne.
const bool _kDev = true;

Future<void> showUnifiedWorldSheet(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  // Coupe l'overlay Orion tant qu'on est dans le Monde (il gênerait le jeu).
  assistantOverlaySuppressed.value = true;
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(.65),
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(10),
      backgroundColor: _kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940, maxHeight: 920),
        child: _UnifiedWorldView(logic: logic, sync: sync),
      ),
    ),
  ).whenComplete(() => assistantOverlaySuppressed.value = false);
}

class _UnifiedWorldView extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _UnifiedWorldView({required this.logic, required this.sync});

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

  // ── Prototype TOWER-DEFENSE (dev, local/éphémère, non persisté) ─────────────
  // Mode test : on pose des tours qui auto-tirent des flèches (GRATUIT en dev) sur
  // les sbires lâchés par la carte ennemie ; les sbires marchent vers la porte et
  // l'assiègent. Couche overlay animée au-dessus de la grille (socle game-feel).
  bool _tdMode = false;
  static const double _kTurretRange = 4.5; // rayon de tir (cases), partagé logique/affichage
  final Map<String, int> _turrets = {}; // tileId "x_y" → niveau (1 pour le test)
  final Map<String, int> _turretLastFireMs = {};
  String? _selectedTurret; // tour sélectionnée (tap, fallback tactile) → portée
  String? _hoveredTurret; // tour survolée (souris) → affiche sa portée
  // Combat de nuisible affiché en ENCART à droite (carte visible derrière).
  ({String type, String id, String tileId})? _combat;
  final List<_Sbire> _sbires = [];
  final List<_Shot> _shots = [];
  static const double _gateHpMax = 120;
  double _gateHp = _gateHpMax;
  Ticker? _gameTicker;
  int _gameMs = 0; // horloge monotone (ms depuis le 1er frame)
  int _lastSimMs = 0;
  int _sbireSeq = 0;

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
    } else if (hadShots && mounted) {
      setState(() {});
    }
  }

  void _simulate(double dt) {
    // Porte cassée (PV ≤ 0) → les sbires défilent vers le château (16,7) ;
    // sinon ils s'arrêtent devant la porte (8,7) et l'assiègent.
    final broken = _gateHp <= 0;
    final gx = broken ? 16.0 : 8.0;
    const gy = 7.0;
    for (final s in _sbires) {
      if (s.hp <= 0) continue;
      final dx = gx - s.x, dy = gy - s.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist > 0.5) {
        const speed = 0.85; // cases/sec (ralenti)
        s.x += dx / dist * speed * dt;
        s.y += dy / dist * speed * dt;
        s.atGate = false;
      } else if (broken) {
        s.hp = 0; // atteint le château → disparaît (proto : pas encore de PV château)
      } else {
        s.atGate = true;
        _gateHp = (_gateHp - 4 * dt).clamp(0, _gateHpMax); // 4 PV/s/sbire
      }
    }
    // Tours : ciblent le sbire vivant le plus proche dans le rayon, tirent gratis.
    const range = _kTurretRange, cooldownMs = 650, dmg = 1.0;
    _turrets.forEach((tile, lvl) {
      final p = tile.split('_');
      final tx = double.parse(p[0]), ty = double.parse(p[1]);
      if (_gameMs - (_turretLastFireMs[tile] ?? -99999) < cooldownMs) return;
      _Sbire? best;
      double bestD = range;
      for (final s in _sbires) {
        if (s.hp <= 0) continue;
        final d = sqrt(pow(s.x - tx, 2) + pow(s.y - ty, 2));
        if (d <= bestD) {
          bestD = d;
          best = s;
        }
      }
      if (best != null) {
        _turretLastFireMs[tile] = _gameMs;
        _shots.add(_Shot(Offset(tx, ty), Offset(best.x, best.y), _gameMs, 520));
        best.hp -= dmg; // hitscan : dégâts au tir (flèche = cosmétique)
      }
    });
    _sbires.removeWhere((s) => s.hp <= 0);
  }

  // Dev : lâche une vague de sbires depuis la carte ennemie (x=0, y 6..8).
  void _spawnWave() {
    setState(() {
      _tdMode = true;
      for (int i = 0; i < 6; i++) {
        final sy = 6 + (i % 3); // 6,7,8
        _sbires.add(_Sbire(_sbireSeq++, -0.8 * (i ~/ 3), sy.toDouble(), 3));
      }
    });
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
        // Génère la map une fois (seed du territoire → déterministe/spectatable),
        // et reprend le walk state persisté (position + brouillard) si présent.
        if (_w == null && t != null) {
          final w = generateUnifiedWorld(t.seed,
              caveIds: t.caves.map((c) => c.id).toList());
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
          // Tours TD persistées (état perso de la grande map).
          for (final tile in logic.state.unifiedTurrets) {
            _turrets[tile] = 1;
          }
          _revealAround(_pos);
          _populateFarm(); // disperse le backlog sur toute la zone (caché par le fog)
        }
      });
      // À la 1ʳᵉ map chargée : auto-trigger hebdo (1×/sem) si la semaine a décliné.
      if (!_autoThreatChecked && t != null) {
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
    return added;
  }

  List<Point<int>> _ortho(int x, int y) {
    final w = _w!;
    return [
      Point(x + 1, y),
      Point(x - 1, y),
      Point(x, y + 1),
      Point(x, y - 1),
    ].where((p) => w.walkable(p.x, p.y)).toList();
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
    final backlog = logic.backlogEnemies()
        .where((e) => !placed.contains(e.id))
        .toList();
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
        if (logic.enemyHp(c.type, c.id) <= 0) _farmPests.remove(c.tileId);
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
    final nx = _pos.x + dx, ny = _pos.y + dy;
    if (!w.walkable(nx, ny)) return;
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
    // Mode TD (dev) : tap = pose/retrait d'une tour sur une case sol marchable.
    if (_tdMode) {
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
    final spider = _spiderPos();
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
    if (!w.walkable(x, y)) {
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
          const Text('🗺️ Monde',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(width: 8),
          Text('farm · château · territoire',
              style: TextStyle(color: Colors.white.withOpacity(.4), fontSize: 11)),
          const Spacer(),
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
      if (!_loading && t != null) _siegeBar(t),
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
        // Panneau d'actions à gauche — masqué quand le combat est ouvert (place).
        if (_combat == null)
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
          pill(
              _tdMode ? '⚔️ TD ON — pose des tours' : '⚔️ Mode tower-defense',
              const Color(0xFFB07CF0),
              () => setState(() => _tdMode = !_tdMode),
              on: _tdMode),
          pill('🐀 Lâcher une vague', _kEnemy, _spawnWave),
          if (_tdMode)
            pill('🧹 Vider', Colors.white70, () {
              setState(() {
                _sbires.clear();
                _turrets.clear();
                _turretLastFireMs.clear();
                _shots.clear();
                _selectedTurret = null;
                _gateHp = _gateHpMax;
              });
              _persistTurrets();
            }),
        ],
      ),
      if (_tdMode) ...[
        const SizedBox(height: 6),
        Text(
            '🏹 $arcs flèches · 🚪 porte ${((_gateHp / _gateHpMax) * 100).round()}% · 🐀 ${_sbires.length} · 🗼 ${_turrets.length} tours · (tirs gratuits en dev)',
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
    final spider = _spiderPos();
    return LayoutBuilder(builder: (context, c) {
      final slot = (c.maxWidth / w.cols).clamp(22.0, 46.0);
      final inner = slot - 3;
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
      return Center(
        child: SizedBox(
          width: w.cols * slot,
          height: w.rows * slot,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              grid,
              // ── Couche TD : tours, sbires, flèches, PV porte ────────────────
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
              // Sbires (position continue) + petite barre de PV.
              for (final s in _sbires)
                () {
                  final c0 = centerD(s.x, s.y);
                  return Positioned(
                    left: c0.dx - slot / 2,
                    top: c0.dy - slot / 2,
                    width: slot,
                    height: slot,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('🕷️', style: TextStyle(fontSize: slot * 0.44)),
                        Container(
                          width: slot * 0.6,
                          height: 3,
                          decoration: BoxDecoration(
                              color: Colors.black.withOpacity(.5),
                              borderRadius: BorderRadius.circular(2)),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: (s.hp / s.maxHp).clamp(0.0, 1.0),
                            child: Container(
                                decoration: BoxDecoration(
                                    color: _kEnemy,
                                    borderRadius: BorderRadius.circular(2))),
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
      );
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
      // Mur = terrain rocheux ; certains portent un rocher 🪨.
      bg = const Color(0xFF241F1B).withOpacity(.55);
      border = Colors.white.withOpacity(.06);
      if (w.hasRock(x, y)) {
        child = Text('🪨', style: TextStyle(fontSize: inner * 0.5));
      }
    } else if (kind == UwTile.floor) {
      // Teinte la zone farm (gauche du château) en vert discret ; buissons 🌿.
      final farmSide = x < w.castle.x - 1;
      bg = (farmSide ? _kFarm : Colors.white).withOpacity(.08);
      border = (farmSide ? _kFarm : Colors.white).withOpacity(.12);
      if (w.hasBush(x, y)) {
        child = Text('🌿', style: TextStyle(fontSize: inner * 0.5));
      }
    } else if (kind == UwTile.castle) {
      bg = _kGold.withOpacity(.22);
      border = _kGold.withOpacity(.7);
      child = Text('🏰', style: TextStyle(fontSize: inner * 0.5));
    }

    // Porte en bois (chokepoint) : planches intactes, ou cassée (PV ≤ 0).
    if (w.isGate(x, y)) {
      final broken = _gateHp <= 0;
      bg = const Color(0xFF6B4423).withOpacity(broken ? .22 : .7);
      border = const Color(0xFF3E2A18).withOpacity(broken ? .4 : 1);
      child = Text(broken ? '💥' : '🚪',
          style: TextStyle(fontSize: inner * 0.5));
    }
    // Carte ennemie (spawner) = le même envahisseur araignée que l'invasion,
    // mais il lâche de petites araignées.
    if (w.isSpawner(x, y)) {
      bg = _kEnemy.withOpacity(.2);
      border = _kEnemy.withOpacity(.7);
      child = Text('🕷️', style: TextStyle(fontSize: inner * 0.5));
    }

    // Grotte (overlay depuis le doc territoire).
    final caveId = w.caveIdAt(x, y);
    if (caveId != null) {
      final cave = t.caveById(caveId);
      final mine = cave != null && cave.ownerUid == t.uid;
      // Grotte à moi = couleur de son domaine (dashboard d'équilibre) ;
      // grotte prise = rouge (réservé à l'ennemi).
      final col = mine ? _caveColor(cave) : _kEnemy;
      bg = col.withOpacity(.22);
      border = col.withOpacity(.7);
      final name = cave != null ? _domainName(cave.domainId) : '';
      child = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🕳️', style: TextStyle(fontSize: inner * 0.32)),
          Text('${cave?.blueLevel ?? 0}',
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
    final farmPest = _farmPests['${x}_$y'];
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

/// Sbire TD (éphémère) : position continue en coords de tuiles, PV, état d'assaut.
class _Sbire {
  final int id;
  double x, y, hp;
  final double maxHp;
  bool atGate = false;
  _Sbire(this.id, this.x, this.y, this.hp) : maxHp = hp;
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
