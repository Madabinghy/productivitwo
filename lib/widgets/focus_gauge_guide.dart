import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/focus_gauge.dart';
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';

enum GaugePart { end, fill, tick, target }

/// Tuto de la jauge Focus du lanceur (retour user 2026-10-31) : la ligne d'une
/// vraie activité, puis chaque partie isolée avec ses chiffres.
Future<void> showFocusGaugeGuide(BuildContext context, FocusGaugeStory story, Color color) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .88),
      child: FocusGaugeGuide(story: story, color: color),
    ),
  );
}

class FocusGaugeGuide extends StatelessWidget {
  final FocusGaugeStory story;
  final Color color;
  const FocusGaugeGuide({super.key, required this.story, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = story;
    final total = s.expectedMin <= 0 ? 1 : s.expectedMin;
    final past = (s.pastMin / total).clamp(0.0, 1.0).toDouble();
    final done = (s.doneMin / total).clamp(0.0, 1.0).toDouble();
    final mute = cs.onSurface.withValues(alpha: .65);

    Widget step(int n, Widget visual, String text) => Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: .18), shape: BoxShape.circle),
              child: Text('$n', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: color)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                visual,
                const SizedBox(height: 8),
                Text(text, style: TextStyle(fontSize: 14, height: 1.4, color: cs.onSurface.withValues(alpha: .85))),
              ]),
            ),
          ]),
        );

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        children: [
          Text('LIRE LA JAUGE FOCUS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: cs.onSurface.withValues(alpha: .5))),
          const SizedBox(height: 4),
          Text(s.sample ? 'Un exemple' : 'Avec ta ligne « ${s.name} »',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          // La ligne telle qu'elle apparaît dans le lanceur, en plus grand.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .05), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              GaugeRing(pct: s.ringPct, color: color, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(s.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                    Text('${fmtMin(s.doneMin)} / ${fmtMin(s.expectedMin)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFFF0B44C))),
                  ]),
                  const SizedBox(height: 2),
                  Text('${fmtMin(s.todayMin)} / ${fmtMin(s.targetMin)} aujourd’hui · reste ${fmtMin(s.missingMin)}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: mute)),
                  const SizedBox(height: 8),
                  GaugeBar(past: past, done: done, color: color, height: 8),
                ]),
              ),
            ]),
          ),
          step(1, GaugeBar(past: past, done: done, color: color, focus: GaugePart.end), s.endLine),
          step(2, GaugeBar(past: past, done: done, color: color, focus: GaugePart.fill), s.fillLine),
          step(3, GaugeBar(past: past, done: done, color: color, focus: GaugePart.tick), s.tickLine),
          step(4, GaugeBar(past: past, done: done, color: color, focus: GaugePart.target), s.targetLine),
          step(5, Align(alignment: Alignment.centerLeft, child: GaugeRing(pct: s.ringPct, color: color, size: 40)), s.ringLine),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
            child: Text(s.verdict, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, height: 1.35)),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            child: const Text('Compris'),
          ),
          TextButton(
            onPressed: () => showRuleSheet(context, kRuleActivityPace),
            child: const Text('Et la vue « Tout » ?'),
          ),
        ],
      ),
    );
  }
}

/// La jauge Focus ; [focus] isole une partie (le reste s'efface) et l'entoure.
class GaugeBar extends StatelessWidget {
  final double past, done;
  final Color color;
  final GaugePart? focus;
  final double height;
  const GaugeBar({super.key, required this.past, required this.done, required this.color, this.focus, this.height = 10});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final f = focus;
    final fillOn = f == null || f == GaugePart.fill;
    final tickOn = f == null || f == GaugePart.tick;
    const pad = 4.0;
    return SizedBox(
      height: height + pad * 2,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final tickX = (w * past - 1).clamp(0.0, w - 2);
        Widget outline(double left, double width) => Positioned(
              left: left - 2,
              width: width + 4,
              top: pad - 3,
              height: height + 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: cs.onSurface, width: 1.5),
                  borderRadius: BorderRadius.circular(height / 2 + 3),
                ),
              ),
            );
        return Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0,
            right: 0,
            top: pad,
            height: height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(height / 2),
              child: Stack(children: [
                Positioned.fill(child: ColoredBox(color: cs.onSurface.withValues(alpha: .08))),
                Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: w * done,
                    child: ColoredBox(color: color.withValues(alpha: fillOn ? 1 : .3))),
              ]),
            ),
          ),
          if (past > 0 || f == GaugePart.tick)
            Positioned(
              left: tickX,
              top: 0,
              bottom: 0,
              width: 2,
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: tickOn ? 1 : .35), borderRadius: BorderRadius.circular(1))),
            ),
          if (f == GaugePart.end) outline(0, w),
          if (f == GaugePart.target) outline(w * past, w * (1 - past)),
          if (f == GaugePart.tick)
            Positioned(
              left: tickX - 5,
              top: -6,
              child: Icon(Icons.arrow_drop_down_rounded, size: 12, color: cs.onSurface),
            ),
        ]);
      }),
    );
  }
}

class GaugeRing extends StatelessWidget {
  final int pct;
  final Color color;
  final double size;
  const GaugeRing({super.key, required this.pct, required this.color, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final full = pct >= 100;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        if (full)
          Container(decoration: BoxDecoration(color: color, shape: BoxShape.circle))
        else
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: pct / 100,
              strokeWidth: 4,
              strokeCap: StrokeCap.round,
              color: color,
              backgroundColor: cs.onSurface.withValues(alpha: .1),
            ),
          ),
        full
            ? Icon(Icons.check_rounded, size: size * .45, color: Colors.white)
            : Text('$pct %', style: TextStyle(fontSize: size * .24, fontWeight: FontWeight.w900, color: color)),
      ]),
    );
  }
}
