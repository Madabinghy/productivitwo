import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_font.dart';
import 'package:productivitwo_v1/utils/sniper.dart';
import 'package:productivitwo_v1/utils/sniper_scope.dart';
import 'package:productivitwo_v1/utils/stakes.dart';

/// Les dessins du Sniper (maquette validée 2026-11-20 « Sniper en lunette ») :
/// la lunette du viseur, celle du tir, l'impact, le carton du bilan, le chargeur.
/// Géométrie : `utils/sniper_scope.dart`. Tout est dessiné sur une base de 280.
const kSniperAccent = Color(0xFF7FD3FF);
const kSniperInk = Color(0xFF062130);
const kSniperGreen = Color(0xFF3DDC84);
const _bg = Color(0xFF0A1218);
const _card = Color(0xFF13202A);
const _card2 = Color(0xFF1A2A35);
const _line = Color(0xFF24384A);
const _text2 = Color(0xFFB4C8D4);
const _text3 = Color(0xFF8DA2AF);

/// La couleur d'un enjeu : rose = se perd ce soir, or = palier ou série,
/// vert = la journée, violet = un objectif.
Color sniperGainColor(StakeGain g) {
  if (g.losesTonight) return const Color(0xFFFFB3AB);
  return switch (g.kind) {
    StakeGainKind.tierTonight || StakeGainKind.series || StakeGainKind.reprise || StakeGainKind.reading => const Color(0xFFFFD98A),
    StakeGainKind.halfDay || StakeGainKind.week => const Color(0xFF9FF0C1),
    StakeGainKind.objective || StakeGainKind.session => const Color(0xFFD3C6FF),
    _ => _text2,
  };
}

/// La couleur d'une cible = celle de ce qu'elle sauve de plus lourd (ce qui se
/// perd ce soir passe devant) ; bleu du mode sans enjeu coloré.
Color sniperTargetColor(SniperTarget t) {
  if (t.gains.isEmpty) return kSniperAccent;
  final losing = t.gains.where((g) => g.losesTonight).firstOrNull;
  final top = losing ?? t.gains.reduce((a, b) => b.weight > a.weight ? b : a);
  final c = sniperGainColor(top);
  return c == _text2 ? kSniperAccent : c;
}

Offset _at(Offset c, double r, double deg) {
  final a = (deg - 90) * math.pi / 180;
  return c + Offset(r * math.cos(a), r * math.sin(a));
}

double _rad(double deg) => deg * math.pi / 180;

void _arc(Canvas canvas, Offset c, double r, double start, double sweep, Paint p) =>
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), _rad(start - 90), _rad(sweep), false, p);

void _ticks(Canvas canvas, Offset c, int n, double r0, double r1, Paint p, {int major = 0, double rMajor = 0}) {
  for (var i = 0; i < n; i++) {
    final d = i * 360 / n;
    canvas.drawLine(_at(c, major > 0 && i % major == 0 ? rMajor : r0, d), _at(c, r1, d), p);
  }
}

void _cross(Canvas canvas, Offset c, double r0, double r1, Paint p) {
  for (final d in const [0.0, 90.0, 180.0, 270.0]) {
    canvas.drawLine(_at(c, r0, d), _at(c, r1, d), p);
  }
}

void _lens(Canvas canvas, Offset c, double r, Color color, double alpha) {
  canvas.drawCircle(
    c,
    r,
    Paint()..shader = RadialGradient(colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)),
  );
}

void _label(Canvas canvas, Offset center, String text, double size, Color color, {FontWeight weight = FontWeight.w800}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: TextStyle(fontFamily: kAppFont, fontSize: size, fontWeight: weight, color: color, height: 1)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

/// Un carré qui porte un dessin et, au centre, [child] (les chiffres).
class _Scope extends StatelessWidget {
  final double size;
  final CustomPainter painter;
  final Widget? child;
  final String? label;
  const _Scope({required this.size, required this.painter, this.child, this.label});

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          label: label,
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(painter: painter, child: child == null ? null : Center(child: child)),
          ),
        ),
      );
}

