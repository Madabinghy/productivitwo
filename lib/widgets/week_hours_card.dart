import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/leisure.dart' show leisureActivityIds;
import 'package:productivitwo_v1/utils/week_hours.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart' show kBSurface;
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche, FicheHeader, FicheTitle;

/// Les 168 dernières heures en compteur (maquette validée 2026-11-11) : carte en tête d'Organisation, feuille en grand au tap.
/// Redessiné le 2026-11-18 (maquette « Couleurs de la jauge », choix user) : palette plus vive, temps libre en tirets,
/// une graduation par jour, et « le socle d'abord » : besoins → sommeil → détente → actif.
/// Aiguille et repère (maquette validée 2026-11-19) : l'aiguille suit ce qui tourne maintenant, le triangle blanc
/// dit ce qui tournait il y a 7 jours à la même minute.
/// L'aiguille qui redescend (maquette validée 2026-11-19, demande user) : sans chrono, l'aiguille quitte les tirets et
/// se pose DANS le vert, là où il s'arrêtera demain à la même heure si rien n'est fait ; le bout du vert qui la
/// dépasse est hachuré (ce qui sort de la fenêtre d'ici là).
/// L'aiguille suit ce que tu fais (maquette validée 2026-11-20) : chrono actif = elle montre demain à fond.
const kHoursActive = Color(0xFF3DDC84);
const kHoursActiveHi = Color(0xFFB4F7D0);
const kHoursLeisure = Color(0xFFF08BC0);
const kHoursBasic = Color(0xFFFFD479);
const kHoursSleep = Color(0xFF6F92F2);
const kHoursFree = Color(0xFF7FF0D6);
const kHoursLoss = Color(0xFFF5B041);
const _kHatchBase = Color(0xFF0F2A1E);

Color hoursKindColor(HoursKind k) => switch (k) {
      HoursKind.active => kHoursActive,
      HoursKind.leisure => kHoursLeisure,
      HoursKind.basic => kHoursBasic,
      HoursKind.sleep => kHoursSleep,
      HoursKind.free => kHoursFree,
    };

String hoursLabel(int min) => '${(min / 60).round()} h';

String _deltaLabel(int min) {
  final h = (min / 60).round();
  return h == 0 ? 'comme les 7 jours d\'avant' : '${h > 0 ? '+' : '−'}${h.abs()} h sur les 7 jours d\'avant';
}

/// Le compteur : arc de 240° (les 168 h). Le socle d'abord (choix user 2026-11-18) : besoins de base (ils remplissent
/// le bout arrondi du départ) → sommeil → détente, puis l'actif, puis le temps libre en tirets. L'actif touche le
/// temps libre, dans lequel il grandit. Le filet intérieur, sous le vert = les heures actives des 7 jours d'avant
/// ([showPrev]).
///
/// L'aiguille suit ce que tu fais (maquette validée 2026-11-20, variante A) : sommeil, détente, besoins de base →
/// au bout du morceau en cours, qui s'éclaire ; sans chrono → elle recule dans le vert, là où il s'arrêtera demain
/// à la même heure si rien n'est fait ([GaugeLayout.idleAt]), le bout du vert qui la dépasse est hachuré ; chrono
/// ACTIF → elle passe de l'autre côté, là où le vert arrivera demain à fond ([GaugeLayout.fullAt], 24 h sans
/// arrêt). La bande vert clair après le vert, fermée par un trait, est ce plafond. Le triangle blanc se pose de la
/// même façon sur ce qui tournait il y a 7 jours : alignés = tu fais pareil.
///
/// Changer de cible prend deux minutes ([kNeedleTravel], demande user : une minute d'abord, deux depuis le
/// 2026-11-20) : l'aiguille glisse vers sa nouvelle place.
const kNeedleTravel = Duration(seconds: 120);

class WeekHoursGauge extends StatefulWidget {
  final WeekHours h;
  final double size;
  final bool showPrev;
  const WeekHoursGauge({super.key, required this.h, required this.size, this.showPrev = true});

  @override
  State<WeekHoursGauge> createState() => _WeekHoursGaugeState();
}

