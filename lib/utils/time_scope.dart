// Déplace (ou définis) l’énum ici si elle était dans main.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';

enum TimeScope { day, week, month }

// Renvoie un record (start, end, days)
({DateTime start, DateTime end, int days}) rangeForScope(
    TimeScope scope, DateTime now) {
  switch (scope) {
    case TimeScope.day:
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));
      return (start: start, end: end, days: 1);

    case TimeScope.week:
      // Semaine courante: Lundi 00:00 → Lundi suivant 00:00
      final dow = now.weekday; // 1=lundi..7=dimanche
      final start = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: dow - 1));
      final end = start.add(const Duration(days: 7));
      return (start: start, end: end, days: 7);

    case TimeScope.month:
      final start = DateTime(now.year, now.month, 1);
      final nextMonth = (now.month == 12)
          ? DateTime(now.year + 1, 1, 1)
          : DateTime(now.year, now.month + 1, 1);
      final end = nextMonth;
      final days = end.difference(start).inDays;
      return (start: start, end: end, days: days);
  }
}

String fmtCompactFromMin(int minutes) => fmtCompact(Duration(minutes: minutes));

String fmtCompact(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return "${m}m";
  return "${h}h ${m.toString().padLeft(2, '0')}m";
}

DateTime dayKey(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

double _avgMinutesPerDayTrailing({
  required Map<DateTime, int> minutesByDay,
  required DateTime endDay, // jour d (à minuit)
  required int windowDays, // 7 ou 30
}) {
  int sum = 0;
  for (int i = 0; i < windowDays; i++) {
    final d = endDay.subtract(Duration(days: i));
    sum += minutesByDay[dayKey(d)] ?? 0;
  }
  return sum / windowDays;
}

List<double> buildMovingAvgHoursSeries({
  required Map<DateTime, int> minutesByDay,
  required DateTime today,
  required int windowDays, // 7 ou 30
  int points = 30,
}) {
  // points sur [today-(points-1) .. today]
  final start = dayKey(today).subtract(Duration(days: points - 1));
  return List<double>.generate(points, (i) {
    final d = start.add(Duration(days: i));
    final avgMin = _avgMinutesPerDayTrailing(
      minutesByDay: minutesByDay,
      endDay: d,
      windowDays: windowDays,
    );
    return avgMin / 60.0; // heures / jour
  });
}

double avgHoursLastWindow({
  required Map<DateTime, int> minutesByDay,
  required DateTime today,
  required int windowDays, // 7 ou 30
}) {
  final avgMin = _avgMinutesPerDayTrailing(
    minutesByDay: minutesByDay,
    endDay: dayKey(today),
    windowDays: windowDays,
  );
  return avgMin / 60.0;
}

String fmtHhMm(double hours) {
  final totalMin = (hours * 60).round();
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}";
}

class DigitalAvgText extends StatelessWidget {
  const DigitalAvgText({super.key, required this.text, this.suffix = "/j"});

  final String text;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.onSurface.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
              color: cs.onSurface.withOpacity(0.92),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            suffix,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withOpacity(0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class MiniAvgLineChart extends StatelessWidget {
  const MiniAvgLineChart({
    super.key,
    required this.series7,
    required this.series30,
    this.goalHoursPerDay, // 👈 repère
  });

  final List<double> series7;
  final List<double> series30;
  final double? goalHoursPerDay;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _MiniAvgLinePainter(
        series7: series7,
        series30: series30,
        goalHoursPerDay: goalHoursPerDay,
        line7: cs.primary.withOpacity(0.95),
        line30: cs.onSurface.withOpacity(0.22),
        grid: cs.onSurface.withOpacity(0.10),
        goalLine: cs.onSurface.withOpacity(0.22),
      ),
      size: Size.infinite,
    );
  }
}
class _MiniAvgLinePainter extends CustomPainter {
  _MiniAvgLinePainter({
    required this.series7,
    required this.series30,
    required this.line7,
    required this.line30,
    required this.grid,
    required this.goalLine,
    this.goalHoursPerDay,
  });

  final List<double> series7;
  final List<double> series30;
  final double? goalHoursPerDay;

  final Color line7;
  final Color line30;
  final Color grid;
  final Color goalLine;

  @override
  void paint(Canvas canvas, Size size) {
    if (series7.length < 2) return;

    // Max pour scaler (inclut goal pour qu'il soit toujours visible)
    double maxV = 0;
    for (final v in series7) if (v > maxV) maxV = v;
    for (final v in series30) if (v > maxV) maxV = v;
    if (goalHoursPerDay != null && goalHoursPerDay! > maxV) maxV = goalHoursPerDay!;
    if (maxV <= 0) maxV = 1.0;

    // petite marge
    maxV *= 1.10;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;

    // 2 lignes de grille
    canvas.drawLine(
      Offset(0, size.height * 0.33),
      Offset(size.width, size.height * 0.33),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.66),
      Offset(size.width, size.height * 0.66),
      gridPaint,
    );

