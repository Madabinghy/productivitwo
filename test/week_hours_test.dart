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

  test('sans chrono, l\'aiguille dit où sera le vert demain si rien : ce qui sort des 24 premières heures', () {
    // 3 h il y a 6 jours et demi (elles sortent d'ici demain) et 5 h avant-hier (elles restent).
    final h = weekHours(now: now, activities: acts, sessions: [s('w', DateTime(2026, 11, 5, 1), 180), s('w', DateTime(2026, 11, 9, 9), 300)]);
    expect((h.activeMin, h.leavingMin, h.tomorrowActiveMin), (480, 180, 300));
    expect(h.tomorrowShare, closeTo(300 / 480, 1e-9));
    expect(hoursTomorrowLabel(h), '5 h · −3 h');
    // Rien ne sort : l'aiguille reste au bout du vert.
    final keep = weekHours(now: now, activities: acts, sessions: [s('w', DateTime(2026, 11, 9, 9), 300)]);
    expect((keep.leavingMin, keep.tomorrowActiveMin, keep.tomorrowShare), (0, 300, 1.0));
    expect(hoursTomorrowLabel(keep), '5 h · rien ne sort');
    // Aucune heure active : pas de division par zéro.
    final none = weekHours(now: now, activities: acts, sessions: const []);
    expect((none.tomorrowActiveMin, none.tomorrowShare), (0, 1.0));
    // Sommeil et repas qui sortent ne font pas reculer l'aiguille : le vert seul.
    final sleep = weekHours(now: now, activities: acts, sessions: [s('s', DateTime(2026, 11, 5, 0), 360), s('w', DateTime(2026, 11, 9, 9), 60)]);
    expect((sleep.leavingMin, sleep.tomorrowActiveMin), (0, 60));
    expect([spanExact(0), spanExact(45), spanExact(60), spanExact(747)], ['0 min', '45 min', '1 h', '12 h 27']);
  });

  test('à fond : 24 h actives entrent pendant que les 24 premières heures sortent', () {
    // 3 h sortent d'ici demain, 5 h restent : si rien 5 h, à fond 5 h + 24 h.
    final h = weekHours(now: now, activities: acts, sessions: [s('w', DateTime(2026, 11, 5, 1), 180), s('w', DateTime(2026, 11, 9, 9), 300)]);
    expect((h.tomorrowActiveMin, h.fullTomorrowActiveMin, h.fullGainMin), (300, 300 + 1440, 1440 - 180));
    expect(hoursFullLabel(h), '29 h · +21 h');
    // Rien d'actif : à fond = 24 h de gagnées.
    final none = weekHours(now: now, activities: acts, sessions: const []);
    expect((none.fullTomorrowActiveMin, none.fullGainMin), (1440, 1440));
  });

  test('cadran : sans chrono le repère recule dans le vert, en actif il passe au bout de la bande claire', () {
    final h = weekHours(now: now, activities: acts, sessions: [s('w', DateTime(2026, 11, 5, 1), 180), s('w', DateTime(2026, 11, 9, 9), 300)]);
    final g = gaugeLayout(h);
    expect(g.arcs.map((a) => a.kind), [HoursKind.active]);
    // Rien de tracé : dans le vert, à la part qui reste demain.
    expect(g.marks[HoursKind.free], closeTo(g.activeStart + g.activeLen * 300 / 480, 1e-9));
    expect(g.idleAt, lessThan(g.activeEnd));
    // Actif : après le vert, du gain de demain à fond.
    expect(g.marks[HoursKind.active], closeTo(g.activeEnd + kGaugeSweep * (1440 - 180) / kWeekHoursMin, 1e-9));
    expect(g.fullAt, greaterThan(g.activeEnd));
    expect(g.fullAt, lessThanOrEqualTo(g.end));
    // Un cadran presque plein : la bande claire s'arrête au bout du cadran.
    final full = WeekHours(activeMin: kWeekHoursMin - 60, basicMin: 0, sleepMin: 0, prevActiveMin: 0, leavingMin: 0, dayActive: const [], days: const []);
    final gf = gaugeLayout(full);
    expect(gf.fullAt, lessThanOrEqualTo(gf.end));
    expect(gf.end - gf.fullAt, lessThan(2 * 3.141592653589793 / 180));
  });
}