/// L'aiguille est la MÊME partout (demande user 2026-11-20 : la tuile d'Aujourd'hui, la feuille qu'elle ouvre et la
/// carte d'Organisation montraient chacune la leur — la feuille s'ouvrait aiguille déjà arrivée pendant que celle de
/// la tuile glissait encore). Le trajet est daté sur l'horloge des images : une jauge qui s'ouvre ou revient à
/// l'écran en cours de route reprend l'aiguille là où elle en est. La première jauge affichée est en place, sans
/// glissement ; plus aucune jauge à l'écran = on oublie tout.
class HoursNeedle {
  HoursNeedle._();

  static int _gauges = 0;
  static double _from = 0, _to = 0;

  /// Début du trajet en cours, null = l'aiguille est en place.
  static Duration? _start;
  static final _moves = _Bell();

  /// En dessous, la cible a seulement dérivé (une minute de plus) : l'aiguille suit sans repartir pour deux minutes.
  static const _drift = 2 * math.pi / 180;

  // L'heure de la dernière image (elle reste lisible entre deux images, au contraire de `currentFrameTimeStamp`).
  static Duration get _clock => SchedulerBinding.instance.currentSystemFrameTimeStamp;

  static double get _t {
    final s = _start;
    if (s == null) return 1;
    return ((_clock - s).inMicroseconds / kNeedleTravel.inMicroseconds).clamp(0.0, 1.0);
  }

  static bool get moving => _start != null && _t < 1;

  /// Où est l'aiguille en ce moment.
  static double get angle => _from + (_to - _from) * Curves.easeInOutCubic.transform(_t);

  /// Redessine les jauges quand l'aiguille bouge.
  static Listenable get moves => _moves;

  static void _attach(double target, {required bool still}) {
    _gauges++;
    if (_gauges == 1) {
      _from = _to = target;
      _start = null;
      return;
    }
    aim(target, still: still);
  }

  static void _detach() {
    _gauges--;
    if (_gauges > 0) return;
    _gauges = 0;
    _start = null;
  }

  /// Nouvelle cible. [still] = animations coupées : tout de suite en place.
  static void aim(double target, {bool still = false}) {
    if (target == _to) return;
    if (still || (target - _to).abs() < _drift) {
      if (moving && !still) {
        _to = target;
      } else {
        _from = _to = target;
        _start = null;
      }
    } else {
      _from = angle;
      _to = target;
      _start = _clock;
    }
    _moves.ring();
  }
}

class _Bell extends ChangeNotifier {
  void ring() => notifyListeners();
}

class _WeekHoursGaugeState extends State<WeekHoursGauge> with SingleTickerProviderStateMixin {
  // Le battement de CETTE jauge : coupé quand son onglet est caché, il ne sert qu'à redessiner pendant le trajet.
  late final Ticker _beat;
  late GaugeLayout _layout = gaugeLayout(widget.h);
  bool _attached = false;