    double yOf(double v) {
      final t = (v / maxV).clamp(0.0, 1.0);
      return size.height - (t * size.height);
    }

    List<Offset> toPoints(List<double> s) {
      final n = s.length;
      final dx = size.width / (n - 1);
      return List.generate(n, (i) => Offset(dx * i, yOf(s[i])));
    }

    Path smoothPath(List<Offset> pts) {
      if (pts.length < 2) return Path();

      final p = Path()..moveTo(pts[0].dx, pts[0].dy);

      // Quadratic Bezier through midpoints
      for (int i = 0; i < pts.length - 1; i++) {
        final p0 = pts[i];
        final p1 = pts[i + 1];
        final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);

        if (i == 0) {
          // first segment
          p.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
        } else {
          p.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
        }
      }

      // Finish at last point
      final last = pts.last;
      p.lineTo(last.dx, last.dy);
      return p;
    }

    // Repère objectif
    if (goalHoursPerDay != null) {
      final yGoal = yOf(goalHoursPerDay!.clamp(0.0, maxV));
      final goalPaint = Paint()
        ..color = goalLine
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;

      // ligne
      canvas.drawLine(Offset(0, yGoal), Offset(size.width, yGoal), goalPaint);

      // petit point à droite (repère)
      canvas.drawCircle(Offset(size.width, yGoal), 2.2, goalPaint);
    }

    // 30j (fond) — lissé
    if (series30.length >= 2) {
      final pts30 = toPoints(series30);
      final p30 = Paint()
        ..color = line30
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(smoothPath(pts30), p30);
    }

    // 7j (devant) — lissé
    final pts7 = toPoints(series7);
    final p7 = Paint()
      ..color = line7
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(smoothPath(pts7), p7);
  }

  @override
  bool shouldRepaint(covariant _MiniAvgLinePainter old) {
    return old.series7 != series7 ||
        old.series30 != series30 ||
        old.goalHoursPerDay != goalHoursPerDay ||
        old.line7 != line7 ||
        old.line30 != line30 ||
        old.grid != grid ||
        old.goalLine != goalLine;
  }
}
DateTime nextDay(DateTime d) => d.add(const Duration(days: 1));

Map<DateTime, int> timeByDayForActivity({
  required List<Session> sessions,
  required String activityId,
  required DateTime start,
  required DateTime end,
  DateTime? now,
}) {
  final tNow = now ?? DateTime.now();
  final map = <DateTime, int>{};

  for (final s in sessions) {
    if (s.activityId != activityId) continue;

    final segStart = s.startAt.isAfter(start) ? s.startAt : start;
    final segEndRaw = s.endAt ?? tNow;
    final segEnd = segEndRaw.isBefore(end) ? segEndRaw : end;

    if (!segEnd.isAfter(segStart)) continue;

    var cursor = segStart;
    while (cursor.isBefore(segEnd)) {
      final d0 = DateTime(cursor.year, cursor.month, cursor.day);
      final d1 = d0.add(const Duration(days: 1));
      final sliceEnd = segEnd.isBefore(d1) ? segEnd : d1;

      final minutes = sliceEnd.difference(cursor).inMinutes;
      map[d0] = (map[d0] ?? 0) + minutes;

      cursor = sliceEnd;
    }
  }

  return map;
}

double avgMinutesPerDayTrailing({
  required Map<DateTime, int> minutesByDay,
  required DateTime endDay, // jour (minuit)
  required int windowDays, // 7 ou 30
}) {
  int sum = 0;
  for (int i = 0; i < windowDays; i++) {
    final d = endDay.subtract(Duration(days: i));
    sum += minutesByDay[dayKey(d)] ?? 0;
  }
  return sum / windowDays;
}

List<double> movingAvgHoursSeries({
  required Map<DateTime, int> minutesByDay,
  required DateTime today, // maintenant
  required int windowDays, // 7 ou 30
  int points = 30,
}) {
  final t0 = dayKey(today).subtract(Duration(days: points - 1));
  return List<double>.generate(points, (i) {
    final d = t0.add(Duration(days: i));
    final avgMin = avgMinutesPerDayTrailing(
      minutesByDay: minutesByDay,
      endDay: d,
      windowDays: windowDays,
    );
    return avgMin / 60.0; // heures/jour
  });
}

double avgHoursNow({
  required Map<DateTime, int> minutesByDay,
  required DateTime today,
  required int windowDays,
}) {
  final avgMin = avgMinutesPerDayTrailing(
    minutesByDay: minutesByDay,
    endDay: dayKey(today),
    windowDays: windowDays,
  );
  return avgMin / 60.0;
}

String fmtHhMmFromHours(double hours) {
  final totalMin = (hours * 60).round();
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}";
}
