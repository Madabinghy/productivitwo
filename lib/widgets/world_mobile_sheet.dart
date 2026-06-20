import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/assign_activity_sheet.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/backlog_combat.dart';
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart';
import 'package:productivitwo_v1/widgets/activity_detail_sheet.dart';

const _kBg = Color(0xFF0E1512);
const _kEnemy = Color(0xFFE5604D);
const _kCharge = Color(0xFF4FC26B); // vert — chargeur (munitions non tirées)
const _kLife = Color(0xFFF5C518); // jaune — vie moyenne
const _kLifeHigh = Color(0xFF4FA3FF); // bleu — bonne santé

// Code couleur de la vie : bleu (≥5/7) → jaune (≥3/7) → rouge.
Color _lifeColor(double frac) =>
    frac >= 5 / 7 ? _kLifeHigh : (frac >= 3 / 7 ? _kLife : _kEnemy);

String _tokenEmoji(String type, {required bool scorpion}) => type == 'flame'
    ? '🔥'
    : type == 'spider'
        ? (scorpion ? '🦂' : '🕷️')
        : ''; // 'leaf' (fait, 1er jour) → case vide, plus clean

/// UI MOBILE native du « Monde » (reconstruite, pas le portage du sheet web).
/// Étape 1 : la LISTE des domaines. Tap → gameplay mobile du domaine (étape 2).
Future<void> showWorldMobile(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(.6),
    builder: (_) => Dialog.fullscreen(
      backgroundColor: _kBg,
      child: _WorldMobileList(logic: logic, sync: sync),
    ),
  );
}

/// Même UI, rendue comme PAGE plein-écran (pour la prévisu mobile sur le web,
/// dans un cadre téléphone — itération hot-reload sans build Codemagic).
class WorldMobileScreen extends StatelessWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  /// Optionnel : ouvre le VRAI sheet d'activité (FAB lanceur de main.dart) au tap
  /// sur une tour d'activité-temps. Si null → sheet compact interne.
  final void Function(String activityId)? onOpenActivity;
  const WorldMobileScreen(
      {required this.logic,
      required this.sync,
      this.onOpenActivity,
      super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _kBg,
        body: SafeArea(
            child: _WorldMobileList(
                logic: logic, sync: sync, onOpenActivity: onOpenActivity)),
      );
}

class _WorldMobileList extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final void Function(String activityId)? onOpenActivity;
  const _WorldMobileList(
      {required this.logic, required this.sync, this.onOpenActivity});
  @override
  State<_WorldMobileList> createState() => _WorldMobileListState();
}

class _WorldMobileListState extends State<_WorldMobileList> {
  AppLogic get logic => widget.logic;

  // Santé agrégée du domaine (0..1) = jours tenus / jours possibles sur ses
  // routines + activités-temps (fenêtre 7 jours glissants). Couleur de la tour.
  double _domainLife(String domainId) {
    var done = 0, total = 0;
    for (final a in logic.state.activeActivities) {
      if (a.domainId != domainId) continue;
      final tokens =
          a.isHabit ? logic.routineWeekTokens(a.id) : logic.activityTimeTokens(a.id);
      if (tokens.isEmpty) continue;
      done += tokens.where((t) => t.type == 'leaf' || t.type == 'flame').length;
      total += 7;
    }
    return total == 0 ? 0 : done / total;
  }

  // Statut du JOUR d'un domaine : nb de nuisibles en retard / faits aujourd'hui,
  // sur ses routines quotidiennes + activités-temps.
  ({int spiders, int scorpions, int done}) _todayStatus(String domainId) {
    var spiders = 0, scorpions = 0, done = 0;
    for (final a in logic.state.activeActivities) {
      if (a.domainId != domainId) continue;
      final tokens =
          a.isHabit ? logic.routineWeekTokens(a.id) : logic.activityTimeTokens(a.id);
      if (tokens.isEmpty) continue;
      final t = tokens.last.type; // aujourd'hui = dernier
      if (t == 'spider') {
        if (a.isHabit) {
          spiders++; // routine en retard = 🕷️
        } else {
          scorpions++; // activité-temps en retard = 🦂
        }
      } else if (t == 'flame' || t == 'leaf') {
        done++;
      }
    }
    return (spiders: spiders, scorpions: scorpions, done: done);
  }

  @override
  Widget build(BuildContext context) {
    final domains = logic.state.activeDomains;
    return Column(
      children: [
        const SizedBox(height: 12),
        Expanded(
          child: domains.isEmpty
              ? const Center(
                  child: Text('Aucun domaine actif.',
                      style: TextStyle(color: Colors.white38)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                  itemCount: domains.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _domainTile(domains[i]),
                ),
        ),
      ],
    );
  }

  Widget _domainTile(Domain d) {
    final color = domainColor(d.id, logic.state.activeDomains) ?? const Color(0xFF4FA3FF);
    final st = _todayStatus(d.id);
    return Material(
      color: color.withOpacity(.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // Sheet natif : le jardin/château s'ouvre en bottom sheet (glisser pour
        // fermer ; la flèche retour de la fiche ferme aussi).
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => FractionallySizedBox(
            heightFactor: 0.95,
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              child: _DomainGameplay(
                  logic: logic,
                  sync: widget.sync,
                  domain: d,
                  color: color,
                  onOpenActivity: widget.onOpenActivity),
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(.45)),
          ),
          child: Row(children: [
            // Tour du domaine + son état (barre de vie agrégée) à la place du point.
            () {
              final life = _domainLife(d.id);
              return SizedBox(
                width: 30,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset('assets/icons/turret.svg',
                        width: 26,
                        height: 26,
                        colorFilter: ColorFilter.mode(
                            life <= 0 ? _kEnemy : color, BlendMode.srcIn)),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: Container(
                        width: 26,
                        height: 4,
                        color: _lifeColor(life).withOpacity(.2),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: life.clamp(0.0, 1.0),
                          child: Container(color: _lifeColor(life)),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }(),
            const SizedBox(width: 14),
            Expanded(
              child: Text(d.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
            ),
            if (st.spiders > 0) ...[
              const Text('🕷️', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 3),
              Text('${st.spiders}',
                  style: const TextStyle(
                      color: Color(0xFFE5604D),
                      fontWeight: FontWeight.w900,
                      fontSize: 15)),
              const SizedBox(width: 10),
            ],
            if (st.scorpions > 0) ...[
              const Text('🦂', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 3),
              Text('${st.scorpions}',
                  style: const TextStyle(
                      color: Color(0xFFE5604D),
                      fontWeight: FontWeight.w900,
                      fontSize: 15)),
              const SizedBox(width: 10),
            ],
            if (st.done > 0) ...[
              const Text('🔥', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 3),
              Text('${st.done}',
                  style: TextStyle(
                      color: color.withOpacity(.9),
                      fontWeight: FontWeight.w900,
                      fontSize: 15)),
            ],
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: color.withOpacity(.6)),
          ]),
        ),
      ),
    );
  }
}

// ── Gameplay d'un domaine, MOBILE-natif, coupé en 2 : JARDIN (les 7 jours, tokens
//    + tours) ↔ CHÂTEAU (les toiles/feuilles accumulées). Bouton fléché pour passer.
typedef _Item = ({
  String id,
  String name,
  String kind, // 'spider' (routine) | 'scorpion' (temps)
  String icon, // asset SVG de la tour (turret / DCA hebdo-mensuelle)
  List<({String type, int hp})> tokens,
  int charger,
  ({int webs, int leaves}) fill,
  int active,
});

class _DomainGameplay extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final Domain domain;
  final Color color;
  final void Function(String activityId)? onOpenActivity;
  const _DomainGameplay(
      {required this.logic,
      required this.sync,
      required this.domain,
      required this.color,
      this.onOpenActivity});
  @override
  State<_DomainGameplay> createState() => _DomainGameplayState();
}