  double get _target => _layout.marks[widget.h.nowKind]!;
  bool get _still => MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _beat = createTicker((_) {
      HoursNeedle._moves.ring();
      if (!HoursNeedle.moving) _beat.stop();
    });
    HoursNeedle._moves.addListener(_follow);
  }

  void _follow() {
    if (HoursNeedle.moving && !_beat.isActive) _beat.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_attached) return;
    _attached = true;
    HoursNeedle._attach(_target, still: _still);
    _follow();
  }

  @override
  void didUpdateWidget(covariant WeekHoursGauge old) {
    super.didUpdateWidget(old);
    _layout = gaugeLayout(widget.h);
    HoursNeedle.aim(_target, still: _still);
  }

  @override
  void dispose() {
    HoursNeedle._moves.removeListener(_follow);
    _beat.dispose();
    if (_attached) HoursNeedle._detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size(widget.size, widget.size * .76),
      painter: _GaugePainter(widget.h, _layout,
          track: cs.onSurface.withValues(alpha: .09), needle: cs.onSurface, hole: cs.surface, showPrev: widget.showPrev),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final WeekHours h;
  final GaugeLayout g;
  final Color track, needle, hole;
  final bool showPrev;
  _GaugePainter(this.h, this.g, {required this.track, required this.needle, required this.hole, required this.showPrev})
      : super(repaint: HoursNeedle.moves);

  /// Où est l'aiguille en ce moment (elle glisse vers `g.marks[h.nowKind]`) : la même pour toutes les jauges.
  double get needleAt => HoursNeedle.angle;

  static const _start = kGaugeStart;
  static const _sweep = kGaugeSweep;
  static const _deg = math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final stroke = w * .067;
    final r = w * .358;
    final c = Offset(w / 2, w * .467);
    final rect = Rect.fromCircle(center: c, radius: r);
    Offset at(double radius, double a) => c + Offset(math.cos(a), math.sin(a)) * radius;
    Paint band(Color col) => Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // Une graduation par jour : 168 h = 7 traits de 24 h.
    for (var d = 0; d <= 7; d++) {
      final a = _start + _sweep * d / 7;
      final edge = d == 0 || d == 7;
      canvas.drawLine(
          at(r + stroke / 2 + w * .015, a),
          at(r + stroke / 2 + w * (edge ? .042 : .032), a),
          Paint()
            ..color = needle.withValues(alpha: edge ? .7 : .35)
            ..strokeWidth = math.max(1, w * .008));
    }
    canvas.drawArc(rect, _start, _sweep, false, band(track)..strokeCap = StrokeCap.round);

    Paint glow(Color col) => band(col.withValues(alpha: .45))..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * .55);
    var first = true;
    for (final arc in g.arcs) {
      final col = hoursKindColor(arc.kind);
      // Le morceau en cours s'éclaire.
      if (h.nowKind == arc.kind) canvas.drawArc(rect, arc.start, arc.len, false, glow(col));
      if (first) {
        // Le premier morceau remplit le bout arrondi du départ.
        canvas.drawArc(rect, arc.start, .2 * _deg, false, band(col)..strokeCap = StrokeCap.round);
        first = false;
      }
      if (arc.kind == HoursKind.active) {
        canvas.drawArc(rect, arc.start, arc.len, false,
            band(kHoursActive)..shader = const LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [kHoursActive, kHoursActiveHi]).createShader(rect));
      } else {
        canvas.drawArc(rect, arc.start, arc.len, false, band(col));
      }
    }
    final end = g.end;
    final idle = h.nowKind == HoursKind.free;
    final working = h.nowKind == HoursKind.active;
    // Ce qui sort d'ici demain si rien : hachuré (sans chrono, et pendant un chrono actif : c'est ce qu'il rattrape).
    if ((idle || working) && h.leavingMin > 0 && g.activeLen > 0) {
      final from = g.idleAt, to = g.activeEnd;
      canvas.drawArc(rect, from, to - from, false, band(_kHatchBase));
      final px = math.max(1.3, w * .0085);
      final step = px / r;
      final stripe = band(kHoursActive.withValues(alpha: .8));
      for (var d = from + step; d < to - .001; d += step * 2) {
        canvas.drawArc(rect, d, math.min(step, to - d), false, stripe);
      }
    }

    // Demain à fond : la bande claire après le vert, fermée par un trait. Elle s'allume quand un chrono actif tourne.
    final ghostFrom = g.activeLen > 0 ? g.activeEnd + .4 * _deg : g.trackedEnd;
    final ghost = g.fullAt - ghostFrom > .6 * _deg;
    if (ghost) {
      canvas.drawArc(rect, ghostFrom, g.fullAt - ghostFrom, false, band(kHoursActive.withValues(alpha: working ? .62 : .32)));
    }

    // Le temps libre : des tirets, des cases à remplir.
    const dash = 4.3 * _deg, space = 3.4 * _deg;
    final free = band(kHoursFree.withValues(alpha: .85));
    for (var d = math.max(g.trackedEnd, ghost ? g.fullAt : 0) + _deg; d < end - .002; d += dash + space) {
      canvas.drawArc(rect, d, math.min(dash, end - d), false, free);
    }
    if (ghost) {
      canvas.drawLine(
          at(r - stroke / 2 - w * .012, g.fullAt),
          at(r + stroke / 2 + w * .012, g.fullAt),
          Paint()
            ..color = kHoursActiveHi
            ..strokeWidth = math.max(1.6, w * .011)
            ..strokeCap = StrokeCap.round);
    }

    if (showPrev && h.prevActiveMin > 0) {
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r - stroke / 2 - w * .027),
          g.activeStart,
          math.min(_sweep * h.prevActiveMin / kWeekHoursMin, end - g.activeStart),
          false,
          Paint()
            ..color = needle.withValues(alpha: .42)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.2, w * .0125)
            ..strokeCap = StrokeCap.round);
    }

    // Le triangle blanc, au-dessus du cadran : ce qui tournait il y a 7 jours à la même minute.
    final pa = g.marks[h.pastKind]!;
    final t0 = at(r + stroke / 2 + w * .008, pa), tb = at(r + stroke / 2 + w * .05, pa);
    final side = Offset(math.cos(pa + math.pi / 2), math.sin(pa + math.pi / 2)) * (w * .023);
    canvas.drawPath(
        Path()
          ..moveTo(t0.dx, t0.dy)
          ..lineTo(tb.dx + side.dx, tb.dy + side.dy)
          ..lineTo(tb.dx - side.dx, tb.dy - side.dy)
          ..close(),
        Paint()..color = needle);

    // L'aiguille, effilée. Sans chrono ou en actif, elle montre demain : elle traverse la bande.
    final na = needleAt;
    final tip = at(idle || working ? r + stroke / 2 + w * .004 : r - w * .008, na);
    final b1 = at(w * .022, na + math.pi / 2), b2 = at(w * .022, na - math.pi / 2);
    canvas.drawPath(
        Path()
          ..moveTo(b1.dx, b1.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(b2.dx, b2.dy)
          ..close(),
        Paint()..color = needle);
    canvas.drawCircle(c, w * .042, Paint()..color = hole);
    canvas.drawCircle(
        c,
        w * .042,
        Paint()
          ..color = needle
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.8, w * .015));
    canvas.drawCircle(c, w * .018, Paint()..color = hoursKindColor(h.nowKind));
  }

  @override
  bool shouldRepaint(covariant _GaugePainter o) =>
      o.h.activeMin != h.activeMin ||
      o.h.leisureMin != h.leisureMin ||
      o.h.basicMin != h.basicMin ||
      o.h.sleepMin != h.sleepMin ||
      o.h.prevActiveMin != h.prevActiveMin ||
      o.h.leavingMin != h.leavingMin ||
      o.h.nowKind != h.nowKind ||
      o.h.pastKind != h.pastKind ||
      o.track != track ||
      o.needle != needle;
}

