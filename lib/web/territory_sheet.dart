import 'dart:async';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/territory.dart';
import 'package:productivitwo_v1/web/invasion_defense_sheet.dart';

// Sous-tranche A : rend la map de territoire PERSISTÉE (château + 4 grottes +
// brouillard), lue depuis `territories/{uid}`. La grille se régénère depuis la
// seed (déterministe). Pas encore de gameplay (bot/siège = tranches C/D).

const _kBg = Color(0xFF0E0A0A);
const _kCard = Color(0xFF160C0C);
const _kBlue = Color(0xFF3B82F6); // grottes à moi
const _kGold = Color(0xFFD4A017); // château
const _kEnemy = Color(0xFFFF2B2B); // grottes prises (ennemi)

Future<void> showTerritorySheet(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(.65),
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: _kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: _TerritoryView(logic: logic, sync: sync),
      ),
    ),
  );
}

class _TerritoryView extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _TerritoryView({required this.logic, required this.sync});

  @override
  State<_TerritoryView> createState() => _TerritoryViewState();
}

class _TerritoryViewState extends State<_TerritoryView> {
  // Cadence de marche : TEST = 1 pas / 3 s (prod visée = 1 tick / 1 h).
  static const int _kStepMs = 3000;
  // Fenêtre devant la grotte avant l'auto-résolution (laisse le temps de Défendre).
  static const int _kCaveWindowMs = 9000;

  Territory? _t;
  bool _loading = true;
  bool _paused = false; // gelé pendant un combat/écran (pas de marche/résolution)
  StreamSubscription<Territory?>? _sub;
  Timer? _timer;

