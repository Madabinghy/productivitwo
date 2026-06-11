import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/confetti.dart';
import 'package:productivitwo_v1/widgets/gold_icon.dart';

const _kGold = Color(0xFFD4A017);
const double _rowH = 92;
const double _nodeR = 26;

/// Donjon (Phase 2) : carte à nœuds qu'on EXPLORE pour débloquer le niveau. Les
/// défis (préparés côté app à partir des vraies données) sont posés sur des nœuds
/// et se DÉCOUVRENT en avançant. Un nœud-défi se franchit quand son défi est
/// accompli (auto-validé). Atteindre le 🏁 (tous les défis relevés) débloque.
Future<void> showExpeditionSheet(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ExpeditionSheet(logic: logic, sync: sync),
  );
}

class _ExpeditionSheet extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _ExpeditionSheet({required this.logic, required this.sync});
  @override
  State<_ExpeditionSheet> createState() => _ExpeditionSheetState();
}

class _ExpeditionSheetState extends State<_ExpeditionSheet> {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => widget.sync;
  bool _busy = false;

  int get _level => logic.effectiveLevel() + 1; // niveau VISÉ (déblocage)
  int get _mapLevel => logic.effectiveLevel(); // identité de la carte (affichage)
  late final Expedition _exp = generateExpedition(_level);

  Set<String> get _cleared => {_exp.start.id, ...logic.state.expeditionCleared};

  @override
  void initState() {
    super.initState();
    // Génère les défis du donjon à l'ouverture (instantané, sans Orion).
    logic.ensureExpeditionChallenges(sync);
    // Mémorise l'entrée → entrée auto dans le donjon ensuite (jusqu'au déblocage).
    if (logic.state.expeditionDonjonLevel != _level) {
      logic.state.expeditionDonjonLevel = _level;
      logic.onChange();
      sync.setExpeditionDonjonLevel(_level);
    }
  }

  /// Défis auto-validés (ordre = stockage). Index → état {label,progress,done}.
  List<({String label, String type, int target, int progress, bool done})>
      get _challenges => logic.expeditionChallengeStatuses();

  /// Mappe chaque défi sur un nœud-obstacle (dans l'ordre des rangées).
  Map<String, int> _nodeChallengeMap() {
    final obstacles = _exp.nodes
        .where((n) =>
            n.type == ExpNodeType.rock ||
            n.type == ExpNodeType.gate ||
            n.type == ExpNodeType.hole)
        .toList()
      ..sort((a, b) => a.row.compareTo(b.row));
    final m = <String, int>{};
    final n = _challenges.length;
    for (var i = 0; i < obstacles.length && i < n; i++) {
      m[obstacles[i].id] = i;
    }
    return m;
  }

