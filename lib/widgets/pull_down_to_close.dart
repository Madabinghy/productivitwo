import 'package:flutter/material.dart';

/// Page plein écran refermable d'un geste vers le bas (retour user
/// 2026-10-30 : « plutôt qu'aller chercher la croix »). Tire depuis le haut de
/// la liste (rebond iOS ou overscroll Android) ou depuis une zone non
/// défilante ; au-delà de [threshold] ou d'un geste vif, la page se ferme.
class PullDownToClose extends StatefulWidget {
  final Widget child;
  final double threshold;
  const PullDownToClose({super.key, required this.child, this.threshold = 110});

  @override
  State<PullDownToClose> createState() => _PullDownToCloseState();
}

class _PullDownToCloseState extends State<PullDownToClose> with SingleTickerProviderStateMixin {
  double _dy = 0;
  bool _closing = false;
  late final AnimationController _back;
  double _from = 0;

  @override
  void initState() {
    super.initState();
    _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))
      ..addListener(() => setState(() => _dy = _from * (1 - _back.value)));
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _drag(double delta) {
    if (_closing) return;
    _back.stop();
    setState(() => _dy = (_dy + delta).clamp(0.0, double.infinity));
  }

  void _release({double velocity = 0}) {
    if (_closing) return;
    if (_dy > widget.threshold || velocity > 900) {
      _closing = true;
      Navigator.of(context).maybePop();
      return;
    }
    if (_dy == 0) return;
    _from = _dy;
    _back.forward(from: 0);
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || n.depth != 0) return false;
    if (n is OverscrollNotification && n.dragDetails != null && n.overscroll < 0) {
      _drag(-n.overscroll);
    } else if (n is ScrollUpdateNotification && n.dragDetails != null) {
      if (n.metrics.pixels < 0) {
        // Rebond iOS : la liste descend sous zéro, on suit le doigt.
        setState(() => _dy = -n.metrics.pixels);
      } else if (_dy > 0 && (n.scrollDelta ?? 0) > 0) {
        _drag(-(n.scrollDelta ?? 0));
      }
    } else if (n is ScrollEndNotification) {
      _release(velocity: n.dragDetails?.primaryVelocity ?? 0);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (d) => _drag(d.delta.dy),
        onVerticalDragEnd: (d) => _release(velocity: d.primaryVelocity ?? 0),
        onVerticalDragCancel: () => _release(),
        child: Transform.translate(
          offset: Offset(0, _dy * .6),
          child: Opacity(opacity: (1 - _dy / (h * .9)).clamp(.4, 1.0), child: widget.child),
        ),
      ),
    );
  }
}