// ── Viseur ─────────────────────────────────────────────────────────────────

/// La lunette du viseur : le tour = le temps libre, un arc par cible.
class SniperAimScope extends StatelessWidget {
  final AimScope scope;
  final List<Color> colors;
  final double size;
  final Widget? child;
  final String? label;

  /// Miniature (tuile du mode d'Aujourd'hui) : arcs épais, ni numéros ni traits de minute.
  final bool mini;

  /// Miniature en train de se recharger : un balayage tourne de 0 à 1 ([reveal]) ; derrière
  /// lui la lunette d'aujourd'hui, devant lui celle d'avant ([oldScope], [oldColors]).
  final double reveal;
  final AimScope? oldScope;
  final List<Color> oldColors;
  const SniperAimScope({
    super.key,
    required this.scope,
    required this.colors,
    this.size = 250,
    this.child,
    this.label,
    this.mini = false,
    this.reveal = 1,
    this.oldScope,
    this.oldColors = const [],
  });

  @override
  Widget build(BuildContext context) =>
      _Scope(size: size, painter: _AimPainter(scope, colors, mini, reveal: reveal, oldScope: oldScope, oldColors: oldColors), label: label, child: child);
}

class _AimPainter extends CustomPainter {
  final AimScope scope;
  final List<Color> colors;
  final bool mini;
  final double reveal;
  final AimScope? oldScope;
  final List<Color> oldColors;
  _AimPainter(this.scope, this.colors, this.mini, {this.reveal = 1, this.oldScope, this.oldColors = const []});

  /// Les arcs et l'air d'une lunette, entre deux angles seulement.
  void _miniRing(Canvas canvas, Offset c, double s, AimScope sc, List<Color> cols, double from, double to) {
    final r = 122 * s;
    for (final a in sc.arcs) {
      final trim = a.sweep > 14 ? 3.5 : 1.0;
      final lo = math.max(a.start + trim, from), hi = math.min(a.end - trim, to);
      if (hi <= lo) continue;
      _arc(canvas, c, r, lo, hi - lo, Paint()
        ..color = a.index < cols.length ? cols[a.index] : kSniperAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 24 * s);
    }
    if (sc.airSweep > 0) {
      final dots = Paint()..color = _text3.withValues(alpha: .8);
      for (var d = sc.airStart + 8; d < sc.airStart + sc.airSweep - 4; d += 12) {
        if (d >= from && d <= to) canvas.drawCircle(_at(c, r, d), 3.6 * s, dots);
      }
    }
  }

