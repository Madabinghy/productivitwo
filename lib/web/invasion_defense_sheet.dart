import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/battle_sim.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';

// Board de DÉFENSE d'invasion (mode « Territoires »), tower-defense asymétrique.
// Ici : PRACTICE SOLO uniquement (aucun backend) — la force envahisseur est figée,
// le défenseur joue en direct (dépose des bloqueurs + tire des flèches), horloge
// rapide. Sert à sentir l'équilibrage des flèches avant de figer les règles serveur.
// L'abstraction `_InvasionCtrl` accueillera la version remote (Phase 4 réseau).

const _kGold = Color(0xFFD4A017);
const _kYou = Color(0xFF3B82F6); // tes unités (défenseur, side 1)
const _kInv = Color(0xFFFF2B2B); // envahisseur (side 0)
const _kBg = Color(0xFF0E0A0A);
const _kCard = Color(0xFF160C0C);
const _kWin = Color(0xFF22C55E);
const int _kBotTickMs = 2500; // tick rapide pour le combat solo contre un bot
const int _kArrowsPerTick = 3; // cap de flèches par tour (= règle serveur visée)

String _tierEmoji(String tier) =>
    tier == 'serpent' ? '🐍' : (tier == 'scorpion' ? '🦂' : '🕷️');

/// Construit la force d'invasion FIGÉE d'un boss bot, déversée en VAGUES (1 par
/// tour) sur plusieurs couloirs — pas une salve unique. La difficulté vient du
/// DÉBIT, pas de ton stock : le cap de 3 flèches/tour ne peut pas couvrir tous les
/// couloirs d'une vague → tu dois choisir (quel couloir, flèche ou bloqueur). La
/// taille est FIXE par palier (ne taxe pas ton accumulation de flèches). `extra`
/// = vagues supplémentaires optionnelles (réservé au futur trigger hebdo, scalé
/// sur l'AMPLEUR de la chute de score, pas sur la réserve). Un boss du palier
/// apparaît une vague sur deux ; le reste = grunts/araignées.
List<BattleEvent> buildInvaderForce(int level, {int extra = 0}) {
  final boss = level >= 5 ? 'serpent' : (level >= 3 ? 'scorpion' : 'spider');
  final grunt = level >= 3 ? 'scorpion' : 'spider';
  const weak = 'spider';
  final baseWaves = level >= 5 ? 5 : (level >= 3 ? 4 : 3);
  final waves = baseWaves + extra.clamp(0, 6);
  final lanesPerWave = level >= 5 ? 5 : (level >= 3 ? 4 : 3);
  const laneOrder = [2, 1, 3, 0, 4]; // centre d'abord
  final out = <BattleEvent>[];
  var seq = 0;
  for (var w = 0; w < waves; w++) {
    final hasBoss = w.isEven; // un boss une vague sur deux
    for (var i = 0; i < lanesPerWave; i++) {
      final tier = (i == 0 && hasBoss) ? boss : (i.isOdd ? grunt : weak);
      out.add(BattleEvent(
          id: 'inv${seq++}',
          side: 0,
          lane: laneOrder[i % laneOrder.length],
          kind: 'pest',
          tier: tier,
          tick: w));
    }
  }
  return out;
}

/// Défense BLEUE d'une grotte (side 1) pour la résolution AUTO green-vs-blue quand
/// tu ne défends pas l'envahisseur à temps. Calquée sur `buildInvaderForce` mais en
/// bloqueurs side 1, scalée par `blueLevel` → à niveau égal, combat ~équilibré
/// (chaque cran de grotte montée pèse vraiment dans la résolution).
List<BattleEvent> buildBlueDefense(int blueLevel) {
  final boss = blueLevel >= 5 ? 'serpent' : (blueLevel >= 3 ? 'scorpion' : 'spider');
  final grunt = blueLevel >= 3 ? 'scorpion' : 'spider';
  const weak = 'spider';
  final waves = blueLevel >= 5 ? 5 : (blueLevel >= 3 ? 4 : 3);
  final lanesPerWave = blueLevel >= 5 ? 5 : (blueLevel >= 3 ? 4 : 3);
  const laneOrder = [2, 1, 3, 0, 4];
  final out = <BattleEvent>[];
  var seq = 0;
  for (var w = 0; w < waves; w++) {
    final hasBoss = w.isEven;
    for (var i = 0; i < lanesPerWave; i++) {
      final tier = (i == 0 && hasBoss) ? boss : (i.isOdd ? grunt : weak);
      out.add(BattleEvent(
          id: 'blue${seq++}',
          side: 1,
          lane: laneOrder[i % laneOrder.length],
          kind: 'pest',
          tier: tier,
          tick: w));
    }
  }
  return out;
}

