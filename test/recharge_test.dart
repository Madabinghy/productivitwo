import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/recharge.dart';

MoodMark _elan(DateTime at, int v, {String ymd = '2026-10-28'}) => MoodMark(at: at, ymd: ymd, kind: kMoodElan, value: v);

void main() {
  final dayStart = DateTime(2026, 10, 28, 5);
  final sommeil = Activity(id: 's', name: 'Sommeil', domainId: 'd', type: 'time');
  final sieste = Activity(id: 'n', name: 'Sieste', domainId: 'd', type: 'time');
  final travail = Activity(id: 'w', name: 'Productivitwo', domainId: 'd', type: 'time');
  final byId = {for (final a in [sommeil, sieste, travail]) a.id: a};

  test('noms : sommeil de nuit vs sieste', () {
    expect(isSleepName('Sommeil'), isTrue);
    expect(isSleepName('Sieste'), isFalse);
    expect(isRestName('Sieste'), isTrue);
    expect(isRestName('Lecture'), isFalse);
  });

  test('débuts de sommeil : bloc du soir, bloc de la nuit du lendemain, chrono', () {
    final starts = sleepStartsOf(
      dayStart: dayStart,
      blocks: [
        ScheduleBlock(startTime: '03:00', durationMin: 60, title: 'Sommeil'), // nuit de la veille
        ScheduleBlock(startTime: '22:40', durationMin: 440, title: 'Sommeil'),
      ],
      nextDayBlocks: [ScheduleBlock(startTime: '00:30', durationMin: 300, title: 'Sommeil')],
      sessions: [Session(activityId: 's', startAt: DateTime(2026, 10, 28, 23, 10))],
      activitiesById: byId,
    );
    expect(starts, [DateTime(2026, 10, 28, 22, 40), DateTime(2026, 10, 28, 23, 10), DateTime(2026, 10, 29, 0, 30)]);
  });

  test('« Pas encore couché » : un pointage après le bloc repousse la recharge au chrono', () {
    final starts = [DateTime(2026, 10, 28, 22, 40), DateTime(2026, 10, 28, 23, 10)];
    expect(rechargeStart(sleepStarts: starts, dayMarks: [_elan(DateTime(2026, 10, 28, 21), 2)]), DateTime(2026, 10, 28, 22, 40));
    expect(rechargeStart(sleepStarts: starts, dayMarks: [_elan(DateTime(2026, 10, 28, 22, 50), 3)]), DateTime(2026, 10, 28, 23, 10));
  });

  test('la nuit ne pèse plus dans l’élan moyen', () {
    final marks = [_elan(DateTime(2026, 10, 28, 9), 4), _elan(DateTime(2026, 10, 28, 21), 2)];
    final now = DateTime(2026, 10, 29, 12);
    final without = buildElanDays(marks: marks, schedulesByYmd: const {}, hits: const [], activities: const [], now: now, days: 2);
    final withR = buildElanDays(
        marks: withRechargeMarks(marks, {'2026-10-28': DateTime(2026, 10, 28, 22)}, now),
        schedulesByYmd: const {},
        hits: const [],
        activities: const [],
        now: now,
        days: 2);
    // Sans recharge : 12 h à 4 puis 8 h à 2 → 3,2 ; avec : 12 h à 4 puis 1 h à 2.
    expect(without.first.mean!, closeTo(3.2, .01));
    expect(withR.first.mean!, closeTo((4 * 720 + 2 * 60) / 780, .01));
    expect(withR.first.marks.length, 2);
  });

  test('une sieste faite pendant la flemme n’est pas une victoire', () {
    final w = ElanWindow(_elan(DateTime(2026, 10, 28, 13), 2), DateTime(2026, 10, 28, 18));
    final nap = ScheduleBlock(startTime: '14:00', durationMin: 30, title: 'Sieste', status: 'done', doneAt: DateTime(2026, 10, 28, 14, 30));
    final work = ScheduleBlock(startTime: '15:00', durationMin: 60, title: 'Rédiger', status: 'done', doneAt: DateTime(2026, 10, 28, 16));
    expect(winsIn(w, blocks: [nap, work], hits: const [], activities: [sieste]).length, 1);
  });

  test('en recharge : soir au sommeil, matin jusqu’au premier geste', () {
    final starts = [DateTime(2026, 10, 28, 22, 40)];
    DateTime? since(DateTime now, {List<MoodMark> marks = const [], List<HabitHit> hits = const [], List<Session> sessions = const []}) => rechargeSince(
        now: now, dayStart: dayStart, sleepStarts: starts, dayMarks: marks, sessions: sessions, hits: hits, blocks: const [], activitiesById: byId);
    final day = [_elan(DateTime(2026, 10, 28, 9), 3)];
    expect(since(DateTime(2026, 10, 28, 22), marks: day), isNull);
    expect(since(DateTime(2026, 10, 28, 23), marks: day), DateTime(2026, 10, 28, 22, 40));
    // Matin du jour suivant (journée vécue 29) : avant tout geste.
    final d29 = DateTime(2026, 10, 29, 5);
    DateTime? morning(DateTime now, {List<HabitHit> hits = const [], List<Session> sessions = const []}) => rechargeSince(
        now: now, dayStart: d29, sleepStarts: const [], dayMarks: const [], sessions: sessions, hits: hits, blocks: const [], activitiesById: byId,
        lastSleepStart: DateTime(2026, 10, 28, 22, 40));
    expect(morning(DateTime(2026, 10, 29, 7)), DateTime(2026, 10, 28, 22, 40));
    expect(morning(DateTime(2026, 10, 29, 7, 30), hits: [HabitHit(habitId: 'h', ts: DateTime(2026, 10, 29, 7, 10))]), isNull);
    expect(morning(DateTime(2026, 10, 29, 8), sessions: [Session(activityId: 'w', startAt: DateTime(2026, 10, 29, 7, 50))]), isNull);
  });
}
