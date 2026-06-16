import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/models.dart';
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

const _weekdayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
List<String> _last7DayLabels() {
  final n = DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  return [
    for (var i = 0; i < 7; i++)
      _weekdayLetters[today.subtract(Duration(days: 6 - i)).weekday - 1]
  ];
}

String _tokenEmoji(String type, {required bool scorpion}) => type == 'flame'
    ? '🔥'
    : type == 'spider'
        ? (scorpion ? '🦂' : '🕷️')
        : type == 'leaf'
            ? '🍃'
            : '';

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
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..addListener(() => setState(() {}));
  String? _firingId; // ligne en cours de tir
  String? _targetId; // ligne VISÉE (viseur) → cible de « Faire feu »
  final Map<String, int> _mobileDec = {}; // décréments du jour par itemId

  @override
  void dispose() {
    _fireCtrl.dispose();
    super.dispose();
  }

  // Lance le tir sur le nuisible du JOUR (dernière colonne) de la 1ʳᵉ ligne qui
  // en a un (sinon la 1ʳᵉ ligne). La tour se transforme (DCA) le temps du tir.
  void _fire() {
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
    // Sinon : 1ʳᵉ ligne avec un nuisible du jour, sinon la 1ʳᵉ.
    if (target == null) {
      for (final it in items) {
        final n = it.tokens.length;
        if (n > 0 && it.tokens[n - 1].type == 'spider') {
          target = it;
          break;
        }
      }
      target ??= items.isNotEmpty ? items.first : null;
    }
    if (target == null) return;
    final id = target.id;
    setState(() => _firingId = id);
    _fireCtrl.forward(from: 0).then((_) {
      if (!mounted) return;
      setState(() {
        _mobileDec[id] = (_mobileDec[id] ?? 0) + 1; // -1 sur l'araignée du jour
        _firingId = null;
      });
    });
  }

  List<_Item> _items() {
    final dom = widget.domain.id;
    final routines = <_Item>[];
    final times = <_Item>[];
    for (final a in logic.state.activeActivities) {
      if (a.domainId != dom) continue;
      if (a.isHabit) {
        final tok = logic.routineWeekTokens(a.id);
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
    final days = _last7DayLabels();
    const cell = 34.0;
    final routines = items.where((i) => i.kind == 'spider').toList();
    final times = items.where((i) => i.kind == 'scorpion').toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      children: [
        if (routines.isNotEmpty) ...[
          _sectionHeader('🕷️ Routines', routines.length),
          for (final it in routines) _gardenRow(it, cell, days),
        ],
        if (times.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionHeader('🦂 Activités-temps', times.length),
          for (final it in times) _gardenRow(it, cell, days),
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

  Widget _actionsView() {
    final dom = widget.domain.id;
    final projects = logic.currentProjects
        .where((p) =>
            p.domainId == dom && p.status != 'archived' && p.status != 'done')
        .toList();
    if (projects.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucun projet dans ce domaine.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38)),
        ),
      );
    }
    final days = _last7DayLabels();
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
            _actionTaskRow(t, days),
        ],
      ],
    );
  }

  Widget _actionTaskRow(ProjectTask t, List<String> days) {
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.withOpacity(.95),
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          const SizedBox(height: 2),
          Row(children: [
            const SizedBox(width: 60),
            for (final l in days)
              SizedBox(
                width: cell + 2,
                child: Center(
                  child: Text(l,
                      style: TextStyle(
                          color: Colors.white.withOpacity(.4),
                          fontWeight: FontWeight.w900,
                          fontSize: 11)),
                ),
              ),
          ]),
          const SizedBox(height: 1),
          // Lance‑missiles (à la place de la tourelle) + cases‑jours (validations).
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
          // Liste des ACTIONS — fusil devant chacune.
          for (final a in t.actions)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
              child: Row(children: [
                SvgPicture.asset('assets/icons/rifle.svg',
                    width: 15,
                    height: 15,
                    colorFilter: ColorFilter.mode(
                        a.done ? c.withOpacity(.5) : Colors.white60,
                        BlendMode.srcIn)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(a.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: a.done ? Colors.white38 : Colors.white70,
                          decoration:
                              a.done ? TextDecoration.lineThrough : null,
                          fontSize: 12)),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _gardenRow(_Item it, double cell, List<String> days) {
    final c = widget.color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Viseur : tap → cette ligne devient la cible de « Faire feu ».
          Row(children: [
            GestureDetector(
              onTap: () => setState(
                  () => _targetId = _targetId == it.id ? null : it.id),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(right: 6, top: 1, bottom: 1),
                child: Icon(Icons.gps_fixed,
                    size: 18,
                    color: _targetId == it.id
                        ? const Color(0xFFFF8A3D)
                        : Colors.white24),
              ),
            ),
            Expanded(
              child: Text(it.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.withOpacity(.95),
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 2),
          // Lettres des jours, centrées sur chaque case (alignées après la tour).
          Row(children: [
            const SizedBox(width: 60),
            for (final l in days)
              SizedBox(
                width: cell + 2,
                child: Center(
                  child: Text(l,
                      style: TextStyle(
                          color: Colors.white.withOpacity(.4),
                          fontWeight: FontWeight.w900,
                          fontSize: 11)),
                ),
              ),
          ]),
          const SizedBox(height: 1),
          () {
            final firing = _firingId == it.id;
            // Position du boulet : de la tour (x≈30) vers la case du JOUR.
            final todayX = 60.0 + (it.tokens.length - 1) * (cell + 2) + cell / 2;
            final fx = 30 + (todayX - 30) * _fireCtrl.value;
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
                ]),
                // Boulet de feu en vol (tour → jour) pendant le tir.
                if (firing && _fireCtrl.value < 0.96)
                  Positioned(
                    left: fx - 8,
                    top: 22,
                    child: SvgPicture.asset('assets/icons/fireball.svg',
                        width: 16,
                        height: 16,
                        colorFilter: const ColorFilter.mode(
                            Color(0xFFFF8A3D), BlendMode.srcIn)),
                  ),
              ],
            );
          }(),
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
    final dec = isToday ? (_mobileDec[it.id] ?? 0) : 0;
    final shownHp = tok.type == 'spider' ? tok.hp - dec : 0;
    final killed = tok.type == 'spider' && shownHp <= 0;
    final impact = isToday && _firingId == it.id && _fireCtrl.value > 0.9;
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