/// Compose la force OFFENSIVE d'une invasion depuis le deck vert : une COPIE
/// (non consommée) de tous les nuisibles ≤ palier du rouge `redTier`, métrée en
/// VAGUES (budget de masse par tick → gros deck = siège long). Boss (plus fort)
/// au centre tick 0, le reste en round-robin sur les couloirs et les vagues.
/// Retourne `[{id,tier,lane,tick}]` prêt pour `releaseInvasion`. Vide si pas de deck.
List<Map<String, dynamic>> composeInvasionForce(AppLogic logic, String redTier) {
  final cap = GoldEconomy.redPower(redTier); // tierStrength du plafond
  // Plus forts d'abord (serpent, scorpion, spider), filtrés au plafond du rouge.
  final units = <String>[];
  for (final t in const ['serpent', 'scorpion', 'spider']) {
    if (GoldEconomy.redPower(t) > cap) continue;
    final n = logic.redCraftable(t); // deck vert restant de ce palier
    for (var i = 0; i < n; i++) {
      units.add(t);
    }
  }
  if (units.isEmpty) return const [];
  // Cap anti-siège-absurde : garde les plus forts (déjà triés fort→faible).
  const maxUnits = 40;
  final force = units.length <= maxUnits ? units : units.sublist(0, maxUnits);
  const budgetPerTick = 20; // masse déversée par vague
  const laneOrder = [2, 1, 3, 0, 4]; // centre d'abord
  final out = <Map<String, dynamic>>[];
  var tick = 0, tickMasse = 0, laneIdx = 0, seq = 0;
  for (final t in force) {
    final cost = GoldEconomy.masseCost(t);
    if (tickMasse > 0 && tickMasse + cost > budgetPerTick) {
      tick++;
      tickMasse = 0;
      laneIdx = 0;
    }
    final lane = seq == 0 ? 2 : laneOrder[laneIdx % laneOrder.length];
    out.add({'id': 'a$seq', 'tier': t, 'lane': lane, 'tick': tick});
    tickMasse += cost;
    laneIdx++;
    seq++;
  }
  return out;
}

/// Ouvre le hub d'invasion (practice solo pour l'instant).
Future<void> showInvasionSheet(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(.65),
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: _kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: _InvasionHub(logic: logic, sync: sync),
      ),
    ),
  );
}

/// Combat de grotte (lever ton deck bleu) : le boss de TA grotte t'assaille, tu le
/// repousses. La difficulté monte avec `blueLevel` (boss + dur, plus de vagues) →
/// plafonné par ton budget de flèches. Dépense tes vraies flèches/masse ; l'issue
/// (montée de niveau) est gérée par l'appelant (applyDefaultOutcome=false).
/// Retourne le vainqueur ('defender' = grotte tenue → monte d'un niveau).
Future<String?> showCaveFight(
    BuildContext context, AppLogic logic, FirestoreSync sync,
    {required int blueLevel, required String title}) {
  final level = blueLevel >= 5 ? 5 : (blueLevel >= 3 ? 3 : 1);
  final extra = (blueLevel - 1).clamp(0, 6);
  return Navigator.of(context).push<String>(MaterialPageRoute(
    builder: (_) => _InvasionBoardScreen(
      ctrl: _BotInvasionCtrl(logic, sync, level,
          stakes: true,
          extra: extra,
          applyDefaultOutcome: false,
          defenseFromDeck: true),
      title: title,
    ),
  ));
}

// ── Contrôleur abstrait (partagé practice / remote à venir) ──────────────────

abstract class _InvasionCtrl extends ChangeNotifier {
  int get width;
  int get lanes;
  int get tickMs;
  int? get startMs;
  List<BattleEvent> get events; // force envahisseur (tick0 side0) + défense (side1)
  int get masseAvailable;
  int get arrowsAvailable;
  String? get winner; // 'invader' | 'defender' | null

  bool get started => startMs != null;

  int nowTick() {
    final s = startMs;
    if (s == null) return 0;
    final t = (DateTime.now().millisecondsSinceEpoch - s) ~/ tickMs;
    return t < 0 ? 0 : t;
  }

  int? msToNextTick() {
    final s = startMs;
    if (s == null) return null;
    final next = s + (nowTick() + 1) * tickMs;
    final d = next - DateTime.now().millisecondsSinceEpoch;
    return d < 0 ? 0 : d;
  }

  int masseSpentThisTick() {
    final t = nowTick();
    return events
        .where((e) => e.side == 1 && e.kind == 'pest' && e.tick == t)
        .fold(0, (s, e) => s + GoldEconomy.masseCost(e.tier));
  }

  int arrowsSpentThisTick() {
    final t = nowTick();
    return events
        .where((e) => e.side == 1 && e.kind == 'arrow' && e.tick == t)
        .length;
  }

  // Mêmes règles que le serveur visé (budget masse 15/tick, cap flèches/tick).
  String? validate(int lane, String kind, String tier) {
    if (lane < 0 || lane >= lanes) return 'Couloir invalide';
    if (kind == 'arrow') {
      if (arrowsAvailable <= 0) return 'Plus de flèches';
      if (arrowsSpentThisTick() >= _kArrowsPerTick) {
        return 'Max $_kArrowsPerTick flèches par tour';
      }
    } else {
      if (masseSpentThisTick() + GoldEconomy.masseCost(tier) >
          GoldEconomy.masseBudgetPerTick) {
        return 'Budget du tour atteint (${GoldEconomy.masseBudgetPerTick} masse)';
      }
      if (masseAvailable < GoldEconomy.masseCost(tier)) {
        return 'Masse insuffisante';
      }
    }
    return null;
  }

  Future<String?> deploy(int lane, String kind, String tier);
}

