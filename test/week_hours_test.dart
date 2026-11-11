import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/week_hours.dart';

void main() {
  final now = DateTime(2026, 11, 11, 15, 0);
  final acts = [
    Activity(id: 'w', domainId: 'd', name: 'Travail'),
    Activity(id: 's', domainId: 'd', name: 'Sommeil'),
    Activity(id: 'm', domainId: 'd', name: 'Manger'),
  ];
  Session s(String a, DateTime from, int min) => Session(activityId: a, startAt: from, endAt: from.add(Duration(minutes: min)));

  test('fenêtre glissante : actif, sommeil, besoins, flou ; une minute comptée une fois', () {
    final h = weekHours(now: now, activities: acts, sessions: [
      s('w', DateTime(2026, 11, 11, 9), 120),
      s('w', DateTime(2026, 11, 11, 10), 60), // chevauche : pas compté deux fois
      s('s', DateTime(2026, 11, 10, 23), 420),
      s('m', DateTime(2026, 11, 11, 12), 30),
      s('w', DateTime(2026, 11, 3, 10), 60), // avant la fenêtre : les 7 jours d'avant
    ]);
    expect(h.activeMin, 120);
    expect(h.sleepMin, 420);
    expect(h.basicMin, 30);
    expect(h.untrackedMin, kWeekHoursMin - 570);
    expect(h.prevActiveMin, 60);
    expect(h.deltaMin, 60);
    expect(h.dayActive.last, 120);
  });

  test('ce qui sort de la fenêtre d\'ici demain et sommeil prioritaire', () {
    final h = weekHours(now: now, activities: acts, sessions: [
      s('w', DateTime(2026, 11, 4, 16), 60), // dans les 24 premières heures de la fenêtre
      s('w', DateTime(2026, 11, 10, 22), 120),
      s('s', DateTime(2026, 11, 10, 23), 60), // le sommeil prime sur le chrono resté ouvert
    ]);
    expect(h.leavingMin, 60);
    expect(h.activeMin, 120);
    expect(h.sleepMin, 60);
  });

  test('chrono en cours compté jusqu\'à maintenant', () {
    final h = weekHours(now: now, activities: acts, sessions: [Session(activityId: 'w', startAt: DateTime(2026, 11, 11, 14))]);
    expect(h.activeMin, 60);
  });
}
