import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/auto_target.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/held_weeks.dart';
import 'package:productivitwo_v1/utils/routine_cover.dart';

/// Cible automatique : un cran de plus à 120 % sur 7 jours clos, un cran de moins sous 50 %, et un jour passé
/// reste jugé avec la cible de ce jour-là.
void main() {
  // Vendredi 20 nov. 2026, midi.
  final now = DateTime(2026, 11, 20, 12);

  Activity pompes({int target = 20, bool auto = true, bool rolling = false, int? cap, DateTime? tunedAt, DateTime? createdAt}) => Activity(
        id: 'pompes',
        domainId: 'sport',
        name: 'Pompes',
        type: 'habit',
        habitFreq: HabitFreq.daily,
        habitTarget: target,
        autoTarget: auto,
        rolling: rolling,
        finalTarget: cap,
        lastTuneAt: tunedAt,
        createdAt: createdAt ?? DateTime(2026, 1, 1),
      );

  /// [perDay] : coches des jours passés, le dernier élément = HIER.
  List<HabitHit> hits(List<int> perDay, {String id = 'pompes'}) => [
        for (var i = 0; i < perDay.length; i++)
          for (var k = 0; k < perDay[i]; k++)
            HabitHit(habitId: id, ts: DateTime(2026, 11, 19 - (perDay.length - 1 - i), 9, k ~/ 60, k % 60)),
      ];

  group('la règle', () {
    test('120 % sur 7 jours : un cran de plus (10 %)', () {
      final d = autoTargetDecision(pompes(), hits([24, 24, 24, 24, 24, 24, 24]), now)!;
      expect((d.from, d.to, d.pct, d.up), (20, 22, 120, true));
      expect(d.note('Pompes'), 'Pompes : cible 20 → 22 par jour (120 % sur 7 jours)');
    });

    test('119 % : rien ne bouge', () {
      expect(autoTargetDecision(pompes(), hits([24, 24, 24, 24, 24, 24, 22]), now), isNull);
    });

    test('entre 50 et 120 % : rien ne bouge', () {
      expect(autoTargetDecision(pompes(), hits([20, 20, 10, 20, 0, 20, 20]), now), isNull);
    });

    test('sous 50 % : un cran de moins', () {
      final d = autoTargetDecision(pompes(), hits([20, 0, 0, 20, 0, 20, 0]), now)!;
      expect((d.from, d.to, d.up), (20, 18, false));
    });

    test('jamais sous 1', () {
      expect(autoTargetDecision(pompes(target: 1), hits([0, 0, 0, 0, 0, 0, 0]), now), isNull);
      expect(autoTargetDecision(pompes(target: 2), hits([0, 0, 0, 0, 0, 0, 0]), now)!.to, 1);
    });

    test('la nouvelle cible ne dépasse jamais la moyenne vraiment faite', () {
      // Cible 1, 9 coches en 7 jours (129 %) : passer à 2 par jour serait au-dessus du réel.
      expect(autoTargetDecision(pompes(target: 1), hits([2, 1, 1, 2, 1, 1, 1]), now), isNull);
      // 14 coches : 2 par jour sont déjà tenues.
      expect(autoTargetDecision(pompes(target: 1), hits([2, 2, 2, 2, 2, 2, 2]), now)!.to, 2);
    });

    test('aujourd\'hui ne compte pas : seuls les jours clos', () {
      final today = [for (var k = 0; k < 200; k++) HabitHit(habitId: 'pompes', ts: DateTime(2026, 11, 20, 9, k ~/ 60, k % 60))];
      expect(autoTargetDecision(pompes(), [...hits([20, 20, 20, 20, 20, 20, 20]), ...today], now), isNull);
    });

    test('éteinte, hebdomadaire ou à cap : pas concernée', () {
      final h = hits([30, 30, 30, 30, 30, 30, 30]);
      expect(autoTargetDecision(pompes(auto: false), h, now), isNull);
      expect(autoTargetDecision(pompes(cap: 50), h, now), isNull);
      final weekly = pompes()..habitFreq = HabitFreq.weekly;
      expect(autoTargetDecision(weekly, h, now), isNull);
    });

    test('une semaine pleine à la cible actuelle avant de juger', () {
      final h = hits([30, 30, 30, 30, 30, 30, 30]);
      // Cible changée il y a 3 jours : on attend.
      expect(autoTargetDecision(pompes(tunedAt: DateTime(2026, 11, 17, 8)), h, now), isNull);
      // Il y a 7 jours : la fenêtre est entière.
      expect(autoTargetDecision(pompes(tunedAt: DateTime(2026, 11, 13, 8)), h, now), isNotNull);
      // Routine créée il y a 4 jours : trop jeune.
      expect(autoTargetDecision(pompes(createdAt: DateTime(2026, 11, 16)), h, now), isNull);
    });

    test('un jour gelé ne compte ni dans le fait ni dans le demandé', () {
      // 2 jours gelés à zéro, 5 jours à 24 : 120 % sur 5 jours.
      final d = autoTargetDecision(pompes(), hits([24, 24, 0, 0, 24, 24, 24]), now, frozen: {'2026-11-15', '2026-11-16'})!;
      expect((d.to, d.days, d.pct), (22, 5, 120));
      // Sans le gel, la semaine est à 86 % : rien.
      expect(autoTargetDecision(pompes(), hits([24, 24, 0, 0, 24, 24, 24]), now), isNull);
      // Moins de 5 jours comptés : on ne décide pas.
      expect(autoTargetDecision(pompes(), hits([0, 0, 0, 0, 0, 0, 0]), now, frozen: {'2026-11-13', '2026-11-14', '2026-11-15'}), isNull);
    });
  });

  group('la cible d\'un jour passé', () {
    test('sans historique : la cible d\'aujourd\'hui', () {
      expect(pompes().targetOnYmd('2026-01-05'), 20);
    });

    test('après un changement : chaque jour garde la sienne', () {
      final a = pompes(target: 10)..keepTargetUntil('2026-11-12');
      a.habitTarget = 12;
      a.keepTargetUntil('2026-11-19');
      a.habitTarget = 14;
      expect(a.targetOnYmd('2026-11-01'), 10);
      expect(a.targetOnYmd('2026-11-12'), 10);
      expect(a.targetOnYmd('2026-11-13'), 12);
      expect(a.targetOnYmd('2026-11-19'), 12);
      expect(a.targetOnYmd('2026-11-20'), 14);
    });

    test('deux changements le même jour : une seule trace, celle d\'avant', () {
      final a = pompes(target: 10)..keepTargetUntil('2026-11-19');
      a.habitTarget = 30;
      a.keepTargetUntil('2026-11-19');
      a.habitTarget = 12;
      expect(a.targetLog.length, 1);
      expect(a.targetOnYmd('2026-11-19'), 10);
    });

    test('l\'historique survit à l\'enregistrement', () {
      final a = pompes(target: 10)..keepTargetUntil('2026-11-19');
      a.habitTarget = 11;
      final b = Activity.from(a.toJson());
      expect((b.autoTarget, b.targetOnYmd('2026-11-19'), b.targetOnYmd('2026-11-20')), (true, 10, 11));
      // Une routine d'avant : ni réglage ni historique.
      final old = Activity.from({'id': 'r', 'name': 'X', 'type': 'habit', 'habitFreq': 0, 'habitTarget': 3});
      expect((old.autoTarget, old.targetLog.length, old.targetOnYmd('2026-01-01')), (false, 0, 3));
    });
  });

  group('une hausse ne casse aucune série', () {
    test('routine « chaque jour » : les jours tenus à l\'ancienne cible le restent', () {
      final state = AppState(domains: [], activities: [pompes()], sessions: [], habitProgress: []);
      state.habitHits.addAll(hits([24, 24, 24, 24, 24, 24, 24, 20, 20, 20, 24, 24, 24, 24, 24, 24, 24]));
      final logic = AppLogic(state, () {});
      final a = state.activities.first;
      final before = routineSeries(a, state.habitHits, now).current;
      expect(before, 17);

      final notes = logic.applyAutoTargets(now: now);
      expect(notes, ['Pompes : cible 20 → 22 par jour (120 % sur 7 jours)']);
      expect(a.habitTarget, 22);
      expect(a.lastTuneAt, now);
      // Les trois jours à 20 d'il y a deux semaines tiennent toujours la série.
      expect(routineSeries(a, state.habitHits, now).current, before);
      expect(routineReachedDays(a, state.habitHits, now: now).length, 17);
      // Une seconde passe le même jour ne remonte pas encore.
      expect(logic.applyAutoTargets(now: now), isEmpty);
    });

    test('routine « sur 7 jours » : les jours tenus le restent', () {
      final a = pompes(rolling: true);
      final h = hits([20, 20, 20, 20, 20, 20, 20, 24, 24, 24, 24, 24, 24, 24]);
      final before = rollingHeldDays(a, h, now).length;
      a.keepTargetUntil('2026-11-19');
      a.habitTarget = 40;
      // Seul aujourd'hui (rien de fait, nouvelle cible) n'est pas tenu.
      expect(rollingHeldDays(a, h, now).length, before - 1);
    });

    test('routine rattrapable : pas de nouveau trou dans le passé', () {
      final a = pompes(target: 1)..catchUp = true;
      final h = hits([1, 1, 1, 1, 1, 1, 1]);
      expect(catchUpOf(a, h, now).open, isEmpty);
      a.keepTargetUntil('2026-11-19');
      a.habitTarget = 2;
      expect(catchUpOf(a, h, now).open, isEmpty);
    });

    test('semaines tenues : une semaine passée garde sa cible', () {
      final a = pompes(target: 10)..keepTargetUntil('2026-11-15');
      a.habitTarget = 20;
      expect(weekTargetFor(a, 7, monday: DateTime(2026, 11, 9)), 70);
      expect(weekTargetFor(a, 7, monday: DateTime(2026, 11, 16)), 140);
      expect(weekTargetFor(a, 7), 140);
    });
  });

  test('changer la cible à la main fait attendre une semaine', () {
    final state = AppState(domains: [], activities: [pompes()], sessions: [], habitProgress: []);
    final logic = AppLogic(state, () {});
    final a = state.activities.first;
    logic.setRoutineTarget(a, 25);
    expect(a.habitTarget, 25);
    expect(a.lastTuneAt, isNotNull);
    // Sans la cible automatique, rien n'est noté.
    final b = pompes(auto: false);
    logic.setRoutineTarget(b, 5);
    expect(b.lastTuneAt, isNull);
  });

  test('« dernier changement » de la fiche', () {
    final a = pompes(target: 20);
    expect(lastTargetChangeLabel(a), isNull);
    a.keepTargetUntil('2026-11-19');
    a.habitTarget = 22;
    expect(lastTargetChangeLabel(a), '20 → 22 depuis le 20 nov.');
  });
}