/// Carte compacte en tête d'Organisation.
class WeekHoursCard extends StatelessWidget {
  final AppLogic logic;
  final WeekHours hours;
  const WeekHoursCard({super.key, required this.logic, required this.hours});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    final h = hours;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: .35),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: const ValueKey('week-hours-card'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => showWeekHoursSheet(context, logic),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: kHoursActive.withValues(alpha: .45), width: 1.5)),
          child: Column(children: [
            Row(children: [
              WeekHoursGauge(h: h, size: 112),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('TES 7 DERNIERS JOURS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: mute)),
                  const SizedBox(height: 2),
                  Text.rich(TextSpan(children: [
                    TextSpan(text: spanLabel(h.activeMin), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kHoursActive)),
                    TextSpan(text: ' actives', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: mute)),
                  ])),
                  // Le reste du cadran, dans son ordre et à ses couleurs.
                  Wrap(spacing: 10, runSpacing: 1, children: [
                    if (h.basicMin > 0) _part('week-hours-basic', '${spanLabel(h.basicMin)} de besoins', kHoursBasic),
                    if (h.sleepMin > 0) _part('week-hours-sleep', '${spanLabel(h.sleepMin)} de sommeil', kHoursSleep),
                    if (h.leisureMin > 0) _part('week-hours-leisure', '${spanLabel(h.leisureMin)} de détente', kHoursLeisure),
                    if (h.untrackedMin > 0) _part('week-hours-free', '${spanLabel(h.untrackedMin)} libres', kHoursFree),
                  ]),
                  const SizedBox(height: 2),
                  Text('${hoursLabel(h.trackedMin)} / 168 h tracées', style: TextStyle(fontSize: 12.5, color: mute)),
                  Text(_deltaLabel(h.deltaMin), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: h.deltaMin >= 0 ? kHoursActive : const Color(0xFFF5B041))),
                ]),
              ),
            ]),
            // Le cadran est petit : ce que montrent l'aiguille et le triangle, en clair.
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Divider(height: 1, thickness: 1, color: cs.onSurface.withValues(alpha: .1)),
            ),
            const SizedBox(height: 8),
            // « Il y a 7 jours » juste sous « Maintenant » (demande user 2026-11-20) : les deux se comparent,
            // les deux projections de demain viennent ensuite.
            HoursMomentLine(h: h, now: true, labelWidth: 96, key: const ValueKey('week-hours-now')),
            const SizedBox(height: 3),
            HoursMomentLine(h: h, now: false, labelWidth: 96, key: const ValueKey('week-hours-past')),
            if (hoursShowsTomorrow(h)) ...[
              const SizedBox(height: 3),
              HoursTomorrowLine(h: h, labelWidth: 96, key: const ValueKey('week-hours-tomorrow')),
              const SizedBox(height: 3),
              HoursTomorrowLine(h: h, full: true, labelWidth: 96, key: const ValueKey('week-hours-full')),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _part(String key, String text, Color color) => Text(text, key: ValueKey(key), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color));
}

