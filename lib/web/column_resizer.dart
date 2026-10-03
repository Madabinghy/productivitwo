import 'package:flutter/material.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

const double kColumnMinW = 220.0;
const double kColumnMaxW = 640.0;

/// Borne la largeur d'une colonne redimensionnable (libellés des Gantt).
double clampColumnWidth(double w, {double min = kColumnMinW, double max = kColumnMaxW}) =>
    w.clamp(min, max).toDouble();

/// Poignée verticale à poser dans un `Stack` sur la frontière d'une colonne :
/// glisser = redimensionner, double-clic = largeur par défaut. 8 px de prise,
/// trait visible au survol et pendant le glisser.
class ColumnResizeHandle extends StatefulWidget {
  final double left;
  final double top;
  final ValueChanged<double> onDrag; // delta en px
  final VoidCallback? onEnd;
  final VoidCallback? onReset;
  const ColumnResizeHandle({
    super.key,
    required this.left,
    this.top = 0,
    required this.onDrag,
    this.onEnd,
    this.onReset,
  });

  @override
  State<ColumnResizeHandle> createState() => _ColumnResizeHandleState();
}

class _ColumnResizeHandleState extends State<ColumnResizeHandle> {
  bool _hover = false;
  bool _drag = false;

  @override
  Widget build(BuildContext context) {
    final on = _hover || _drag;
    return Positioned(
      left: widget.left - 4,
      top: widget.top,
      bottom: 0,
      width: 8,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Tooltip(
          message: 'Glisser pour élargir la colonne · double-clic = largeur par défaut',
          waitDuration: const Duration(milliseconds: 800),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => setState(() => _drag = true),
            onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
            onHorizontalDragEnd: (_) {
              setState(() => _drag = false);
              widget.onEnd?.call();
            },
            onHorizontalDragCancel: () => setState(() => _drag = false),
            onDoubleTap: widget.onReset,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: on ? 3 : 1,
                color: on ? kBPrimary.withOpacity(.8) : Colors.transparent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
