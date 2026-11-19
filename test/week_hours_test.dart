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

  test('détente : comptée à part, jamais dans l\'actif ; le sommeil et les repas priment', () {
    final all = [...acts, Activity(id: 'j', domainId: 'chill', name: 'Jeux vidéo')];
    final sessions = [
      s('w', DateTime(2026, 11, 11, 9), 120),
      s('j', DateTime(2026, 11, 11, 10), 120), // chevauche 1 h de travail : la détente prime sur l'actif
      s('j', DateTime(2026, 11, 10, 20), 90),
      s('m', DateTime(2026, 11, 10, 20), 30), // le repas prime sur la détente
      s('j', DateTime(2026, 11, 2, 20), 45), // les 7 jours d'avant
    ];
    final h = weekHours(now: now, activities: all, sessions: sessions, leisureIds: {'j'});
    expect(h.activeMin, 60);
    expect(h.leisureMin, 120 + 60);
    expect(h.basicMin, 30);
    expect(h.trackedMin, 60 + 180 + 30);
    expect(h.prevLeisureMin, 45);
    expect(h.dayActive.last, 60);
    expect(h.dayLeisure.last, 120);
    expect(h.dayLeisure[h.dayLeisure.length - 2], 60);
    // Sans domaine de détente, tout reste actif comme avant.
    final plain = weekHours(now: now, activities: all, sessions: sessions);
    expect(plain.leisureMin, 0);
    expect(plain.activeMin, 180 + 60);
  });

  test('petites durées : en minutes sous une heure, et un arc jamais invisible', () {
    expect(spanLabel(0), '0 h');
    expect(spanLabel(20), '20 min');
    expect(spanLabel(30), '30 min');
    expect(spanLabel(60), '1 h');
    expect(spanLabel(69 * 60 + 20), '69 h');
    final all = [...acts, Activity(id: 'j', domainId: 'chill', name: 'Jeux vidéo')];
    final h = weekHours(now: now, activities: all, leisureIds: {'j'}, sessions: [
      s('w', DateTime(2026, 11, 10, 8), 12 * 60),
      s('j', DateTime(2026, 11, 11, 10), 30),
    ]);
    final f = gaugeFractions(h);
    expect(f.length, 5);
    expect(f[0], closeTo(12 / 168, 1e-9));
    // 30 min = 0,3 % du cadran : dessiné au plancher de 3° sur 240.
    expect(f[1], closeTo(3 / 240, 1e-9));
    expect(f[2], 0);
    expect(f.fold<double>(0, (a, b) => a + b), closeTo(1, 1e-9));
    // Rien de tracé : tout le cadran est libre.
    final empty = gaugeFractions(weekHours(now: now, activities: all, sessions: const []));
    expect(empty, [0, 0, 0, 0, 1]);
  });

  test('chrono en cours compté jusqu\'à maintenant', () {
    final h = weekHours(now: now, activities: acts, sessions: [Session(activityId: 'w', startAt: DateTime(2026, 11, 11, 14))]);
    expect(h.activeMin, 60);
  });

  test('aiguille et triangle : ce qui tourne maintenant, ce qui tournait il y a 7 jours à la même minute', () {
    final all = [...acts, Activity(id: 'j', domainId: 'c', name: 'Jeux vidéo')];
    final h = weekHours(now: now, activities: all, leisureIds: {'j'}, sessions: [
      Session(activityId: 'j', startAt: DateTime(2026, 11, 11, 14, 30)), // chrono ouvert : maintenant
      s('w', DateTime(2026, 11, 4, 14), 120), // couvre le 4 à 15 h : il y a 7 jours
      s('m', DateTime(2026, 11, 11, 12), 30), // fini : ne dit rien de maintenant
    ]);
    expect(h.nowKind, HoursKind.leisure);
    expect(h.nowName, 'Jeux vidéo');
    expect(h.pastKind, HoursKind.active);
    expect(h.pastName, 'Travail');
    expect(hoursMomentLabel(h.nowKind, h.nowName, now: true), 'Détente · Jeux vidéo');
    expect(hoursMoveSentence(h.nowKind, h.pastKind), 'La détente avance, le vert recule.');

    // Rien ne tourne, rien ne tournait : la jauge ne bouge pas.
    final idle = weekHours(now: now, activities: all, sessions: [s('w', DateTime(2026, 11, 4, 15, 1), 60), s('w', DateTime(2026, 11, 11, 13), 60)]);
    expect(idle.nowKind, HoursKind.free);
    expect(idle.pastKind, HoursKind.free);
    expect(hoursMomentLabel(idle.nowKind, null, now: true), 'aucun chrono');
    expect(hoursMomentLabel(idle.pastKind, null), 'rien de tracé');
    expect(hoursMoveSentence(HoursKind.free, HoursKind.free), contains('ne bouge pas'));

    // Deux chronos sur la même minute : le plus fort gagne, comme dans le compte ; « Sommeil » ne se répète pas.
    final both = weekHours(now: now, activities: all, sessions: [
      Session(activityId: 'w', startAt: DateTime(2026, 11, 11, 9)),
      Session(activityId: 's', startAt: DateTime(2026, 11, 11, 14)),
      Session(activityId: 'w', startAt: DateTime(2026, 11, 4, 16), endAt: DateTime(2026, 11, 4, 17), deleted: true),
    ]);
    expect(both.nowKind, HoursKind.sleep);
    expect(hoursMomentLabel(both.nowKind, both.nowName, now: true), 'Sommeil');
    expect(hoursMoveSentence(HoursKind.active, HoursKind.free), 'Le vert avance, ton temps libre recule.');
  });
}
