import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/battle_sim.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';

const _kGold = Color(0xFFD4A017);
const _kMine = Color(0xFF3B82F6); // mes unités (côté 0 en local)
const _kFoe = Color(0xFFFF2B2B); // unités adverses
const _kBg = Color(0xFF0E0A0A);
const _kCard = Color(0xFF160C0C);
const int _kPracticeTickMs = 2500; // tick rapide pour tester seul

String tierEmoji(String tier) =>
    tier == 'serpent' ? '🐍' : (tier == 'scorpion' ? '🦂' : '🕷️');
String tierName(String tier) =>
    tier == 'serpent' ? 'Serpent' : (tier == 'scorpion' ? 'Scorpion' : 'Araignée');

/// Ouvre le hub « Bataille de nuisibles ».
Future<void> showBattleSheet(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(.65),
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: _kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 800),
        child: _BattleHub(logic: logic, sync: sync),
      ),
    ),
  );
}

// ── Contrôleur abstrait (partagé par practice & remote) ──────────────────────

abstract class _BattleCtrl extends ChangeNotifier {
  int get width;
  int get lanes;
  int get tickMs;
  int? get startMs; // null tant que la partie n'a pas démarré
  int get mySide;
  bool get isPractice;
  List<BattleEvent> get events;
  int get masseAvailable;
  String? get statusLabel; // ex. « En attente d'adversaire »
  int? get winnerSide; // null = en cours

  bool get started => startMs != null;
  int nowTick() {
    final s = startMs;
    if (s == null) return 0;
    final t = (DateTime.now().millisecondsSinceEpoch - s) ~/ tickMs;
    return t < 0 ? 0 : t;
  }

  /// ms avant le prochain tick (null si pas démarrée).
  int? msToNextTick() {
    final s = startMs;
    if (s == null) return null;
    final next = s + (nowTick() + 1) * tickMs;
    final d = next - DateTime.now().millisecondsSinceEpoch;
    return d < 0 ? 0 : d;
  }

  /// Masse déjà déployée ce tick (mes nuisibles) — pour le budget 15/tick.
  int masseSpentThisTick() {
    final t = nowTick();
    return events
        .where((e) => e.side == mySide && e.kind == 'pest' && e.tick == t)
        .fold(0, (s, e) => s + GoldEconomy.masseCost(e.tier));
  }

  int flamesUsed() =>
      events.where((e) => e.side == mySide && e.kind == 'flame').length;

  /// Validation commune au dépôt (mêmes règles que le serveur).
  String? validate(int lane, String kind, String tier) {
    if (lane < 0 || lane >= lanes) return 'Couloir invalide';
    final t = nowTick();
    if (kind == 'flame') {
      if (flamesUsed() >= 3) return 'Plus de flammes (3 max)';
      if (events
          .any((e) => e.side == mySide && e.kind == 'flame' && e.tick == t)) {
        return 'Une seule flamme par tick';
      }
      final liveInLane = events.any((e) =>
          e.side == mySide && e.lane == lane && e.tick + width > t);
      if (liveInLane) return 'Couloir occupé — la flamme exige un couloir libre';
    } else {
      if (masseSpentThisTick() + GoldEconomy.masseCost(tier) >
          GoldEconomy.masseBudgetPerTick) {
        return 'Budget du tick atteint (${GoldEconomy.masseBudgetPerTick} masse)';
      }
      if (masseAvailable < GoldEconomy.masseCost(tier)) {
        return 'Masse insuffisante';
      }
      final flameInLane = events.any((e) =>
          e.side == mySide &&
          e.kind == 'flame' &&
          e.lane == lane &&
          e.tick + width > t);
      if (flameInLane) return 'Une de tes flammes traverse ce couloir';
    }
    return null;
  }

  /// Effectue le dépôt. Retourne null si OK, sinon un message d'erreur.
  Future<String?> deploy(int lane, String kind, String tier);
}

// ── Practice solo : local, bot, horloge rapide ───────────────────────────────

