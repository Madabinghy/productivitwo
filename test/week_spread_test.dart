import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/planning.dart' show WeekWant;
import 'package:productivitwo_v1/utils/week_spread.dart';

WeekWant w(String id, int weekly) => WeekWant(activityId: id, title: id, weeklyMin: weekly, reason: '');

void main() {
  final wants = [
    w('Interventions', 188 * 7), w('Contenu', 72 * 7), w('Productivitwo', 30 * 7), w('GDS', 45 * 7), w('Louanges', 34 * 7),
    w('Motivation', 30 * 7), w('Lecture', 180), w('Cuisiner', 180), w('Manger', 120), w('Courir', 120), w('Musculation', 120),
    w('Vaisselle', 70), w('Soins', 77),
  ];
  const domains = {'Interventions': 'biz', 'Contenu': 'biz', 'Productivitwo': 'biz', 'GDS': 'spi', 'Louanges': 'spi', 'Motivation': 'mind'};
  final fam = classifyWants(wants,
      domainOf: (id) => domains[id], isBase: (id) => id == 'Manger', isSport: (id) => id == 'Courir' || id == 'Musculation');

  test('familles', () {
    expect(fam['Manger'], PlanFamily.base);
    expect(fam['Courir'], PlanFamily.body);
    expect(fam['Vaisselle'], PlanFamily.daily);
    expect(fam['Cuisiner'], PlanFamily.daily);
    expect(fam['GDS'], PlanFamily.fond);
    expect(fam['Productivitwo'], PlanFamily.work); // domaine du travail
    expect(fam['Interventions'], PlanFamily.work);
  });

  test('répartition naturelle', () {
    final s = spreadByFamily(wants, fam, List.filled(7, 600));
    for (var d = 0; d < 7; d++) {
      expect(s.days[d].containsKey('Manger'), isFalse);
      expect(s.days[d].containsKey('Vaisselle'), isFalse);
      expect(s.days[d]['GDS'], 45);
      final work = ['Interventions', 'Contenu', 'Productivitwo'].where(s.days[d].containsKey).length;
      expect(work, lessThanOrEqualTo(2));
      if (d >= 5) expect(work, 0);
    }
    for (final a in ['Courir', 'Musculation']) {
      final ds = [for (var d = 0; d < 7; d++) if (s.days[d].containsKey(a)) d];
      expect(ds.length, greaterThanOrEqualTo(2));
      for (var k = 1; k < ds.length; k++) {
        expect(ds[k] - ds[k - 1], greaterThan(1));
      }
    }
    expect(s.unplaced['Interventions'], greaterThan(0));
    expect(s.dailyReserve, greaterThan(0));
  });
}
