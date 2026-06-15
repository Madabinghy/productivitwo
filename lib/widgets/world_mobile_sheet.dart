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
  const WorldMobileScreen(
      {required this.logic, required this.sync, super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _kBg,
        body: SafeArea(child: _WorldMobileList(logic: logic, sync: sync)),
      );
}

class _WorldMobileList extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _WorldMobileList({required this.logic, required this.sync});
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 8, 6),
          child: Row(children: [
            const Text('🌍 Tes domaines',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ]),
        ),
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
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _DomainGameplay(
                logic: logic, sync: widget.sync, domain: d, color: color))),
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
  const _DomainGameplay(
      {required this.logic,
      required this.sync,
      required this.domain,
      required this.color});
  @override
  State<_DomainGameplay> createState() => _DomainGameplayState();
}

class _DomainGameplayState extends State<_DomainGameplay> {
  AppLogic get logic => widget.logic;
  bool _chateau = false; // false = jardin, true = intérieur château

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
    return [...routines.take(5), ...times.take(5)];
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
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            'Aucune routine quotidienne ni activité-temps dans ce domaine.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38)),
                      ),
                    )
                  : (_chateau ? _chateauView(items) : _gardenView(items)),
            ),
            // CTA de navigation jardin ↔ château (le bouton fléché).
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
                  icon: Icon(_chateau ? Icons.arrow_forward : Icons.arrow_back),
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

  Widget _gardenRow(_Item it, double cell, List<String> days) {
    final c = widget.color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
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
          Row(children: [
            // Tour (barres + icône) : tap n'importe où dessus → ouvre le sheet.
            GestureDetector(
              onTap: () => _openItemSheet(it),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 60,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Vie (jaune, continue) = jours faits → pleine quand j'ai tiré.
                    _lifeBar(it.charger / 7),
                    const SizedBox(height: 2),
                    // Chargeur (cases vertes) = jours non faits (7-n) → vide si tiré.
                    _segBar(7 - it.charger, _kCharge),
                    const SizedBox(height: 2),
                    SvgPicture.asset(it.icon,
                        width: 22,
                        height: 22,
                        colorFilter: ColorFilter.mode(
                            it.charger == 0 ? _kEnemy : c, BlendMode.srcIn)),
                  ],
                ),
              ),
            ),
            for (var d = 0; d < it.tokens.length; d++)
              _tokenCell(it, d, cell),
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
    final spider = tok.type == 'spider';
    final emoji = _tokenEmoji(tok.type, scorpion: it.kind == 'scorpion');
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
                        Text('${tok.hp}',
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