class _PracticeCtrl extends _BattleCtrl {
  @override
  final int width = 7;
  @override
  final int lanes = 5;
  @override
  int get tickMs => _kPracticeTickMs;
  @override
  final int mySide = 0;
  @override
  final bool isPractice = true;
  @override
  String? get statusLabel => _winner != null
      ? null
      : 'Entraînement — adversaire automatique';

  final List<BattleEvent> _events = [];
  @override
  List<BattleEvent> get events => _events;

  int _practiceMasse = 300; // réserve d'entraînement (n'affecte pas le vrai or)
  @override
  int get masseAvailable => _practiceMasse;

  int? _winner;
  @override
  int? get winnerSide => _winner;

  @override
  final int startMs = DateTime.now().millisecondsSinceEpoch;

  Timer? _timer;
  int _lastBotTick = -1;
  int _seq = 0;
  final _rng = Random(DateTime.now().millisecondsSinceEpoch & 0x7fffffff);

  _PracticeCtrl() {
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _onPulse());
  }

  void _onPulse() {
    if (_winner != null) return;
    final t = nowTick();
    // Le bot agit une fois par tick (≤ 15 masse, lanes aléatoires).
    if (t != _lastBotTick) {
      _lastBotTick = t;
      _botPlay(t);
    }
    _checkWinner(t);
    notifyListeners();
  }

  void _botPlay(int t) {
    // Le bot dépose 0–1 nuisible/tick, palier pondéré, sur un couloir libre.
    if (_rng.nextDouble() < 0.45) return;
    final roll = _rng.nextDouble();
    final tier = roll < .6 ? 'spider' : (roll < .9 ? 'scorpion' : 'serpent');
    final lane = _rng.nextInt(lanes);
    _events.add(BattleEvent(
        id: 'b${_seq++}', side: 1, lane: lane, kind: 'pest', tier: tier, tick: t));
  }

  void _checkWinner(int t) {
    final sim = simulateBattle(
        events: _events, width: width, lanes: lanes, nowTick: t);
    if (sim.winnerSide != null) {
      _winner = sim.winnerSide;
      _timer?.cancel();
    }
  }

  @override
  Future<String?> deploy(int lane, String kind, String tier) async {
    final err = validate(lane, kind, tier);
    if (err != null) return err;
    if (kind == 'pest') _practiceMasse -= GoldEconomy.masseCost(tier);
    _events.add(BattleEvent(
        id: 'p${_seq++}',
        side: mySide,
        lane: lane,
        kind: kind,
        tier: kind == 'pest' ? tier : '',
        tick: nowTick()));
    _checkWinner(nowTick());
    notifyListeners();
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ── Remote : partie réelle adossée à Firestore ───────────────────────────────

class _RemoteCtrl extends _BattleCtrl {
  final AppLogic logic;
  final FirestoreSync sync;
  final String battleId;
  final String uid;

  Battle? _battle;
  final List<BattleEvent> _events = [];
  StreamSubscription? _bSub, _eSub;
  Timer? _ticker;
  bool _resolving = false;

  _RemoteCtrl(this.logic, this.sync, this.battleId, this.uid) {
    _bSub = sync.streamBattle(battleId).listen((b) {
      _battle = b;
      notifyListeners();
    });
    _eSub = sync.streamBattleEvents(battleId).listen((ev) {
      _events
        ..clear()
        ..addAll(ev);
      notifyListeners();
    });
    // Rafraîchit le rebours + détecte la victoire au fil de l'horloge.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _maybeResolve();
      notifyListeners();
    });
  }

  @override
  int get width => _battle?.width ?? 7;
  @override
  int get lanes => _battle?.lanes ?? 5;
  @override
  int get tickMs => (_battle?.tickMinutes ?? 60) * 60000;
  @override
  int? get startMs => _battle?.startAtMs;
  @override
  int get mySide => _battle?.sideOf(uid) ?? 0;
  @override
  final bool isPractice = false;
  @override
  List<BattleEvent> get events => _events;
  @override
  int get masseAvailable => logic.battleMasseAvailable;
  @override
  int? get winnerSide =>
      _battle?.finished == true ? (_battle?.sideOf(_battle!.winnerUid ?? '')) : null;

  @override
  String? get statusLabel {
    final b = _battle;
    if (b == null) return 'Chargement…';
    if (b.status == 'waiting') return 'En attente d\'un adversaire — partage le code';
    if (b.finished) return null;
    return null;
  }

  void _maybeResolve() {
    final b = _battle;
    if (b == null || !b.active || _resolving) return;
    final sim = simulateBattle(
        events: _events, width: width, lanes: lanes, nowTick: nowTick());
    if (sim.winnerSide != null) {
      _resolving = true;
      sync.resolveBattle(battleId).whenComplete(() => _resolving = false);
    }
  }

  @override
  Future<String?> deploy(int lane, String kind, String tier) async {
    if (_battle?.active != true) return 'Partie non active';
    final err = validate(lane, kind, tier);
    if (err != null) return err;
    final remoteErr = await sync.deployUnit(battleId, lane, kind, tier);
    if (remoteErr != null) return remoteErr;
    if (kind == 'pest') logic.spendBattleMasse(tier, sync); // débit masse réel
    return null;
  }

  @override
  void dispose() {
    _bSub?.cancel();
    _eSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}

