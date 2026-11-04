import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/freedom.dart';

void main() {
  final now = DateTime(2026, 11, 4, 15);
  int ms(DateTime d) => d.millisecondsSinceEpoch;

  test('cartes Liberté : envies surmontées et jours libres cumulés, un écart n’efface rien', () {
    final stop = Freedom(
      plan: const FreedomPlan(name: 'Ma pause', goal: FreedomGoal.stop, startYmd: '2026-10-25', why: ''),
      urges: {
        for (var i = 0; i < 10; i++) 'u$i': FreedomUrge(id: 'u$i', at: ms(DateTime(2026, 10, 26 + i % 8, 10 + i)), intensity: 3, passed: true),
        'x': FreedomUrge(id: 'x', at: ms(DateTime(2026, 11, 1, 9)), intensity: 4, passed: false),
      },
      slips: {'s': FreedomSlip(id: 's', at: ms(DateTime(2026, 11, 1, 20)))},
    );
    final cards = freedomBadges({'a': stop}, now);
    expect(cards.map((c) => c.def.id), ['liberte-envies', 'liberte-jours']);
    expect(cards.every((c) => c.def.family == BadgeFamily.freedom), isTrue);
    expect(cards[0].value, 10);
    expect(cards[0].level, 2);
    // 25 oct → 3 nov : 10 jours, moins le jour de l'écart.
    expect(cards[1].value, 9);
    expect(cards[1].level, 1);
    expect(cards[1].def.name.contains('pause'), isFalse);
  });

  test('sous la limite : semaines closes tenues, seulement en Réduire ; rien sans chose suivie', () {
    final reduce = Freedom(
      plan: const FreedomPlan(name: 'X', goal: FreedomGoal.reduce, limit: 3, period: FreedomPeriod.week, startYmd: '2026-10-12', why: ''),
      slips: {
        's1': FreedomSlip(id: 's1', at: ms(DateTime(2026, 10, 14)), count: 2),
        's2': FreedomSlip(id: 's2', at: ms(DateTime(2026, 10, 21)), count: 5),
      },
    );
    expect(weeksUnderLimit(reduce, now), [DateTime(2026, 10, 18), DateTime(2026, 11, 1)]);
    expect(freedomBadges({'r': reduce}, now).last.def.id, 'liberte-limite');
    expect(freedomBadges(const {}, now), isEmpty);
  });
}