  void _paintMini(Canvas canvas, Size size) {
    final s = size.width / 280;
    final c = size.center(Offset.zero);
    final old = oldScope;
    final loading = old != null && reveal < 1;
    final front = loading ? 360 * reveal.clamp(0, 1).toDouble() : 360.0;
    _lens(canvas, c, 104 * s, kSniperAccent, .16);
    final empty = scope.arcs.isEmpty && !(loading && old.arcs.isNotEmpty);
    _cross(canvas, c, 98 * s, empty ? 14 * s : 66 * s, Paint()
      ..color = kSniperAccent.withValues(alpha: .45)
      ..strokeWidth = 3 * s);
    _miniRing(canvas, c, s, scope, colors, 0, front);
    if (loading) {
      _miniRing(canvas, c, s, old, oldColors, front, 360);
      // Le balayage : une traînée qui s'efface derrière un trait clair.
      final rect = Rect.fromCircle(center: c, radius: 136 * s);
      for (var i = 0; i < 5; i++) {
        final back = math.min(front, (i + 1) * 9.0);
        canvas.drawArc(rect, _rad(front - back - 90), _rad(back), true, Paint()..color = kSniperAccent.withValues(alpha: .07));
      }
      canvas.drawLine(_at(c, 20 * s, front), _at(c, 136 * s, front), Paint()
        ..color = Colors.white.withValues(alpha: .9)
        ..strokeWidth = 4 * s
        ..strokeCap = StrokeCap.round);
    }
    // Rien à viser : le réticule seul, avec son point au centre.
    if (empty) canvas.drawCircle(c, 9 * s, Paint()..color = kSniperAccent);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (mini) return _paintMini(canvas, size);
    final s = size.width / 280;
    final c = size.center(Offset.zero);
    _lens(canvas, c, 96 * s, kSniperAccent, .10);
    _ticks(canvas, c, scope.ticks, 84 * s, 91 * s, Paint()
      ..color = _line
      ..strokeWidth = 1.5 * s);
    _cross(canvas, c, 80 * s, 62 * s, Paint()
      ..color = kSniperAccent.withValues(alpha: .35)
      ..strokeWidth = 1.2 * s);
    final r = 104 * s;
    for (final a in scope.arcs) {
      final col = a.index < colors.length ? colors[a.index] : kSniperAccent;
      final trim = a.sweep > 6 ? 1.2 : 0.0;
      _arc(canvas, c, r, a.start + trim, a.sweep - 2 * trim, Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12 * s);
    }
    if (scope.airSweep > 0) {
      final dots = Paint()..color = _text3.withValues(alpha: .75);
      for (var d = scope.airStart + 4; d < scope.airStart + scope.airSweep - 2; d += 5) {
        canvas.drawCircle(_at(c, r, d), 1.4 * s, dots);
      }
    }
    for (final a in scope.arcs) {
      final col = a.index < colors.length ? colors[a.index] : kSniperAccent;
      final p = _at(c, 125 * s, a.mid);
      canvas.drawCircle(p, 9 * s, Paint()..color = _bg);
      canvas.drawCircle(p, 9 * s, Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * s);
      _label(canvas, p, '${a.index + 1}', 10 * s, col);
    }
  }

  @override
  bool shouldRepaint(_AimPainter old) => true;
}

// ── Tir ────────────────────────────────────────────────────────────────────

/// La lunette du tir : l'anneau du temps, les graduations, le réticule et le
/// point des secondes. [progress] null = un geste sans minuteur.
class SniperShotScope extends StatelessWidget {
  final double? progress;

  /// Le minuteur est passé : la lunette vire au vert, le chrono continue.
  final bool over;

  /// Position du point des secondes (degrés), null = à l'arrêt.
  final double? sweepDeg;
  final double size;
  final Widget? child;
  final String? label;
  const SniperShotScope({super.key, this.progress, this.over = false, this.sweepDeg, this.size = 250, this.child, this.label});

  @override
  Widget build(BuildContext context) => _Scope(size: size, painter: _ShotPainter(progress, over, sweepDeg), label: label, child: child);
}

class _ShotPainter extends CustomPainter {
  final double? progress;
  final bool over;
  final double? sweepDeg;
  _ShotPainter(this.progress, this.over, this.sweepDeg);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 280;
    final c = size.center(Offset.zero);
    final col = over ? kSniperGreen : kSniperAccent;
    _ticks(
        canvas,
        c,
        60,
        128 * s,
        133 * s,
        Paint()
          ..color = (over ? kSniperGreen : _text3).withValues(alpha: over ? .5 : .7)
          ..strokeWidth = 1.4 * s,
        major: 5,
        rMajor: 124 * s);
    _lens(canvas, c, 98 * s, col, .13);
    _cross(canvas, c, 98 * s, 64 * s, Paint()
      ..color = col.withValues(alpha: .35)
      ..strokeWidth = 1.2 * s);
    final dot = Paint()..color = col.withValues(alpha: .7);
    for (final q in const [72.0, 80.0, 88.0]) {
      for (final d in const [0.0, 90.0, 180.0, 270.0]) {
        canvas.drawCircle(_at(c, q * s, d), 1.5 * s, dot);
      }
    }
    final r = 108 * s;
    if (progress == null) {
      canvas.drawCircle(c, r, Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * s);
      return;
    }
    canvas.drawCircle(c, r, Paint()
      ..color = _card2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10 * s);
    final sweep = over ? 360.0 : (progress!.clamp(0, 1) * 360).clamp(1.0, 359.5).toDouble();
    final glow = Paint()
      ..color = col.withValues(alpha: .8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10 * s
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 * s);
    final solid = Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10 * s
      ..strokeCap = StrokeCap.round;
    _arc(canvas, c, r, 0, sweep, glow);
    _arc(canvas, c, r, 0, sweep, solid);
    if (!over) canvas.drawCircle(_at(c, r, sweep), 4 * s, Paint()..color = Colors.white);
    if (sweepDeg != null) canvas.drawCircle(_at(c, 118 * s, sweepDeg!), 2.6 * s, Paint()..color = col);
  }

  @override
  bool shouldRepaint(_ShotPainter old) => old.progress != progress || old.over != over || old.sweepDeg != sweepDeg;
}