// ── Hub ──────────────────────────────────────────────────────────────────────

class _BattleHub extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _BattleHub({required this.logic, required this.sync});

  @override
  State<_BattleHub> createState() => _BattleHubState();
}

class _BattleHubState extends State<_BattleHub> {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => widget.sync;
  bool _busy = false;
  List<Battle> _mine = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final m = await sync.fetchMyBattles();
    if (mounted) setState(() => _mine = m);
  }

  void _openBoard(_BattleCtrl ctrl, String title) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _BattleBoardScreen(
          ctrl: ctrl, logic: logic, sync: sync, title: title),
    )).then((_) => _reload());
  }

  Future<void> _practice() async {
    _openBoard(_PracticeCtrl(), 'Entraînement');
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    final id = await sync.createBattle();
    setState(() => _busy = false);
    if (id == null) {
      _toast('Échec de la création', _kFoe);
      return;
    }
    await _reload();
    if (!mounted) return;
    _showCode(id);
  }

  void _showCode(String id) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('Partie créée', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Donne ce code à ton adversaire :',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 10),
          SelectableText(id,
              style: const TextStyle(
                  color: _kGold, fontWeight: FontWeight.w900, fontSize: 14)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _join() async {
    final ctl = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('Rejoindre', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Code de la partie'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctl.text.trim()),
              child: const Text('Rejoindre')),
        ],
      ),
    );
    if (id == null || id.isEmpty) return;
    setState(() => _busy = true);
    final err = await sync.joinBattle(id);
    setState(() => _busy = false);
    if (err != null) {
      _toast(err, _kFoe);
      return;
    }
    await _reload();
    _toast('Partie rejointe !', const Color(0xFF22C55E));
  }

  void _toast(String m, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: c, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(children: [
            const Text('⚔️ Bataille de nuisibles',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
            const Spacer(),
            IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Flexible(
          child: ListView(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            children: [
              _deckButton(),
              const SizedBox(height: 16),
              _bigBtn('🎯', 'Entraînement solo',
                  'Teste contre un adversaire automatique', const Color(0xFF22C55E),
                  _busy ? null : _practice),
              const SizedBox(height: 10),
              _bigBtn('➕', 'Créer une partie', 'Obtiens un code à partager',
                  _kGold, _busy ? null : _create),
              const SizedBox(height: 10),
              _bigBtn('🔗', 'Rejoindre', 'Avec le code d\'un adversaire',
                  _kMine, _busy ? null : _join),
              const SizedBox(height: 18),
              if (_mine.isNotEmpty) ...[
                const Text('Mes parties',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.white70)),
                const SizedBox(height: 8),
                for (final b in _mine) _battleRow(b),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static const int _kDeckCapPerType = 30; // cartes max affichées par type

  // Bouton compact : résumé de la masse → ouvre le deck au clic.
  Widget _deckButton() {
    final masse = logic.battleMasseAvailable;
    final today = logic.battleMasseEarnedToday;
    return InkWell(
      onTap: _showDeckDialog,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [_kGold.withOpacity(.18), _kGold.withOpacity(.04)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kGold.withOpacity(.3)),
        ),
        child: Row(children: [
          const Text('🪖', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mes nuisibles · $masse de masse',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
                Text('Tape pour voir ton deck (7 derniers jours)',
                    style: TextStyle(
                        fontSize: 11, color: Colors.white.withOpacity(.55))),
              ],
            ),
          ),
          if (today > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withOpacity(.18),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: const Color(0xFF22C55E).withOpacity(.5)),
              ),
              child: Text('+$today auj.',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF4ADE80))),
            ),
          const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
        ]),
      ),
    );
  }

  void _showDeckDialog() {
    final deck = logic.battleDeckByCapture();
    final masse = logic.battleMasseAvailable;
    final empty =
        deck.serpents == 0 && deck.scorpions == 0 && deck.spiders == 0;
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(.7),
      builder: (_) => Dialog(
        backgroundColor: _kBg,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(children: [
                const Text('🃏 Mon deck',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
                const SizedBox(width: 10),
                Text('$masse de masse',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _kGold)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context)),
              ]),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(16),
                shrinkWrap: true,
                children: [
                  if (empty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                          'Deck vide. Capture tes routines (combat) cette semaine pour le remplir.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(.55))),
                    )
                  else ...[
                    _deckTypeRow('🐍', 'Serpents', deck.serpents),
                    _deckTypeRow('🦂', 'Scorpions', deck.scorpions),
                    _deckTypeRow('🕷️', 'Araignées', deck.spiders),
                  ],
                  const SizedBox(height: 6),
                  Text(
                      'Chaque routine complétée devient un nuisible (le plus gros d\'abord : '
                      '🕷️${GoldEconomy.masseSpider} · 🦂${GoldEconomy.masseScorpion} · 🐍${GoldEconomy.masseSerpent}). '
                      'Un nuisible reste 7 jours dans ton deck, puis sort.',
                      style: TextStyle(
                          fontSize: 11, color: Colors.white.withOpacity(.45))),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _deckTypeRow(String emoji, String name, int count) {
    final shown = count < _kDeckCapPerType ? count : _kDeckCapPerType;
    final overflow = count - shown;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('$emoji  $name',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const Spacer(),
            Text('×$count',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: count > 0 ? _kGold : Colors.white38)),
          ]),
          const SizedBox(height: 8),
          if (count == 0)
            Text('aucun',
                style:
                    TextStyle(fontSize: 11, color: Colors.white.withOpacity(.3)))
          else
            Wrap(
              spacing: 5,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (int i = 0; i < shown; i++) _deckCard(emoji),
                if (overflow > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Text('+$overflow',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: _kGold)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _deckCard(String emoji) => Container(
        width: 30,
        height: 40,
        decoration: BoxDecoration(
          color: _kMine.withOpacity(.16),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _kGold.withOpacity(.45)),
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 17)),
      );

  Widget _battleRow(Battle b) {
    final uid = sync.uid ?? '';
    final foe = b.players.where((p) => p != uid).map(b.pseudoOf).join();
    final label = b.status == 'waiting'
        ? 'En attente d\'un adversaire'
        : 'Contre @${foe.isEmpty ? '?' : foe}';
    return InkWell(
      onTap: () => _openBoard(
          _RemoteCtrl(logic, sync, b.id, uid), 'Bataille'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(.1)),
        ),
        child: Row(children: [
          Text(b.status == 'waiting' ? '⏳' : '⚔️',
              style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
        ]),
      ),
    );
  }

  Widget _bigBtn(String emoji, String title, String sub, Color color,
          VoidCallback? onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Opacity(
          opacity: onTap == null ? .5 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: color.withOpacity(.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(.4)),
            ),
            child: Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    Text(sub,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white.withOpacity(.55))),
                  ],
                ),
              ),
            ]),
          ),
        ),
      );
}

