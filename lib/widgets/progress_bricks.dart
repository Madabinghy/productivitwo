import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/progress_bricks.dart';

/// Couleur « chrono dessus » des briques (bleu-vert, distinct du vert fait).
const kBrickRunning = Color(0xFF2FB3A3);

Color brickColor(BrickState s, {Color accent = kPalierGreen}) => switch (s) {
      BrickState.done || BrickState.started || BrickState.todo || BrickState.upcoming => accent,
      BrickState.late => kPalierCoral,
      BrickState.running => kBrickRunning,
    };

/// Rangée de briques (mur des projets, 2026-10) : une brique par enfant, de
/// largeur égale ; pleine = finie, remplie au prorata = entamée, bord corail =
/// en retard, bord bleu-vert = chrono dessus, creuse = à venir. Trait blanc =
/// attendu aujourd'hui. [onBrick] = tap sur une brique (index). Quand les
/// briques sont plus étroites que [kBrickMinTapWidth] (retour user : dur à
/// viser), le tap ouvre un **sélecteur** (`showBrickPicker`) qui liste les
/// briques avec leur titre ; appui long = toujours le sélecteur.
class ProgressBricks extends StatelessWidget {
  final BrickRow row;
  final double height;
  final double gap;
  final void Function(int index)? onBrick;
  /// Brique mise en avant (bord clair), ex. la tâche ouverte.
  final int? highlight;
  /// Titre du sélecteur (« Les tâches du projet »).
  final String pickerTitle;
  /// Couleur du « fait » (vert par défaut ; violet pour un objectif).
  final Color accent;
  const ProgressBricks(
      {super.key,
      required this.row,
      this.height = 12,
      this.gap = 3,
      this.onBrick,
      this.highlight,
      this.pickerTitle = 'Choisir une brique',
      this.accent = kPalierGreen});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final painter = _BricksPainter(
      row: row,
      gap: gap,
      dim: cs.onSurface.withValues(alpha: .10),
      tick: cs.onSurface.withValues(alpha: .92),
      highlight: highlight,
      highlightColor: cs.onSurface,
      accent: accent,
    );
    final child = SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: painter));
    if (onBrick == null || row.total == 0) return child;
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      final narrow = w <= 0 || w / row.total < kBrickMinTapWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          if (narrow) {
            showBrickPicker(ctx, row, title: pickerTitle, onBrick: onBrick!);
            return;
          }
          final i = ((d.localPosition.dx / w) * row.total).floor().clamp(0, row.total - 1);
          onBrick!(i);
        },
        onLongPress: () => showBrickPicker(ctx, row, title: pickerTitle, onBrick: onBrick!),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: child),
      );
    });
  }
}

/// Largeur de brique en dessous de laquelle un tap direct n'est plus fiable.
const double kBrickMinTapWidth = 26;

String brickStateLabel(BrickState s) => switch (s) {
      BrickState.done => 'finie',
      BrickState.started => 'entamée',
      BrickState.late => 'en retard',
      BrickState.running => 'chrono dessus',
      BrickState.todo => 'à faire',
      BrickState.upcoming => 'à venir',
    };

/// Sélecteur de brique : une ligne par brique (carré d'état, titre, k / n
/// enfants, état) dans l'ordre de la rangée ; tap = [onBrick].
Future<void> showBrickPicker(BuildContext context, BrickRow row, {required String title, required void Function(int index) onBrick}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final text3 = cs.onSurface.withValues(alpha: .55);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .75),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Row(children: [
                Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                Text('${row.done} / ${row.total}', style: TextStyle(fontSize: 12.5, color: text3)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: ProgressBricks(row: row, height: 10),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                itemCount: row.total,
                itemBuilder: (_, i) {
                  final b = row.bricks[i];
                  final c = brickColor(b.state);
                  final afterTick = row.expected > 0 && i == row.expected;
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    if (afterTick)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: Row(children: [
                          Expanded(child: Divider(color: cs.onSurface.withValues(alpha: .35), thickness: 1.5)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text('attendu aujourd\'hui', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: text3)),
                          ),
                          Expanded(child: Divider(color: cs.onSurface.withValues(alpha: .35), thickness: 1.5)),
                        ]),
                      ),
                    ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: SizedBox(
                        width: 22,
                        height: 22,
                        child: CustomPaint(
                          painter: _BricksPainter(
                            row: BrickRow(bricks: [b], expected: 0),
                            gap: 0,
                            dim: cs.onSurface.withValues(alpha: .10),
                            tick: Colors.transparent,
                            highlightColor: cs.onSurface,
                          ),
                        ),
                      ),
                      title: Text(b.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: b.state == BrickState.done ? text3 : cs.onSurface,
                              decoration: b.state == BrickState.done ? TextDecoration.lineThrough : null)),
                      subtitle: Text(
                        [if (b.total > 0) '${b.done} / ${b.total}', brickStateLabel(b.state)].join(' · '),
                        style: TextStyle(fontSize: 11.5, color: b.state == BrickState.late || b.state == BrickState.running ? c : text3),
                      ),
                      trailing: Icon(Icons.chevron_right, size: 18, color: text3),
                      onTap: () {
                        Navigator.pop(ctx);
                        onBrick(i);
                      },
                    ),
                  ]);
                },
              ),
            ),
          ]),
        ),
      );
    },
  );
}

