import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/week_hours.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche, FicheHeader, FicheTitle;

/// Les 168 dernières heures en compteur (maquette validée 2026-11-11) : carte en tête d'Organisation, feuille en grand au tap.
const kHoursActive = Color(0xFF3DDC84);
const kHoursBasic = Color(0xFF9FB3A8);
const kHoursSleep = Color(0xFF5B7FC7);
const kHoursBlur = Color(0x8CF5B041);

String hoursLabel(int min) => '${(min / 60).round()} h';

String _deltaLabel(int min) {
  final h = (min / 60).round();
  return h == 0 ? 'comme les 7 jours d\'avant' : '${h > 0 ? '+' : '−'}${h.abs()} h sur les 7 jours d\'avant';
}

/// Le compteur : arc de 240° (les 168 h), rempli actif → besoins → sommeil → flou ; aiguille au bout de l'actif ;
/// [prevActiveMin] = trait en pointillés des 7 jours d'avant.
class WeekHoursGauge extends StatelessWidget {
  final WeekHours h;
  final double size;
  final bool showPrev;
  const WeekHoursGauge({super.key, required this.h, required this.size, this.showPrev = true});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size(size, size * .8),
      painter: _GaugePainter(h, track: cs.onSurface.withValues(alpha: .08), needle: cs.onSurface, hole: cs.surface, showPrev: showPrev),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final WeekHours h;
  final Color track, needle, hole;
  final bool showPrev;
  _GaugePainter(this.h, {required this.track, required this.needle, required this.hole, required this.showPrev});