  AppLogic get logic => widget.logic;
  FirestoreSync get sync => widget.sync;

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
      });
    });
    // L'owner pilote la marche du bot en solo (trust v1) + persiste.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (_paused) return;
    final t = _t;
    final inv = t?.invader;
    if (t == null || inv == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (inv.marching) {
      final r = advanceInvader(t, now, _kStepMs);
      if (r.moved) {
        _t = r.t; // optimiste ; le stream confirmera
        sync.saveTerritory(r.t);
        setState(() {});
      }
      return;
    }
    // Devant la grotte sans interception à temps → auto-résolution green-vs-blue.
    if (inv.atCave && now - inv.lastStepAtMs >= _kCaveWindowMs) {
      _autoResolveCave(t, inv);
    }
  }

  // Interception en partie-minute : la force (cachée) du bot t'assaille, tu défends
  // (flèches + bloqueurs). Victoire = bot repoussé, map sauve.
  Future<void> _intercept(Invader inv) async {
    _paused = true;
    final winner = await showCaveFight(context, logic, sync,
        blueLevel: inv.level,
        title: 'Interception — grotte ${inv.targetCaveId.toUpperCase()}');
    _paused = false;
    if (!mounted) return;
    final cur = _t;
    if (winner == 'defender' && cur != null) {
      final next = cur.copyWith(fog: true, clearInvader: true);
      _t = next;
      await sync.saveTerritory(next);
      if (mounted) setState(() {});
      _toast('🏹 Bot repoussé — ta map est sauve.', _kBlue);
    } else if (winner != 'defender') {
      _toast('Le bot continue vers ta grotte…', _kEnemy);
    }
  }

  // Auto-résolution déterministe à la grotte : green (force du bot) vs blue (défense
  // de la grotte, scalée sur son niveau). Bot gagne → grotte PRISE (passe au bot,
  // ton niveau de map baisse) ; sinon la grotte tient. Invasion résolue dans tous
  // les cas (reprise d'une grotte prise = partie longue, sous-tranche D).
  void _autoResolveCave(Territory t, Invader inv) {
    final me = sync.uid;
    final cave = t.caveById(inv.targetCaveId);
    if (me == null || cave == null) return;
    _paused = true;
    // Résolution PASSIVE déterministe : la menace du bot vs le niveau de la grotte.
    // Tu n'as pas défendu activement → seul le niveau de ta grotte la protège.
    final botWins = inv.level > cave.blueLevel;
    final Territory next;
    if (botWins) {
      // Le bot s'installe avec SA force (blueLevel = sa menace) → la reprise devra
      // battre ce boss installé (sous-tranche D).
      final caves = t.caves
          .map((c) => c.id == cave.id
              ? c.copyWith(ownerUid: 'bot', occupied: true, blueLevel: inv.level)
              : c)
          .toList();
      next = t.copyWith(caves: caves, fog: true, clearInvader: true);
    } else {
      next = t.copyWith(fog: true, clearInvader: true);
    }
    _t = next;
    sync.saveTerritory(next);
    if (mounted) setState(() {});
    _paused = false;
    _toast(
        botWins
            ? '🟡 Le bot a PRIS ta grotte ${cave.id.toUpperCase()} ! '
                'Tape-la (rouge) pour la reprendre.'
            : '🛡️ Ta grotte ${cave.id.toUpperCase()} a tenu — le bot s\'est brisé dessus.',
        botWins ? _kEnemy : _kBlue);
  }

  Future<void> _summon() async {
    final t = _t;
    final me = sync.uid;
    if (t == null || me == null) return;
    if (t.invader != null) {
      _toast('Un envahisseur est déjà sur ta map (1 à la fois)', _kEnemy);
      return;
    }
    final next = spawnBotInvader(t, me, DateTime.now().millisecondsSinceEpoch);
    if (next.invader == null) {
      _toast('Plus de grotte à défendre', _kEnemy);
      return;
    }
    _t = next;
    await sync.saveTerritory(next);
    if (!mounted) return;
    setState(() {});
    _toast(
        '🟡 Une araignée jaune marche vers ta grotte '
        '${next.invader!.targetCaveId.toUpperCase()} !',
        _kGold);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = sync.uid;
    final t = _t;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
        child: Row(children: [
          const Text('🗺️ Mon territoire',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
          const Spacer(),
          IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => Navigator.pop(context)),
        ]),
      ),
      Flexible(child: (_loading || t == null) ? _loader() : _content(t, me)),
    ]);
  }

  Widget _loader() => const Center(
      child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: _kBlue)));

  Widget _content(Territory t, String? me) {
    final inv = t.invader;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statusBar(t),
        const SizedBox(height: 12),
        // Sous invasion : bannière + actions EN HAUT (visibles sans scroller).
        if (inv != null) ...[
          _invaderBanner(inv),
          _defendBtn(inv),
          if (inv.atCave) ...[
            const SizedBox(height: 8),
            _letGoBtn(),
          ],
          const SizedBox(height: 12),
        ],
        _board(t, me),
        const SizedBox(height: 8),
        Text(
          'Grotte BLEUE 🕳️ : touche-la pour entraîner son boss → +1 niveau (défense '
          '+ niveau de map), ça dépense tes flèches 🏹. Grotte ROUGE (prise) : touche-la '
          'pour la REPRENDRE en battant le boss installé.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(.45), fontSize: 11),
        ),
        const SizedBox(height: 12),
        if (inv == null) _summonBtn(),
        const SizedBox(height: 12),
        _legend(),
      ],
    );
  }

  Widget _letGoBtn() => Center(
        child: InkWell(
          onTap: () {
            final t = _t;
            if (t?.invader != null) _autoResolveCave(t!, t.invader!);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(.18)),
            ),
            child: Text('🏳️ Laisser tomber (résoudre maintenant)',
                style: TextStyle(
                    color: Colors.white.withOpacity(.6),
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ),
        ),
      );

  Widget _summonBtn() => Center(
        child: InkWell(
          onTap: _summon,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: _kGold.withOpacity(.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kGold.withOpacity(.5)),
            ),
            child: const Text('🟡 Convoquer le bot (test)',
                style: TextStyle(
                    color: _kGold, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
        ),
      );

  Widget _defendBtn(Invader inv) => Center(
        child: InkWell(
          onTap: () => _intercept(inv),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: _kBlue.withOpacity(.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBlue.withOpacity(.6)),
            ),
            child: const Text('🏹 Intercepter (partie-minute)',
                style: TextStyle(
                    color: _kBlue, fontWeight: FontWeight.w900, fontSize: 13)),
          ),
        ),
      );

  Widget _invaderBanner(Invader inv) {
    final atCave = inv.atCave;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _kGold.withOpacity(.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kGold.withOpacity(.5)),
      ),
      child: Row(children: [
        const Text('🕷️', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            atCave
                ? 'Devant ta grotte ${inv.targetCaveId.toUpperCase()} ! Intercepte vite, '
                    'sinon ta défense bleue résout seule (et peut céder la grotte).'
                : 'Une araignée jaune marche vers ${inv.targetCaveId.toUpperCase()} '
                    '— force inconnue (cachée jusqu\'au combat). Intercepte avant la grotte.',
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }

  // Grotte à MOI → entraîner son boss (+1 niveau). Grotte PRISE par le bot →
  // REPRENDRE (sous-tranche D) : bats le boss installé pour récupérer ton territoire.
  Future<void> _fightCave(Territory t, TerritoryCave cave, String? me) async {
    if (cave.ownerUid != me) {
      await _reclaimCave(cave, me);
      return;
    }
    _paused = true;
    final winner = await showCaveFight(context, logic, sync,
        blueLevel: cave.blueLevel, title: 'Grotte ${cave.id.toUpperCase()} — niv. ${cave.blueLevel}');
    _paused = false;
    if (!mounted || winner != 'defender') return;
    // Persiste +1 niveau (le stream rafraîchit l'affichage).
    final next = (_t ?? t)
        .caves
        .map((c) => c.id == cave.id ? c.copyWith(blueLevel: c.blueLevel + 1) : c)
        .toList();
    await sync.saveTerritory((_t ?? t).copyWith(caves: next));
    if (!mounted) return;
    _toast('🕳️ Grotte ${cave.id.toUpperCase()} montée → niveau ${cave.blueLevel + 1}',
        _kBlue);
  }

  // Sous-tranche D — reprendre une grotte prise : tu attaques le boss installé du
  // bot et le fais fondre (partie-longue en prod = tick 1h ; modélisé ici sur le
  // board partie-minute pour le solo). Victoire → la grotte te revient (défense à
  // re-monter depuis 1) ; ton niveau de map remonte.
  Future<void> _reclaimCave(TerritoryCave cave, String? me) async {
    if (me == null) return;
    _paused = true;
    final winner = await showCaveFight(context, logic, sync,
        blueLevel: cave.blueLevel,
        title: 'Reprendre grotte ${cave.id.toUpperCase()}');
    _paused = false;
    if (!mounted) return;
    if (winner != 'defender') {
      _toast('Le boss installé a tenu — la grotte reste prise.', _kEnemy);
      return;
    }
    final base = _t;
    if (base == null) return;
    final next = base.caves
        .map((c) => c.id == cave.id
            ? c.copyWith(ownerUid: me, occupied: false, blueLevel: 1)
            : c)
        .toList();
    await sync.saveTerritory(base.copyWith(caves: next));
    if (!mounted) return;
    _toast(
        '🔵 Grotte ${cave.id.toUpperCase()} REPRISE ! Défense à re-monter (niv. 1).',
        _kBlue);
  }

  void _toast(String m, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: c,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2)));
  }

  Widget _statusBar(Territory t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Niveau de map',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          Text('${t.level}',
              style: const TextStyle(
                  color: _kBlue, fontSize: 22, fontWeight: FontWeight.w900)),
          Text('Σ des 4 grottes',
              style: TextStyle(color: Colors.white.withOpacity(.4), fontSize: 10)),
        ]),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: (t.fog ? Colors.white12 : _kEnemy.withOpacity(.18)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: t.fog ? Colors.white24 : _kEnemy.withOpacity(.6)),
          ),
          child: Text(t.fog ? '🌫️ brouillard' : '⚔️ sous invasion',
              style: TextStyle(
                  color: t.fog ? Colors.white60 : _kEnemy,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5)),
        ),
      ]),
    );
  }

  Widget _board(Territory t, String? me) {
    final grid = generateTerritoryGrid(t);
    // Index des grottes par position pour superposer niveau + propriété.
    final caveAt = <String, TerritoryCave>{
      for (final c in t.caves) '${c.x}_${c.y}': c,
    };
    return LayoutBuilder(builder: (context, c) {
      final slot = (c.maxWidth / t.cols).clamp(18.0, 52.0);
      final inner = slot - 4;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int y = 0; y < t.rows; y++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (int x = 0; x < t.cols; x++)
                  _cell(grid[y][x], caveAt['${x}_$y'], me, inner,
                      isInvader:
                          t.invader != null && t.invader!.x == x && t.invader!.y == y,
                      onTapCave: caveAt['${x}_$y'] != null
                          ? () => _fightCave(t, caveAt['${x}_$y']!, me)
                          : null),
              ]),
          ],
        ),
      );
    });
  }

  Widget _cell(TerrTile kind, TerritoryCave? cave, String? me, double inner,
      {VoidCallback? onTapCave, bool isInvader = false}) {
    Color bg;
    Color border;
    Widget? child;
    switch (kind) {
      case TerrTile.wall:
        bg = Colors.white.withOpacity(.03);
        border = Colors.white.withOpacity(.05);
        break;
      case TerrTile.floor:
        bg = Colors.white.withOpacity(.10);
        border = Colors.white.withOpacity(.12);
        break;
      case TerrTile.castle:
        bg = _kGold.withOpacity(.22);
        border = _kGold.withOpacity(.7);
        child = Text('❤️', style: TextStyle(fontSize: inner * 0.5));
        break;
      case TerrTile.cave:
        final mine = cave != null && cave.ownerUid == me;
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
                    fontSize: inner * 0.28,
                    fontWeight: FontWeight.w900,
                    height: 1)),
          ],
        );
        break;
    }
    final tile = Container(
      width: inner,
      height: inner,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isInvader ? _kGold.withOpacity(.25) : bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: isInvader ? _kGold : border, width: isInvader ? 2 : 1),
      ),
      alignment: Alignment.center,
      // Le bot 🟡 se superpose à la case qu'il occupe.
      child: isInvader
          ? Text('🕷️', style: TextStyle(fontSize: inner * 0.55))
          : child,
    );
    if (onTapCave == null) return tile;
    return GestureDetector(onTap: onTapCave, child: tile);
  }

  Widget _legend() {
    Widget item(String emoji, String label, Color c) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: c, fontSize: 11.5)),
          ],
        );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        item('❤️', 'Château', _kGold),
        item('🕳️', 'Grotte à toi', _kBlue),
        item('🕳️', 'Grotte prise', _kEnemy),
      ],
    );
  }
}
