import 'package:flutter/material.dart';

/// Pulsation douce en boucle (scale) — attire l'œil sur une action « à faire
/// maintenant » (cœur exposé, CTA d'achèvement). Pur game-feel, réutilisable
/// mobile + web. Quand [active] est faux, l'enfant est rendu tel quel.
class PulseScale extends StatefulWidget {
  final Widget child;
  final double minScale;
  final double maxScale;
  final Duration period;
  final bool active;
  const PulseScale({
    super.key,
    required this.child,
    this.minScale = 1.0,
    this.maxScale = 1.07,
    this.period = const Duration(milliseconds: 900),
    this.active = true,
  });

  @override
  State<PulseScale> createState() => _PulseScaleState();
}

class _PulseScaleState extends State<PulseScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period);

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PulseScale old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return ScaleTransition(
      scale: Tween<double>(begin: widget.minScale, end: widget.maxScale)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}