// ── Impact ─────────────────────────────────────────────────────────────────

/// L'impact : la lunette se referme en vert, un éclat au centre. [t] va de 0 à 1.
class SniperImpactScope extends StatelessWidget {
  final double t;
  final double size;
  const SniperImpactScope({super.key, required this.t, this.size = 250});

  @override
  Widget build(BuildContext context) => _Scope(size: size, painter: _ImpactPainter(t), label: 'Touché');
}

class _ImpactPainter extends CustomPainter {
  final double t;
  _ImpactPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 280;
    final c = size.center(Offset.zero);
    const g = kSniperGreen;
    _ticks(
        canvas,
        c,
        60,
        128 * s,
        133 * s,
        Paint()
          ..color = g.withValues(alpha: .45)
          ..strokeWidth = 1.4 * s,
        major: 5,
        rMajor: 124 * s);
    _lens(canvas, c, 98 * s, g, .20);
    _cross(canvas, c, 98 * s, 46 * s, Paint()
      ..color = g.withValues(alpha: .45)
      ..strokeWidth = 1.2 * s);
    // La lunette se referme sur la cible.
    final close = Curves.easeOutCubic.transform((t / .22).clamp(0, 1).toDouble());
    final r = (122 - 14 * close) * s;
    canvas.drawCircle(c, r, Paint()
      ..color = g.withValues(alpha: .8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10 * s
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 9 * s));
    canvas.drawCircle(c, r, Paint()
      ..color = g
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10 * s);
    // L'onde part du centre et s'efface.
    final wave = (t / .6).clamp(0, 1).toDouble();
    if (wave < 1) {
      canvas.drawCircle(c, 30 * s * (.25 + 2.35 * wave), Paint()
        ..color = g.withValues(alpha: .9 * (1 - wave))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * s);
    }
    final pop = .3 + .7 * Curves.easeOutBack.transform((t / .25).clamp(0, 1).toDouble());
    final burst = Paint()
      ..color = g
      ..strokeWidth = 3 * s
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      canvas.drawLine(_at(c, 15 * s * pop, i * 30), _at(c, (i.isOdd ? 27 : 36) * s * pop, i * 30), burst);
    }
    canvas.drawCircle(c, 8 * s * pop, Paint()..color = g);
    canvas.drawCircle(c, 3 * s * pop, Paint()..color = _bg);
  }

  @override
  bool shouldRepaint(_ImpactPainter old) => old.t != t;
}

// ── Carton ─────────────────────────────────────────────────────────────────

/// Le carton de tir du bilan : un impact par cible touchée, au centre = pile
/// le temps visé.
class SniperShotCard extends StatelessWidget {
  final List<CardImpact> impacts;
  final double size;
  const SniperShotCard({super.key, required this.impacts, this.size = 230});

  @override
  Widget build(BuildContext context) {
    final off = impacts.where((i) => i.gapMin != 0).length;
    return _Scope(
      size: size,
      painter: _CardPainter(impacts),
      label: 'Carton de tir : ${impacts.length} impact${impacts.length > 1 ? 's' : ''}, ${impacts.length - off} au centre',
    );
  }
}

