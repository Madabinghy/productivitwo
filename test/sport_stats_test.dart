import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/sport_stats.dart';

Activity act(String id, String dom, {String type = 'time', HabitFreq? freq, int? target, String? linked}) => Activity(
    id: id, domainId: dom, name: id, role: ActivityRole.generic, type: type, goalMin: 1, habitFreq: freq, habitTarget: target, linkedActivityId: linked, createdAt: DateTime(2026, 1, 1));

Session ses(String a, DateTime start, int min) => Session(activityId: a, startAt: start, endAt: start.add(Duration(minutes: min)));

void main() {
  final domains = [Domain(id: 'sp', name: 'Sport'), Domain(id: 'mu', name: 'Musculation'), Domain(id: 'tr', name: 'Travail')];
  final run = act('courir', 'sp');
  final gym = act('muscu', 'mu');
  final work = act('boulot', 'tr');
  final footing = act('footing', 'sp', type: 'habit', freq: HabitFreq.weekly, target: 3, linked: 'courir');
  final pompes = act('pompes', 'mu', type: 'habit', freq: HabitFreq.daily, target: 20);
  final all = [run, gym, work, footing, pompes];

  test('choix par défaut : domaines de sport, rôles par type', () {
    final pick = resolveSportPick(all, domains);
    expect(pick.kinds, {'courir': SportKind.session, 'muscu': SportKind.session, 'footing': SportKind.sessionRoutine, 'pompes': SportKind.reps});
    final o = const SportOverrides().toggled('muscu', byDefault: true, on: false).toggled('boulot', byDefault: false, on: true);
    final p2 = resolveSportPick(all, domains, o);
    expect(p2.contains('muscu'), isFalse);
    expect(p2.kinds['boulot'], SportKind.session);
    expect(SportOverrides.from(o.toJson()).sameAs(o), isTrue);
  });

  test('séances : 10 min cumulées, routine couverte par son chrono, répétitions à part', () {
    final pick = resolveSportPick(all, domains);
    final now = DateTime(2026, 11, 1, 20); // dimanche
    final sessions = [
      ses('courir', DateTime(2026, 10, 26, 7), 6), ses('courir', DateTime(2026, 10, 26, 18), 6), // lundi : 12 min = 1 séance
      ses('muscu', DateTime(2026, 10, 27, 7), 5), // mardi : 5 min, pas une séance
    ];
    final hits = [
      HabitHit(habitId: 'footing', ts: DateTime(2026, 10, 26, 19)), // couvert par Courir lundi
      HabitHit(habitId: 'footing', ts: DateTime(2026, 10, 28, 8)), // mercredi : séance par la routine
      for (var i = 0; i < 15; i++) HabitHit(habitId: 'pompes', ts: DateTime(2026, 10, 29, 9)),
    ];
    final days = sportDays(pick: pick, sessions: sessions, hits: hits, fromYmd: '2026-09-01', toYmd: '2026-11-01', now: now, dayStartMin: 0);
    final byYmd = {for (final d in days) d.ymd: d};
    expect(byYmd['2026-10-26']!.sessions, 1);
    expect(byYmd['2026-10-27']!.isRest, isTrue);
    expect(byYmd['2026-10-28']!.sessionIds, ['footing']);
    expect(byYmd['2026-10-29']!.repsOnly, isTrue);
    final s = sportSummary(days);
    expect(s.weekSessions, 2);
    expect(s.weekMin, 17);
    expect(s.weekRestDays, 4); // mar, jeu, ven, sam (aujourd'hui vide exclu)
    expect(s.longestRest, 23); // du 3 au 25 oct.
    final reps = repsStats(pick, days, hits, 0);
    expect(reps.single.week, 15);
    expect(reps.single.weekTarget, 140);
    expect(reps.single.record, 15);
  });

  test('baisse sur 4 semaines et lendemains', () {
    final weeks = [
      for (var i = 0; i < 9; i++) SportWeekVolume('w$i', {'muscu': i < 4 ? 60 : 10, 'courir': 40}),
    ];
    final d = sportDecline(weeks)!;
    expect(d.activityId, 'muscu');
    expect(d.priorMin, 60);
    expect(d.recentMin, 10);

    final days = [
      for (var i = 1; i <= 12; i++) SportDay('2026-10-${i.toString().padLeft(2, '0')}', const {}, i.isOdd ? const ['courir'] : const [], const {}),
    ];
    final low = {for (var i = 2; i <= 13; i++) '2026-10-${i.toString().padLeft(2, '0')}': i.isEven ? 0.1 : 0.4};
    final imp = sportImpact(days, low, const {}, '2026-10-20');
    expect(imp.enough, isTrue);
    expect(imp.after.lowShare, closeTo(0.1, 1e-9));
    expect(imp.without.lowShare, closeTo(0.4, 1e-9));
  });
}
