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
  // Cadence de marche, configurable test/prod. La cadence est une INTERPRÉTATION
  // client de `lastStepAtMs` (advanceInvader rattrape les pas dus à l'horloge
  // murale) → toute valeur marche, et la marche se rattrape entre sessions. Le
  // toggle Test est un affordance DEV (ne doit pas shipper activé : en PvP la
  // cadence réelle doit être une constante partagée, sinon les positions divergent
  // entre clients) — figé sur Réel quand le trigger hebdo (item #3) atterrira.
  static const int _kStepMsTest = 3000; // 3 s/pas
  static const int _kStepMsReal = 3600000; // 1 h/pas (prod)
  // Fenêtre devant la grotte avant l'auto-résolution (laisse le temps d'intercepter).
  static const int _kCaveWindowMsTest = 9000; // 9 s
  static const int _kCaveWindowMsReal = 3600000; // 1 h (= 1 pas)

  bool _realCadence = false; // défaut Test (jouable/démontrable en session)
  int get _stepMs => _realCadence ? _kStepMsReal : _kStepMsTest;
  int get _caveWindowMs => _realCadence ? _kCaveWindowMsReal : _kCaveWindowMsTest;

  Territory? _t;
  bool _loading = true;
  bool _paused = false; // gelé pendant un combat/écran (pas de marche/résolution)
  bool _autoThreatChecked = false; // auto-trigger hebdo évalué une fois par ouverture
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
      // À la première map chargée : déclenche (au plus 1×/semaine) une invasion
      // scalée sur la chute de score hebdo. Le boot, pas le tick (le tick re-tourne
      // chaque seconde ; ici on veut une évaluation unique par ouverture).
      if (!_autoThreatChecked && t != null) {
        _autoThreatChecked = true;
        _maybeAutoThreat(t);
      }
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
      final r = advanceInvader(t, now, _stepMs);
      if (r.moved) {
        _t = r.t; // optimiste ; le stream confirmera
        sync.saveTerritory(r.t);
        setState(() {});
      }
      return;
    }
    // Devant la grotte sans interception à temps → auto-résolution green-vs-blue.
    if (inv.atCave && now - inv.lastStepAtMs >= _caveWindowMs) {
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
    if (me == null) return;
    _paused = true;
    // Château (toutes les grottes sont prises) : sans interception → MAP PRISE.
    if (inv.targetCaveId == 'castle') {
      final next = t.copyWith(mapTaken: true, fog: true, clearInvader: true);
      _t = next;
      sync.saveTerritory(next);
      if (mounted) setState(() {});
      _paused = false;
      _toast('💀 Ton château est tombé — MAP PRISE. Reconquiers tes grottes (rouges).',
          _kEnemy);
      return;
    }
    final cave = t.caveById(inv.targetCaveId);
    if (cave == null) {
      _paused = false;
      return;
    }
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

  // Courbe DOUCE (validée) chute de score hebdo → menace du bot : pas de chute → 1
  // (inoffensif), ≤25 % → 2, ≤50 % → 3, >50 % → 4. Pardonne une mauvaise semaine,
  // punit l'effondrement. Une grotte tombe en passif si menace > son niveau (départ
  // 1) → monter ses grottes au-dessus de la menace les protège.
  int _threatLevel(double drop) {
    if (drop <= 0) return 1;
    if (drop <= 0.25) return 2;
    if (drop <= 0.50) return 3;
    return 4;
  }

  // Auto-trigger d'accountability : à l'ouverture, si la dernière semaine complète
  // a décliné (menace ≥ 2) et qu'aucune invasion n'est en cours, fait spawner un bot
  // scalé sur l'ampleur de la chute — une seule fois par semaine (clé `lastThreatWeek`).
  // Une semaine égale/meilleure marque juste la semaine évaluée (pas de spawn).
  // `force` (bouton dev) : ignore la clé hebdo (rejouable) et NE consomme PAS la
  // semaine (test répétable) ; toaste explicitement la décision même sans spawn.
  void _maybeAutoThreat(Territory t, {bool force = false}) {
    final me = sync.uid;
    if (me == null) return;
    if (t.invader != null || t.mapTaken) {
      if (force) _toast('Déjà une invasion en cours / map prise.', _kEnemy);
      return;
    }
    final sig = logic.territoryThreatSignal();
    if (!force && t.lastThreatWeek == sig.weekKey) return; // déjà déclenché cette sem.
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
        // Pas de déclin : marque la semaine pour ne pas ré-évaluer en boucle.
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
    // Auto réel : consomme la semaine (idempotence). Forcé : ne consomme pas.
    final spawned = force ? base : base.copyWith(lastThreatWeek: sig.weekKey);
    _t = spawned;
    sync.saveTerritory(spawned);
    if (mounted) setState(() {});
    final pct = (sig.drop * 100).round();
    _toast(
        '${force ? '🐞 (forcé) ' : '🕷️ '}Ta semaine a chuté de $pct % → '
        'araignée niv $level sur ta map.',
        _kEnemy);
  }

  // Bascule la cadence. Rebase `lastStepAtMs` de l'envahisseur sur maintenant pour
  // éviter un saut de position au changement d'échelle de temps (sinon test→réel
  // gèlerait ~1 h, réel→test rattraperait des dizaines de pas d'un coup).
  void _setCadence(bool real) {
    if (_realCadence == real) return;
    setState(() => _realCadence = real);
    final t = _t;
    final inv = t?.invader;
    if (t != null && inv != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final next = t.copyWith(invader: inv.copyWith(lastStepAtMs: now));
      _t = next;
      sync.saveTerritory(next);
    }
  }

  Future<void> _summon() async {
    final t = _t;
    final me = sync.uid;
    if (t == null || me == null) return;
    if (t.invader != null) {
      _toast('Un envahisseur est déjà sur ta map (1 à la fois)', _kEnemy);
      return;
    }
    // Menace scalée sur la vraie chute hebdo ; bouton dev planché à 2 (toujours
    // un test significatif même sans données de score).
    final sig = logic.territoryThreatSignal();
    final scaled = sig.hadData ? _threatLevel(sig.drop) : 1;
    final level = scaled < 2 ? 2 : scaled;
    final next = spawnBotInvader(t, me, DateTime.now().millisecondsSinceEpoch,
        botLevel: level);
    if (next.invader == null) {
      _toast(t.mapTaken ? 'Map déjà prise — reconquiers tes grottes' : 'Plus de grotte à défendre',
          _kEnemy);
      return;
    }
    _t = next;
    await sync.saveTerritory(next);
    if (!mounted) return;
    setState(() {});
    final target = next.invader!.targetCaveId;
    _toast(
        target == 'castle'
            ? '🟡 Toutes tes grottes sont prises — l\'araignée (niv $level) fonce sur ton CHÂTEAU ❤️ !'
            : '🟡 Une araignée jaune (niv $level) marche vers ta grotte ${target.toUpperCase()} !',
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
        if (t.mapTaken) ...[
          _mapTakenBanner(),
          const SizedBox(height: 12),
        ],
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
        if (inv == null) ...[
          _threatReadout(),
          const SizedBox(height: 12),
        ],
        _cadenceToggle(),
        const SizedBox(height: 12),
        if (inv == null) ...[
          _summonBtn(),
          const SizedBox(height: 8),
          _forceThreatBtn(),
        ],
        const SizedBox(height: 12),
        _legend(),
      ],
    );
  }

  Widget _mapTakenBanner() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kEnemy.withOpacity(.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kEnemy.withOpacity(.6)),
        ),
        child: Row(children: [
          const Text('💀', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'MAP PRISE — ton château est tombé. Reconquiers tes grottes (rouges) '
              'pour reprendre le contrôle.',
              style: TextStyle(
                  color: _kEnemy.withOpacity(.95),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ]),
      );

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

  // Readout du signal d'accountability : où en est ta semaine et quelle menace elle
  // appelle. Rend visible le lien chute de score → bot, même sans invasion en cours.
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

  // Sélecteur de cadence (dev) : Test 3 s/pas pour jouer en session ⇄ Réel 1 h/pas
  // pour valider le rythme d'accountability. Cf note d'archi : affordance dev.
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
        color: _kCard,
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

  // Bouton dev : rejoue la décision d'auto-trigger maintenant (ignore la clé hebdo,
  // ne consomme pas la semaine) pour tester le chemin sans attendre une vraie semaine.
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
    final castle = inv.targetCaveId == 'castle';
    final cible = castle ? 'ton CHÂTEAU ❤️' : 'grotte ${inv.targetCaveId.toUpperCase()}';
    final String msg;
    if (castle) {
      msg = atCave
          ? 'Devant $cible ! Intercepte ou ta MAP TOMBE.'
          : 'L\'araignée fonce sur $cible — dernière ligne. Intercepte avant qu\'elle arrive.';
    } else {
      msg = atCave
          ? 'Devant ta $cible ! Intercepte vite, sinon ta défense bleue résout seule '
              '(et peut céder la grotte).'
          : 'Une araignée jaune marche vers ta $cible — force inconnue (cachée jusqu\'au '
              'combat). Intercepte avant la grotte.';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: (castle ? _kEnemy : _kGold).withOpacity(.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (castle ? _kEnemy : _kGold).withOpacity(.5)),
      ),
      child: Row(children: [
        const Text('🕷️', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(msg,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
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
    // Reconquérir une grotte ramène le château (la map n'est plus prise).
    await sync.saveTerritory(base.copyWith(caves: next, mapTaken: false));
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

  // Vrai fog-of-war : tu ne vois que ce que TES structures éclairent. Le château
  // et chaque grotte que tu possèdes projettent un disque de vision (distance de
  // Manhattan) ; une grotte mieux défendue voit plus loin (early-warning ↔
  // investissement défensif). Une grotte prise par le bot n'éclaire plus rien (tu
  // as perdu ce poste de guet). Renvoie l'ensemble des tuiles éclairées, encodées
  // `y * cols + x`. Tes grottes/château eux-mêmes restent toujours rendus (cf.
  // `_cell`) : le fog ne masque que le sol, les murs et l'envahisseur.
  Set<int> _visibleTiles(Territory t, String? me) {
    final vis = <int>{};
    void disc(int cx, int cy, int r) {
      for (int y = 0; y < t.rows; y++) {
        for (int x = 0; x < t.cols; x++) {
          if ((x - cx).abs() + (y - cy).abs() <= r) vis.add(y * t.cols + x);
        }
      }
    }

    disc(t.castle.x, t.castle.y, 3);
    for (final c in t.caves) {
      if (c.ownerUid == me) disc(c.x, c.y, 2 + (c.blueLevel >= 3 ? 1 : 0));
    }
    return vis;
  }

  Widget _board(Territory t, String? me) {
    final grid = generateTerritoryGrid(t);
    // Index des grottes par position pour superposer niveau + propriété.
    final caveAt = <String, TerritoryCave>{
      for (final c in t.caves) '${c.x}_${c.y}': c,
    };
    final vis = _visibleTiles(t, me);
    final inv = t.invader;
    // L'araignée n'est dessinée qu'une fois entrée dans ton champ de vision : sa
    // POSITION est cachée tant qu'elle marche au loin (l'interception reste
    // possible via la bannière, indépendante du plateau).
    final invVisible = inv != null && vis.contains(inv.y * t.cols + inv.x);
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
                      // Château/grotte = tes structures, jamais masquées ; le fog
                      // ne couvre que sol + murs hors vision.
                      fogged: grid[y][x] != TerrTile.castle &&
                          grid[y][x] != TerrTile.cave &&
                          !vis.contains(y * t.cols + x),
                      isInvader: invVisible && inv.x == x && inv.y == y,
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
      {VoidCallback? onTapCave, bool isInvader = false, bool fogged = false}) {
    // Hors vision : tuile noyée dans le brouillard, contenu masqué, non tappable.
    if (fogged) {
      return Container(
        width: inner,
        height: inner,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.55),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withOpacity(.04)),
        ),
      );
    }
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
        item('🌫️', 'Hors vision', Colors.white60),
      ],
    );
  }
}
