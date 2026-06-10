import 'dart:math';
import 'package:flutter/material.dart';

/// Affiche un burst de confettis plein écran (~1.6 s), overlay auto-retiré.
/// Pur Dart (aucune dépendance) — à appeler sur les moments de victoire.
void showConfetti(BuildContext context, {int count = 28}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ConfettiOverlay(count: count, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _Particle {
  final double x0; // position horizontale de départ (0-1)
  final double dx; // dérive horizontale
  final double delay; // 0-0.3
  final double rot;
  final Color color;
  final double size;
  _Particle(this.x0, this.dx, this.delay, this.rot, this.color, this.size);
}

class _ConfettiOverlay extends StatefulWidget {
  final int count;
  final VoidCallback onDone;
  const _ConfettiOverlay({required this.count, required this.onDone});
  @override
  State<_ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<_ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_Particle> _parts;
  static const _colors = [
    Color(0xFFD4A017), Color(0xFF1D9E75), Color(0xFF4A90E2),
    Color(0xFFE24A6B), Color(0xFF9B59B6), Color(0xFFF5A623),
  ];

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _parts = List.generate(widget.count, (_) {
      return _Particle(
        rng.nextDouble(),
        (rng.nextDouble() - 0.5) * 0.4,
        rng.nextDouble() * 0.3,
        rng.nextDouble() * 6.28,
        _colors[rng.nextInt(_colors.length)],
        6 + rng.nextDouble() * 7,
      );
    });
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_parts, _c.value),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> parts;
  final double t; // 0-1
  _ConfettiPainter(this.parts, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in parts) {
      final lt = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (lt <= 0) continue;
      final x = (p.x0 + p.dx * lt) * size.width;
      final y = -20 + lt * (size.height + 40); // tombe du haut vers le bas
      final opacity = (1 - lt).clamp(0.0, 1.0);
      final paint = Paint()..color = p.color.withOpacity(opacity);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rot + lt * 8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