// ── Bot PvE : combat solo contre un boss bot ─────────────────────────────────
// Force figée + horloge rapide. Deux variantes via `stakes` :
//  • Escarmouche (stakes=false) : ta vraie réserve est AFFICHÉE mais rien n'est
//    consommé/persisté, aucune conséquence — pour régler l'équilibrage à volonté.
//  • Boss réel (stakes=true) : dépense ta vraie masse/flèches ; si le boss atteint
//    ton cœur il grignote ton deck vert (plafonné, récupérable) ; le repousser
//    rapporte de l'or.

class _BotInvasionCtrl extends _InvasionCtrl {
  final AppLogic logic;
  final FirestoreSync sync;
  final int level;
  final bool stakes;
  final int extra; // vagues supplémentaires (siège de grotte plus dur)
  // false = l'appelant gère l'issue (ex. lever une grotte) → pas d'or/deckDamage.
  final bool applyDefaultOutcome;
  // true = défense de territoire : la masse vient du DECK LIFETIME (force permanente)
  // et n'est PAS consommée (copies, budget/tick). Cohérent avec le Dock vert.
  final bool defenseFromDeck;

  @override
  final int width = 7;
  @override
  final int lanes = 5;
  @override
  int get tickMs => _kBotTickMs;

  final List<BattleEvent> _events;
  @override
  List<BattleEvent> get events => _events;

  // Escarmouche : dépense LOCALE (non persistée) déduite de la vraie réserve.
  int _localMasse = 0;
  int _localArrows = 0;

  @override
  int get masseAvailable {
    // Défense de territoire : deck lifetime, constant (non consommé, copies).
    if (defenseFromDeck) return logic.lifetimeBattleMasse;
    final real = logic.battleMasseAvailable;
    return stakes ? real : (real - _localMasse).clamp(0, real);
  }

  @override
  int get arrowsAvailable {
    final real = logic.weaponsAvailable('arc');
    return stakes ? real : (real - _localArrows).clamp(0, real);
  }

  String? _winner;
  @override
  String? get winner => _winner;

  // Bilan d'issue (Boss réel) pour l'UI.
  int rewardGold = 0;
  Map<String, int> deckLoss = const {};
  bool _outcomeApplied = false;

  @override
  final int startMs = DateTime.now().millisecondsSinceEpoch;

  Timer? _timer;
  int _seq = 0;

