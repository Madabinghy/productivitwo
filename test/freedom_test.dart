import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/freedom.dart';

int at(int d, int h) => DateTime(2026, 11, d, h).millisecondsSinceEpoch;

void main() {
  const plan = FreedomPlan(name: 'Ma pause', startYmd: '2026-10-23', costPerDay: 1200, why: 'Courir sans être essoufflé', triggers: ['Café'], parades: ['Marcher']);

  test('aller-retour JSON : plan, envies, écarts', () {
    final f = Freedom(
      plan: plan,
      urges: {'u1': FreedomUrge(id: 'u1', at: at(1, 14), intensity: 4, trigger: 'Café', parade: 'Marcher', durationSec: 380)},
      slips: {'s1': FreedomSlip(id: 's1', at: at(1, 22), count: 2, triggers: const ['Soirée'], next: 'Prévenir Sam')},
    );
    final back = parseFreedom(f.toJson());
    expect(back.plan!.name, 'Ma pause');
    expect(back.plan!.costPerDay, 1200);
    expect(back.urges['u1']!.intensity, 4);
    expect(back.slips['s1']!.count, 2);
    expect(back.slips['s1']!.next, 'Prévenir Sam');
    expect(parseFreedom(null).active, isFalse);
  });

  test('libre depuis le dernier écart ; envies surmontées jamais perdues', () {
    final f = Freedom(
      plan: plan,
      urges: {
        'a': FreedomUrge(id: 'a', at: at(1, 9), intensity: 3),
        'b': FreedomUrge(id: 'b', at: at(2, 9), intensity: 4, passed: false),
        'c': FreedomUrge(id: 'c', at: at(3, 9), intensity: 2),
      },
      slips: {'s': FreedomSlip(id: 's', at: at(2, 10))},
    );
    expect(freeSince(f), DateTime.fromMillisecondsSinceEpoch(at(2, 10)));
    expect(urgesOvercome(f), 2);
    expect(freeLabel(const Duration(days: 12, hours: 6)), '12 j 6 h');
    expect(freeLabel(const Duration(minutes: 20)), '20 min');
  });

  test('libre depuis l\'heure exacte du départ (sinon minuit)', () {
    final exact = Freedom(plan: FreedomPlan(name: 'X', startYmd: '2026-11-04', startAt: at(4, 11)));
    expect(freeSince(exact), DateTime.fromMillisecondsSinceEpoch(at(4, 11)));
    expect(parseFreedom(exact.toJson()).plan!.startAt, at(4, 11));
    final old = Freedom(plan: FreedomPlan(name: 'X', startYmd: '2026-11-04'));
    expect(freeSince(old), DateTime(2026, 11, 4));
  });

  test('argent pas dépensé : jours sans écart × coût ; prochain cap', () {
    final f = Freedom(plan: plan, slips: {'s': FreedomSlip(id: 's', at: at(1, 22))});
    // du 23 oct. au 3 nov. inclus = 12 jours, dont 1 avec écart.
    expect(freeDaysTotal(f, DateTime(2026, 11, 4, 10)), 11);
    expect(savedCents(f, DateTime(2026, 11, 4, 10)), 11 * 1200);
    expect(nextMilestone(const Duration(days: 12)), (days: 14, left: 2));
    expect(milestoneLabel(30), '1 mois');
  });

  test('réduire : consommé dans la semaine et dépassement', () {
    const red = FreedomPlan(name: 'Le soir', goal: FreedomGoal.reduce, limit: 3, unit: 'verres', startYmd: '2026-10-01');
    final f = Freedom(plan: red, slips: {
      'a': FreedomSlip(id: 'a', at: at(1, 20), count: 2), // dimanche 1er : semaine d'avant
      'b': FreedomSlip(id: 'b', at: at(3, 20), count: 2),
      'c': FreedomSlip(id: 'c', at: at(4, 20), count: 2),
    });
    expect(usedThisPeriod(f, DateTime(2026, 11, 4, 21)), 4);
    expect(overLimit(f, DateTime(2026, 11, 4, 21)), isTrue);
    expect(savedCents(f, DateTime(2026, 11, 4, 21)), 0);
  });

  test('ce que ça apprend : jours, force, moments, déclencheurs, parades', () {
    final f = Freedom(plan: plan, urges: {
      for (var i = 0; i < 4; i++) 'm$i': FreedomUrge(id: 'm$i', at: at(3, 14), intensity: 2, trigger: 'Café', parade: 'Marcher', durationSec: 300),
      'x': FreedomUrge(id: 'x', at: at(3, 15), intensity: 2, trigger: 'Stress', parade: 'Eau', passed: false),
      'old': FreedomUrge(id: 'old', at: DateTime(2026, 10, 25, 9).millisecondsSinceEpoch, intensity: 5),
    });
    final now = DateTime(2026, 11, 4, 10);
    final days = urgeDays(f, now, days: 3);
    expect(days.map((d) => d.urges), [0, 5, 0]);
    expect(intensityTrendPct(f, now), -60);
    expect(urgeHeat(f, now)[0][2], 5); // mardi 14 h-18 h
    expect(triggerShares(f, now).first.trigger, 'Café');
    expect(paradeRates(f).first.parade, 'Marcher');
    expect(bestParade(f), 'Marcher');
    expect(meanUrgeSec(f), 300);
  });

  test('plusieurs libertés : chacune à part, rangées par date de départ', () {
    final all = parseFreedoms({
      'b': {'plan': const FreedomPlan(name: 'Écrans', startYmd: '2026-11-01').toJson(), 'urges': {}},
      'a': {'plan': plan.toJson(), 'urges': {'u1': FreedomUrge(id: 'u1', at: at(1, 9), intensity: 2).toJson()}},
      'c': {'urges': {}},
    });
    expect(activeFreedomIds(all), ['a', 'b']);
    expect(urgesOvercome(all['a']!), 1);
    expect(urgesOvercome(all['b']!), 0);
    expect(parseFreedoms(null), isEmpty);
  });

  test('une envie validée deux fois ne compte qu’une fois', () {
    final t = at(7, 21);
    final f = parseFreedom({
      'urges': {
        'mz3k': {'at': t, 'intensity': 3, 'passed': true},
        'mz9a': {'at': t, 'intensity': 3, 'passed': true},
        urgeIdOf(at(7, 9)): {'at': at(7, 9), 'intensity': 2, 'passed': true},
      },
    });
    expect(f.urges.length, 2);
    expect(f.urges.containsKey('mz3k'), isTrue);
    expect(urgesOvercome(f), 2);
    expect(urgeIdOf(t), urgeIdOf(t));
  });
}