class _CardPainter extends CustomPainter {
  final List<CardImpact> impacts;
  _CardPainter(this.impacts);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 280;
    final c = size.center(Offset.zero);
    const edge = 118.0;
    final stroke = Paint()
      ..color = _line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * s;
    final rings = kCardRings.reversed.toList();
    for (var i = 0; i < rings.length; i++) {
      final r = edge * rings[i].$2 * s;
      canvas.drawCircle(c, r, Paint()..color = i.isOdd ? _card2 : _card);
      canvas.drawCircle(c, r, stroke);
      _label(canvas, c - Offset(0, r - 10 * s), '±${rings[i].$1} min', 9.5 * s, _text3, weight: FontWeight.w700);
    }
    final bull = edge * kCardBull * s;
    canvas.drawCircle(c, bull, Paint()..color = Color.lerp(_bg, kSniperAccent, .22)!);
    canvas.drawCircle(c, bull, Paint()
      ..color = kSniperAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * s);
    _cross(canvas, c, edge * s, bull + 2 * s, Paint()
      ..color = _text3.withValues(alpha: .3)
      ..strokeWidth = 1.2 * s);
    final rad = (impacts.length > 5 ? 6.5 : 8) * s;
    for (final i in impacts) {
      final p = _at(c, edge * i.radius * s, i.angle);
      canvas.drawCircle(p, rad + 1.5 * s, Paint()..color = _bg);
      if (i.mini) {
        canvas.drawCircle(p, rad, Paint()
          ..color = kSniperAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 * s);
      } else {
        canvas.drawCircle(p, rad, Paint()..color = kSniperAccent);
      }
      _label(canvas, p, '${i.number}', (impacts.length > 5 ? 8 : 9.5) * s, i.mini ? kSniperAccent : kSniperInk);
    }
  }

  @override
  bool shouldRepaint(_CardPainter old) => true;
}

// ── Chargeur ───────────────────────────────────────────────────────────────

enum MagRound { done, current, skipped, todo }

/// Les tirs d'une session gardée sur l'appareil (`PendingRun.extra` : `aimed`, `hit`,
/// `skipped`, `cur`), dans l'ordre : touché, passé, en cours (le tir laissé en route, sinon
/// le prochain à tirer), à venir. Vide quand la session n'a pas encore de cibles.
List<MagRound> sniperRounds(Map<String, dynamic> extra) {
  List<String> strings(dynamic v) => v is List ? [for (final x in v) '$x'] : const [];
  final aimed = strings(extra['aimed']);
  final hit = strings(extra['hit']).toSet(), skipped = strings(extra['skipped']).toSet();
  final cur = extra['cur'];
  final next = cur is String && aimed.contains(cur) ? cur : aimed.where((k) => !hit.contains(k) && !skipped.contains(k)).firstOrNull;
  return [
    for (final k in aimed)
      hit.contains(k)
          ? MagRound.done
          : skipped.contains(k)
              ? MagRound.skipped
              : k == next
                  ? MagRound.current
                  : MagRound.todo,
  ];
}

/// Le chargeur : un tir par cartouche (faits en vert, en cours allumé).
class SniperMagazine extends StatelessWidget {
  final List<MagRound> rounds;
  const SniperMagazine({super.key, required this.rounds});

  @override
  Widget build(BuildContext context) {
    final done = rounds.where((r) => r == MagRound.done).length;
    return Semantics(
      label: 'Chargeur : $done tir${done > 1 ? 's' : ''} fait${done > 1 ? 's' : ''} sur ${rounds.length}',
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final r in rounds)
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 36),
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(2), right: Radius.circular(8)),
                color: switch (r) { MagRound.done => kSniperGreen, MagRound.current => kSniperAccent, MagRound.skipped => _line, MagRound.todo => _card2 },
                border: Border.all(color: switch (r) { MagRound.done => kSniperGreen, MagRound.current => kSniperAccent, _ => _line }),
                boxShadow: r == MagRound.current ? [BoxShadow(color: kSniperAccent.withValues(alpha: .8), blurRadius: 10)] : null,
              ),
            ),
          ),
      ]),
    );
  }
}

/// La petite cible devant un enjeu.
class SniperTargetDot extends StatelessWidget {
  final Color color;
  final double size;
  const SniperTargetDot({super.key, required this.color, this.size = 10});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 1.2)),
        child: Container(width: size * .36, height: size * .36, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      );
}

