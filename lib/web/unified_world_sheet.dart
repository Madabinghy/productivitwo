import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/territory.dart';
import 'package:productivitwo_v1/unified_world.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/web/invasion_defense_sheet.dart';

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
const int _kStepMs = 3000; // cadence de marche de l'araignée (test : 1 pas / 3 s)
const int _kCaveWindowMs = 9000; // fenêtre devant la cible avant résolution passive

Future<void> showUnifiedWorldSheet(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(.65),
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(10),
      backgroundColor: _kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 920),
        child: _UnifiedWorldView(logic: logic, sync: sync),
      ),
    ),
  );
}

class _UnifiedWorldView extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _UnifiedWorldView({required this.logic, required this.sync});

  @override
  State<_UnifiedWorldView> createState() => _UnifiedWorldViewState();
}

class _UnifiedWorldViewState extends State<_UnifiedWorldView> {
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
  // Nuisibles de FARM (zone gauche) : LOCAUX/éphémères (région farm procédurale,
  // non persistée — cf split de persistance). tileId "x_y" → type de nuisible.
  final Map<String, String> _farmPests = {};
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await sync.ensureTerritory('Toi');
    final me = sync.uid ?? '';
    _sub = sync.streamTerritory(me).listen((t) {
      if (!mounted) return;
      setState(() {
        _t = t;
        _loading = false;
        // Génère la map une fois (seed du territoire → déterministe/spectatable).
        if (_w == null && t != null) {
          _w = generateUnifiedWorld(t.seed);
          _pos = _w!.start;
          _revealAround(_pos);
        }
      });
    });
    // Pilote la marche de l'araignée (position dérivée du temps depuis le spawn).
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
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
    final added = _revealAround(to);
    final t = _t;
    if (t != null) _maybeSpawnFarm(added, t);
    setState(() => _pos = to);
    _announce(to);
  }

  // Spawn de nuisibles à CHASSER dans la zone farm (gauche), à la révélation.
  // Local/éphémère (farm non persistée), plafonné, type scalé sur le niveau de map.
  void _maybeSpawnFarm(List<String> newly, Territory t) {
    final w = _w;
    if (w == null || _farmPests.length >= 3) return;
    final farm = newly.where((id) {
      final s = id.split('_');
      final x = int.parse(s[0]), y = int.parse(s[1]);
      if (x >= w.castle.x - 1) return false; // zone farm uniquement
      if (w.at(x, y) != UwTile.floor) return false;
      if (w.hasBush(x, y) || _farmPests.containsKey(id)) return false;
      if (x == _pos.x && y == _pos.y) return false;
      return true;
    }).toList();
    if (farm.isEmpty || _rng.nextInt(100) >= 30) return;
    _farmPests[farm[_rng.nextInt(farm.length)]] =
        GoldEconomy.pestTypeForLevel(t.level);
  }

  String _weaponHint(String w) => w == 'epee'
      ? 'finis une tâche → 🗡️'
      : w == 'arc'
          ? 'logge ~1 h → 🏹'
          : 'fais une routine → 🔪';

  // Capture d'un nuisible de farm : arme requise dispo → recordKill (crédite la
  // capture + recettes, dépense l'arme) + butin d'or. Réutilise l'éco existante.
  Future<void> _captureFarmPest(String tileId, String type) async {
    final weapon = GoldEconomy.weaponForPest(type);
    if (logic.weaponsAvailable(weapon) < 1) {
      _toast('${logic.weaponEmoji(weapon)} Pas d\'arme — ${_weaponHint(weapon)}',
          _kGold);
      return;
    }
    setState(() => _busy = true);
    final unlocked = logic.recordKill(type, sync, spendWeapon: true);
    final loot = GoldEconomy.pestLootBase(type, false);
    logic.applyGold(sync, loot,
        category: 'gain', reasonCode: 'pest_loot', label: 'Butin de chasse');
    logic.onChange();
    _farmPests.remove(tileId);
    if (mounted) setState(() => _busy = false);
    _toast('⚔️ ${pestName(type)} capturé ! +$loot or', _kFarm);
    if (unlocked.isNotEmpty && mounted) {
      _toast('${unlocked.first.emoji} ${unlocked.first.name} débloqué (recette) !',
          _kFarm);
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

  // Spawn = bord droit, rangée de la cible (« l'ennemi arrive par l'est »).
  Point<int> _invaderSpawn(UnifiedWorld w, Point<int> target) =>
      Point(w.cols - 1, target.y);

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
        ((DateTime.now().millisecondsSinceEpoch - inv.spawnAtMs) ~/ _kStepMs)
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
    final steps = (now - inv.spawnAtMs) ~/ _kStepMs;
    if (steps < len) {
      setState(() {}); // marche → re-render la position
      return;
    }
    // Arrivée : fenêtre d'interception puis résolution passive.
    final arrivalMs = inv.spawnAtMs + len * _kStepMs;
    if (now - arrivalMs >= _kCaveWindowMs) {
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
            ? '🟡 Le bot a PRIS ta grotte ${cave.id.toUpperCase()} ! Va la reprendre.'
            : '🛡️ Ta grotte ${cave.id.toUpperCase()} a tenu — le bot s\'est brisé dessus.',
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
    final cible = next.invader!.targetCaveId == 'castle'
        ? 'ton CHÂTEAU ❤️'
        : 'ta grotte ${next.invader!.targetCaveId.toUpperCase()}';
    _toast(
        '🕷️ Un envahisseur (niv $level) arrive par l\'est vers $cible !', _kEnemy);
  }

  Future<void> _onTap(int x, int y) async {
    final w = _w;
    if (_busy || w == null) return;
    final p = _pos;
    final caveId = w.caveIdAt(x, y);
    final farmType = _farmPests['${x}_$y'];
    final spider = _spiderPos();
    final isSpider = spider != null && spider.x == x && spider.y == y;
    // Re-tap de la case courante : araignée > nuisible de farm > grotte.
    if (x == p.x && y == p.y) {
      if (isSpider) {
        await _intercept();
      } else if (farmType != null) {
        await _captureFarmPest('${x}_$y', farmType);
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
    // Arrivé sur la case visée → engage : araignée (interception) > nuisible de
    // farm (capture) > grotte (défendre / reprendre).
    if (_pos.x == x && _pos.y == y) {
      if (isSpider) {
        await _intercept();
      } else if (farmType != null) {
        await _captureFarmPest('${x}_$y', farmType);
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
            ? 'Reprendre grotte ${id.toUpperCase()}'
            : 'Grotte ${id.toUpperCase()} — niv ${cave.blueLevel}');
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
      _toast('🔵 Grotte ${id.toUpperCase()} REPRISE ! Défense à re-monter (niv 1).',
          _kBlue);
    } else {
      final caves = base.caves
          .map((c) =>
              c.id == id ? c.copyWith(blueLevel: c.blueLevel + 1) : c)
          .toList();
      await sync.saveTerritory(base.copyWith(caves: caves));
      _toast('🕳️ Grotte ${id.toUpperCase()} montée → niveau ${cave.blueLevel + 1}',
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
    return Column(mainAxisSize: MainAxisSize.min, children: [
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
    ]);
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
          : 'grotte ${inv.targetCaveId.toUpperCase()}';
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
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _zonesLegend(),
        const SizedBox(height: 12),
        _board(t, w),
        const SizedBox(height: 12),
        Text(
          'Avatar : touche une case éclairée. À GAUCHE, chasse les nuisibles (va à '
          'leur contact, arme requise) → captures + or. À DROITE, défends tes '
          'grottes (bleue → +1 niveau ; rouge → reprends-la). Quand une araignée 🕷️ '
          'arrive par l\'est, intercepte-la au contact avant sa cible.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(.45), fontSize: 11),
        ),
        if (t.invader == null && !t.mapTaken) ...[
          const SizedBox(height: 12),
          _summonBtn(),
        ],
      ],
    );
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
        item('🕳️', 'Grottes (droite)', _kBlue),
      ],
    );
  }

  Widget _board(Territory t, UnifiedWorld w) {
    final avatar = logic.state.activeAvatar ?? '🧍';
    final spider = _spiderPos();
    return LayoutBuilder(builder: (context, c) {
      final slot = (c.maxWidth / w.cols).clamp(22.0, 46.0);
      final inner = slot - 3;
      return Center(
        child: Column(
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
        ),
      );
    });
  }

  Widget _cell(
      Territory t, UnifiedWorld w, int x, int y, double inner, String avatar,
      {bool isSpider = false}) {
    final id = '${x}_$y';
    final revealed = _revealed.contains(id);
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

    // Grotte (overlay depuis le doc territoire).
    final caveId = w.caveIdAt(x, y);
    if (caveId != null) {
      final cave = t.caveById(caveId);
      final mine = cave != null && cave.ownerUid == t.uid;
      final col = mine ? _kBlue : _kEnemy;
      bg = col.withOpacity(.22);
      border = col.withOpacity(.7);
      child = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🕳️', style: TextStyle(fontSize: inner * 0.36)),
          Text('${cave?.blueLevel ?? 0}',
              style: TextStyle(
                  color: col,
                  fontSize: inner * 0.26,
                  fontWeight: FontWeight.w900,
                  height: 1)),
        ],
      );
    }

    // L'araignée d'invasion se superpose à la case (sauf si l'avatar y est =
    // interception) ; un nuisible de farm (zone gauche) s'affiche à chasser.
    final spiderHere = isSpider && !isAvatar;
    final farmType = _farmPests['${x}_$y'];
    final farmHere = farmType != null && !isAvatar && !spiderHere;
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
                  ? Text(entityEmoji(farmType),
                      style: TextStyle(fontSize: inner * 0.5))
                  : child,
    );

    return GestureDetector(onTap: () => _onTap(x, y), child: tile);
  }
}
