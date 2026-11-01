import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/week_review.dart';

void main() {
  const ds = 5 * 60;

  test('fenêtre de la carte et semaine regardée', () {
    expect(reviewWindowOpen(DateTime(2026, 10, 31, 17), ds), isFalse); // samedi 17 h
    expect(reviewWindowOpen(DateTime(2026, 10, 31, 19), ds), isTrue);
    expect(reviewWindowOpen(DateTime(2026, 11, 1, 10), ds), isTrue); // dimanche
    expect(reviewWindowOpen(DateTime(2026, 11, 2, 2), ds), isTrue); // nuit de dimanche à lundi = encore dimanche
    expect(reviewWindowOpen(DateTime(2026, 11, 2, 11), ds), isTrue); // lundi matin
    expect(reviewWindowOpen(DateTime(2026, 11, 2, 13), ds), isFalse);
    expect(reviewedMonday(DateTime(2026, 11, 1, 10), ds), '2026-10-26');
    expect(reviewedMonday(DateTime(2026, 11, 2, 9), ds), '2026-10-26');
    expect(weekDays('2026-10-26').last, '2026-11-01');
  });

  test('revue gardée, phrase rappelée la semaine suivante', () {
    final r = parseWeekReviews({
      '2026-10-26': {'at': '2026-11-01T20:00:00.000', 'intention': ' Me coucher avant minuit ', 'decisions': ['Courses : 6 min']},
      'cassé': {'intention': 'x'},
    });
    expect(r.keys, ['2026-10-26']);
    expect(r['2026-10-26']!.decisions, ['Courses : 6 min']);
    expect(weekIntention(r, DateTime(2026, 11, 3, 9), ds), 'Me coucher avant minuit');
    expect(weekIntention(r, DateTime(2026, 11, 10, 9), ds), isNull);
    expect(r['2026-10-26']!.toJson()['intention'], 'Me coucher avant minuit');
  });

  test('projets : avancé dans la semaine, endormis', () {
    TaskAction a(String t, DateTime? done) => TaskAction(title: t, done: done != null, doneAt: done);
    final p1 = Project(title: 'App', startDate: DateTime(2026, 9, 1), createdBy: 'u', tasks: [
      ProjectTask(title: 'T1', startDate: DateTime(2026, 10, 1), actions: [a('x', DateTime(2026, 10, 28, 10)), a('y', DateTime(2026, 10, 29, 10))]),
      ProjectTask(title: 'T2', startDate: DateTime(2026, 10, 1), actions: [a('z', DateTime(2026, 10, 30, 10)), a('w', null)]),
    ]);
    final p2 = Project(title: 'Site', startDate: DateTime(2026, 9, 1), createdBy: 'u', tasks: [
      ProjectTask(title: 'T', startDate: DateTime(2026, 10, 1), actions: [a('old', DateTime(2026, 10, 15, 10)), a('open', null)]),
    ]);
    final paused = Project(title: 'Pause', startDate: DateTime(2026, 9, 1), createdBy: 'u', paused: true, tasks: [
      ProjectTask(title: 'T', startDate: DateTime(2026, 10, 1), actions: [a('open', null)]),
    ]);
    final weeks = projectWeeks([p2, p1], weekDays('2026-10-26'), ds);
    expect(weeks.first.project.title, 'App');
    expect(weeks.first.actions, 3);
    expect(weeks.first.tasks, 1);
    expect(weeks.last.actions, 0);
    final st = stalledProjects([p1, p2, paused], DateTime(2026, 11, 1, 10));
    expect(st.map((e) => e.$1.title), ['Site']);
    expect(st.first.$2, 17);
  });

  test('minutes par domaine, coupées aux bornes de la semaine', () {
    final act = Activity(id: 'w', domainId: 'travail', name: 'Code', type: 'time');
    final m = minutesByDomainOf([
      Session(activityId: 'w', startAt: DateTime(2026, 10, 25, 23), endAt: DateTime(2026, 10, 26, 1)),
      Session(activityId: 'w', startAt: DateTime(2026, 10, 28, 9), endAt: DateTime(2026, 10, 28, 10)),
    ], [act], weekDays('2026-10-26'), DateTime(2026, 11, 1, 12));
    expect(m['travail'], 120);
  });
}
