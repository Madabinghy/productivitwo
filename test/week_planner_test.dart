import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/week_capacity.dart';
import 'package:productivitwo_v1/utils/week_planner.dart';

ScheduleBlock _blk(String start, int dur, {String? taskId}) => ScheduleBlock(
    startTime: start, durationMin: dur, title: 't', taskId: taskId);

ProjectTask _task(String id, String start, String? end,
        {String status = 'pending', int? est}) =>
    ProjectTask(
        id: id,
        title: id,
        startDate: DateTime.parse(start),
        endDate: end == null ? null : DateTime.parse(end),
        status: status,
        estimatedMin: est);

Project _proj(String id, List<ProjectTask> tasks,
        {String status = 'active', bool paused = false}) =>
    Project(
        id: id,
        title: id,
        startDate: DateTime(2026, 9, 1),
        createdBy: 'u',
        tasks: tasks,
        status: status,
        paused: paused);

void main() {
  _windowTests();
  final monday = DateTime(2026, 9, 28); // lundi
  final today = DateTime(2026, 9, 30); // mercredi

  test('weekStart / weekDates : lundi → dimanche', () {
    expect(weekStart(DateTime(2026, 10, 4, 15)), monday); // dimanche
    expect(weekStart(monday), monday);
    final days = weekDates(monday);
    expect(days.length, 7);
    expect(days.last, DateTime(2026, 10, 4));
  });

  group('weekTasks', () {
    final projects = [
      _proj('p1', [
        _task('in', '2026-09-29', '2026-10-01'), // chevauche
        _task('late', '2026-09-20', '2026-09-25'), // retard
        _task('lateDone', '2026-09-20', '2026-09-25',
            status: 'done'), // hors semaine, fait
        _task('next', '2026-10-06', '2026-10-08'), // semaine suivante
        _task('skip', '2026-09-29', null, status: 'skipped'),
      ]),
      _proj('paused', [_task('x', '2026-09-29', null)], paused: true),
      _proj('arch', [_task('y', '2026-09-29', null)], status: 'archived'),
    ];
    final tasks = weekTasks(
        projects: projects,
        monday: monday,
        scheduled: [_blk('09:00', 60, taskId: 'in')],
        today: today);

    test('filtre : chevauchement ou retard, projets actifs non en pause', () {
      expect(tasks.map((t) => t.task.id).toList(), ['in', 'late']);
    });
    test('attributs dérivés', () {
      final inT = tasks.firstWhere((t) => t.task.id == 'in');
      final late = tasks.firstWhere((t) => t.task.id == 'late');
      expect(inT.planned, isTrue);
      expect(inT.plannedBlocks, 1);
      expect(inT.toPlace, isFalse);
      expect(late.overdue, isTrue);
      expect(late.toPlace, isTrue);
    });
    test('tasksToPlace : retards d\'abord puis échéance', () {
      final all = weekTasks(
          projects: [
            _proj('p', [
              _task('b', '2026-09-29', '2026-10-02'),
              _task('a', '2026-09-29', '2026-10-01'),
              _task('late', '2026-09-20', '2026-09-25'),
            ])
          ],
          monday: monday,
          scheduled: [],
          today: today);
      expect(
          tasksToPlace(all).map((t) => t.task.id).toList(), ['late', 'a', 'b']);
    });
  });

  test('plannedMin / isBlockedDay', () {
    expect(plannedMin([_blk('09:00', 60), _blk('11:00', 30)]), 90);
    expect(isBlockedDay([_blk('09:00', 6 * 60)]), isTrue);
    expect(isBlockedDay([_blk('09:00', 5 * 60 + 59)]), isFalse);
  });

  group('firstFreeSlot', () {
    test('journée vide → 8 h', () {
      expect(firstFreeSlot([], 45), 8 * 60);
    });
    test('saute les blocs, trouve le premier trou assez grand', () {
      final blocks = [_blk('08:00', 60), _blk('09:15', 30), _blk('10:00', 120)];
      expect(firstFreeSlot(blocks, 15), 9 * 60); // 9:00-9:15
      expect(firstFreeSlot(blocks, 30), 12 * 60); // après 12:00
    });
    test('blocs avant 8 h ignorés, dépassement 22 h → null', () {
      expect(firstFreeSlot([_blk('06:00', 60)], 30), 8 * 60);
      expect(firstFreeSlot([_blk('08:00', 13 * 60 + 30)], 60), isNull);
    });
    test('minToClock', () {
      expect(minToClock(9 * 60 + 5), '09:05');
    });
  });

  group('autoPlace', () {
    final days = weekDates(monday);
    final cap = parseWeekCapacity(
        {'wed': 120, 'thu': 60, 'fri': 0, 'sat': 0, 'sun': 0});

    test('place par échéance sur le premier jour ≥ aujourd\'hui qui tient', () {
      final wts = tasksToPlace(weekTasks(
          projects: [
            _proj('p', [
              _task('a', '2026-09-28', '2026-10-01', est: 60),
              _task('b', '2026-09-28', '2026-10-02', est: 90),
              _task('c', '2026-09-28', '2026-10-03', est: 60),
              _task('d', '2026-09-28', '2026-10-03', est: 60),
            ])
          ],
          monday: monday,
          scheduled: [],
          today: today));
      final r = autoPlace(
          toPlace: wts,
          days: days,
          scheduledByDay: {},
          capacity: cap,
          today: today);
      // mercredi (120) : a (60) + c (60) ; b (90) ne tient plus → jeudi (60) non → nulle part.
      expect(r.blocks['2026-09-30']!.map((b) => b.taskId).toList(), ['a', 'c']);
      expect(r.blocks['2026-09-30']!.map((b) => b.startTime).toList(),
          ['08:00', '09:00']);
      expect(r.blocks['2026-10-01']!.map((b) => b.taskId).toList(), ['d']);
      expect(r.left.map((t) => t.task.id).toList(), ['b']);
    });

    test('jour bloqué et jours passés ignorés', () {
      final wts = tasksToPlace(weekTasks(
          projects: [
            _proj('p', [_task('a', '2026-09-28', '2026-10-01')])
          ],
          monday: monday,
          scheduled: [],
          today: today));
      final r = autoPlace(
          toPlace: wts,
          days: days,
          scheduledByDay: {
            '2026-09-30': [_blk('08:00', 6 * 60)]
          },
          capacity: parseWeekCapacity({}),
          today: today);
      expect(r.blocks.keys.toList(), ['2026-10-01']);
      final b = r.blocks['2026-10-01']!.single;
      expect(b.category, 'project');
      expect(b.projectId, 'p');
      expect(b.durationMin, kDefaultTaskEstimatedMin);
    });
  });
}

