import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/game_rules.dart';

/// Petit ⓘ posé à côté d'une fonctionnalité à enjeux : ouvre la règle en
/// quelques cartes (`showRuleSheet`).
class InfoDot extends StatelessWidget {
  final GameRule rule;
  final int startAt;
  final double size;
  const InfoDot(this.rule, {super.key, this.startAt = 0, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Comment ça marche : ${rule.title}',
      child: InkResponse(
        radius: 20,
        onTap: () => showRuleSheet(context, rule, startAt: startAt),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(Icons.info_outline_rounded, size: size, color: cs.onSurface.withValues(alpha: .5)),
        ),
      ),
    );
  }
}

/// Mini-tuto : une carte par écran, points de progression, Suivant / Compris.
Future<void> showRuleSheet(BuildContext context, GameRule rule, {int startAt = 0}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _RuleSheet(rule: rule, startAt: startAt),
  );
}

class _RuleSheet extends StatefulWidget {
  final GameRule rule;
  final int startAt;
  const _RuleSheet({required this.rule, required this.startAt});

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  late final PageController _pages = PageController(initialPage: widget.startAt);
  late int _i = widget.startAt;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cards = widget.rule.cards;
    final last = _i >= cards.length - 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.rule.title.toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: cs.onSurface.withValues(alpha: .5))),
          SizedBox(
            height: 190,
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _i = i),
              children: [
                for (final c in cards)
                  Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(c.emoji, style: const TextStyle(fontSize: 40)),
                    const SizedBox(height: 10),
                    Text(c.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(c.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, height: 1.4, color: cs.onSurface.withValues(alpha: .7))),
                  ]),
              ],
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var k = 0; k < cards.length; k++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: k == _i ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: k == _i ? cs.primary : cs.onSurface.withValues(alpha: .2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: last
                ? () => Navigator.pop(context)
                : () => _pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            child: Text(last ? 'Compris' : 'Suivant'),
          ),
        ]),
      ),
    );
  }
}