  _BotInvasionCtrl(this.logic, this.sync, this.level,
      {required this.stakes,
      this.extra = 0,
      this.applyDefaultOutcome = true,
      this.defenseFromDeck = false})
      : _events = List<BattleEvent>.from(buildInvaderForce(level, extra: extra)) {
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _pulse());
  }

  void _pulse() {
    if (_winner != null) return;
    _checkWinner(nowTick());
    notifyListeners();
  }

  void _checkWinner(int t) {
    final r = simulateInvasion(
        events: _events, width: width, lanes: lanes, nowTick: t);
    if (r.winner != null) {
      _winner = r.winner;
      _timer?.cancel();
      _applyOutcome(r);
    }
  }

  void _applyOutcome(InvasionSimResult r) {
    if (!stakes || _outcomeApplied || !applyDefaultOutcome) return;
    _outcomeApplied = true;
    if (r.winner == 'defender') {
      rewardGold = GoldEconomy.bossWinReward;
      logic.applyGold(sync, rewardGold,
          category: 'gain',
          reasonCode: 'invasion_boss_win',
          label: 'Boss repoussé');
    } else if (r.winner == 'invader') {
      // Chaque envahisseur ayant atteint le cœur grignote 1 unité du deck (même
      // palier). Plafonné/récupérable côté moteur (applyBossDeckDamage).
      final crossing = <String, int>{};
      for (final u in r.units) {
        if (u.side == 0 && !u.isFlame && u.cell >= width) {
          crossing[u.tier] = (crossing[u.tier] ?? 0) + 1;
        }
      }
      logic.applyBossDeckDamage(crossing, sync);
      deckLoss = crossing;
    }
  }

  @override
  Future<String?> deploy(int lane, String kind, String tier) async {
    if (_winner != null) return 'Partie terminée';
    final err = validate(lane, kind, tier);
    if (err != null) return err;
    if (stakes) {
      if (kind == 'pest') {
        // Défense de territoire : copies du deck lifetime → NON consommées.
        if (!defenseFromDeck && !logic.spendBattleMasse(tier, sync)) {
          return 'Masse insuffisante';
        }
      } else {
        if (!logic.spendWeaponForWorld('arc', sync)) return 'Plus de flèches';
      }
    } else {
      if (kind == 'pest') {
        _localMasse += GoldEconomy.masseCost(tier);
      } else {
        _localArrows += 1;
      }
    }
    _events.add(BattleEvent(
        id: 'd${_seq++}',
        side: 1,
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

// ── Remote : invasion réelle (streams Firestore + Cloud Functions) ───────────
// Le DÉFENSEUR joue ici contre une force figée déposée par un autre joueur. La
// force + les events vivent dans `invasions/{id}` ; chaque dépôt passe par
// `deployDefense` (validé serveur), l'économie réelle est débitée localement
// (trust v1). Quand la simu locale détecte une élimination totale, on demande au
// serveur de trancher (`resolveInvasion`, autoritatif) — le statut revient par le
// stream et fige le board.

class _RemoteInvasionCtrl extends _InvasionCtrl {
  final AppLogic logic;
  final FirestoreSync sync;
  final String invasionId;

  Invasion? _inv;
  List<BattleEvent> _defense = const [];
  Timer? _timer;
  StreamSubscription<Invasion?>? _invSub;
  StreamSubscription<List<BattleEvent>>? _evSub;
  bool _resolving = false;

  _RemoteInvasionCtrl(this.logic, this.sync, this.invasionId, Invasion seed)
      : _inv = seed {
    _invSub = sync.streamInvasion(invasionId).listen((i) {
      if (i != null) _inv = i;
      notifyListeners();
    });
    _evSub = sync.streamInvasionEvents(invasionId).listen((e) {
      _defense = e;
      notifyListeners();
    });
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) => _pulse());
  }

  @override
  int get width => _inv?.width ?? 7;
  @override
  int get lanes => _inv?.lanes ?? 5;
  @override
  int get tickMs => (_inv?.tickMinutes ?? 60) * 60000;
  @override
  int? get startMs => _inv?.startAtMs;

  @override
  List<BattleEvent> get events =>
      [...(_inv?.force ?? const <BattleEvent>[]), ..._defense];

  @override
  int get masseAvailable => logic.battleMasseAvailable;
  @override
  int get arrowsAvailable => logic.weaponsAvailable('arc');

  @override
  String? get winner => _inv?.winner;

  void _pulse() {
    final inv = _inv;
    if (inv != null && inv.winner == null && inv.active && !_resolving) {
      final r = simulateInvasion(
          events: events, width: width, lanes: lanes, nowTick: nowTick());
      if (r.winner != null) {
        _resolving = true;
        sync.resolveInvasion(invasionId).whenComplete(() => _resolving = false);
      }
    }
    notifyListeners();
  }

  @override
  Future<String?> deploy(int lane, String kind, String tier) async {
    final inv = _inv;
    if (inv == null) return 'Chargement…';
    if (inv.winner != null) return 'Invasion terminée';
    if (!inv.active) return 'Invasion pas encore engagée';
    final err = validate(lane, kind, tier);
    if (err != null) return err;
    // Le serveur tranche le budget/tick ; on ne débite l'économie locale qu'après
    // son accord (cohérent trust v1 : pas de double dépense si le serveur refuse).
    final serverErr = await sync.deployDefense(invasionId, lane, kind, tier);
    if (serverErr != null) return serverErr;
    if (kind == 'pest') {
      logic.spendBattleMasse(tier, sync);
    } else {
      logic.spendWeaponForWorld('arc', sync);
    }
    notifyListeners();
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _invSub?.cancel();
    _evSub?.cancel();
    super.dispose();
  }
}

// ── Hub ───────────────────────────────────────────────────────────────────────

// Icône Flutter rouge représentant un nuisible d'invasion (« rouge »), par palier.
IconData _redTierIcon(String tier) => switch (tier) {
      'serpent' => Icons.gesture, // serpent (ondulé)
      'scorpion' => Icons.pest_control, // scorpion
      _ => Icons.bug_report, // araignée
    };
String _redTierName(String tier) => switch (tier) {
      'serpent' => 'Serpent rouge',
      'scorpion' => 'Scorpion rouge',
      _ => 'Araignée rouge',
    };

class _InvasionHub extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _InvasionHub({required this.logic, required this.sync});

  @override
  State<_InvasionHub> createState() => _InvasionHubState();
}

class _InvasionHubState extends State<_InvasionHub> {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => widget.sync;

  List<Invasion> _incoming = const [];
  List<Invasion> _outgoing = const [];
  bool _loadingIncoming = true;

  @override
  void initState() {
    super.initState();
    _loadIncoming();
    _loadOutgoing();
  }

  Future<void> _loadIncoming() async {
    final list = await sync.fetchInvasionsAsDefender();
    if (!mounted) return;
    setState(() {
      _incoming = list;
      _loadingIncoming = false;
    });
  }

  Future<void> _loadOutgoing() async {
    final list = await sync.fetchInvasionsAsInvader();
    if (!mounted) return;
    setState(() => _outgoing = list);
  }

  Future<void> _openRemote(Invasion inv) async {
    // Engage l'invasion si elle est encore en attente (lance l'horloge serveur).
    if (inv.pending) {
      final err = await sync.engageInvasion(inv.id);
      if (err != null) {
        _toast(err, _kInv);
        return;
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _InvasionBoardScreen(
        ctrl: _RemoteInvasionCtrl(logic, sync, inv.id, inv),
        title: 'Défense — ${inv.invaderLabelForDefender()}',
      ),
    ));
    _loadIncoming(); // rafraîchit la liste après une partie (statut peut changer)
  }

  bool _botStakes = false; // false = Escarmouche · true = Boss réel

