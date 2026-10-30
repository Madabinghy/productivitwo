import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/recharge.dart';

void main() {
  final flemme = ElanWindow(MoodMark(at: DateTime(2026, 10, 30, 17), ymd: '2026-10-30', kind: kMoodElan, value: 2), DateTime(2026, 10, 30, 21));
  final cuisiner = Activity(id: 'c', name: 'Cuisiner', domainId: 'd', type: 'time');
  final manger = Activity(id: 'm', name: 'Manger', domainId: 'd', type: 'time');
  final travail = Activity(id: 'w', name: 'Productivitwo', domainId: 'd', type: 'time');
  final acts = [cuisiner, manger, travail];
  final now = DateTime(2026, 10, 30, 22);

  test('besoins de base : repos et repas, pas cuisiner', () {
    expect(isBasicNeedName('Manger'), isTrue);
    expect(isBasicNeedName('Repas équilibré'), isTrue);
    expect(isBasicNeedName('Dîner'), isTrue);
    expect(isBasicNeedName('Sieste'), isTrue);
    expect(isBasicNeedName('Cuisiner'), isFalse);
  });

  test('un chrono lancé en Flemme et tenu 10 min est une victoire ; 8 min non', () {
    final w = flemmeWinsIn(flemme, blocks: const [], hits: const [], activities: acts, now: now, sessions: [
      Session(activityId: 'c', startAt: DateTime(2026, 10, 30, 19), endAt: DateTime(2026, 10, 30, 19, 12)),
      Session(activityId: 'w', startAt: DateTime(2026, 10, 30, 18), endAt: DateTime(2026, 10, 30, 18, 8)),
      Session(activityId: 'm', startAt: DateTime(2026, 10, 30, 19, 45), endAt: DateTime(2026, 10, 30, 20, 15)),
    ]);
    expect(w.map((x) => (x.what, x.how)).toList(), [('Cuisiner', 'chrono tenu 12 min')]);
    expect(w.single.at, DateTime(2026, 10, 30, 19, 10));
  });

  test('un chrono qui tourne encore compte dès 10 min', () {
    final w = flemmeWinsIn(flemme, blocks: const [], hits: const [], activities: acts, now: DateTime(2026, 10, 30, 19, 11), sessions: [
      Session(activityId: 'c', startAt: DateTime(2026, 10, 30, 19)),
    ]);
    expect(w.length, 1);
  });

  test('action cochée = victoire ; bloc fait déjà compté par son chrono = une seule', () {
    final w = flemmeWinsIn(
      flemme,
      blocks: [
        ScheduleBlock(startTime: '19:00', durationMin: 45, title: 'Cuisiner', activityId: 'c', status: 'done', doneAt: DateTime(2026, 10, 30, 19, 45)),
        ScheduleBlock(startTime: '19:45', durationMin: 30, title: 'Manger', status: 'done', doneAt: DateTime(2026, 10, 30, 20, 15)),
      ],
      hits: const [],
      activities: acts,
      now: now,
      sessions: [Session(activityId: 'c', startAt: DateTime(2026, 10, 30, 19), endAt: DateTime(2026, 10, 30, 19, 40))],
      doneActions: [(at: DateTime(2026, 10, 30, 18, 20), title: 'Envoyer le devis')],
    );
    expect(w.map((x) => x.how).toList(), ['action cochée', 'chrono tenu 40 min']);
  });

  test('actions faites des projets et des activités', () {
    final a = TaskAction(title: 'Envoyer le devis')
      ..done = true
      ..doneAt = DateTime(2026, 10, 30, 18);
    final d = DateTime(2026, 10, 1);
    final p = Project(title: 'P', startDate: d, createdBy: 'user', tasks: [ProjectTask(title: 'T', startDate: d, actions: [a])]);
    expect(doneActionsOf([p], const []).single.title, 'Envoyer le devis');
  });
}