class _DomainGameplayState extends State<_DomainGameplay>
    with SingleTickerProviderStateMixin {
  AppLogic get logic => widget.logic;
  bool _chateau = false; // false = jardin, true = intérieur château
  int _tab = 0; // 0 = Routines/Activités · 1 = Actions (projets/tâches)

  // ── « Faire feu » : la tour se transforme en canon et attaque le nuisible du
  //    jour (dernière colonne). Décrément persistant (💥 si l'araignée meurt). ──
  late final AnimationController _fireCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..addListener(() => setState(() {}));
  String? _firingId; // ligne en cours de tir (canon affiché)
  String? _explodingId; // ligne en explosion (💥) pendant 2 s
  Timer? _explosionTimer;
  String? _targetId; // ligne VISÉE (viseur) → cible de « Faire feu »
  // Onglet ACTIONS : action VISÉE (viseur) + action en cours de tir (missile).
  String? _actionTargetId;
  String? _firingActionId;
  // Mode de tir par ligne (case « petit » en bout de ligne) :
  //   'timer'  → minuteur · 'chrono' → chrono libre · 'check' → marque faite (+1).
  // Le mode 'check' n'est proposé que pour les routines (spider).
  final Map<String, String> _fireMode = {};
  // MODE MINUTEUR (étape A) : « Faire feu » ne quitte plus le domaine ; le viseur
  // devient un décompte ⏱, et à zéro la tourelle fait feu. Un seul minuteur à la fois
  // (une session active). Persisté → survit à la réouverture.
  final Map<String, DateTime> _minuteurEnd = {}; // itemId → fin du décompte
  // (étape B) tirs intermédiaires déjà joués (1 / palier de 5 min) pour les
  // activités-temps : toutes les 5 min, un tir anime la baisse de PV du scorpion.
  final Map<String, int> _minuteurShots = {};
  Timer? _minuteurTicker;
  String get _minuteurPrefKey => 'combat_minuteur_${widget.domain.id}';
  // (étape C) RATTRAPAGE des complétions faites HORS-APP : à l'ouverture, l'écart
  // entre le PV du jour vu au dernier passage et le PV actuel = des flammes à tirer.
  // La queue décharge ces flammes une à une (cinématique → le PV affiché rattrape) ;
  // si trop de flammes, un seul tir agrège. Pendant l'animation, le PV affiché de
  // l'araignée du jour = PV réel + flammes restantes.
  final Map<String, int> _catchupFlames = {}; // itemId → flammes de rattrapage
  final Map<String, int> _lastSeenHp = {}; // itemId → PV du jour vu au dernier passage
  bool _catchupRunning = false;
  String get _lastSeenPrefKey => 'combat_lastseen_${widget.domain.id}';

  // Clé de persistance du viseur, propre à ce domaine.
  String get _targetPrefKey => 'combat_target_${widget.domain.id}';
  // Clé de persistance des modes de tir (minuteur/chrono/coche) par routine.
  String get _modePrefKey => 'combat_firemode_${widget.domain.id}';

  @override
  void initState() {
    super.initState();
    // Viseur par défaut sur la 1ʳᵉ routine (1ʳᵉ ligne), puis restaure le dernier
    // viseur déplacé s'il a été persisté pour ce domaine.
    final items = _items();
    if (items.isNotEmpty) _targetId = items.first.id;
    _loadTarget();
    _loadModes();
    // Charge les minuteurs persistés PUIS adopte une éventuelle session d'activité
    // déjà ouverte (lancée depuis le web) comme un minuteur en cours.
    _loadMinuteurs().then((_) {
      if (mounted) _adoptOpenSessions();
    });
    // Rattrapage des complétions faites hors-app (queue de cinématiques).
    _loadLastSeen();
  }

  // Restaure les modes de tir persistés (par routine) pour ce domaine.
  Future<void> _loadModes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_modePrefKey);
    if (raw == null || !mounted) return;
    try {
      final m = (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
      setState(() => _fireMode.addAll(m));
    } catch (_) {}
  }

  Future<void> _saveModes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modePrefKey, jsonEncode(_fireMode));
  }

  // ── MODE MINUTEUR (étape A) ───────────────────────────────────────────────
  Future<void> _loadMinuteurs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_minuteurPrefKey);
    if (raw == null || !mounted) return;
    try {
      (jsonDecode(raw) as Map).forEach((k, v) {
        final end = DateTime.tryParse('$v');
        if (end != null) _minuteurEnd['$k'] = end;
      });
      if (_minuteurEnd.isNotEmpty) {
        setState(() {});
        _ensureMinuteurTicker();
      }
    } catch (_) {}
  }

  Future<void> _saveMinuteurs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _minuteurPrefKey,
        jsonEncode(
            _minuteurEnd.map((k, v) => MapEntry(k, v.toIso8601String()))));
  }

  void _ensureMinuteurTicker() {
    if (_minuteurTicker != null || _minuteurEnd.isEmpty) return;
    _minuteurTicker =
        Timer.periodic(const Duration(seconds: 1), (_) => _tickMinuteurs());
  }

  void _tickMinuteurs() {
    if (!mounted) return;
    if (_minuteurEnd.isEmpty) {
      _minuteurTicker?.cancel();
      _minuteurTicker = null;
      return;
    }
    if (_firingId == null) {
      final now = DateTime.now();
      // 1) Décompte à zéro → tir FINAL (valide la routine / ferme la session).
      String? readyId;
      for (final e in _minuteurEnd.entries) {
        if (!now.isBefore(e.value)) {
          readyId = e.key;
          break;
        }
      }
      if (readyId != null) {
        _Item? it;
        for (final x in _items()) {
          if (x.id == readyId) {
            it = x;
            break;
          }
        }
        if (it != null) {
          _minuteurFire(it);
        } else {
          _minuteurEnd.remove(readyId);
          _minuteurShots.remove(readyId);
          _saveMinuteurs();
        }
      } else {
        // 2) (étape B) Activité-temps en cours : un tir intermédiaire par palier de
        //    5 min de temps loggué → anime la baisse de PV du scorpion.
        _maybeIntermediateShot(now);
      }
    }
    setState(() {}); // rafraîchit l'affichage du décompte
  }

  // Joue UN tir intermédiaire si un nouveau palier de 5 min a été franchi sur une
  // activité-temps dont le minuteur tourne (le PV réel baisse déjà via le temps loggué).
  void _maybeIntermediateShot(DateTime now) {
    for (final id in _minuteurEnd.keys) {
      _Item? it;
      for (final x in _items()) {
        if (x.id == id) {
          it = x;
          break;
        }
      }
      if (it == null || it.kind != 'scorpion') continue; // tirs périodiques = temps
      Session? sess;
      for (final s in logic.state.sessions) {
        if (s.endAt == null && s.activityId == it.id) {
          sess = s;
          break;
        }
      }
      if (sess == null) continue;
      final paliers = now.difference(sess.startAt).inMinutes ~/ 5;
      final shot = _minuteurShots[id] ?? 0;
      if (paliers > shot) {
        _minuteurShots[id] = shot + 1; // un seul palier par tick
        _playFireCine(id, () {
          logic.onChange(); // le token PV se recalcule depuis le temps loggué
          if (mounted) setState(() {});
        });
        return;
      }
    }
  }

  // COHÉRENCE WEB/MOBILE : adopte une session d'activité-temps déjà OUVERTE (ex.
  // lancée depuis le web → partagée via Firestore) comme un minuteur en cours, sans
  // rejouer les tirs des paliers déjà franchis.
  void _adoptOpenSessions() {
    final dom = widget.domain.id;
    for (final s in logic.state.sessions) {
      if (s.endAt != null) continue;
      Activity? a;
      for (final x in logic.state.activeActivities) {
        if (x.id == s.activityId && x.domainId == dom && !x.isHabit) {
          a = x;
          break;
        }
      }
      if (a == null || _minuteurEnd.containsKey(a.id)) continue;
      // Durée : timerMin défini, sinon estimation (jamais de dialog au chargement).
      final mins = (a.timerMin != null && a.timerMin! > 0)
          ? a.timerMin!
          : logic.challengeDurationFor(a);
      _minuteurEnd[a.id] =
          s.startAt.add(Duration(minutes: mins < 1 ? 1 : mins));
      _minuteurShots[a.id] = DateTime.now().difference(s.startAt).inMinutes ~/ 5;
    }
    if (_minuteurEnd.isNotEmpty && mounted) {
      setState(() {});
      _ensureMinuteurTicker();
    }
  }

  // Activité-temps cible d'un item : elle-même (scorpion) ou l'activité liée (routine).
  String? _activityIdFor(_Item it) {
    if (it.kind == 'scorpion') return it.id;
    for (final a in logic.state.activities) {
      if (a.id == it.id) {
        final linked = (a.linkedActivityId ?? '').trim();
        return linked.isEmpty ? null : linked;
      }
    }
    return null;
  }

  // Lance le décompte d'une ligne (mode minuteur) : démarre la session et arme le
  // ticker. Le tir viendra à zéro (cf. _minuteurFire). UN seul minuteur à la fois.
  Future<void> _startMinuteur(_Item it) async {
    final actId = _activityIdFor(it);
    if (actId == null) {
      logic.incHabit(it.id, 1, logic.routineCatchUpDay(it.id)); // rattrape la plus vieille araignée
      logic.onChange();
      if (mounted) setState(() {});
      return;
    }
    // Durée = celle DÉFINIE sur la routine/activité (timerMin) ; sinon on la demande.
    Activity? self;
    for (final a in logic.state.activities) {
      if (a.id == it.id) {
        self = a;
        break;
      }
    }
    int? mins =
        (self?.timerMin != null && self!.timerMin! > 0) ? self.timerMin : null;
    mins ??= await _askDuration(it.name);
    if (mins == null || mins < 1 || !mounted) return; // annulé
    final d = mins;
    logic.start(actId); // ferme toute session ouverte + en démarre une (temps loggé)
    setState(() {
      _minuteurEnd
        ..clear()
        ..[it.id] = DateTime.now().add(Duration(minutes: d));
      _minuteurShots
        ..clear()
        ..[it.id] = 0;
    });
    _saveMinuteurs();
    _ensureMinuteurTicker();
  }

  // Demande une durée (min) quand la routine/activité n'en définit pas (timerMin vide).
  Future<int?> _askDuration(String name) async {
    final ctrl = TextEditingController();
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) {
        Widget quick(int m) => OutlinedButton(
            onPressed: () => Navigator.pop(ctx, m), child: Text('$m min'));
        return AlertDialog(
          backgroundColor: const Color(0xFF14130F),
          title: const Text('Durée du minuteur',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('« $name » n\'a pas de durée définie. Combien de minutes ?',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 14),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [for (final m in [15, 25, 45, 60]) quick(m)]),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  hintText: 'Autre (minutes)…',
                  hintStyle: TextStyle(color: Colors.white38)),
              onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)),
                child: const Text('Lancer')),
          ],
        );
      },
    );
    ctrl.dispose();
    return (res != null && res > 0) ? res : null;
  }

  // Décompte fini → cinématique de tir, puis validation + fermeture de la session.
  void _minuteurFire(_Item it) {
    _playFireCine(it.id, () {
      if (it.kind == 'spider') {
        logic.incHabit(it.id, 1, logic.routineCatchUpDay(it.id)); // routine validée (plus vieille araignée)
      }
      logic.stopActive(); // ferme la session (temps loggé → PV du scorpion)
      logic.onChange();
      if (mounted) {
        setState(() {
          _minuteurEnd.remove(it.id);
          _minuteurShots.remove(it.id);
        });
      }
      _saveMinuteurs();
    });
  }

  // Tap sur le décompte = annuler le minuteur (sans valider).
  void _cancelMinuteur(_Item it) {
    logic.stopActive();
    logic.onChange();
    setState(() {
      _minuteurEnd.remove(it.id);
      _minuteurShots.remove(it.id);
    });
    _saveMinuteurs();
  }

  // Joue la cinématique de tir d'une ligne (tour → canon → boulet → 💥) puis `onDone`.
  Future<void> _playFireCine(String id, void Function() onDone) async {
    if (_firingId != null) return;
    _fireCtrl.reset();
    setState(() => _firingId = id);
    await Future.delayed(const Duration(milliseconds: 280));
    if (!mounted || _firingId != id) return;
    await _fireCtrl.forward(from: 0);
    if (!mounted) return;
    setState(() => _explodingId = id);
    _explosionTimer?.cancel();
    _explosionTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _explodingId = null;
        _firingId = null;
      });
      onDone();
    });
  }

  // Version "attendue" de la cinématique (pour enchaîner la queue de rattrapage).
  Future<void> _playFireCineAwait(String id) async {
    final c = Completer<void>();
    await _playFireCine(id, () {
      if (!c.isCompleted) c.complete();
    });
    if (_firingId == null && !c.isCompleted) return; // cine annulée → on n'attend pas
    await c.future;
  }

  // ── ÉTAPE C — RATTRAPAGE des complétions hors-app ─────────────────────────
  int _todayHpOf(_Item it) {
    if (it.tokens.isEmpty) return 0;
    final t = it.tokens.last;
    return t.type == 'spider' ? t.hp : 0;
  }

  Future<void> _loadLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSeenPrefKey);
    if (raw != null) {
      try {
        (jsonDecode(raw) as Map).forEach((k, v) {
          final n = int.tryParse('$v');
          if (n != null) _lastSeenHp['$k'] = n;
        });
      } catch (_) {}
    }
    if (mounted) _computeCatchup();
  }

  Future<void> _saveLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSeenPrefKey, jsonEncode(_lastSeenHp));
  }

  // Snapshot de l'état VU (PV du jour) — appelé après le rattrapage et à la fermeture.
  void _snapshotLastSeen() {
    for (final it in _items()) {
      _lastSeenHp[it.id] = _todayHpOf(it);
    }
    _saveLastSeen();
  }

  // À l'ouverture : écart PV vu → PV actuel = flammes à rattraper (validations hors-app).
  void _computeCatchup() {
    var any = false;
    for (final it in _items()) {
      final cur = _todayHpOf(it);
      final seen = _lastSeenHp[it.id];
      if (seen != null && seen > cur) {
        _catchupFlames[it.id] = seen - cur; // baisse de PV non encore animée
        any = true;
      }
    }
    if (any) {
      setState(() {});
      _runCatchupQueue();
    } else {
      _snapshotLastSeen(); // rien à rattraper → on aligne le snapshot
    }
  }

  // Décharge la queue : pour chaque routine en retard, le canon tire une à une les
  // flammes (PV affiché rattrape). Trop de flammes (>3) → UN seul tir agrège tout.
  Future<void> _runCatchupQueue() async {
    if (_catchupRunning) return;
    _catchupRunning = true;
    try {
      for (final it in _items()) {
        var pend = _catchupFlames[it.id] ?? 0;
        if (pend <= 0) continue;
        while (pend > 0 && mounted) {
          final per = pend > 3 ? pend : 1; // agrégation si trop de flammes
          await _playFireCineAwait(it.id);
          if (!mounted) break;
          pend -= per;
          setState(() => _catchupFlames[it.id] = pend < 0 ? 0 : pend);
          await Future.delayed(const Duration(milliseconds: 150));
        }
        _catchupFlames.remove(it.id);
      }
    } finally {
      _catchupRunning = false;
      if (mounted) _snapshotLastSeen();
    }
  }

  // Restaure le dernier viseur déplacé (s'il pointe encore sur un item existant).
  Future<void> _loadTarget() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_targetPrefKey);
    if (saved == null) return;
    if (_items().any((it) => it.id == saved) && mounted) {
      setState(() => _targetId = saved);
    }
  }

  // Persiste le viseur courant (ou l'efface si aucune cible).
  Future<void> _saveTarget() async {
    final prefs = await SharedPreferences.getInstance();
    final id = _targetId;
    if (id == null) {
      await prefs.remove(_targetPrefKey);
    } else {
      await prefs.setString(_targetPrefKey, id);
    }
  }

  // Tape le viseur d'une ligne : (dé)cible + persiste.
  void _toggleTarget(_Item it) {
    setState(() => _targetId = _targetId == it.id ? null : it.id);
    _saveTarget();
  }

  // Mode suivant du sélecteur : routines = 3 états, activités-temps = 2 états.
  String _nextMode(_Item it, String cur) {
    if (it.kind == 'spider') {
      return cur == 'timer'
          ? 'chrono'
          : (cur == 'chrono' ? 'check' : 'timer');
    }
    return cur == 'timer' ? 'chrono' : 'timer';
  }

  // « Faire feu » (onglet Actions) : missile sur l'action VISÉE (sinon la 1ʳᵉ non
  // faite) → cinématique courte, puis l'action est VALIDÉE (coche verte, persistée).
  Future<void> _fireAction() async {
    if (_firingActionId != null) return;
    Project? proj;
    TaskAction? act;
    Activity? ownOwner; // activité propriétaire si l'action est PROPRE
    // 1) Action visée en priorité (projet OU action propre).
    if (_actionTargetId != null) {
      for (final p in _actionProjects()) {
        for (final t in p.tasks) {
          for (final a in t.actions) {
            if (a.id == _actionTargetId && !a.done) {
              proj = p;
              act = a;
            }
          }
        }
      }
      if (act == null) {
        for (final e in _domainOwnActions()) {
          if (e.action.id == _actionTargetId && !e.action.done) {
            ownOwner = e.activity;
            act = e.action;
          }
        }
      }
    }
    // 2) Sinon la 1ʳᵉ action non faite (projets puis actions propres).
    if (act == null) {
      for (final p in _actionProjects()) {
        for (final t in p.tasks) {
          if (t.status == 'done' || t.status == 'skipped') continue;
          for (final a in t.actions) {
            if (!a.done) {
              proj = p;
              act = a;
              break;
            }
          }
          if (act != null) break;
        }
        if (act != null) break;
      }
    }
    if (act == null) {
      for (final e in _domainOwnActions()) {
        if (!e.action.done) {
          ownOwner = e.activity;
          act = e.action;
          break;
        }
      }
    }
    if (act == null || (proj == null && ownOwner == null)) return;
    final id = act.id;
    _fireCtrl.reset();
    setState(() => _firingActionId = id);
    await _fireCtrl.forward(from: 0);
    if (!mounted) {
      _firingActionId = null;
      return;
    }
    if (ownOwner != null) {
      logic.toggleOwnAction(ownOwner.id, id, true); // persiste via onChange→pushDeltas
    } else {
      act.done = true;
      act.doneAt = DateTime.now();
      await widget.sync.saveProjectTasks(proj!.id, proj.tasks);
      logic.onChange();
    }
    if (mounted) {
      setState(() {
        _firingActionId = null;
        if (_actionTargetId == id) _actionTargetId = null;
      });
    }
  }

  @override
  void dispose() {
    // Snapshot de l'état VU avant de quitter → la prochaine ouverture ne ré-anime que
    // les complétions faites HORS de l'app entre-temps.
    _snapshotLastSeen();
    _explosionTimer?.cancel();
    _minuteurTicker?.cancel();
    _fireCtrl.dispose();
    super.dispose();
  }

  String _modeOf(String id) => _fireMode[id] ?? 'timer';

  // Lance le minuteur (mode 'timer') ou le chrono libre (mode 'chrono') de la
  // cible, après la cinématique. Routine → activité liée (routineId = la routine) ;
  // activité-temps → elle-même. Routine sans activité liée → simple +1.
  void _launchForTarget(_Item it) {
    final mode = _modeOf(it.id);
    // Mode « coche » : marque la routine faite du jour (+1), sans minuteur ni
    // chrono. Réservé aux routines (le sélecteur ne propose pas 'check' ailleurs).
    if (mode == 'check' && it.kind == 'spider') {
      logic.incHabit(it.id, 1, logic.routineCatchUpDay(it.id)); // plus vieille araignée
      logic.onChange();
      if (mounted) setState(() {});
      return;
    }
    final timer = mode == 'timer';
    String? actId;
    String? routineId;
    Activity? act;
    if (it.kind == 'scorpion') {
      actId = it.id;
    } else {
      for (final a in logic.state.activities) {
        if (a.id == it.id) {
          final linked = (a.linkedActivityId ?? '').trim();
          if (linked.isNotEmpty) {
            actId = linked;
            routineId = it.id;
          }
          break;
        }
      }
    }
    if (actId == null) {
      // Routine sans activité liée : pas de minuteur possible → +1 sur place.
      logic.incHabit(it.id, 1, logic.routineCatchUpDay(it.id)); // plus vieille araignée
      logic.onChange();
      setState(() {});
      return;
    }
    for (final a in logic.state.activities) {
      if (a.id == actId) {
        act = a;
        break;
      }
    }
    logic.start(actId);
    if (timer && logic.launchTimerHook != null && act != null) {
      logic.launchTimerHook!(logic.challengeDurationFor(act), it.name,
          routineId: routineId);
    } else {
      logic.onChange();
    }
    // Ferme la fiche du domaine pour voir le minuteur/chrono qui tourne.
    if (mounted) Navigator.of(context).maybePop();
  }

  // Lance le tir sur la PREMIÈRE araignée (jour manqué le plus ancien) de la 1ʳᵉ
  // ligne qui en a une (sinon la 1ʳᵉ ligne). La tour se transforme (DCA) le temps du tir.
  Future<void> _fire() async {
    if (_firingId != null) return;
    final items = _items();
    _Item? target;
    // Cible VISÉE (viseur) en priorité.
    if (_targetId != null) {
      for (final it in items) {
        if (it.id == _targetId) {
          target = it;
          break;
        }
      }
    }
    // Sinon : 1ʳᵉ ligne avec une araignée (peu importe le jour — on rattrape la
    // plus ancienne), sinon la 1ʳᵉ ligne.
    if (target == null) {
      for (final it in items) {
        if (it.tokens.any((t) => t.type == 'spider')) {
          target = it;
          break;
        }
      }
      target ??= items.isNotEmpty ? items.first : null;
    }
    if (target == null) return;
    final it = target;
    // MODE MINUTEUR (avec activité) : on ne tire PAS de suite ni ne quitte le
    // domaine — on lance le DÉCOMPTE ; le tir viendra à zéro (cf. _minuteurFire).
    if (_modeOf(it.id) == 'timer' && _activityIdFor(it) != null) {
      await _startMinuteur(it);
      return;
    }
    // Chrono / coche : cinématique immédiate puis lancement (comportement existant).
    _playFireCine(it.id, () => _launchForTarget(it));
  }

  List<_Item> _items() {
    final dom = widget.domain.id;
    final routines = <_Item>[];
    final times = <_Item>[];
    for (final a in logic.state.activeActivities) {
      if (a.domainId != dom) continue;
      if (a.isHabit) {
        final tok = logic.routineWaveTokens(a.id); // post-pardon de série
        if (tok.isEmpty) continue;
        routines.add((
          id: a.id,
          name: a.name,
          kind: 'spider',
          // Hebdo/mensuelle → canon DCA ; quotidienne → turret.
          icon: logic.effectiveHabitFreq(a).name != 'daily'
              ? 'assets/icons/anti-aircraft-gun.svg'
              : 'assets/icons/turret.svg',
          tokens: tok,
          charger: logic.routineDefenseCharger(a.id),
          fill: logic.routineChateauFill(a.id),
          active: logic.routine30dActive(a.id),
        ));
      } else {
        final tok = logic.activityTimeTokens(a.id);
        if (tok.isEmpty) continue;
        times.add((
          id: a.id,
          name: a.name,
          kind: 'scorpion',
          icon: 'assets/icons/turret.svg',
          // Chargeur = jours où l'objectif-temps a été atteint sur les 7 glissants.
          tokens: tok,
          charger:
              tok.where((t) => t.type == 'leaf' || t.type == 'flame').length,
          fill: logic.activityTimeChateauFill(a.id),
          active: logic.activityTime30dMin(a.id),
        ));
      }
    }
    routines.sort((a, b) => b.active.compareTo(a.active));
    times.sort((a, b) => b.active.compareTo(a.active));
    // Cap retiré : toutes les routines/activités (le jardin défile en ListView).
    return [...routines, ...times];
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final items = _items();
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            // En-tête.
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Text('🏴 ${widget.domain.name}',
                    style: TextStyle(
                        color: c, fontSize: 18, fontWeight: FontWeight.w900)),
                const Spacer(),
                Text(_chateau ? '🏰 Château' : '🌿 Jardin',
                    style: TextStyle(
                        color: Colors.white.withOpacity(.5), fontSize: 12)),
                const SizedBox(width: 12),
              ]),
            ),
            // Sous‑onglets : Routines/Activités · Actions (projets/tâches).
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
              child: Row(children: [
                _subTabBtn('Routines/Activités', 0, c),
                const SizedBox(width: 6),
                _subTabBtn('Actions', 1, c),
              ]),
            ),
            Expanded(
              child: _tab == 1
                  ? _actionsView()
                  : (items.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                                'Aucune routine quotidienne ni activité-temps dans ce domaine.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white38)),
                          ),
                        )
                      : (_chateau ? _chateauView(items) : _gardenView(items))),
            ),
            // FAIRE FEU : la tour se transforme en canon et attaque le nuisible
            // du jour (onglet Routines/Activités · vue jardin uniquement).
            if (_tab == 0 && !_chateau && items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8A3D).withOpacity(.22),
                        foregroundColor: const Color(0xFFFF8A3D),
                        minimumSize: const Size.fromHeight(46)),
                    onPressed: _firingId == null ? _fire : null,
                    icon: const Icon(Icons.gps_fixed),
                    label: Text(_firingId == null ? 'Faire feu 🔥' : 'Tir en cours…'),
                  ),
                ),
              ),
            // FAIRE FEU (onglet Actions) : le missile valide l'action visée.
            if (_tab == 1 && _actionProjects().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8A3D).withOpacity(.22),
                        foregroundColor: const Color(0xFFFF8A3D),
                        minimumSize: const Size.fromHeight(46)),
                    onPressed: _firingActionId == null ? _fireAction : null,
                    icon: const Icon(Icons.gps_fixed),
                    label: Text(
                        _firingActionId == null ? 'Faire feu 🚀' : 'Tir en cours…'),
                  ),
                ),
              ),
            // CTA de navigation jardin ↔ château (onglet Routines/Activités).
            if (_tab == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: c.withOpacity(.18),
                        foregroundColor: c,
                        minimumSize: const Size.fromHeight(46)),
                    onPressed: () => setState(() => _chateau = !_chateau),
                    icon:
                        Icon(_chateau ? Icons.arrow_forward : Icons.arrow_back),
                    label: Text(_chateau
                        ? 'Retour au jardin 🌿'
                        : 'Entrer dans le château 🏰'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Ouvre le sheet de l'objet derrière la tour : routine (habit) ou activité-temps.
  Future<void> _openItemSheet(_Item it) async {
    if (it.kind == 'spider') {
      await showRoutineSheet(context,
          logic: logic, habitId: it.id, day: DateTime.now());
    } else if (widget.onOpenActivity != null) {
      // Vrai sheet FAB (lanceur) fourni par l'app mobile.
      widget.onOpenActivity!(it.id);
    } else {
      await showActivitySheet(context, logic, it.id);
    }
    if (mounted) setState(() {});
  }

  // ── JARDIN : en-tête des jours + une ligne par routine/activité ─────────────
  Widget _gardenView(List<_Item> items) {
    const cell = 34.0;
    final routines = items.where((i) => i.kind == 'spider').toList();
    final times = items.where((i) => i.kind == 'scorpion').toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      children: [
        if (routines.isNotEmpty) ...[
          _sectionHeader('🕷️ Routines', routines.length),
          for (final it in routines) _gardenRow(it, cell),
        ],
        if (times.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionHeader('🦂 Activités-temps', times.length),
          for (final it in times) _gardenRow(it, cell),
        ],
      ],
    );
  }

  Widget _sectionHeader(String label, int count) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Row(children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(.85),
                  fontWeight: FontWeight.w900,
                  fontSize: 14)),
          const SizedBox(width: 6),
          Text('$count',
              style: TextStyle(
                  color: Colors.white.withOpacity(.35),
                  fontWeight: FontWeight.w700,
                  fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
                height: 1, color: Colors.white.withOpacity(.08)),
          ),
        ]),
      );

  // ── Sous‑onglet ACTIONS : projets/tâches du domaine, même structure ──────────
  Widget _subTabBtn(String label, int idx, Color c) {
    final on = _tab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = idx),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: on ? c.withOpacity(.22) : Colors.white.withOpacity(.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? c.withOpacity(.7) : Colors.white12),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  color: on ? c : Colors.white54,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
        ),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Project> _actionProjects() {
    final dom = widget.domain.id;
    return logic.currentProjects
        .where((p) =>
            p.domainId == dom && p.status != 'archived' && p.status != 'done')
        .toList();
  }

  // Actions PROPRES (Activity.ownActions) des activités-temps de ce domaine.
  List<({Activity activity, TaskAction action})> _domainOwnActions() {
    final dom = widget.domain.id;
    final out = <({Activity activity, TaskAction action})>[];
    for (final a in logic.state.activeActivities) {
      if (a.domainId != dom || a.deleted || a.isHabit) continue;
      for (final act in a.ownActions) {
        out.add((activity: a, action: act));
      }
    }
    return out;
  }

  Widget _actionsView() {
    final projects = _actionProjects();
    final own = _domainOwnActions();
    if (projects.isEmpty && own.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucune action dans ce domaine.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38)),
        ),
      );
    }
    // Regroupe les actions propres par activité propriétaire.
    final ownByActivity = <Activity, List<TaskAction>>{};
    for (final e in own) {
      ownByActivity.putIfAbsent(e.activity, () => []).add(e.action);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      children: [
        for (final p in projects) ...[
          _sectionHeader(
              '📋 ${p.title}',
              p.tasks
                  .where((t) => t.status != 'done' && t.status != 'skipped')
                  .length),
          for (final t in p.tasks
              .where((t) => t.status != 'done' && t.status != 'skipped'))
            _actionTaskRow(p, t),
        ],
        // Actions propres aux activités du domaine (sans tâche).
        for (final entry in ownByActivity.entries) ...[
          _sectionHeader('⏱️ ${entry.key.name}', entry.value.length),
          for (final a in entry.value)
            _ownActionLine(entry.key, a, widget.color),
        ],
      ],
    );
  }

  // Ligne d'une action PROPRE dans l'onglet Actions du combat : viseur 🎯 pour
  // cibler, « Faire feu » la valide (comme une action de projet).
  Widget _ownActionLine(Activity owner, TaskAction a, Color c) {
    final aimed = _actionTargetId == a.id;
    final firing = _firingActionId == a.id;
    return InkWell(
      onTap: a.done ? null : () => _aimAction(a.id),
      child: Container(
        decoration: BoxDecoration(
          color: aimed ? c.withOpacity(.12) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          a.done
              ? const Icon(Icons.check_circle,
                  size: 16, color: Color(0xFF4CD787))
              : SvgPicture.asset('assets/icons/rifle.svg',
                  width: 15,
                  height: 15,
                  colorFilter:
                      const ColorFilter.mode(Colors.white60, BlendMode.srcIn)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(a.title,
                style: TextStyle(
                    color: a.done ? Colors.white38 : Colors.white70,
                    decoration: a.done ? TextDecoration.lineThrough : null,
                    fontSize: 12,
                    height: 1.3)),
          ),
          if (firing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SvgPicture.asset('assets/icons/missile-launcher.svg',
                  width: 14,
                  height: 14,
                  colorFilter:
                      const ColorFilter.mode(Color(0xFFFF8A3D), BlendMode.srcIn)),
            )
          else if (!a.done)
            GestureDetector(
              onTap: () => _aimAction(a.id),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.gps_fixed,
                    size: 16,
                    color:
                        aimed ? const Color(0xFFFF8A3D) : Colors.white24),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _actionTaskRow(Project p, ProjectTask t) {
    const cell = 34.0;
    final c = widget.color;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    bool validatedOn(DateTime d) => t.actions
        .any((a) => a.done && a.doneAt != null && _sameDay(a.doneAt!, d));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.withOpacity(.95),
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          const SizedBox(height: 3),
          // Libellés de jours retirés.
          // Lance‑missiles à GAUCHE + cases‑jours (validations).
          Row(children: [
            SizedBox(
              width: 60,
              child: Center(
                child: SvgPicture.asset('assets/icons/missile-launcher.svg',
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(c, BlendMode.srcIn)),
              ),
            ),
            for (var d = 0; d < 7; d++)
              () {
                final done = validatedOn(today.subtract(Duration(days: 6 - d)));
                return SizedBox(
                  width: cell + 2,
                  height: cell,
                  child: Center(
                    child: done
                        ? const Text('🍃', style: TextStyle(fontSize: 16))
                        : Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(.12))),
                  ),
                );
              }(),
          ]),
          const SizedBox(height: 4),
          // Liste des ACTIONS — coche verte si faite, viseur 🎯 pour cibler (tap =
          // cible) ; « Faire feu » valide la cible. Descriptions sur plusieurs lignes.
          for (final a in t.actions) _actionLine(p, t, a, c),
        ],
      ),
    );
  }

  Widget _actionLine(Project p, ProjectTask t, TaskAction a, Color c) {
    final aimed = _actionTargetId == a.id;
    final firing = _firingActionId == a.id;
    return InkWell(
      onTap: a.done ? null : () => _aimAction(a.id),
      child: Container(
        decoration: BoxDecoration(
          color: aimed ? c.withOpacity(.12) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Coche VERTE si faite, sinon fusil.
          a.done
              ? const Icon(Icons.check_circle,
                  size: 16, color: Color(0xFF4CD787))
              : SvgPicture.asset('assets/icons/rifle.svg',
                  width: 15,
                  height: 15,
                  colorFilter:
                      const ColorFilter.mode(Colors.white60, BlendMode.srcIn)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(a.title,
                style: TextStyle(
                    color: a.done ? Colors.white38 : Colors.white70,
                    decoration: a.done ? TextDecoration.lineThrough : null,
                    fontSize: 12,
                    height: 1.3)),
          ),
          // Lien à une activité (chrono ciblé) — coloré si lié.
          if (!a.done)
            GestureDetector(
              onTap: () => _linkActionToActivity(p, a),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                    (a.linkedActivityId ?? '').isEmpty
                        ? Icons.add_link
                        : Icons.link,
                    size: 15,
                    color:
                        (a.linkedActivityId ?? '').isEmpty ? Colors.white24 : c),
              ),
            ),
          // Missile en vol (cinématique) sur la ligne ciblée.
          if (firing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SvgPicture.asset('assets/icons/missile-launcher.svg',
                  width: 14,
                  height: 14,
                  colorFilter:
                      const ColorFilter.mode(Color(0xFFFF8A3D), BlendMode.srcIn)),
            )
          else if (!a.done)
            // Viseur 🎯 : cible cette action pour « Faire feu ».
            GestureDetector(
              onTap: () => _aimAction(a.id),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.gps_fixed,
                    size: 16,
                    color: aimed
                        ? const Color(0xFFFF8A3D)
                        : Colors.white24),
              ),
            ),
        ]),
      ),
    );
  }

  void _aimAction(String id) {
    setState(() => _actionTargetId = _actionTargetId == id ? null : id);
  }

  // Lie/délie une action à une activité-temps (chrono ciblé). Lié → tap = délier.
  Future<void> _linkActionToActivity(Project p, TaskAction a) async {
    if ((a.linkedActivityId ?? '').isNotEmpty) {
      setState(() => a.linkedActivityId = null);
      await widget.sync.saveProjectTasks(p.id, p.tasks);
      logic.onChange();
      return;
    }
    await showActivityPicker(context, logic.state, (act) async {
      a.linkedActivityId = act.id;
      logic.onChange();
      await widget.sync.saveProjectTasks(p.id, p.tasks);
      if (mounted) setState(() {});
    }, domainId: widget.domain.id);
  }

  Widget _gardenRow(_Item it, double cell) {
    final c = widget.color;
    // Le NOM est rendu SOUS la tourelle (cf. fin du Column) : ainsi il est clairement
    // rattaché à SA grille et n'est plus confondu avec le titre de la routine suivante.
    // Gros espace EN HAUT (sépare de la routine précédente), petit en bas.
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // La grille (jours + colonnes de contrôle) défile horizontalement pour
          // ne pas déborder sur les petits écrans (2 cases de plus qu'avant).
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Libellés de jours retirés (on combat la vague d'araignées, pas un
                // jour précis) — on garde l'espace pour aligner le sélecteur de mode
                // au-dessus du viseur.
                Row(children: [
                  const SizedBox(width: 60),
                  SizedBox(width: it.tokens.length * (cell + 2)),
                  // Sélecteur de mode empilé AU-DESSUS du viseur (même colonne).
                  _modeCell(it, cell),
                ]),
          const SizedBox(height: 1),
          () {
            final firing = _firingId == it.id;
            // Boulet : de la tour (x≈30, y≈30) vers la PREMIÈRE araignée/scorpion
            // (jour manqué le plus ancien) ; sinon la case d'aujourd'hui. En COURBE.
            var tgtIdx = it.tokens.length - 1;
            for (var i = 0; i < it.tokens.length; i++) {
              if (it.tokens[i].type == 'spider') {
                tgtIdx = i;
                break;
              }
            }
            final targetX = 60.0 + tgtIdx * (cell + 2) + cell / 2;
            const fy0 = 30.0, fx0 = 30.0;
            const arc = 36.0; // hauteur du lobe (plus haut = trajectoire plus courbée)
            final u = _fireCtrl.value;
            final fx = fx0 + (targetX - fx0) * u;
            final fy = fy0 - arc * sin(pi * u);
            // Orientation : tangente RÉELLE de la parabole (continue) → la boule
            // reste tête en avant sur tout l'arc (montée ET descente), sans saut au
            // sommet. vx/vy = dérivées de fx/fy selon u ; +pi/2 = offset du sprite.
            final vx = targetX - fx0;
            final vy = -arc * pi * cos(pi * u);
            final fAngle = atan2(vy, vx) + pi / 2;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Row(children: [
                  // Tour (barres + icône) : tap → ouvre le sheet. Pendant le tir,
                  // l'icône se TRANSFORME en canon DCA (+ lueur orange).
                  GestureDetector(
                    onTap: () => _openItemSheet(it),
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 60,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _lifeBar(it.charger / 7),
                          const SizedBox(height: 2),
                          _segBar(7 - it.charger, _kCharge),
                          const SizedBox(height: 2),
                          Container(
                            decoration: firing
                                ? BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                          color: const Color(0xFFFF8A3D)
                                              .withOpacity(.7),
                                          blurRadius: 10,
                                          spreadRadius: 1)
                                    ])
                                : null,
                            child: SvgPicture.asset(
                                firing
                                    ? 'assets/icons/anti-aircraft-gun.svg'
                                    : it.icon,
                                width: 22,
                                height: 22,
                                colorFilter: ColorFilter.mode(
                                    firing
                                        ? const Color(0xFFFF8A3D)
                                        : (it.charger == 0 ? _kEnemy : c),
                                    BlendMode.srcIn)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (var d = 0; d < it.tokens.length; d++)
                    _tokenCell(it, d, cell),
                  // Case VISEUR, juste SOUS le sélecteur de mode (même colonne).
                  _viseurCell(it, cell),
                ]),
                // Boulet de feu en vol (tour → jour) en courbe, orienté.
                if (firing && _explodingId != it.id && u < 0.98)
                  Positioned(
                    left: fx - 8,
                    top: fy - 8,
                    child: Transform.rotate(
                      angle: fAngle,
                      child: SvgPicture.asset('assets/icons/fireball.svg',
                          width: 16,
                          height: 16,
                          colorFilter: const ColorFilter.mode(
                              Color(0xFFFF8A3D), BlendMode.srcIn)),
                    ),
                  ),
              ],
            );
          }(),
              ],
            ),
          ),
          const SizedBox(height: 5),
          // NOM de la routine/activité, SOUS sa tourelle (rattaché à SA grille).
          Row(children: [
            Container(
              width: 3,
              height: 14,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                  color: c.withOpacity(.9),
                  borderRadius: BorderRadius.circular(2)),
            ),
            Flexible(
              child: Text(it.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.withOpacity(.95),
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
          ]),
        ],
      ),
    );
  }

  // Barre de vie CONTINUE : remplissage `frac` (0..1), couleur = code santé.
  Widget _lifeBar(double frac) {
    final col = _lifeColor(frac);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Container(
        width: 40,
        height: 5,
        color: col.withOpacity(.18),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: frac.clamp(0.0, 1.0),
          child: Container(color: col),
        ),
      ),
    );
  }

  // Barre segmentée (7 cases) : les `filled` premières en `color`, le reste faible.
  Widget _segBar(int filled, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 7; i++)
            Container(
              width: 4.5,
              height: 4.5,
              margin: const EdgeInsets.only(right: 1.2),
              decoration: BoxDecoration(
                color: i < filled ? color : Colors.white.withOpacity(.12),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      );

  Widget _tokenCell(_Item it, int d, double cell) {
    final tok = it.tokens[d];
    // Le tir d'arrivée décrémente le nuisible du JOUR (dernière colonne).
    final isToday = d == it.tokens.length - 1;
    // (étape C) PV affiché gonflé des flammes encore à rattraper → la queue le fait
    // redescendre tir par tir jusqu'au PV réel.
    final pend = isToday ? (_catchupFlames[it.id] ?? 0) : 0;
    final shownHp = tok.type == 'spider' ? tok.hp + pend : 0;
    final killed = tok.type == 'spider' && shownHp <= 0;
    final impact = isToday && _explodingId == it.id;
    final spider = tok.type == 'spider' && !killed;
    final emoji = (killed || impact)
        ? '💥'
        : _tokenEmoji(tok.type, scorpion: it.kind == 'scorpion');
    return GestureDetector(
      onTap: spider
          ? () async {
              await showBacklogCombat(
                  context, logic, widget.sync, it.kind, it.id);
              if (mounted) setState(() {});
            }
          : null,
      child: Container(
        width: cell,
        height: cell,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.03),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withOpacity(.06)),
        ),
        child: emoji.isEmpty
            ? null
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 15)),
                      if (spider)
                        Text('$shownHp',
                            style: const TextStyle(
                                color: _kEnemy,
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                                height: 1)),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // Case VISEUR en bout de ligne : orange si cette ligne est visée, sinon grise.
  Widget _viseurCell(_Item it, double cell) {
    // Minuteur en cours sur cette ligne → le viseur devient un DÉCOMPTE (tap = annuler).
    final end = _minuteurEnd[it.id];
    if (end != null) {
      final rem = end.difference(DateTime.now());
      final s = rem.isNegative ? Duration.zero : rem;
      final mm = s.inMinutes.toString().padLeft(2, '0');
      final ss = (s.inSeconds % 60).toString().padLeft(2, '0');
      return GestureDetector(
        onTap: () => _cancelMinuteur(it),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: cell,
          height: cell,
          margin: const EdgeInsets.all(1),
          alignment: Alignment.center,
          child: Text('$mm:$ss',
              style: const TextStyle(
                  color: Color(0xFFFF8A3D),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900)),
        ),
      );
    }
    final on = _targetId == it.id;
    return GestureDetector(
      onTap: () => _toggleTarget(it),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: cell,
        height: cell,
        margin: const EdgeInsets.all(1),
        alignment: Alignment.center,
        child: Icon(Icons.gps_fixed,
            size: 18,
            color: on ? const Color(0xFFFF8A3D) : Colors.white24),
      ),
    );
  }

  // Case sélecteur de mode (« le petit ») : cycle minuteur → chrono → coche.
  // « Faire feu » applique le mode courant à la ligne visée.
  Widget _modeCell(_Item it, double cell) {
    final mode = _modeOf(it.id);
    final IconData icon = mode == 'chrono'
        ? Icons.play_circle_outline
        : (mode == 'check' ? Icons.check_box_outlined : Icons.timer_outlined);
    return GestureDetector(
      onTap: () {
        setState(() => _fireMode[it.id] = _nextMode(it, mode));
        _saveModes(); // le type de lancement choisi est mémorisé
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: cell,
        height: cell,
        margin: const EdgeInsets.all(1),
        alignment: Alignment.center,
        child: Icon(icon, size: 19, color: const Color(0xFFFF8A3D)),
      ),
    );
  }

  // ── CHÂTEAU : heatmap des 12 dernières semaines par ligne ───────────────────
  // Chaque case = 1 semaine écoulée (ancienne → récente) ; nb de flammes tenues,
  // ou 🕸️ toile si la semaine est perdue (0).
  Widget _chateauView(List<_Item> items) {
    final c = widget.color;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
              '🏰 Heatmap — 12 semaines · le nombre = jours tenus · 🕸️ = semaine perdue',
              style: TextStyle(
                  color: Colors.white.withOpacity(.4), fontSize: 11)),
        ),
        for (final it in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.withOpacity(.95),
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(height: 3),
                Row(children: [
                  for (final n in (it.kind == 'spider'
                      ? logic.routineWeeklyHeatmap(it.id)
                      : logic.activityTimeWeeklyHeatmap(it.id)))
                    _heatCell(n),
                ]),
              ],
            ),
          ),
      ],
    );
  }

  // Case de heatmap : 0 = 🕸️ toile, sinon le nb de flammes avec un vert d'autant
  // plus vif que la semaine a été tenue.
  Widget _heatCell(int n) {
    final filled = n > 0;
    return Container(
      width: 24,
      height: 24,
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: filled
            ? _kCharge.withOpacity(0.2 + 0.8 * (n / 7).clamp(0.0, 1.0))
            : Colors.white.withOpacity(.04),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white.withOpacity(.06)),
      ),
      alignment: Alignment.center,
      child: filled
          ? Text('$n',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12))
          : const Text('🕸️', style: TextStyle(fontSize: 12)),
    );
  }
}