  void _openBoard(int level, String title) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _InvasionBoardScreen(
          ctrl: _BotInvasionCtrl(logic, sync, level, stakes: _botStakes),
          title: title),
    ));
  }

  void _toast(String m, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: c,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1)));
  }

  void _craft(String tier) {
    final ok = logic.craftRed(tier, sync);
    setState(() {});
    _toast(ok ? '${_redTierName(tier)} forgée 🔴' : 'Pas assez de captures',
        ok ? _kWin : _kInv);
  }

  void _upgrade(String tier) {
    final ok = logic.upgradeRed(tier, sync);
    setState(() {});
    _toast(ok ? 'Monté en gamme 🔴' : 'Impossible (captures / rouge manquant)',
        ok ? _kWin : _kInv);
  }

  // Lance une invasion avec un ticket rouge : compose la force depuis le deck vert,
  // confirme, appelle releaseInvasion (matchmaking ladder serveur), puis consomme
  // le ticket. La cible (~3 rangs au-dessus) est révélée au succès.
  Future<void> _attack(String tier) async {
    if (logic.redCount(tier) <= 0) {
      _toast('Aucun ${_redTierName(tier).toLowerCase()} à envoyer', _kInv);
      return;
    }
    final force = composeInvasionForce(logic, tier);
    if (force.isEmpty) {
      _toast('Ton deck vert est vide — farme/forge avant d\'attaquer', _kInv);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kCard,
        title: Text('Lancer ${_redTierName(tier).toLowerCase()} ?',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          'Ta force : ${force.length} nuisible${force.length > 1 ? 's' : ''} '
          '(copie de ton deck vert ≤ ${_tierEmoji(tier)}), déversée en vagues. '
          'Le ticket rouge est immobilisé tant que l\'invasion dure. Cible : un '
          'joueur juste au-dessus de toi au classement.',
          style: TextStyle(color: Colors.white.withOpacity(.75), fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kInv),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Envahir')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await sync.releaseInvasion(tier, force);
    if (!mounted) return;
    if (res == null) {
      _toast('Aucune cible disponible (ou réseau) — réessaie plus tard', _kInv);
      return;
    }
    logic.releaseRed(tier, sync); // consomme le ticket après succès serveur
    setState(() {});
    _loadOutgoing(); // la nouvelle invasion apparaît dans « mes offensives »
    final pseudo = (res['defenderPseudo'] as String?) ?? '?';
    _toast('👑 Invasion lancée contre @$pseudo', _kWin);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(children: [
            const Text('👑 Invasion',
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
              _arsenalSection(),
              const SizedBox(height: 18),
              _defenseSection(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Arsenal : craft de nuisibles rouges depuis les captures ────────────────
  Widget _arsenalSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kInv.withOpacity(.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kInv.withOpacity(.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.local_fire_department, color: _kInv, size: 20),
          const SizedBox(width: 8),
          const Text('Mon arsenal',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _kInv.withOpacity(.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kInv.withOpacity(.5)),
            ),
            child: Text('Puissance ${logic.invasionDeckPower}',
                style: const TextStyle(
                    color: _kInv, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          'Un ROUGE est un ticket d\'invasion (palier = portée) : il envoie une COPIE '
          'de ton deck vert ≤ son palier. Le forger CONSOMME des verts. Peu de rouges '
          '+ gros deck = peu de fronts mais écrasants ; beaucoup de rouges = deck mince.',
          style: TextStyle(
              fontSize: 11.5, color: Colors.white.withOpacity(.6), height: 1.3),
        ),
        const SizedBox(height: 10),
        // Deck vert (réserve) — la matière qui se fait consommer au craft ET qui
        // attaque (en copie). Affiché en clair pour VOIR la consommation.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: _kWin.withOpacity(.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kWin.withOpacity(.35)),
          ),
          child: Row(children: [
            const Text('Ton deck vert',
                style: TextStyle(
                    color: _kWin, fontSize: 12, fontWeight: FontWeight.w900)),
            const Spacer(),
            Text(
                '🕷️ ${logic.redCraftable('spider')}   '
                '🦂 ${logic.redCraftable('scorpion')}   '
                '🐍 ${logic.redCraftable('serpent')}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(height: 12),
        for (final tier in const ['spider', 'scorpion', 'serpent'])
          _redTierRow(tier),
        _outgoingSection(),
      ]),
    );
  }

  // Mes invasions en cours (envahisseur) : cible + statut. Informative — le board
  // spectateur live (read-only) reste un raffinement Phase 5.
  Widget _outgoingSection() {
    if (_outgoing.isEmpty) return const SizedBox.shrink();
    String label(Invasion i) => i.held
        ? 'tenu 👑'
        : (i.active ? 'en cours' : 'en attente');
    Color col(Invasion i) => i.held ? _kGold : (i.active ? _kInv : Colors.white54);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Divider(color: Colors.white.withOpacity(.08), height: 18),
        Text('Mes offensives (${_outgoing.length})',
            style: TextStyle(
                color: Colors.white.withOpacity(.55),
                fontSize: 11,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final inv in _outgoing)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Text(_tierEmoji(inv.redTier), style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('contre @${inv.defenderPseudo}',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
              Text(label(inv),
                  style: TextStyle(
                      color: col(inv),
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ]),
          ),
      ]),
    );
  }

  Widget _redTierRow(String tier) {
    final avail = logic.redCraftable(tier); // nuisibles dispo de ce palier
    final count = logic.redCount(tier);
    final canCraft = avail >= GoldEconomy.redCraftCost;
    final above = GoldEconomy.tierAbove(tier);
    final canUpgrade =
        above != null && count > 0 && avail >= GoldEconomy.redUpgradeCost;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _kInv.withOpacity(.14),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _kInv.withOpacity(.5)),
          ),
          alignment: Alignment.center,
          child: Icon(_redTierIcon(tier), color: _kInv, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(_redTierName(tier),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(width: 6),
                Text('×$count',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: count > 0 ? _kGold : Colors.white38)),
              ]),
              Text(
                  'nuisibles ${_tierEmoji(tier)} dispo : $avail',
                  style:
                      TextStyle(fontSize: 10.5, color: Colors.white.withOpacity(.5))),
            ],
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _miniBtn('Forger (${GoldEconomy.redCraftCost})', _kWin,
              canCraft ? () => _craft(tier) : null),
          if (above != null) ...[
            const SizedBox(height: 4),
            _miniBtn('Monter → ${_tierEmoji(above)} (${GoldEconomy.redUpgradeCost})',
                _kGold, canUpgrade ? () => _upgrade(tier) : null),
          ],
          if (count > 0) ...[
            const SizedBox(height: 4),
            _miniBtn('⚔️ Attaquer', _kInv, () => _attack(tier)),
          ],
        ]),
      ]),
    );
  }

  Widget _miniBtn(String label, Color color, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: onTap == null ? .35 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(.16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(.5)),
            ),
            child: Text(label,
                style: TextStyle(
                    color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
          ),
        ),
      );

  // Invasions réelles à défendre (fetchInvasionsAsDefender). Tap → engage + board.
  Widget _incomingSection() {
    if (_loadingIncoming) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: Center(
          child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _kInv)),
        ),
      );
    }
    if (_incoming.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.warning_amber_rounded, color: _kInv, size: 18),
        const SizedBox(width: 6),
        Text('Tu es envahi (${_incoming.length})',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w900, color: _kInv)),
      ]),
      const SizedBox(height: 10),
      for (final inv in _incoming) _incomingRow(inv),
      const SizedBox(height: 18),
    ]);
  }

  Widget _incomingRow(Invasion inv) {
    final active = inv.active;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _openRemote(inv),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _kInv.withOpacity(.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kInv.withOpacity(.45)),
          ),
          child: Row(children: [
            Text(_tierEmoji(inv.redTier), style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Boss ${_redTierName(inv.redTier).toLowerCase()}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  Text(
                      active
                          ? 'En cours — reprends la défense'
                          : 'Force de ${inv.force.length} nuisible${inv.force.length > 1 ? 's' : ''} · engage pour défendre',
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.white.withOpacity(.6))),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: (active ? _kGold : _kWin).withOpacity(.18),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: (active ? _kGold : _kWin).withOpacity(.6)),
              ),
              child: Text(active ? 'Reprendre' : 'Défendre',
                  style: TextStyle(
                      color: active ? _kGold : _kWin,
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5)),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Défense : invasions réelles reçues + entraînement solo ─────────────────
  Widget _defenseSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kYou.withOpacity(.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kYou.withOpacity(.22)),
        ),
        child: Text(
          'Défense : un envahisseur pose un boss sur ta carte, sa force avance vers '
          'ton cœur. Élimine-la (bloqueurs 🕷️🦂🐍 + flèches 🏹, 1 cran de dégât). '
          'Un seul nuisible qui atteint ton cœur = territoire cédé.',
          style: TextStyle(
              fontSize: 12.5, color: Colors.white.withOpacity(.7), height: 1.35),
        ),
      ),
      const SizedBox(height: 14),
      _incomingSection(),
      const Text('Combat contre un boss — choisis le mode',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white70)),
      const SizedBox(height: 10),
      _modeSelector(),
      const SizedBox(height: 12),
      _diffBtn('🕷️', 'Facile', 'Boss araignée + 1 renfort', _kWin, 1),
      const SizedBox(height: 10),
      _diffBtn('🦂', 'Moyen', 'Boss scorpion + 2 renforts', _kGold, 3),
      const SizedBox(height: 10),
      _diffBtn('🐍', 'Costaud', 'Boss serpent + 3 renforts', _kInv, 5),
      const SizedBox(height: 12),
      Text(
        _botStakes
            ? 'Boss réel : ta vraie masse (${logic.battleMasseAvailable}) et tes flèches '
                '(🏹 ${logic.weaponsAvailable('arc')}) se dépensent. Le repousser '
                'rapporte ${GoldEconomy.bossWinReward} or ; s\'il atteint ton cœur il '
                'grignote ton deck vert (plafonné, tu refarmes). Max $_kArrowsPerTick flèches/tour.'
            : 'Escarmouche : ta vraie réserve est affichée mais RIEN ne se consomme, '
                'aucune conséquence — itère l\'équilibrage à volonté. Max $_kArrowsPerTick flèches/tour.',
        style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(.45)),
      ),
    ]);
  }

  // Sélecteur de mode : Escarmouche (sans enjeu) ⇄ Boss réel (vraies conséquences).
  Widget _modeSelector() {
    Widget chip(String label, String sub, bool stakes, IconData icon) {
      final sel = _botStakes == stakes;
      final c = stakes ? _kInv : _kWin;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _botStakes = stakes),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? c.withOpacity(.2) : Colors.white.withOpacity(.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: sel ? c : Colors.white.withOpacity(.12),
                  width: sel ? 2 : 1),
            ),
            child: Column(children: [
              Icon(icon, color: sel ? c : Colors.white38, size: 20),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      color: sel ? c : Colors.white70,
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5)),
              Text(sub,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withOpacity(.5), fontSize: 10)),
            ]),
          ),
        ),
      );
    }

    return Row(children: [
      chip('Escarmouche', 'sans enjeu', false, Icons.sports_martial_arts),
      const SizedBox(width: 10),
      chip('Boss réel', 'vraies conséquences', true, Icons.local_fire_department),
    ]);
  }

  Widget _diffBtn(String emoji, String title, String sub, Color color, int level) =>
      InkWell(
        onTap: () => _openBoard(level, 'Défense — $title'),
        borderRadius: BorderRadius.circular(14),
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
                          fontSize: 11.5, color: Colors.white.withOpacity(.55))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
          ]),
        ),
      );
}

