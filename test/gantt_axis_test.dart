import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/gantt_axis.dart';

ProjectTask _task(String id, String start, {String? end, bool milestone = false}) =>
    ProjectTask(
        id: id,
        title: id,
        startDate: DateTime.parse(start),
        endDate: end == null ? null : DateTime.parse(end),
        isMilestone: milestone);

Project _proj(List<ProjectTask> tasks, {DateTime? end}) => Project(
    id: 'p',
    title: 'P',
    startDate: DateTime(2026, 10, 7), // mercredi
    endDate: end,
    createdBy: 'u',
    tasks: tasks);

void main() {
  test('ganttRange : lundi − 7 j avant le projet, fin + 14 j arrondie au lundi', () {
    final r = ganttRange(projectStart: DateTime(2026, 10, 7), projectEnd: DateTime(2026, 11, 20));
    expect(r.start, DateTime(2026, 9, 28)); // lundi 5 oct − 7 j
    expect(r.start.weekday, DateTime.monday);
    // 20 nov + 14 j = 4 déc (vendredi) → lundi suivant 7 déc (exclusif)
    expect(r.end, DateTime(2026, 12, 7));
    expect(r.end.weekday, DateTime.monday);
  });

  test('ganttRange : fin tombant un lundi → lundi suivant (exclusif)', () {
    // 2026-11-16 est un lundi ; +14 j = lundi 30 nov → fin = 7 déc
    final r = ganttRange(projectStart: DateTime(2026, 10, 7), projectEnd: DateTime(2026, 11, 16));
    expect(r.end, DateTime(2026, 12, 7));
  });

  test('ganttRange : sans fin de projet = début + 84 j', () {
    final r = ganttRange(projectStart: DateTime(2026, 10, 7));
    expect(r.end.isAfter(DateTime(2026, 10, 7).add(const Duration(days: 84 + 14))), isTrue);
  });

  test('ganttRange : les tâches hors plage projet étendent la plage', () {
    final r = ganttRange(
        projectStart: DateTime(2026, 10, 7),
        projectEnd: DateTime(2026, 10, 30),
        tasks: [
          _task('a', '2026-09-15', end: '2026-09-20'),
          _task('b', '2026-12-01'), // sans fin → +7 j
          _task('m', '2026-12-20', milestone: true),
        ]);
    expect(r.start, DateTime(2026, 9, 7)); // lundi 14 sept − 7 j
    expect(r.end.isAfter(DateTime(2026, 12, 20).add(const Duration(days: 14))), isTrue);
  });

  test('GanttAxis : x() continu, dayW selon l\'échelle et le zoom', () {
    final axis = GanttAxis(rangeStart: DateTime(2026, 9, 28), rangeEnd: DateTime(2026, 12, 7));
    expect(axis.totalDays, 70);
    expect(axis.totalWeeks, 10);
    expect(axis.dayW, kGanttDayW);
    expect(axis.x(DateTime(2026, 9, 28)), 0);
    expect(axis.x(DateTime(2026, 10, 1, 15)), 3 * kGanttDayW); // l'heure est ignorée
    final week = axis.copyWith(scale: GanttScale.week, zoom: 2);
    expect(week.dayW, closeTo(kGanttWeekW * 2 / 7, 1e-9));
    expect(week.width, closeTo(10 * kGanttWeekW * 2, 1e-9));
  });

  test('GanttAxis : zoom clampé, zoomToFit et dateAt', () {
    final axis = GanttAxis(rangeStart: DateTime(2026, 9, 28), rangeEnd: DateTime(2026, 12, 7), zoom: 9);
    expect(axis.zoom, kGanttZoomMax);
    final fit = axis.zoomToFit(700); // 70 j × 28 = 1960 px → 0.357
    expect(fit, closeTo(700 / 1960, 1e-9));
    final fitted = axis.copyWith(zoom: fit);
    expect(fitted.width, closeTo(700, 1e-6));
    expect(fitted.dateAt(0), DateTime(2026, 9, 28));
    expect(fitted.dateAt(699), DateTime(2026, 12, 6));
    expect(fitted.dateAt(5000), DateTime(2026, 12, 6)); // clampé
  });

  test('GanttAxis : mois et semaines calées sur les lundis', () {
    final axis = GanttAxis.forProject(_proj([], end: DateTime(2026, 11, 20)));
    final months = axis.monthSegments();
    expect(months.map((m) => m.label).toList(),
        ['septembre 2026', 'octobre 2026', 'novembre 2026', 'décembre 2026']);
    expect(months.first.days, 3); // 28, 29, 30 sept
    expect(months[1].days, 31);
    expect(months.fold<int>(0, (s, m) => s + m.days), axis.totalDays);
    final weeks = axis.weekStarts();
    expect(weeks.every((d) => d.weekday == DateTime.monday), isTrue);
    expect(ganttWeekLabel(weeks[1]), 'lun. 5 oct.');
  });

  test('GanttAxis : contains et scrollToCenter', () {
    final axis = GanttAxis(rangeStart: DateTime(2026, 9, 28), rangeEnd: DateTime(2026, 12, 7));
    expect(axis.contains(DateTime(2026, 10, 3)), isTrue);
    expect(axis.contains(DateTime(2026, 12, 7)), isFalse);
    expect(axis.contains(DateTime(2026, 9, 27)), isFalse);
    // 3 oct = jour 5 → x = 140, centre 154 ; viewport 300 → 4
    expect(axis.scrollToCenter(DateTime(2026, 10, 3), 300), closeTo(4, 1e-9));
    expect(axis.scrollToCenter(DateTime(2026, 9, 28), 300), 0); // clampé à gauche
    expect(axis.scrollToCenter(DateTime(2026, 12, 6), 300), axis.width - 300);
  });
}
