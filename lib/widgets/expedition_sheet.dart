import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_economy.dart';
import 'package:productivitwo_v1/gold_purchase.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/gold_icon.dart';

const _kGold = Color(0xFFD4A017);
const double _rowH = 92;
const double _nodeR = 26;

/// Ouvre la mini-carte d'expédition du prochain niveau (gate « gagné, pas
/// arrivé ») : on dépense des outils achetés en boutique pour franchir les nœuds
/// jusqu'au drapeau, ce qui révèle le titre et débloque le niveau.
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

  int get _level => logic.effectiveLevel() + 1;
  late Expedition _exp = generateExpedition(_level);

  Set<String> get _cleared =>
      {_exp.start.id, ...logic.state.expeditionCleared};

  String _toolLabel(String key) => const {
        'pas': '🥾 pas',
        'pioche': '⛏️ pioche',
        'cle': '🔑 clé',
        'pelle': '🪏 pelle',
      }[key] ??
      key;

  Future<void> _tap(ExpeditionNode node) async {
    if (_busy) return;
    final reachable = _exp.reachable(_cleared);
    if (!reachable.contains(node.id)) return;

    final toolKey = toolForType(node.type);

    // Nœud gratuit (bonus / arrivée).
    if (toolKey == null) {
      setState(() => _busy = true);
      final ok = await sync.advanceExpedition(nodeId: node.id);
      if (ok) {
        logic.state.expeditionCleared.add(node.id);
        if (node.type == ExpNodeType.bonus && node.bonusGold > 0) {
          logic.state.gold += node.bonusGold;
          logic.state.goldLifetime += node.bonusGold;
          sync.applyGold(GoldLedgerEntry(
            id: '${DateTime.now().microsecondsSinceEpoch}',
            delta: node.bonusGold,
            category: 'gain',
            reasonCode: 'expedition_bonus',
            label: 'Trésor d\'expédition',
          ));
        }
        logic.onChange();
      }
      if (!mounted) return;
      setState(() => _busy = false);
      if (node.type == ExpNodeType.finish && ok) await _finish();
      return;
    }

    // Nœud payant : il faut l'outil correspondant.
    if ((logic.state.goldInventory[toolKey] ?? 0) < 1) {
      final bought = await offerBuyConsumable(
        context,
        sync,
        itemKey: toolKey,
        price: GoldEconomy.scaledPrice(
            GoldEconomy.toolBasePrice(toolKey), logic.effectiveLevel()),
        label: _toolLabel(toolKey),
        rationale:
            'Pour franchir ce nœud, il te faut un « ${_toolLabel(toolKey)} ».',
        logic: logic,
      );
      if (!bought) return;
    }

    setState(() => _busy = true);
    final ok =
        await sync.advanceExpedition(nodeId: node.id, toolKey: toolKey);
    if (ok) {
      logic.state.goldInventory[toolKey] =
          (logic.state.goldInventory[toolKey] ?? 1) - 1;
      logic.state.expeditionCleared.add(node.id);
      logic.onChange();
    }
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _finish() async {
    final ok = await sync.completeExpedition(_level);
    if (ok) {
      logic.state.unlockedLevel = _level;
      logic.state.expeditionCleared.clear();
      logic.onChange();
    }
    if (!mounted) return;
    final lvl = logic.userLevelData();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Niveau ${lvl.level} débloqué ! 🏁'),
        content: Text(
          'Tu as atteint le bout de la carte. Tu es désormais « ${lvl.title} » — '
          'de nouveaux items peuvent s\'ouvrir en boutique.',
        ),
        actions: [
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kGold),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Super')),
        ],
      ),
    );
    if (mounted) Navigator.pop(context); // referme la carte
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final biome = expeditionBiome(_level);
    final cleared = _cleared;
    final reachable = _exp.reachable(cleared);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(children: [
              Text(biome.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Niveau $_level · ???',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('Expédition · ${biome.label} — atteins le 🏁',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurface.withOpacity(.55))),
                  ],
                ),
              ),
              goldAmount('${logic.state.gold}',
                  fontSize: 15, weight: FontWeight.bold, color: _kGold),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                      'Touche un nœud accessible pour le franchir (consomme l\'outil). '
                      'Pas d\'outil ? On te propose de l\'acheter.',
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurface.withOpacity(.5))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final laneW = c.maxWidth / _exp.lanes;
              Offset posOf(ExpeditionNode n) => Offset(
                  n.lane * laneW + laneW / 2, n.row * _rowH + _rowH / 2);
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
                          isFrontier: frontier?.id == n.id,
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

class _NodeDot extends StatelessWidget {
  final ExpeditionNode node;
  final bool cleared, reachable, isFrontier, busy;
  final ColorScheme cs;
  final VoidCallback onTap;
  const _NodeDot({
    required this.node,
    required this.cleared,
    required this.reachable,
    required this.isFrontier,
    required this.busy,
    required this.cs,
    required this.onTap,
  });

  String get _emoji {
    switch (node.type) {
      case ExpNodeType.start:
        return '🏳️';
      case ExpNodeType.finish:
        return '🏁';
      case ExpNodeType.rock:
        return '🪨';
      case ExpNodeType.gate:
        return '🔒';
      case ExpNodeType.hole:
        return '🕳️';
      case ExpNodeType.bonus:
        return '💰';
      case ExpNodeType.step:
        return '•';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color border;
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
    final dim = !cleared && !reachable;

    return GestureDetector(
      onTap: (reachable && !busy) ? onTap : null,
      child: Opacity(
        opacity: dim ? .5 : 1,
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
          child: cleared
              ? (node.type == ExpNodeType.finish || node.type == ExpNodeType.start
                  ? Text(_emoji, style: const TextStyle(fontSize: 20))
                  : Icon(Icons.check, color: Colors.green.shade700, size: 22))
              : Text(
                  isFrontier ? '🧍' : _emoji,
                  style: TextStyle(
                      fontSize: node.type == ExpNodeType.step && !isFrontier
                          ? 18
                          : 20),
                ),
        ),
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
        // Arête « franchie » si les deux extrémités le sont (chemin emprunté).
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
