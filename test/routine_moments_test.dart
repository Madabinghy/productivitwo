import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';

Activity _r(String id, String name, {String? ctx, int target = 1, int? order}) => Activity(
    id: id, domainId: 'd', name: name, type: 'habit', habitFreq: HabitFreq.daily, habitTarget: target, timeContext: ctx)
  ..routineOrder = order;

void main() {
  test('currentMoment : plage, creux → suivant, bords', () {
    expect(currentMoment(7 * 60).key, kMomentMorning);
    expect(currentMoment(11 * 60 + 10).key, kMomentMidday); // creux 11 h → 11 h 30
    expect(currentMoment(15 * 60).key, kMomentAfternoon);
    expect(currentMoment(23 * 60 + 45).key, kMomentEvening);
    expect(currentMoment(3 * 60).key, kMomentMorning);
  });

  test('buildRoutineDay à 00:30 : journée vécue → moment courant = Soir, pas Matin', () {
    final d = buildRoutineDay(activities: [_r('a', 'Pompes')], hits: const [], now: DateTime(2026, 10, 17, 0, 30));
    expect(d.current.key, kMomentEvening);
    final d0 = buildRoutineDay(
        activities: [_r('a', 'Pompes')], hits: const [], now: DateTime(2026, 10, 17, 0, 30), dayStartMin: 0);
    expect(d0.current.key, kMomentMorning);
  });

  test('momentKeyOf : réglage, archétype du nom, repas → midi, rien → libre', () {
    expect(momentKeyOf(_r('a', 'Lecture', ctx: 'evening')), kMomentEvening);
    expect(momentKeyOf(_r('b', 'Hygiène du soir')), kMomentEvening);
    expect(momentKeyOf(_r('c', 'Boire de l\'eau')), kMomentAllDay);
    expect(momentKeyOf(_r('d', 'Repas équilibré')), kMomentMidday);
    expect(momentKeyOf(_r('e', 'Pompes')), kMomentAllDay); // archétype « journée »
    expect(momentKeyOf(_r('f', 'Louanges')), kMomentAny);
  });

  test('buildRoutineDay : file = restées puis moment courant, reculées en fin ; reports ; compteurs', () {
    final acts = [
      _r('lit', 'Faire mon lit', ctx: 'morning', order: 1),
      _r('lou', 'Louanges', ctx: 'morning', order: 2),
      _r('bib', 'Lire la Bible', ctx: 'morning', order: 3),
      _r('rep', 'Repas', ctx: 'midday', target: 2),
      _r('vai', 'Vaisselle', ctx: 'midday'),
      _r('eau', 'Eau', ctx: 'allday', target: 6),
    ];
    final day = DateTime(2026, 10, 17);
    final hits = [HabitHit(habitId: 'lit', ts: day.add(const Duration(hours: 7)))];
    final d = buildRoutineDay(
        activities: acts, hits: hits, now: day.add(const Duration(hours: 12, minutes: 10)),
        deferred: ['rep'], dismissed: {'bib'});
    expect(d.current.key, kMomentMidday);
    expect(d.queue.map((s) => s.id).toList(), ['lou', 'vai', 'rep']);
    expect(d.leftoverCountOf(kMomentMorning), 1);
    expect(d.countOf(kMomentMorning), (done: 1, total: 2)); // bib écartée
    expect(d.countOf(kMomentMidday), (done: 0, total: 2));
    expect(d.shortLine, 'Routines · 1 / 5 · 2 à faire ce midi · 1 restée du matin');
    expect(d.laterMoments.map((m) => m.key).toList(), [kMomentAfternoon, kMomentEvening]);

    // Report « cet après-midi » : sort de la file, compte dans l'après-midi.
    final d2 = buildRoutineDay(
        activities: acts, hits: hits, now: day.add(const Duration(hours: 12, minutes: 10)),
        pushed: {'lou': kMomentAfternoon});
    expect(d2.queue.map((s) => s.id).toList(), ['bib', 'rep', 'vai']); // bib restée du matin, lou reportée
    expect(d2.of(kMomentAfternoon).single.pushed, isTrue);
    expect(d2.countOf(kMomentAfternoon), (done: 0, total: 1));
  });
}