// ── Board ─────────────────────────────────────────────────────────────────────

class _BattleBoardScreen extends StatefulWidget {
  final _BattleCtrl ctrl;
  final AppLogic logic;
  final FirestoreSync sync;
  final String title;
  const _BattleBoardScreen({
    required this.ctrl,
    required this.logic,
    required this.sync,
    required this.title,
  });

  @override
  State<_BattleBoardScreen> createState() => _BattleBoardScreenState();
}

class _BattleBoardScreenState extends State<_BattleBoardScreen> {
  _BattleCtrl get ctrl => widget.ctrl;
  String _selTier = 'spider'; // palier ou 'flame'
  bool _winShown = false;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  String _fmt(int ms) {
    final s = ms ~/ 1000;
    final m = s ~/ 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    if (m >= 60) {
      final h = m ~/ 60;
      final mm = (m % 60).toString().padLeft(2, '0');
      return '$h:$mm:$ss';
    }
    return '$m:$ss';
  }

  Future<void> _tapLane(int lane) async {
    final kind = _selTier == 'flame' ? 'flame' : 'pest';
    final err = await ctrl.deploy(lane, kind, _selTier);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err),
          backgroundColor: _kFoe,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1)));
    }
  }

  void _maybeWinDialog() {
    if (_winShown || ctrl.winnerSide == null) return;
    _winShown = true;
    final won = ctrl.winnerSide == ctrl.mySide;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: _kCard,
          title: Text(won ? '🏆 Victoire !' : '💀 Défaite',
              style: const TextStyle(color: Colors.white)),
          content: Text(
              won
                  ? 'Ton nuisible a atteint la rive adverse.'
                  : 'L\'adversaire a percé en premier.',
              style: const TextStyle(color: Colors.white70)),
          actions: [
            FilledButton(
                onPressed: () {
                  Navigator.pop(context); // dialog
                  Navigator.pop(context); // board
                },
                child: const Text('Retour')),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: AnimatedBuilder(
        animation: ctrl,
        builder: (context, _) {
          _maybeWinDialog();
          return Column(children: [
            _topBar(),
            Expanded(child: _boardGrid()),
            _palette(),
          ]);
        },
      ),
    );
  }

  Widget _topBar() {
    final ms = ctrl.msToNextTick();
    final status = ctrl.statusLabel;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: _kCard,
      child: Column(children: [
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(status,
                style: const TextStyle(color: _kGold, fontSize: 12.5)),
          ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF4ADE80)),
          const SizedBox(width: 8),
          Text(
            ms == null
                ? 'En attente du départ'
                : 'Prochaine avancée dans ${_fmt(ms)}',
            style: const TextStyle(
                color: Color(0xFF4ADE80),
                fontWeight: FontWeight.w800,
                fontSize: 14,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const SizedBox(width: 12),
          Text('tour ${ctrl.nowTick()}',
              style: TextStyle(color: Colors.white.withOpacity(.4), fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _boardGrid() {
    final w = ctrl.width, l = ctrl.lanes;
    final sim = simulateBattle(
        events: ctrl.events, width: w, lanes: l, nowTick: ctrl.nowTick());
    // index (lane,cell) → unité visible (priorité aux unités vivantes).
    final at = <int, BattleUnit>{};
    for (final u in sim.units) {
      if (u.cell < 0 || u.cell >= w) continue;
      at[u.lane * w + u.cell] = u;
    }
    return LayoutBuilder(builder: (context, c) {
      // Taille de cellule = ce qui tient dans l'espace (largeur ET hauteur) →
      // tout le plateau visible sans scroll, quelle que soit la grille.
      const pad = 12.0, headerH = 28.0, hintH = 30.0;
      final availW = c.maxWidth - pad * 2;
      final availH = c.maxHeight - pad * 2 - headerH - hintH - 14;
      double slot = min(availW / w, availH / l);
      slot = slot.clamp(22.0, 64.0);
      final inner = slot - 4;
      final gridW = slot * w;
      return Padding(
        padding: const EdgeInsets.all(pad),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: gridW,
              child: Row(children: [
                _campTag('Toi', _kMine),
                const Spacer(),
                Text(ctrl.mySide == 0 ? '→' : '←',
                    style: TextStyle(
                        color: Colors.white.withOpacity(.4), fontSize: 13)),
                const Spacer(),
                _campTag('Adversaire', _kFoe),
              ]),
            ),
            const SizedBox(height: 6),
            for (int lane = 0; lane < l; lane++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (int cell = 0; cell < w; cell++)
                  _cell(at[lane * w + cell], lane, inner),
              ]),
            const SizedBox(height: 8),
            SizedBox(
              width: gridW,
              child: Text(
                'Touche un palier, puis un couloir pour déposer à ta rive.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.white.withOpacity(.45), fontSize: 11),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _campTag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withOpacity(.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withOpacity(.4)),
        ),
        child: Text(t,
            style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11)),
      );

  Widget _cell(BattleUnit? u, int lane, double inner) {
    final mine = u != null && u.side == ctrl.mySide;
    return GestureDetector(
      onTap: () => _tapLane(lane),
      child: Container(
        width: inner,
        height: inner,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: u == null
              ? Colors.white.withOpacity(.03)
              : (mine ? _kMine : _kFoe).withOpacity(.18),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
              color: u == null
                  ? Colors.white.withOpacity(.06)
                  : (mine ? _kMine : _kFoe).withOpacity(.6)),
        ),
        alignment: Alignment.center,
        child: u == null
            ? null
            : Text(u.isFlame ? '🔥' : tierEmoji(u.tier),
                style: TextStyle(fontSize: inner * 0.56)),
      ),
    );
  }

  Widget _palette() {
    final budgetLeft =
        GoldEconomy.masseBudgetPerTick - ctrl.masseSpentThisTick();
    final flamesLeft = 3 - ctrl.flamesUsed();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      color: _kCard,
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Masse : ${ctrl.masseAvailable}',
              style: const TextStyle(
                  color: _kGold, fontWeight: FontWeight.w800, fontSize: 12.5)),
          const SizedBox(width: 14),
          Text('Budget du tour : $budgetLeft/${GoldEconomy.masseBudgetPerTick}',
              style: TextStyle(
                  color: budgetLeft > 0 ? Colors.white70 : _kFoe, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (final tier in const ['spider', 'scorpion', 'serpent'])
            _tierChip(tier, GoldEconomy.masseCost(tier)),
          _flameChip(flamesLeft),
        ]),
      ]),
    );
  }

  Widget _tierChip(String tier, int cost) {
    final sel = _selTier == tier;
    final affordable = ctrl.masseAvailable >= cost &&
        ctrl.masseSpentThisTick() + cost <= GoldEconomy.masseBudgetPerTick;
    return GestureDetector(
      onTap: () => setState(() => _selTier = tier),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _kMine.withOpacity(.25) : Colors.white.withOpacity(.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: sel ? _kMine : Colors.white.withOpacity(.12), width: sel ? 2 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Opacity(
            opacity: affordable ? 1 : .4,
            child: Text(tierEmoji(tier), style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(height: 2),
          Text('$cost',
              style: TextStyle(
                  color: affordable ? _kGold : Colors.white38,
                  fontWeight: FontWeight.w800,
                  fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _flameChip(int left) {
    final sel = _selTier == 'flame';
    return GestureDetector(
      onTap: left > 0 ? () => setState(() => _selTier = 'flame') : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _kFoe.withOpacity(.25) : Colors.white.withOpacity(.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: sel ? _kFoe : Colors.white.withOpacity(.12), width: sel ? 2 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Opacity(
              opacity: left > 0 ? 1 : .35,
              child: const Text('🔥', style: TextStyle(fontSize: 22))),
          const SizedBox(height: 2),
          Text('×$left',
              style: TextStyle(
                  color: left > 0 ? _kFoe : Colors.white38,
                  fontWeight: FontWeight.w800,
                  fontSize: 11)),
        ]),
      ),
    );
  }
}