/// La jauge seule, en tuile carrée d'Aujourd'hui (à droite de Programme, demande user 2026-11-19) : l'aiguille dit ce
/// qui tourne (sans chrono : où sera le vert demain si rien), le triangle ce qui tournait il y a 7 jours ; tap = la
/// feuille en grand.
class WeekHoursTile extends StatelessWidget {
  final AppLogic logic;
  final WeekHours hours;
  const WeekHoursTile({super.key, required this.logic, required this.hours});

  @override
  Widget build(BuildContext context) {
    final h = hours;
    final label = 'Tes 7 derniers jours · ${spanLabel(h.activeMin)} actives · maintenant : ${hoursMomentLabel(h.nowKind, h.nowName, now: true)}'
        '${hoursShowsTomorrow(h) ? ' · demain si rien : ${hoursTomorrowLabel(h)} · demain à fond : ${hoursFullLabel(h)}' : ''}'
        ' · il y a 7 jours : ${hoursMomentLabel(h.pastKind, h.pastName)}';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          key: const Key('hours-tile'),
          color: kBSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: kHoursActive.withValues(alpha: .45), width: 1.5)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => showWeekHoursSheet(context, logic),
            child: Center(child: ExcludeSemantics(child: WeekHoursGauge(h: h, size: 90))),
          ),
        ),
      ),
    );
  }
}

/// « Maintenant · ● Détente · Jeux vidéo » (le point de l'aiguille) ou « Il y a 7 jours · ▼ Actif · Coder » (le triangle).
class HoursMomentLine extends StatelessWidget {
  final WeekHours h;
  final bool now;
  final double labelWidth;
  const HoursMomentLine({super.key, required this.h, required this.now, required this.labelWidth});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kind = now ? h.nowKind : h.pastKind;
    final col = hoursKindColor(kind);
    return Row(children: [
      SizedBox(width: labelWidth, child: Text(now ? 'Maintenant' : 'Il y a 7 jours', style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .6)))),
      SizedBox(
        width: 16,
        child: now
            ? Align(alignment: Alignment.centerLeft, child: Container(width: 9, height: 9, decoration: BoxDecoration(color: col, shape: BoxShape.circle)))
            : Align(alignment: Alignment.centerLeft, child: CustomPaint(size: const Size(10, 8), painter: _TrianglePainter(cs.onSurface))),
      ),
      Expanded(
        child: Text(hoursMomentLabel(kind, now ? h.nowName : h.pastName, now: now),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: col)),
      ),
    ]);
  }
}

/// Les deux lignes de demain s'affichent quand l'aiguille parle de demain : sans chrono, ou pendant un chrono actif.
bool hoursShowsTomorrow(WeekHours h) => h.nowKind == HoursKind.free || h.nowKind == HoursKind.active;

/// « Demain si rien · ↘ 55 h · −12 h 27 » (où va l'aiguille sans chrono) ou, [full], « Demain à fond · ↗ 79 h ·
/// +11 h 33 » (où elle va pendant un chrono actif).
class HoursTomorrowLine extends StatelessWidget {
  final WeekHours h;
  final bool full;
  final double labelWidth;
  const HoursTomorrowLine({super.key, required this.h, required this.labelWidth, this.full = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final col = full || h.leavingMin <= 0 ? kHoursActive : kHoursLoss;
    final icon = full ? Icons.north_east_rounded : (h.leavingMin > 0 ? Icons.south_east_rounded : Icons.east_rounded);
    return Row(children: [
      SizedBox(width: labelWidth, child: Text(full ? 'Demain à fond' : 'Demain si rien', style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .6)))),
      SizedBox(width: 16, child: Align(alignment: Alignment.centerLeft, child: Icon(icon, size: 12, color: col))),
      Expanded(
        child: Text(full ? hoursFullLabel(h) : hoursTomorrowLabel(h),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: col)),
      ),
    ]);
  }
}