// ── Tuile du mode ──────────────────────────────────────────────────────────

/// La tuile Sniper d'Aujourd'hui (2026-11-20, demande user : la miniature du
/// viseur à la place de l'icône, comme la jauge des 7 jours) : la lunette seule
/// — le tour = le temps libre, un arc par cible — et les minutes visées au
/// centre. Le détail reste en infobulle et pour la lecture d'écran. Pendant une
/// session ([session], la feuille refermée en cours de route) : un arc par cible
/// visée — touchées en vert, celle en cours en bleu, les suivantes éteintes — et
/// « touchées / visées » au centre.
class SniperModeTile extends StatefulWidget {
  final SniperPlan plan;

  /// Temps libre (minutes) jusqu'au prochain bloc.
  final int freeMin;
  final String label;

  /// Une session Sniper attend d'être reprise.
  final bool pending;

  /// Les tirs de la session en cours, dans l'ordre (null = pas de session : le viseur).
  final List<MagRound>? session;

  /// La minute où le temps libre s'arrête (le prochain bloc, la fin de la journée) ; null = pas de borne
  /// fixe. Quand elle bouge (un bloc déplacé, retiré, ajouté), la lunette se recharge.
  final int? until;

  /// Sniper préparé, pas encore lancé : [session] porte ses cibles, la tuile dit « n prêtes ».
  final bool ready;
  final VoidCallback onTap;
  const SniperModeTile(
      {super.key, required this.plan, required this.freeMin, required this.label, required this.onTap, this.pending = false, this.session, this.until, this.ready = false});

  @override
  State<SniperModeTile> createState() => _SniperModeTileState();
}

/// Ce que la tuile montre à un instant : la lunette, ses couleurs, et le centre
/// (des minutes qui peuvent glisser, ou un texte).
class _TileFace {
  final AimScope scope;
  final List<Color> colors;
  final String sig;
  final int? total;
  final String? text;

  /// Le mot sous [text] : « touchées » pendant une session, « prêtes » pour un Sniper préparé.
  final String sub;
  final Color subColor;
  const _TileFace({required this.scope, required this.colors, required this.sig, this.total, this.text, this.sub = 'touchées', this.subColor = kSniperGreen});

  factory _TileFace.of(SniperModeTile w) {
    final rounds = w.session;
    if (w.ready && rounds != null && rounds.isNotEmpty) {
      final n = rounds.length;
      return _TileFace(
        scope: aimScope(costs: List.filled(n, 1), freeMin: n),
        colors: List.filled(n, kSniperAccent),
        sig: 'ready:$n',
        text: '$n',
        sub: n > 1 ? 'prêtes' : 'prête',
        subColor: kSniperAccent,
      );
    }
    if (rounds != null && rounds.isNotEmpty) {
      final done = rounds.where((r) => r == MagRound.done).length;
      return _TileFace(
        scope: aimScope(costs: List.filled(rounds.length, 1), freeMin: rounds.length),
        colors: [
          for (final r in rounds)
            switch (r) {
              MagRound.done => kSniperGreen,
              MagRound.current => kSniperAccent,
              MagRound.skipped => _line,
              MagRound.todo => kSniperAccent.withValues(alpha: .28),
            },
        ],
        sig: 'session:${rounds.map((r) => r.index).join()}',
        text: '$done/${rounds.length}',
      );
    }
    final p = w.plan;
    return _TileFace(
      scope: aimScope(costs: [for (final t in p.aimed) t.cost], freeMin: w.freeMin, pauseMin: p.pauseMin),
      colors: [for (final t in p.aimed) sniperTargetColor(t)],
      sig: '${[for (final t in p.aimed) '${t.key}:${t.amount}'].join('|')}@${w.until ?? ''}',
      total: p.aimed.isEmpty ? null : p.totalMin,
    );
  }
}

