import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/leisure.dart' show leisureActivityIds;
import 'package:productivitwo_v1/utils/week_hours.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche, FicheHeader, FicheTitle;

/// Les 168 dernières heures en compteur (maquette validée 2026-11-11) : carte en tête d'Organisation, feuille en grand au tap.
/// Redessiné le 2026-11-18 (maquette « Couleurs de la jauge », choix user) : palette plus vive, temps libre en tirets,
/// une graduation par jour, et « le socle d'abord » : sommeil → besoins → détente → actif, l'aiguille au bout du vert.
const kHoursActive = Color(0xFF3DDC84);
const kHoursActiveHi = Color(0xFFB4F7D0);
const kHoursLeisure = Color(0xFFF08BC0);
const kHoursBasic = Color(0xFFFFD479);
const kHoursSleep = Color(0xFF6F92F2);
const kHoursFree = Color(0xFF7FF0D6);

String hoursLabel(int min) => '${(min / 60).round()} h';

String _deltaLabel(int min) {
  final h = (min / 60).round();
  return h == 0 ? 'comme les 7 jours d\'avant' : '${h > 0 ? '+' : '−'}${h.abs()} h sur les 7 jours d\'avant';
}

/// Le compteur : arc de 240° (les 168 h). Le socle d'abord (choix user 2026-11-18) : sommeil → besoins de base →
/// détente, puis l'actif, puis le temps libre en tirets. L'aiguille est au bout du vert : elle compte tout ce qui
/// est tracé, et l'actif touche le temps libre, dans lequel il grandit. Le filet intérieur, sous le vert = les
/// heures actives des 7 jours d'avant ([showPrev]).
class WeekHoursGauge extends StatelessWidget {
  final WeekHours h;
  final double size;
  final bool showPrev;
  const WeekHoursGauge({super.key, required this.h, required this.size, this.showPrev = true});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size(size, size * .76),
      painter: _GaugePainter(h, track: cs.onSurface.withValues(alpha: .09), needle: cs.onSurface, hole: cs.surface, showPrev: showPrev),
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

    final f = gaugeFractions(h);
    const colors = [kHoursActive, kHoursLeisure, kHoursBasic, kHoursSleep];
    const gap = 1.3 * _deg;
    var a = _start;
    var activeStart = _start;
    // Le socle d'abord : sommeil, besoins de base, détente, puis l'actif.
    for (final i in const [3, 2, 1, 0]) {
      final sweep = _sweep * f[i];
      if (sweep <= 0) continue;
      final len = sweep > gap * 2.3 ? sweep - gap : sweep;
      if (i == 0) {
        activeStart = a;
        // Le vert de l'actif : un halo dessous, un dégradé dessus.
        canvas.drawArc(rect, a, len, false, band(kHoursActive.withValues(alpha: .45))..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * .55));
        canvas.drawArc(
            rect,
            a,
            len,
            false,
            band(kHoursActive)
              ..shader = const LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [kHoursActive, kHoursActiveHi]).createShader(rect));
      } else {
        canvas.drawArc(rect, a, len, false, band(colors[i]));
      }
      a += sweep;
    }
    final trackedEnd = a;
    if (f[0] <= 0) activeStart = trackedEnd;
    const end = _start + _sweep;

    // Le temps libre : des tirets, des cases à remplir.
    const dash = 4.3 * _deg, space = 3.4 * _deg;
    final free = band(kHoursFree.withValues(alpha: .85));
    for (var d = trackedEnd + _deg; d < end - .002; d += dash + space) {
      canvas.drawArc(rect, d, math.min(dash, end - d), false, free);
    }

    if (showPrev && h.prevActiveMin > 0) {
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r - stroke / 2 - w * .027),
          activeStart,
          math.min(_sweep * h.prevActiveMin / kWeekHoursMin, end - activeStart),
          false,
          Paint()
            ..color = needle.withValues(alpha: .42)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.2, w * .0125)
            ..strokeCap = StrokeCap.round);
    }

    // L'aiguille, effilée, au bout du vert : tout ce qui est tracé.
    final tip = at(r - w * .008, trackedEnd);
    final b1 = at(w * .022, trackedEnd + math.pi / 2), b2 = at(w * .022, trackedEnd - math.pi / 2);
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
    canvas.drawCircle(c, w * .013, Paint()..color = kHoursActive);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter o) =>
      o.h.activeMin != h.activeMin ||
      o.h.leisureMin != h.leisureMin ||
      o.h.basicMin != h.basicMin ||
      o.h.sleepMin != h.sleepMin ||
      o.h.prevActiveMin != h.prevActiveMin ||
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
          child: Row(children: [
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
                if (h.leisureMin > 0)
                  Text('${spanLabel(h.leisureMin)} de détente',
                      key: const ValueKey('week-hours-leisure'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kHoursLeisure)),
                Text('${hoursLabel(h.trackedMin)} / 168 h tracées · ${hoursLabel(h.untrackedMin)} libres', style: TextStyle(fontSize: 12.5, color: mute)),
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
      const SizedBox(height: 12),
      // Comment lire le compteur : ses deux repères et le filet intérieur.
      Text.rich(
        TextSpan(style: TextStyle(fontSize: 12.5, height: 1.45, color: mute), children: [
          TextSpan(text: 'L\'aiguille', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
          TextSpan(text: ' : tout ce que tu as tracé, ${hoursLabel(h.trackedMin)} sur 168. D\'abord ton socle (sommeil, besoins de base, détente), puis '),
          const TextSpan(text: 'le vert', style: TextStyle(fontWeight: FontWeight.w700, color: kHoursActive)),
          const TextSpan(text: ', tes heures actives : il touche ton temps libre et grandit dedans. '),
          TextSpan(text: 'Le filet sous le vert', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
          TextSpan(text: ' : les 7 jours d\'avant, ${hoursLabel(h.prevActiveMin)} actives · ${_deltaLabel(h.deltaMin)}.'),
        ]),
        key: const ValueKey('week-hours-reading'),
      ),
      const SizedBox(height: 14),
      row(kHoursSleep, 'Sommeil', 'tes nuits', h.sleepMin),
      row(kHoursBasic, 'Besoins de base', 'repas, sieste', h.basicMin),
      row(kHoursLeisure, 'Détente', leisureActivityIds.isEmpty ? 'aucun domaine' : 'loisirs, jeux', h.leisureMin),
      row(kHoursActive, 'Actif', 'tout le reste', h.activeMin),
      row(kHoursFree, 'Libre', 'pas encore investi', h.untrackedMin),
      if (leisureActivityIds.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
              'Pour compter ton temps de détente à part : crée un domaine (Détente, Loisirs, Chill…) ou donne la nature Détente à un domaine, par appui long sur sa tuile.',
              key: const ValueKey('week-hours-leisure-hint'),
              style: TextStyle(fontSize: 12.5, color: mute)),
        )
      else if (h.leisureMin > 0 || h.prevLeisureMin > 0)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Détente : ${spanLabel(h.leisureMin)} sur 7 jours · ${spanLabel(h.prevLeisureMin)} les 7 jours d\'avant.',
              style: TextStyle(fontSize: 12.5, color: mute)),
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
