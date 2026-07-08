import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coach_moments.dart';

AppState _st(List<Session> sessions) => AppState(
      domains: [],
      activities: [],
      sessions: sessions,
      habitProgress: [],
    );

DailySchedule _sched(String date, List<ScheduleBlock> blocks) =>
    DailySchedule(date: date, blocks: blocks);

ScheduleBlock _block({
  required String startTime,
  int durationMin = 30,
  String title = 'Bloc',
  String category = 'personal',
  String status = 'pending',
  String? activityId,
  String? projectId,
  String? taskId,
  DateTime? doneAt,
  String kind = 'normal',
  String? prepForDate,
  String? prepForBlockId,
}) =>
    ScheduleBlock(
      startTime: startTime,
      durationMin: durationMin,
      title: title,
      category: category,
      status: status,
      activityId: activityId,
      projectId: projectId,
      taskId: taskId,
      doneAt: doneAt,
      kind: kind,
      prepForDate: prepForDate,
      prepForBlockId: prepForBlockId,
    );

void main() {
  const today = '2026-07-07';
  const yesterday = '2026-07-06';

  group('computeCoachMoment', () {
    test('nuit → carte masquée', () {
      final now = DateTime(2026, 7, 7, 3, 0);
      final m = computeCoachMoment(now, _st([]), null, null, []);
      expect(m.hidden, isTrue);
      expect(m.type, CoachMomentType.hidden);
    });

    test('réveil : affiche « prêtes depuis hier » + compte à rebours', () {
      final now = DateTime(2026, 7, 7, 7, 0);
      final todaySched = _sched(today, [
        _block(
            startTime: '07:15',
            title: 'Séance jambes',
            category: 'routine',
            activityId: 'act-sport'),
      ]);
      final yestSched = _sched(yesterday, [
        _block(
            startTime: '21:45',
            title: 'Préparer les affaires',
            status: 'done',
            kind: 'prep',
            prepForDate: today,
            prepForBlockId: 'x'),
      ]);
      final m = computeCoachMoment(now, _st([]), todaySched, yestSched, []);
      expect(m.type, CoachMomentType.wake);
      expect(m.message, contains('prêtes depuis hier'));
      expect(m.message, contains('dans 15 min'));
      expect(m.stats.any((s) => s.value.contains('prêtes depuis hier')), isTrue);
      expect(m.actions.any((a) => a.kind == CoachActionKind.launchBlock), isTrue);
    });

    test('réveil sans prep : pas de mention « prêtes »', () {
      final now = DateTime(2026, 7, 7, 6, 30);
      final todaySched = _sched(today, [
        _block(startTime: '08:00', title: 'Bloc', activityId: 'a'),
      ]);
      final m = computeCoachMoment(now, _st([]), todaySched, null, []);
      expect(m.type, CoachMomentType.wake);
      expect(m.message, isNot(contains('prêtes depuis hier')));
    });

    test('matin : premier engagement fait → message positif', () {
      final now = DateTime(2026, 7, 7, 10, 0);
      final sched = _sched(today, [
        _block(
            startTime: '07:15',
            title: 'Séance jambes',
            category: 'routine',
            status: 'done',
            doneAt: DateTime(2026, 7, 7, 7, 15)),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.morning);
      expect(m.tone, CoachTone.positive);
      expect(m.message, contains('Séance jambes'));
      expect(m.message, contains('7h15'));
    });

    test('matin : rien fait → carte réduite (prochain bloc)', () {
      final now = DateTime(2026, 7, 7, 9, 30);
      final sched = _sched(today, [
        _block(startTime: '11:00', title: 'Réunion', activityId: 'a'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.morning);
      expect(m.message, contains('Réunion'));
    });

    test('midi : rapport de matinée avec minutes logguées réelles', () {
      final now = DateTime(2026, 7, 7, 12, 30);
      final sched = _sched(today, [
        _block(
            startTime: '08:00',
            title: 'Travail',
            category: 'project',
            status: 'done'),
        _block(
            startTime: '15:00',
            title: 'Formation IA',
            category: 'project',
            projectId: 'p',
            taskId: 't'),
      ]);
      final sessions = [
        Session(
            activityId: 'a',
            startAt: DateTime(2026, 7, 7, 8, 0),
            endAt: DateTime(2026, 7, 7, 9, 30)), // 90 min avant midi
      ];
      final m = computeCoachMoment(now, _st(sessions), sched, null, sessions);
      expect(m.type, CoachMomentType.midday);
      expect(m.stats.any((s) => s.value.contains('1h30')), isTrue);
      expect(m.message, contains('Formation IA'));
    });

    test('dérive : bloc posé > 45 min, 0 min logguée → carte ambre', () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final sched = _sched(today, [
        _block(
            startTime: '14:00',
            title: 'Formation IA',
            category: 'project',
            projectId: 'p',
            taskId: 't',
            activityId: 'a'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.drift);
      expect(m.tone, CoachTone.alert);
      expect(m.message, contains('0 min logguée'));
      expect(m.actions.any((a) => a.kind == CoachActionKind.renegotiate), isTrue);
      expect(m.actions.any((a) => a.kind == CoachActionKind.launchBlock), isTrue);
    });

    test('pas de dérive si du temps a été loggué sur le bloc', () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final sched = _sched(today, [
        _block(
            startTime: '14:00',
            title: 'Formation IA',
            category: 'project',
            activityId: 'a'),
      ]);
      final sessions = [
        Session(
            activityId: 'a',
            startAt: DateTime(2026, 7, 7, 14, 10),
            endAt: DateTime(2026, 7, 7, 14, 40)),
      ];
      final m = computeCoachMoment(now, _st(sessions), sched, null, sessions);
      // Fenêtre 14-19 sans dérive → moment après-midi léger, pas de dérive.
      expect(m.type, isNot(CoachMomentType.drift));
    });

    test('soir : CTA day review + compte des preps à faire', () {
      final now = DateTime(2026, 7, 7, 20, 0);
      final sched = _sched(today, [
        _block(
            startTime: '21:45',
            title: 'Préparer le sac',
            kind: 'prep',
            prepForDate: '2026-07-08',
            prepForBlockId: 'x'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, null, []);
      expect(m.type, CoachMomentType.evening);
      expect(m.message, contains('Demain se gagne ce soir'));
      expect(
          m.actions.any((a) => a.kind == CoachActionKind.openDayReview), isTrue);
    });

    test('rétrocompat : programme sans champ kind → moment calculé normalement',
        () {
      final now = DateTime(2026, 7, 7, 10, 0);
      // Bloc construit depuis une map legacy (aucun champ prep).
      final legacy = ScheduleBlock.from({
        'id': 'b1',
        'startTime': '11:00',
        'durationMin': 30,
        'title': 'Legacy',
        'category': 'personal',
        'status': 'pending',
      });
      expect(legacy.kind, 'normal');
      expect(legacy.isPrep, isFalse);
      final m = computeCoachMoment(now, _st([]), _sched(today, [legacy]), null, []);
      expect(m.type, CoachMomentType.morning);
    });
  });
}