// ── Board ─────────────────────────────────────────────────────────────────────

class _InvasionBoardScreen extends StatefulWidget {
  final _InvasionCtrl ctrl;
  final String title;
  const _InvasionBoardScreen({required this.ctrl, required this.title});

  @override
  State<_InvasionBoardScreen> createState() => _InvasionBoardScreenState();
}

class _InvasionBoardScreenState extends State<_InvasionBoardScreen> {
  _InvasionCtrl get ctrl => widget.ctrl;
  String _sel = 'arrow'; // 'arrow' | 'spider' | 'scorpion' | 'serpent'
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
    return '$m:$ss';
  }

  Future<void> _tapLane(int lane) async {
    final kind = _sel == 'arrow' ? 'arrow' : 'pest';
    final err = await ctrl.deploy(lane, kind, _sel);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err),
          backgroundColor: _kInv,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1)));
    }
  }

  // Bilan supplémentaire en mode « Boss réel » (or gagné / deck grignoté).
  String _outcomeExtra(bool won) {
    final c = ctrl;
    if (c is! _BotInvasionCtrl || !c.stakes || !c.applyDefaultOutcome) return '';
    if (won) return '\n\n+${c.rewardGold} or 🪙';
    if (c.deckLoss.isEmpty) return '';
    final parts = c.deckLoss.entries
        .map((e) => '${_tierEmoji(e.key)}×${e.value}')
        .join(' ');
    return '\n\nDeck grignoté : $parts (récupérable en refarmant).';
  }

  void _maybeWinDialog() {
    if (_winShown || ctrl.winner == null) return;
    _winShown = true;
    final won = ctrl.winner == 'defender';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: _kCard,
          title: Text(won ? '🎉 Territoire libéré !' : '💀 Territoire cédé',
              style: const TextStyle(color: Colors.white)),
          content: Text(
              (won
                      ? 'Tu as chassé toute la force d\'invasion. L\'envahisseur sort de '
                          'ton territoire.'
                      : 'Un nuisible a atteint ton cœur. L\'envahisseur tient le '
                          'territoire — tu pourras le reprendre.') +
                  _outcomeExtra(won),
              style: const TextStyle(color: Colors.white70)),
          actions: [
            FilledButton(
                onPressed: () {
                  Navigator.pop(context); // dialog
                  Navigator.pop(context, ctrl.winner); // board → renvoie le vainqueur
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
          final sim = simulateInvasion(
              events: ctrl.events,
              width: ctrl.width,
              lanes: ctrl.lanes,
              nowTick: ctrl.nowTick());
          return Column(children: [
            _topBar(sim),
            Expanded(child: _boardGrid(sim)),
            _casualtiesBar(sim),
            _palette(),
          ]);
        },
      ),
    );
  }

  Widget _topBar(InvasionSimResult sim) {
    final ms = ctrl.msToNextTick();
    final invLeft = sim.units.where((u) => u.side == 0).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: _kCard,
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('👑',
              style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text('$invLeft envahisseur${invLeft > 1 ? 's' : ''} à chasser',
              style: const TextStyle(
                  color: _kInv, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF4ADE80)),
          const SizedBox(width: 8),
          Text(
            ms == null
                ? 'En attente'
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

  Widget _boardGrid(InvasionSimResult sim) {
    final w = ctrl.width, l = ctrl.lanes;
    final at = <int, BattleUnit>{};
    for (final u in sim.units) {
      if (u.cell < 0 || u.cell >= w) continue;
      at[u.lane * w + u.cell] = u;
    }
    return LayoutBuilder(builder: (context, c) {
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
                _campTag('❤️ Ton cœur', _kYou),
                const Spacer(),
                Text('←',
                    style: TextStyle(
                        color: Colors.white.withOpacity(.4), fontSize: 13)),
                const Spacer(),
                _campTag('⚔️ Envahisseur', _kInv),
              ]),
            ),
            const SizedBox(height: 6),
            // Rendu MIROIR : l'envahisseur (case moteur 0) apparaît à droite et
            // marche vers la gauche (ton cœur). Le moteur reste inchangé.
            for (int lane = 0; lane < l; lane++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (int cell = 0; cell < w; cell++)
                  _cell(at[lane * w + (w - 1 - cell)], lane, inner),
              ]),
            const SizedBox(height: 8),
            SizedBox(
              width: gridW,
              child: Text(
                _sel == 'arrow'
                    ? 'Touche un couloir pour tirer une flèche sur l\'envahisseur le plus avancé.'
                    : 'Touche un couloir pour y déposer un bloqueur à ta rive.',
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
    final mine = u != null && u.side == 1;
    return GestureDetector(
      onTap: () => _tapLane(lane),
      child: Container(
        width: inner,
        height: inner,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: u == null
              ? Colors.white.withOpacity(.03)
              : (mine ? _kYou : _kInv).withOpacity(.18),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
              color: u == null
                  ? Colors.white.withOpacity(.06)
                  : (mine ? _kYou : _kInv).withOpacity(.6)),
        ),
        alignment: Alignment.center,
        child: u == null
            ? null
            : Text(_tierEmoji(u.tier), style: TextStyle(fontSize: inner * 0.56)),
      ),
    );
  }

  // Feed des pertes : qui est tombé, de chaque côté, et par quoi (🏹 flèche /
  // ⚔️ nuisible). Affiché seulement quand il y a eu des morts.
  Widget _casualtiesBar(InvasionSimResult sim) {
    final inv = sim.casualties.where((c) => c.side == 0).toList();
    final def = sim.casualties.where((c) => c.side == 1).toList();
    if (inv.isEmpty && def.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: _kCard,
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Tombés au combat  ·  🏹 flèche  ⚔️ nuisible',
            style: TextStyle(
                color: Colors.white.withOpacity(.4),
                fontSize: 10,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        _casualtyRow('Envahisseur', _kInv, inv),
        if (def.isNotEmpty) ...[
          const SizedBox(height: 4),
          _casualtyRow('Toi', _kYou, def),
        ],
      ]),
    );
  }

  Widget _casualtyRow(String label, Color color, List<BattleCasualty> list) {
    const cap = 16;
    final shown = list.length <= cap ? list : list.sublist(0, cap);
    final overflow = list.length - shown.length;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      SizedBox(
        width: 76,
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w800)),
      ),
      Expanded(
        child: list.isEmpty
            ? Text('—',
                style: TextStyle(color: Colors.white.withOpacity(.3), fontSize: 12))
            : Wrap(spacing: 5, runSpacing: 3, children: [
                for (final c in shown)
                  Text(
                      '${_tierEmoji(c.tier)}${c.cause == 'arrow' ? '🏹' : '⚔️'}',
                      style: const TextStyle(fontSize: 13)),
                if (overflow > 0)
                  Text('+$overflow',
                      style: TextStyle(
                          color: Colors.white.withOpacity(.4),
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
              ]),
      ),
    ]);
  }

  Widget _palette() {
    final budgetLeft =
        GoldEconomy.masseBudgetPerTick - ctrl.masseSpentThisTick();
    final arrowsLeftTick = _kArrowsPerTick - ctrl.arrowsSpentThisTick();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      color: _kCard,
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('🏹 ${ctrl.arrowsAvailable}',
              style: const TextStyle(
                  color: _kWin, fontWeight: FontWeight.w800, fontSize: 12.5)),
          const SizedBox(width: 14),
          Text('Masse : ${ctrl.masseAvailable}',
              style: const TextStyle(
                  color: _kGold, fontWeight: FontWeight.w800, fontSize: 12.5)),
          const SizedBox(width: 14),
          Text('Budget : $budgetLeft/${GoldEconomy.masseBudgetPerTick}',
              style: TextStyle(
                  color: budgetLeft > 0 ? Colors.white70 : _kInv, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _arrowChip(arrowsLeftTick),
          for (final tier in const ['spider', 'scorpion', 'serpent'])
            _tierChip(tier, GoldEconomy.masseCost(tier)),
        ]),
      ]),
    );
  }

  Widget _arrowChip(int leftThisTick) {
    final sel = _sel == 'arrow';
    final usable = ctrl.arrowsAvailable > 0 && leftThisTick > 0;
    return GestureDetector(
      onTap: () => setState(() => _sel = 'arrow'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _kWin.withOpacity(.22) : Colors.white.withOpacity(.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: sel ? _kWin : Colors.white.withOpacity(.12),
              width: sel ? 2 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Opacity(
              opacity: usable ? 1 : .4,
              child: const Text('🏹', style: TextStyle(fontSize: 22))),
          const SizedBox(height: 2),
          Text('$leftThisTick/$_kArrowsPerTick',
              style: TextStyle(
                  color: usable ? _kWin : Colors.white38,
                  fontWeight: FontWeight.w800,
                  fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _tierChip(String tier, int cost) {
    final sel = _sel == tier;
    final affordable = ctrl.masseAvailable >= cost &&
        ctrl.masseSpentThisTick() + cost <= GoldEconomy.masseBudgetPerTick;
    return GestureDetector(
      onTap: () => setState(() => _sel = tier),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _kYou.withOpacity(.25) : Colors.white.withOpacity(.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: sel ? _kYou : Colors.white.withOpacity(.12),
              width: sel ? 2 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Opacity(
            opacity: affordable ? 1 : .4,
            child: Text(_tierEmoji(tier), style: const TextStyle(fontSize: 22)),
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
}