class _BricksPainter extends CustomPainter {
  final BrickRow row;
  final double gap;
  final Color dim;
  final Color tick;
  final int? highlight;
  final Color highlightColor;
  final Color accent;
  _BricksPainter(
      {required this.row, required this.gap, required this.dim, required this.tick, this.highlight, required this.highlightColor, this.accent = kPalierGreen});

  @override
  void paint(Canvas canvas, Size size) {
    final n = row.total;
    if (n == 0) {
      canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)), Paint()..color = dim);
      return;
    }
    final g = n > 40 ? 1.0 : (n > 20 ? 2.0 : gap);
    final w = (size.width - g * (n - 1)) / n;
    final r = Radius.circular(w < 6 ? 1.5 : 3);
    for (var i = 0; i < n; i++) {
      final b = row.bricks[i];
      final rect = Rect.fromLTWH(i * (w + g), 0, w, size.height);
      final rr = RRect.fromRectAndRadius(rect, r);
      final c = brickColor(b.state, accent: accent);
      switch (b.state) {
        case BrickState.done:
          canvas.drawRRect(rr, Paint()..color = c);
        case BrickState.upcoming:
          canvas.drawRRect(rr.deflate(.5), Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = dim.withValues(alpha: .35));
        case BrickState.started:
        case BrickState.todo:
        case BrickState.late:
        case BrickState.running:
          canvas.drawRRect(rr, Paint()..color = dim);
          if (b.fill > 0) {
            canvas.save();
            canvas.clipRRect(rr);
            canvas.drawRect(Rect.fromLTWH(rect.left, 0, w * b.fill.clamp(0, 1), size.height), Paint()..color = c);
            canvas.restore();
          }
          if (b.state == BrickState.late || b.state == BrickState.running) {
            canvas.drawRRect(rr.deflate(.75), Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = c);
          }
      }
      if (highlight == i) {
        canvas.drawRRect(rr.deflate(.75), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = highlightColor);
      }
    }
    final tx = row.tickX;
    if (tx != null && tx < 1) {
      // Le trait tombe sur le joint après la dernière brique attendue.
      final x = row.expected * (w + g) - g / 2;
      canvas.drawRect(Rect.fromLTWH(x - 1, -3, 2, size.height + 6), Paint()..color = tick);
    }
  }

  @override
  bool shouldRepaint(_BricksPainter o) =>
      o.row != row || o.gap != gap || o.dim != dim || o.tick != tick || o.highlight != highlight || o.accent != accent;
}

/// Dernier niveau : une action = ses étapes, un point par étape ; le cerclé =
/// l'étape en cours. Sans étape, un seul point (fait ou pas).
class StepDots extends StatelessWidget {
  final int done;
  final int total;
  final bool allDone;
  final double size;
  const StepDots({super.key, required this.done, required this.total, this.allDone = false, this.size = 10});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = total == 0 ? 1 : total;
    final d = total == 0 ? (allDone ? 1 : 0) : done;
    return Wrap(spacing: 5, runSpacing: 4, children: [
      for (var i = 0; i < n; i++)
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < d ? kPalierGreen : cs.onSurface.withValues(alpha: .10),
            border: i == d && !allDone ? Border.all(color: kBrickRunning, width: 2) : null,
          ),
        ),
    ]);
  }
}