  static const _start = 150 * math.pi / 180;
  static const _sweep = 240 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * .07;
    final r = size.width / 2 - stroke / 2 - 2;
    final c = Offset(size.width / 2, r + stroke / 2 + 2);
    final rect = Rect.fromCircle(center: c, radius: r);
    Paint p(Color col) => Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, _start, _sweep, false, p(track));
    var at = 0.0;
    for (final (min, col) in [(h.activeMin, kHoursActive), (h.basicMin, kHoursBasic), (h.sleepMin, kHoursSleep), (h.untrackedMin, kHoursBlur)]) {
      final f = min / kWeekHoursMin;
      if (f > 0) canvas.drawArc(rect, _start + _sweep * at, _sweep * f, false, p(col));
      at += f;
    }
    if (showPrev && h.prevActiveMin > 0) {
      final a = _start + _sweep * (h.prevActiveMin / kWeekHoursMin).clamp(0.0, 1.0);
      final dir = Offset(math.cos(a), math.sin(a));
      final paint = Paint()
        ..color = needle.withValues(alpha: .8)
        ..strokeWidth = math.max(1.5, size.width * .008);
      final a0 = c + dir * (r - stroke * .9), a1 = c + dir * (r + stroke * .9);
      const dashes = 4;
      for (var i = 0; i < dashes; i += 2) {
        canvas.drawLine(Offset.lerp(a0, a1, i / dashes)!, Offset.lerp(a0, a1, (i + 1) / dashes)!, paint);
      }
    }
    final a = _start + _sweep * (h.activeMin / kWeekHoursMin).clamp(0.0, 1.0);
    final tip = c + Offset(math.cos(a), math.sin(a)) * (r - stroke * .2);
    canvas.drawLine(c, tip, Paint()
      ..color = needle
      ..strokeWidth = math.max(2.5, size.width * .02)
      ..strokeCap = StrokeCap.round);
    canvas.drawCircle(c, size.width * .035, Paint()..color = hole);
    canvas.drawCircle(c, size.width * .035, Paint()
      ..color = needle
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, size.width * .015));
  }

  @override
  bool shouldRepaint(covariant _GaugePainter o) =>
      o.h.activeMin != h.activeMin || o.h.basicMin != h.basicMin || o.h.sleepMin != h.sleepMin || o.h.prevActiveMin != h.prevActiveMin || o.track != track;
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
          child: Row(children: [
            WeekHoursGauge(h: h, size: 112, showPrev: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TES 7 DERNIERS JOURS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: mute)),
                const SizedBox(height: 2),
                Text.rich(TextSpan(children: [
                  TextSpan(text: hoursLabel(h.activeMin), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kHoursActive)),
                  TextSpan(text: ' actives', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: mute)),
                ])),
                Text('${hoursLabel(h.trackedMin)} / 168 h tracées · ${hoursLabel(h.untrackedMin)} dans le flou', style: TextStyle(fontSize: 12.5, color: mute)),
                const SizedBox(height: 2),
                Text(_deltaLabel(h.deltaMin),
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: h.deltaMin >= 0 ? kHoursActive : const Color(0xFFF5B041))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
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
    final h = weekHours(sessions: logic.state.sessions, activities: logic.state.activities, now: DateTime.now());
    // Les 7 derniers jours calendaires (le plus ancien, en partie dans la fenêtre, n'a pas de barre).
    final days = h.days.sublist(h.days.length - 7);
    final values = h.dayActive.sublist(h.dayActive.length - 7);
    final maxV = values.fold<int>(60, math.max);
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
            Text(hint, style: TextStyle(fontSize: 12.5, color: mute)),
            SizedBox(width: 52, child: Text(hoursLabel(min), textAlign: TextAlign.right, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
          ]),
        );
    return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
      const FicheHeader(title: 'Tes 7 derniers jours', chip: '168 h glissantes', chipColor: kHoursActive),
      const SizedBox(height: 6),
      Text('La fenêtre glisse : maintenant moins 7 jours.', style: TextStyle(fontSize: 13, color: mute)),
      const SizedBox(height: 14),
      Center(
        child: Stack(alignment: Alignment.center, children: [
          WeekHoursGauge(h: h, size: 300),
          Positioned(
            bottom: 18,
            child: Column(children: [
              Text(hoursLabel(h.activeMin), style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: kHoursActive, height: 1)),
              const SizedBox(height: 4),
              Text('actives sur 7 jours', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: mute)),
              Text('${hoursLabel(h.trackedMin)} / 168 h tracées', style: TextStyle(fontSize: 12, color: mute)),
            ]),
          ),
        ]),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('┆ ', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800)),
        Flexible(
          child: Text('les 7 jours d\'avant : ${hoursLabel(h.prevActiveMin)} actives · ${_deltaLabel(h.deltaMin)}',
              style: TextStyle(fontSize: 12.5, color: mute), textAlign: TextAlign.center),
        ),
      ]),
      const SizedBox(height: 14),
      row(kHoursActive, 'Actif', 'tout le reste', h.activeMin),
      row(kHoursBasic, 'Besoins de base', 'repas, sieste', h.basicMin),
      row(kHoursSleep, 'Sommeil', 'tes nuits', h.sleepMin),
      row(kHoursBlur, 'Dans le flou', 'rien de tracé', h.untrackedMin),
      const SizedBox(height: 14),
      const FicheTitle('JOUR PAR JOUR · HEURES ACTIVES'),
      const SizedBox(height: 8),
      SizedBox(
        height: 120,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(values[i] == 0 ? '' : hoursLabel(values[i]), style: TextStyle(fontSize: 11, color: i == 6 ? kHoursActive : mute, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
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
          if (best >= 0)
            Text('Ton meilleur jour : ${_dayNames[days[best].weekday - 1]}, ${hoursLabel(values[best])}.', style: TextStyle(fontSize: 12.5, color: mute)),
          Text(
              h.leavingMin > 0
                  ? 'D\'ici demain, ${hoursLabel(h.leavingMin)} actives sortent de la fenêtre : il faudra les refaire pour ne pas redescendre.'
                  : 'Rien d\'actif ne sort de la fenêtre d\'ici demain : tout ce que tu fais fait monter l\'aiguille.',
              style: TextStyle(fontSize: 12.5, color: mute)),
        ]),
      ),
    ]);
  }
}