/// Le triangle du cadran, en petit, pointe en bas.
class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      Paint()..color = color);

  @override
  bool shouldRepaint(covariant _TrianglePainter o) => o.color != color;
}

const _dayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
const _dayNames = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

Future<void> showWeekHoursSheet(BuildContext context, AppLogic logic) {
  return showFiche<void>(context, builder: (ctx, scroll) => _WeekHoursSheet(logic: logic, scroll: scroll));
}

class _WeekHoursSheet extends StatelessWidget {
  final AppLogic logic;
  final ScrollController scroll;
  const _WeekHoursSheet({required this.logic, required this.scroll});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .6);
    final h = weekHours(sessions: logic.state.sessions, activities: logic.state.activities, leisureIds: leisureActivityIds, now: DateTime.now());
    final leisure = h.dayLeisure.sublist(h.dayLeisure.length - 7);
    // Les 7 derniers jours calendaires (le plus ancien, en partie dans la fenêtre, n'a pas de barre).
    final days = h.days.sublist(h.days.length - 7);
    final values = h.dayActive.sublist(h.dayActive.length - 7);
    final maxV = [for (var i = 0; i < 7; i++) values[i] + leisure[i]].fold<int>(60, math.max);
    final best = () {
      var b = -1;
      for (var i = 0; i < values.length; i++) {
        if (values[i] > 0 && (b < 0 || values[i] > values[b])) b = i;
      }
      return b;
    }();
    Widget row(Color col, String label, String hint, int min) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
            Flexible(child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: mute))),
            SizedBox(width: 60, child: Text(spanLabel(min), textAlign: TextAlign.right, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
          ]),
        );
    return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
      const FicheHeader(title: 'Tes 7 derniers jours', chip: '168 h glissantes', chipColor: kHoursActive),
      const SizedBox(height: 6),
      Text('La fenêtre glisse : maintenant moins 7 jours.', style: TextStyle(fontSize: 13, color: mute)),
      const SizedBox(height: 14),
      Center(child: WeekHoursGauge(h: h, size: 300)),
      Center(
        child: Column(children: [
          Text(spanLabel(h.activeMin), style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: kHoursActive, height: 1)),
          const SizedBox(height: 4),
          Text('actives sur 7 jours', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: mute)),
        ]),
      ),
      const SizedBox(height: 14),
      // L'aiguille et le triangle, en clair, puis ce que ça change : la minute d'il y a 7 jours sort, celle de maintenant entre.
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .05), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          HoursMomentLine(h: h, now: true, labelWidth: 104, key: const ValueKey('week-hours-sheet-now')),
          const SizedBox(height: 4),
          HoursMomentLine(h: h, now: false, labelWidth: 104, key: const ValueKey('week-hours-sheet-past')),
          if (hoursShowsTomorrow(h)) ...[
            const SizedBox(height: 4),
            HoursTomorrowLine(h: h, labelWidth: 104, key: const ValueKey('week-hours-sheet-tomorrow')),
            const SizedBox(height: 4),
            HoursTomorrowLine(h: h, full: true, labelWidth: 104, key: const ValueKey('week-hours-sheet-full')),
          ],
          const SizedBox(height: 8),
          Text(hoursMoveSentence(h.nowKind, h.pastKind), key: const ValueKey('week-hours-move'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35)),
        ]),
      ),
      const SizedBox(height: 12),
      // Comment lire le compteur : ses deux repères et le filet intérieur.
      Text.rich(
        TextSpan(style: TextStyle(fontSize: 12.5, height: 1.45, color: mute), children: [
          TextSpan(text: 'L\'aiguille', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
          const TextSpan(
              text: ' suit ce que tu fais, et met deux minutes à changer de place. Sans chrono, elle recule dans le vert, là où il s\'arrêtera demain à la même heure si tu ne '
                  'fais rien : la partie hachurée est ce qui sort de ta fenêtre d\'ici là. Dès qu\'un chrono actif tourne, elle passe de l\'autre côté, au bout de '
                  'la bande claire : là où ton vert arrivera demain si tu y vas à fond, 24 h sans arrêt. C\'est un plafond. '),
          TextSpan(text: 'Le triangle blanc', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
          const TextSpan(
              text: ' montre de la même façon ce que tu faisais il y a 7 jours à la même minute (rien de tracé : il se pose là où va l\'aiguille sans chrono ; actif : au bout de la bande claire) : '
                  'c\'est la minute qui sort de ta fenêtre. Alignés, tu fais pareil. '),
          const TextSpan(text: 'Le vert', style: TextStyle(fontWeight: FontWeight.w700, color: kHoursActive)),
          TextSpan(text: ', tes heures actives, touche ton temps libre et grandit dedans : ${hoursLabel(h.trackedMin)} tracées sur 168. '),
          TextSpan(text: 'Le filet sous le vert', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
          TextSpan(text: ' : les 7 jours d\'avant, ${hoursLabel(h.prevActiveMin)} actives · ${_deltaLabel(h.deltaMin)}.'),
        ]),
        key: const ValueKey('week-hours-reading'),
      ),
      const SizedBox(height: 14),
      row(kHoursBasic, 'Besoins de base', 'repas, sieste', h.basicMin),
      row(kHoursSleep, 'Sommeil', 'tes nuits', h.sleepMin),
      row(kHoursLeisure, 'Détente', leisureActivityIds.isEmpty ? 'aucun domaine' : 'loisirs, jeux', h.leisureMin),
      row(kHoursActive, 'Actif', 'tout le reste', h.activeMin),
      row(kHoursFree, 'Libre', 'pas encore investi', h.untrackedMin),
      if (leisureActivityIds.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Pour compter ton temps de détente à part : crée un domaine (Détente, Loisirs, Chill…) ou donne la nature Détente à un domaine, par appui long sur sa tuile.',
              key: const ValueKey('week-hours-leisure-hint'), style: TextStyle(fontSize: 12.5, color: mute)),
        )
      else if (h.leisureMin > 0 || h.prevLeisureMin > 0)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Détente : ${spanLabel(h.leisureMin)} sur 7 jours · ${spanLabel(h.prevLeisureMin)} les 7 jours d\'avant.', style: TextStyle(fontSize: 12.5, color: mute)),
        ),
      const SizedBox(height: 14),
      FicheTitle(h.leisureMin > 0 ? 'JOUR PAR JOUR · ACTIF ET DÉTENTE' : 'JOUR PAR JOUR · HEURES ACTIVES'),
      const SizedBox(height: 8),
      SizedBox(
        height: 130,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(values[i] == 0 ? '' : spanLabel(values[i]), style: TextStyle(fontSize: 11, color: i == 6 ? kHoursActive : mute, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                if (leisure[i] > 0)
                  Container(
                    width: 26,
                    height: math.max(3, 80 * leisure[i] / maxV),
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(color: kHoursLeisure.withValues(alpha: i == 6 ? 1 : .75), borderRadius: BorderRadius.circular(4)),
                  ),
                Container(
                  width: 26,
                  height: math.max(4, 80 * values[i] / maxV),
                  decoration: BoxDecoration(
                    color: values[i] == 0 ? cs.onSurface.withValues(alpha: .08) : kHoursActive.withValues(alpha: i == 6 ? 1 : .75),
                    borderRadius: BorderRadius.circular(5),
                    border: i == 6 ? Border.all(color: cs.onSurface, width: 1.5) : null,
                  ),
                ),
                const SizedBox(height: 6),
                Text(_dayLetters[days[i].weekday - 1], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: i == 6 ? cs.onSurface : mute)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(color: kHoursActive.withValues(alpha: .08), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('TA ZONE D\'ACCÉLÉRATION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: kHoursActive)),
          const SizedBox(height: 4),
          Text('≈ ${hoursLabel(h.perDayMin.round())} actives par jour', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          if (best >= 0) Text('Ton meilleur jour : ${_dayNames[days[best].weekday - 1]}, ${hoursLabel(values[best])}.', style: TextStyle(fontSize: 12.5, color: mute)),
          Text(
              h.leavingMin > 0
                  ? 'D\'ici demain, ${hoursLabel(h.leavingMin)} actives sortent de la fenêtre : il faudra les refaire pour ne pas redescendre.'
                  : 'Rien d\'actif ne sort de la fenêtre d\'ici demain : tout ce que tu fais d\'actif fait grandir le vert.',
              style: TextStyle(fontSize: 12.5, color: mute)),
        ]),
      ),
    ]);
  }
}
