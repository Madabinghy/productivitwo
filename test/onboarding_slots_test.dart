import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/onboarding_slots.dart';

void main() {
  group('definitionSessionSlots', () {
    // 2026-07-09 est un jeudi.
    final thursday = DateTime(2026, 7, 9, 18, 41);

    test('1ᵉʳ créneau = prochain soir de semaine 18:30 (jamais le week-end)',
        () {
      final slots = definitionSessionSlots(thursday, 1);
      expect(slots.single, DateTime(2026, 7, 10, 18, 30)); // vendredi

      // Depuis un vendredi, demain = samedi → saute au lundi.
      final friday = DateTime(2026, 7, 10, 20, 0);
      expect(definitionSessionSlots(friday, 1).single,
          DateTime(2026, 7, 13, 18, 30));
    });

    test('2ᵉ créneau = prochain dimanche 11:00', () {
      final slots = definitionSessionSlots(thursday, 2);
      expect(slots[1], DateTime(2026, 7, 12, 11, 0)); // dimanche

      // Depuis un dimanche soir : le dimanche proposé est le SUIVANT.
      final sunday = DateTime(2026, 7, 12, 18, 0);
      expect(definitionSessionSlots(sunday, 2)[1],
          DateTime(2026, 7, 19, 11, 0));
    });

    test('3ᵉ et suivants = soirs de semaine en cascade', () {
      final slots = definitionSessionSlots(thursday, 4);
      expect(slots[2], DateTime(2026, 7, 13, 18, 30)); // lundi (après ven)
      expect(slots[3], DateTime(2026, 7, 14, 18, 30)); // mardi
    });

    test('count 0 → vide', () {
      expect(definitionSessionSlots(thursday, 0), isEmpty);
    });
  });

  group('libellés', () {
    test('rationale : dimanche vs semaine', () {
      expect(slotRationale(DateTime(2026, 7, 12, 11, 0)),
          contains('rapport hebdo'));
      expect(slotRationale(DateTime(2026, 7, 10, 18, 30)),
          contains('après ta journée'));
    });

    test('libellé court', () {
      expect(slotShortLabel(DateTime(2026, 7, 10, 18, 30)), 'ven 18:30');
      expect(slotShortLabel(DateTime(2026, 7, 12, 11, 0)), 'dim 11:00');
    });
  });
}