void _windowTests() {
  ScheduleBlock b(String start, int dur, {String? taskId}) =>
      ScheduleBlock(startTime: start, durationMin: dur, title: 't', taskId: taskId);

  group('fenêtre 14 jours / reste à caser / créneau proposé', () {
    test('windowDates : n jours à partir du début', () {
      final d = windowDates(DateTime(2026, 9, 30, 11), 14);
      expect(d.length, 14);
      expect(d.first, DateTime(2026, 9, 30));
      expect(d.last, DateTime(2026, 10, 13));
    });
    test('windowTasks : 14 jours attrape ce que la semaine ne voit pas', () {
      final projects = [
        _proj('p', [_task('far', '2026-10-08', '2026-10-09'), _task('near', '2026-09-29', null)])
      ];
      final week = weekTasks(
          projects: projects, monday: DateTime(2026, 9, 28), scheduled: [], today: DateTime(2026, 9, 30));
      final two = windowTasks(
          projects: projects,
          start: DateTime(2026, 9, 30),
          days: 14,
          scheduled: [],
          today: DateTime(2026, 9, 30));
      expect(week.map((t) => t.task.id).toList(), ['near']);
      expect(two.map((t) => t.task.id).toList(), ['far', 'near']);
    });
    test('remainingToPlaceMin : estimation − blocs liés, jamais négatif', () {
      final t = _task('t', '2026-09-28', null, est: 90);
      expect(remainingToPlaceMin(t, []), 90);
      expect(remainingToPlaceMin(t, [b('09:00', 60, taskId: 't'), b('11:00', 15, taskId: 'x')]), 30);
      expect(remainingToPlaceMin(t, [b('09:00', 120, taskId: 't')]), 0);
      expect(remainingToPlaceMin(_task('u', '2026-09-28', null), []), kDefaultTaskEstimatedMin);
    });
    test('proposedSlot : 8 h, ou après maintenant aujourd\'hui, avant 20 h, sinon plein', () {
      expect(proposedSlot([], 30, isToday: false), (start: 8 * 60, full: false));
      expect(proposedSlot([], 30, isToday: true, nowMin: 9 * 60 + 47), (start: 10 * 60, full: false));
      expect(proposedSlot([b('08:00', 60)], 30, isToday: false), (start: 9 * 60, full: false));
      expect(proposedSlot([b('08:00', 12 * 60)], 30, isToday: false), (start: 8 * 60, full: true));
      expect(proposedSlot([], 30, isToday: true, nowMin: 19 * 60 + 45), (start: 8 * 60, full: true));
    });
  });
}