  Future<void> _tap(ExpeditionNode node) async {
    if (_busy) return;
    if (!_exp.reachable(_cleared).contains(node.id)) return;
    final challenges = _challenges;
    final ci = _nodeChallengeMap()[node.id];

    // Nœud-défi non accompli → bloqué, on l'affiche.
    if (ci != null && ci < challenges.length && !challenges[ci].done) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🎯 Relève ce défi pour passer : ${challenges[ci].label}'),
          duration: const Duration(seconds: 2)));
      setState(() {});
      return;
    }

    // Sortie : exige que TOUS les défis soient relevés (filet de sécurité).
    if (node.type == ExpNodeType.finish &&
        !logic.expeditionChallengesAllDone()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Relève tous les défis avant d\'atteindre la sortie 🏁'),
          duration: Duration(seconds: 2)));
      return;
    }

    // Nœud-étape (sans défi) = ACTION EXPRESS : 5 min sur une routine pour
    // franchir (pousse à agir ; même inachevé, on a avancé).
    if (node.type == ExpNodeType.step && ci == null) {
      await _showMicroAction(node);
      return;
    }

    setState(() => _busy = true);
    final ok = await sync.advanceExpedition(nodeId: node.id);
    if (ok) {
      logic.state.expeditionCleared.add(node.id);
      if (node.type == ExpNodeType.bonus && node.bonusGold > 0) {
        logic.state.gold += node.bonusGold;
        logic.addLifetimeCapped(node.bonusGold);
        sync.applyGold(GoldLedgerEntry(
          id: '${DateTime.now().microsecondsSinceEpoch}',
          delta: node.bonusGold,
          category: 'gain',
          reasonCode: 'expedition_bonus',
          label: 'Trésor de donjon',
        ));
      }
      logic.onChange();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (node.type == ExpNodeType.finish && ok) await _finish();
  }

  Future<void> _launchMicro(
      ExpeditionNode node, Activity routine, int minutes, int bonus) async {
    Navigator.pop(context); // ferme la feuille action express
    final linkedId = (routine.linkedActivityId ?? '').trim();
    Activity? linked;
    for (final a in logic.state.activities) {
      if (a.id == linkedId) {
        linked = a;
        break;
      }
    }
    if (linked != null && logic.launchTimerHook != null) {
      logic.start(linked.id);
      // Le nœud n'est franchi QUE si le minuteur va à son terme (validé dans
      // _onAlarmRing). Annuler le minuteur = on reste où on est.
      logic.launchTimerHook!(minutes, linked.name,
          routineId: routine.id,
          expeditionNodeId: node.id,
          expeditionBonus: bonus);
      if (mounted) Navigator.pop(context); // ferme le donjon → on voit le minuteur
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Lie une activité à « ${routine.name} » pour lancer le minuteur.')));
    }
  }

  // Routines programmées pour plus tard depuis le donjon → retirées de la liste.
  final Set<String> _programmedRoutines = {};

  Future<void> _showMicroAction(ExpeditionNode node) async {
    final allDaily = logic.state.activeActivities
        .where((a) =>
            a.isHabit && (a.habitFreq ?? HabitFreq.monthly) == HabitFreq.daily)
        .toList();
    // Toutes les routines quotidiennes (sauf celles programmées pour plus tard
    // pendant cette session). Faites OU à faire : une routine déjà faite devient
    // une CLÉ « Utiliser ». Tri : à faire → déjà faite (clé) → déjà utilisée.
    int rank(Activity a) {
      final tgt = logic.activeHabitTarget(a);
      final done = tgt > 0 && logic.habitValueOn(a.id, DateTime.now()) >= tgt;
      if (!done) return 0;
      return logic.donjonKeyAvailable(a.id) ? 1 : 2;
    }

    final routines = allDaily
        .where((a) => !_programmedRoutines.contains(a.id))
        .toList()
      ..sort((a, b) => rank(a).compareTo(rank(b)));
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⏱️ Action express',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                    'Fais une routine (minuteur) OU utilise une routine déjà faite '
                    'aujourd\'hui pour franchir ce passage. Version longue = bonus d\'or.',
                    style: TextStyle(
                        fontSize: 12.5, color: cs.onSurface.withOpacity(.6))),
                const SizedBox(height: 14),
                if (routines.isEmpty)
                  Text('Crée une routine quotidienne pour débloquer ce passage.',
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurface.withOpacity(.6)))
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.45),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: routines
                            .map((r) => _microRoutineCard(ctx, node, r))
                            .toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Carte d'une routine dans l'action express, adaptative :
  /// à faire → boutons 5 min / full ; déjà faite + clé → « Utiliser » ;
  /// déjà utilisée aujourd'hui → grisée.
  Widget _microRoutineCard(BuildContext ctx, ExpeditionNode node, Activity r) {
    final cs = Theme.of(ctx).colorScheme;
    final tgt = logic.activeHabitTarget(r);
    final done = tgt > 0 && logic.habitValueOn(r.id, DateTime.now()) >= tgt;
    final keyAvailable = done && logic.donjonKeyAvailable(r.id);
    final usedAlready = done && !keyAvailable; // faite mais clé consommée
    final full = (r.timerMin ?? 0) > 0 ? r.timerMin! : 15;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(usedAlready ? .2 : .4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: usedAlready
                        ? cs.onSurface.withOpacity(.4)
                        : cs.onSurface)),
            const SizedBox(height: 10),
            if (keyAvailable) ...[
              Row(children: [
                Icon(Icons.check_circle, size: 15, color: Colors.green.shade500),
                const SizedBox(width: 6),
                Text('déjà fait aujourd\'hui',
                    style: TextStyle(
                        fontSize: 12.5, color: cs.onSurface.withOpacity(.6))),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: _kGold,
                      foregroundColor: const Color(0xFF231900)),
                  icon: const Icon(Icons.vpn_key_rounded, size: 16),
                  label: const Text('Utiliser'),
                  onPressed: () => _crossNodeWithKey(node, r),
                ),
              ),
            ] else if (usedAlready) ...[
              Row(children: [
                Icon(Icons.lock_clock,
                    size: 15, color: cs.onSurface.withOpacity(.35)),
                const SizedBox(width: 6),
                Text('déjà utilisée pour avancer',
                    style: TextStyle(
                        fontSize: 12.5, color: cs.onSurface.withOpacity(.4))),
              ]),
            ] else ...[
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _launchMicro(node, r, 5, 0),
                    child: const Text('5 min'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: _kGold,
                        foregroundColor: const Color(0xFF231900)),
                    onPressed: () => _launchMicro(node, r, full, 5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$full min +'),
                        const SizedBox(width: 3),
                        const GoldIcon(size: 14, color: Color(0xFF231900)),
                      ],
                    ),
                  ),
                ),
              ]),
              // « Je ne peux pas maintenant » → programmer pour plus tard.
              if (logic.programBacklogHook != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    icon: const Text('📅', style: TextStyle(fontSize: 13)),
                    label: const Text('Programmer pour plus tard',
                        style: TextStyle(fontSize: 12.5)),
                    onPressed: () async {
                      _programmedRoutines.add(r.id);
                      Navigator.pop(ctx);
                      await logic.programBacklogHook!('spider', r.id);
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Franchit le nœud en consommant la clé d'une routine déjà faite aujourd'hui
  /// (pas de travail à refaire ni de bonus d'or — la routine a déjà rapporté).
  Future<void> _crossNodeWithKey(ExpeditionNode node, Activity r) async {
    Navigator.pop(context); // ferme la feuille action express
    final ok = await sync.advanceExpedition(nodeId: node.id);
    if (ok) {
      logic.useDonjonKey(r.id);
      logic.state.expeditionCleared.add(node.id);
      logic.onChange();
      if (mounted) setState(() {});
    }
  }

  Future<void> _finish() async {
    final ok = await sync.completeExpedition(_level);
    if (ok) {
      logic.state.unlockedLevel = _level;
      logic.state.expeditionCleared.clear();
      logic.onChange();
    }
    if (!mounted) return;
    showConfetti(context);
    final lvl = logic.userLevelData();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Niveau ${lvl.level} débloqué ! 🏁'),
        content: Text(
            'Tu as traversé le donjon et relevé tous les défis. Tu es désormais '
            '« ${lvl.title} ».'),
        actions: [
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kGold),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Super')),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  void _showDiscovered(Set<String> discovered) {
    final map = _nodeChallengeMap();
    final challenges = _challenges;
    // Défis dont le nœud est découvert (atteint ou accessible).
    final found = <int>[];
    for (final e in map.entries) {
      if (discovered.contains(e.key) && !found.contains(e.value)) {
        found.add(e.value);
      }
    }
    found.sort();
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Défis découverts',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (found.isEmpty)
                Text('Explore le donjon pour découvrir des défis.',
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurface.withOpacity(.6)))
              else
                for (final i in found)
                  if (i < challenges.length)
                    _ChallengeRow(c: challenges[i], cs: cs),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final biome = expeditionBiome(_level);
    final cleared = _cleared;
    final reachable = _exp.reachable(cleared);
    final discovered = {...cleared, ...reachable};
    final challenges = _challenges;
    final map = _nodeChallengeMap();
    final doneCount = challenges.where((c) => c.done).length;

    // Défi « en cours » = 1er nœud-défi accessible non accompli.
    ({String label, String type, int target, int progress, bool done})? current;
    for (final n in _exp.nodes) {
      if (!reachable.contains(n.id)) continue;
      final ci = map[n.id];
      if (ci != null && ci < challenges.length && !challenges[ci].done) {
        current = challenges[ci];
        break;
      }
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(children: [
              Text(biome.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Donjon · Niveau $_mapLevel',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('Défis relevés : $doneCount / ${challenges.length}',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurface.withOpacity(.55))),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => _showDiscovered(discovered),
                icon: const Icon(Icons.list_alt_outlined, size: 16),
                label: const Text('Défis'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ]),
          ),
          // Bannière du défi en cours.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: current != null
                    ? _kGold.withOpacity(.12)
                    : Colors.green.withOpacity(.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: (current != null ? _kGold : Colors.green)
                        .withOpacity(.4)),
              ),
              child: Row(children: [
                Text(current != null ? '🎯' : '🏁',
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    current != null
                        ? current.label +
                            (current.target > 1
                                ? '  (${current.progress}/${current.target})'
                                : '')
                        : (challenges.isEmpty
                            ? 'Explore le donjon…'
                            : 'Tous les défis relevés — atteins la sortie 🏁'),
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final laneW = c.maxWidth / _exp.lanes;
              Offset posOf(ExpeditionNode n) =>
                  Offset(n.lane * laneW + laneW / 2, n.row * _rowH + _rowH / 2);
              final positions = {for (final n in _exp.nodes) n.id: posOf(n)};
              final frontier = cleared
                  .map((id) => _exp.byId(id))
                  .fold<ExpeditionNode?>(null,
                      (best, n) => best == null || n.row > best.row ? n : best);

              return SingleChildScrollView(
                controller: scroll,
                child: SizedBox(
                  width: c.maxWidth,
                  height: _exp.rows * _rowH + 24,
                  child: Stack(children: [
                    CustomPaint(
                      size: Size(c.maxWidth, _exp.rows * _rowH + 24),
                      painter: _PathPainter(
                        nodes: _exp.nodes,
                        positions: positions,
                        cleared: cleared,
                        edgeColor: cs.onSurface.withOpacity(.18),
                        clearedColor: Colors.green.shade600,
                      ),
                    ),
                    for (final n in _exp.nodes)
                      Positioned(
                        left: positions[n.id]!.dx - _nodeR,
                        top: positions[n.id]!.dy - _nodeR,
                        child: _NodeDot(
                          node: n,
                          cleared: cleared.contains(n.id),
                          reachable: reachable.contains(n.id),
                          discovered: discovered.contains(n.id),
                          isFrontier: frontier?.id == n.id,
                          challengeDone: () {
                            final ci = map[n.id];
                            return ci != null &&
                                ci < challenges.length &&
                                challenges[ci].done;
                          }(),
                          hasChallenge: map.containsKey(n.id),
                          busy: _busy,
                          cs: cs,
                          onTap: () => _tap(n),
                        ),
                      ),
                  ]),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _ChallengeRow extends StatelessWidget {
  final ({String label, String type, int target, int progress, bool done}) c;
  final ColorScheme cs;
  const _ChallengeRow({required this.c, required this.cs});
  @override
  Widget build(BuildContext context) {
    final color = c.done ? Colors.green.shade600 : _kGold;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.done ? '✅' : '🎯', style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              if (c.target > 1) ...[
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (c.progress / c.target).clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: cs.onSurface.withOpacity(.10),
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text('${c.progress} / ${c.target}',
                    style: TextStyle(
                        fontSize: 10.5, color: cs.onSurface.withOpacity(.5))),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

class _NodeDot extends StatelessWidget {
  final ExpeditionNode node;
  final bool cleared, reachable, discovered, isFrontier, busy;
  final bool hasChallenge, challengeDone;
  final ColorScheme cs;
  final VoidCallback onTap;
  const _NodeDot({
    required this.node,
    required this.cleared,
    required this.reachable,
    required this.discovered,
    required this.isFrontier,
    required this.hasChallenge,
    required this.challengeDone,
    required this.busy,
    required this.cs,
    required this.onTap,
  });

  String get _emoji {
    if (hasChallenge && !cleared) return challengeDone ? '🗝️' : '🎯';
    switch (node.type) {
      case ExpNodeType.start:
        return '🏳️';
      case ExpNodeType.finish:
        return '🏁';
      case ExpNodeType.bonus:
        return '💰';
      case ExpNodeType.rock:
        return '🪨';
      case ExpNodeType.gate:
        return '🔒';
      case ExpNodeType.hole:
        return '🕳️';
      case ExpNodeType.step:
        return '⏱️';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bg, border;
    if (cleared) {
      bg = Colors.green.shade100;
      border = Colors.green.shade600;
    } else if (reachable) {
      bg = _kGold.withOpacity(.18);
      border = _kGold;
    } else {
      bg = cs.surfaceContainerHighest.withOpacity(.5);
      border = cs.outlineVariant.withOpacity(.5);
    }
    // Non découvert → brouillard.
    if (!discovered && !cleared) {
      return Container(
        width: _nodeR * 2,
        height: _nodeR * 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.onSurface.withOpacity(.10),
          shape: BoxShape.circle,
        ),
        child: Text('?',
            style: TextStyle(
                fontSize: 16, color: cs.onSurface.withOpacity(.35))),
      );
    }

    return GestureDetector(
      onTap: (reachable && !busy) ? onTap : null,
      child: Container(
        width: _nodeR * 2,
        height: _nodeR * 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(
              color: border, width: reachable && !cleared ? 2.5 : 1.5),
        ),
        child: cleared &&
                node.type != ExpNodeType.finish &&
                node.type != ExpNodeType.start
            ? Icon(Icons.check, color: Colors.green.shade700, size: 22)
            : Text(isFrontier && !cleared ? '🧍' : _emoji,
                style: TextStyle(
                    fontSize:
                        node.type == ExpNodeType.step && !hasChallenge ? 18 : 20)),
      ),
    );
  }
}

class _PathPainter extends CustomPainter {
  final List<ExpeditionNode> nodes;
  final Map<String, Offset> positions;
  final Set<String> cleared;
  final Color edgeColor, clearedColor;
  _PathPainter({
    required this.nodes,
    required this.positions,
    required this.cleared,
    required this.edgeColor,
    required this.clearedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final n in nodes) {
      final from = positions[n.id]!;
      for (final nextId in n.next) {
        final to = positions[nextId]!;
        final done = cleared.contains(n.id) && cleared.contains(nextId);
        final paint = Paint()
          ..color = done ? clearedColor : edgeColor
          ..strokeWidth = done ? 4 : 2.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(from, to, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) =>
      old.cleared != cleared || old.positions != positions;
}