/// Quand les cibles changent (une routine validée, un chrono arrêté, un bloc fait, une cible
/// touchée), la lunette se recharge sous les yeux (2026-11-20, demande user) : un balayage
/// fait le tour en [kSniperReload], l'ancienne lunette devant lui, la nouvelle derrière, et
/// les minutes du centre glissent de l'ancien total au nouveau. Le premier dessin est en
/// place ; une minute qui passe (le temps libre qui rétrécit) ne relance rien.
///
/// Elle se recharge aussi quand la borne du temps libre bouge ([SniperModeTile.until] : un bloc
/// déplacé pour se donner de l'air, demande user 2026-11-21). Un changement arrivé pendant que la
/// tuile est cachée par une feuille (le Programme où l'on déplace le bloc) attend le retour : le
/// balayage part quand on la revoit.
class _SniperModeTileState extends State<SniperModeTile> with SingleTickerProviderStateMixin {
  late final AnimationController _reload;
  _TileFace? _old;

  /// Ce que la tuile montrait avant un changement arrivé sous une feuille.
  _TileFace? _waiting;

  bool get _covered => !(ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    _reload = AnimationController(vsync: this, duration: kSniperReload, value: 1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final before = _waiting;
    if (before == null || _covered) return;
    _waiting = null;
    if (before.sig != _TileFace.of(widget).sig) _play(before);
  }

  @override
  void didUpdateWidget(SniperModeTile old) {
    super.didUpdateWidget(old);
    final before = _TileFace.of(old);
    if (before.sig == _TileFace.of(widget).sig) return;
    if (_covered) {
      _waiting ??= before;
      return;
    }
    _play(before);
  }

  void _play(_TileFace before) {
    _old = before;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _reload.value = 1;
    } else {
      _reload.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  Widget _minutes(int total) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(total < 100 ? '$total' : '${total ~/ 60}h${(total % 60).toString().padLeft(2, '0')}',
            style: TextStyle(
                fontFamily: kAppFont,
                fontSize: total < 100 ? 22 : 15,
                height: 1,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()])),
        if (total < 100) Text('min', style: TextStyle(fontFamily: kAppFont, fontSize: 9.5, height: 1.2, fontWeight: FontWeight.w700, color: _text2)),
      ]);

  Widget _session(String text, {String sub = 'touchées', Color subColor = kSniperGreen}) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(text,
            key: const Key('mode-tile-session'),
            style: TextStyle(fontFamily: kAppFont, fontSize: 19, height: 1, fontWeight: FontWeight.w800, color: Colors.white, fontFeatures: const [FontFeature.tabularFigures()])),
        Text(sub, style: TextStyle(fontFamily: kAppFont, fontSize: 8.5, height: 1.3, fontWeight: FontWeight.w700, color: subColor)),
      ]);

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final face = _TileFace.of(widget);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          key: const Key('mode-tile'),
          color: _bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: kSniperAccent.withValues(alpha: .6), width: 1.5)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: widget.onTap,
            child: Stack(children: [
              Center(
                child: ExcludeSemantics(
                  child: AnimatedBuilder(
                    animation: _reload,
                    builder: (context, _) {
                      final old = _old;
                      final loading = _reload.value < 1 && old != null;
                      final t = Curves.easeInOutCubic.transform(_reload.value);
                      // Les minutes glissent d'un total à l'autre (vers zéro quand tout est tombé).
                      final from = old?.total ?? 0, to = face.total ?? 0;
                      final Widget? center = face.text != null
                          ? _session(face.text!, sub: face.sub, subColor: face.subColor)
                          : loading && (old.total != null || face.total != null) && old.text == null
                              ? _minutes((from + (to - from) * t).round())
                              : face.total == null
                                  ? null
                                  : _minutes(face.total!);
                      return SniperAimScope(
                        key: const Key('mode-tile-scope'),
                        mini: true,
                        size: 88,
                        scope: face.scope,
                        colors: face.colors,
                        reveal: loading ? t : 1,
                        oldScope: loading ? old.scope : null,
                        oldColors: old?.colors ?? const [],
                        child: center,
                      );
                    },
                  ),
                ),
              ),
              if (widget.pending)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(width: 11, height: 11, decoration: BoxDecoration(color: kSniperAccent, shape: BoxShape.circle, border: Border.all(color: _bg, width: 2))),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
