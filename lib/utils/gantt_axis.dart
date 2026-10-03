import 'dart:math';

import 'package:productivitwo_v1/models.dart';

/// Axe de temps du Gantt projet (web) — logique pure, testable sans widget.
///
/// La plage couvre toutes les tâches (aucune n'est collée au bord) : du lundi
/// précédant min(début projet, 1ʳᵉ tâche) − 7 j, jusqu'au lundi suivant
/// max(fin projet, dernière tâche) + 14 j. `rangeEnd` est exclusif.

enum GanttScale { day, week }

const double kGanttDayW = 28.0; // largeur d'un jour en vue Jour, zoom 1
const double kGanttWeekW = 68.0; // largeur d'une semaine en vue Semaine, zoom 1
const double kGanttZoomMin = 0.2;
const double kGanttZoomMax = 3.0;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _mondayOf(DateTime d) {
  final day = _day(d);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// Fin « visuelle » d'une tâche : échéance, sinon début + 7 j (barre), ou le
/// jour même pour un jalon.
DateTime taskVisualEnd(ProjectTask t) {
  if (t.isMilestone) return _day(t.startDate).add(const Duration(days: 1));
  final end = t.endDate ?? t.startDate.add(const Duration(days: 7));
  return _day(end);
}

({DateTime start, DateTime end}) ganttRange({
  required DateTime projectStart,
  DateTime? projectEnd,
  Iterable<ProjectTask> tasks = const [],
}) {
  var minD = _day(projectStart);
  var maxD = _day(projectEnd ?? projectStart.add(const Duration(days: 84)));
  for (final t in tasks) {
    final s = _day(t.startDate);
    if (s.isBefore(minD)) minD = s;
    final e = taskVisualEnd(t);
    if (e.isAfter(maxD)) maxD = e;
  }
  final start = _mondayOf(minD).subtract(const Duration(days: 7));
  final padded = maxD.add(const Duration(days: 14));
  var end = _mondayOf(padded);
  if (end.isBefore(padded) || end == padded) end = end.add(const Duration(days: 7));
  return (start: start, end: end);
}

class GanttAxis {
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final GanttScale scale;
  final double zoom;

  GanttAxis({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    this.scale = GanttScale.day,
    double zoom = 1,
  })  : rangeStart = _day(rangeStart),
        rangeEnd = _day(rangeEnd),
        zoom = zoom.clamp(kGanttZoomMin, kGanttZoomMax).toDouble();

  factory GanttAxis.forProject(Project p,
      {GanttScale scale = GanttScale.day, double zoom = 1}) {
    final r = ganttRange(
        projectStart: p.startDate, projectEnd: p.endDate, tasks: p.tasks);
    return GanttAxis(rangeStart: r.start, rangeEnd: r.end, scale: scale, zoom: zoom);
  }

  GanttAxis copyWith({GanttScale? scale, double? zoom}) => GanttAxis(
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      scale: scale ?? this.scale,
      zoom: zoom ?? this.zoom);

  /// Largeur d'un jour en pixels (continue, y compris en vue Semaine).
  double get dayW =>
      scale == GanttScale.day ? kGanttDayW * zoom : kGanttWeekW * zoom / 7;

  int get totalDays => rangeEnd.difference(rangeStart).inDays;
  int get totalWeeks => (totalDays / 7).ceil();
  double get width => totalDays * dayW;

  bool contains(DateTime d) {
    final day = _day(d);
    return !day.isBefore(rangeStart) && day.isBefore(rangeEnd);
  }

  /// Abscisse (depuis le bord gauche de la zone de temps) du début du jour [d].
  double x(DateTime d) => _day(d).difference(rangeStart).inDays * dayW;

  /// Jour sous l'abscisse [px] (clampé dans la plage).
  DateTime dateAt(double px) {
    final i = (px / dayW).floor().clamp(0, max(0, totalDays - 1)).toInt();
    return rangeStart.add(Duration(days: i));
  }

  /// Zoom pour que toute la plage tienne dans [viewportW] (clampé).
  double zoomToFit(double viewportW) {
    final base = scale == GanttScale.day ? kGanttDayW : kGanttWeekW / 7;
    if (totalDays == 0 || viewportW <= 0) return 1;
    return (viewportW / (totalDays * base)).clamp(kGanttZoomMin, kGanttZoomMax).toDouble();
  }

  /// Segments de mois couverts par la plage, avec libellé « octobre 2026 ».
  List<({DateTime start, int days, String label})> monthSegments() {
    final out = <({DateTime start, int days, String label})>[];
    var cursor = rangeStart;
    while (cursor.isBefore(rangeEnd)) {
      final nextMonth = DateTime(cursor.year, cursor.month + 1, 1);
      final segEnd = nextMonth.isBefore(rangeEnd) ? nextMonth : rangeEnd;
      out.add((
        start: cursor,
        days: segEnd.difference(cursor).inDays,
        label: '${kGanttMonths[cursor.month - 1]} ${cursor.year}',
      ));
      cursor = segEnd;
    }
    return out;
  }

  /// Lundis de la plage (colonnes de la vue Semaine).
  List<DateTime> weekStarts() =>
      List.generate(totalWeeks, (i) => rangeStart.add(Duration(days: 7 * i)));

  /// Offset de défilement horizontal qui centre le jour [d] dans [viewportW].
  double scrollToCenter(DateTime d, double viewportW) {
    final target = x(d) + dayW / 2 - viewportW / 2;
    return target.clamp(0, max(0, width - viewportW)).toDouble();
  }
}

const kGanttMonths = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
];
const kGanttMonthsShort = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
];
const kGanttWeekdayInitials = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
const kGanttWeekdaysShort = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];

/// « lun. 5 oct. »
String ganttWeekLabel(DateTime monday) =>
    '${kGanttWeekdaysShort[monday.weekday - 1]} ${monday.day} ${kGanttMonthsShort[monday.month - 1]}';
