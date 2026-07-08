import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';

void main() {
  group('Domain — intention & minimum vital', () {
    test('round-trip complet (toJson → from)', () {
      final d = Domain(
        name: 'Santé',
        colorValue: 0xFF27C48F,
        intention: 'Retrouver un corps qui suit le rythme que je m\'impose',
        vitalMinimum: [
          VitalMinimum(
              label: '2 séances / sem',
              metric: 'sessions_week',
              target: 2,
              period: 'week'),
        ],
        modalities: ['séances le matin 7h15 (prep la veille)'],
        wantedArtifacts: ['Plan de reprise — 6 semaines'],
        definitionStatus: 'active',
        definedAt: DateTime(2026, 7, 9),
      );
      final back = Domain.from(d.toJson());
      expect(back.intention, d.intention);
      expect(back.vitalMinimum.single.label, '2 séances / sem');
      expect(back.vitalMinimum.single.target, 2);
      expect(back.modalities.single, contains('7h15'));
      expect(back.wantedArtifacts.single, contains('Plan de reprise'));
      expect(back.definitionStatus, 'active');
      expect(back.isDefined, isTrue);
      expect(back.definedAt, DateTime(2026, 7, 9));
    });

    test('modalities accepte [{label}] (spec) et ["…"] (tolérance)', () {
      final fromMaps = Domain.from({
        'name': 'X',
        'modalities': [
          {'label': 'a'},
          {'label': 'b'},
        ],
      });
      expect(fromMaps.modalities, ['a', 'b']);
      final fromStrings = Domain.from({
        'name': 'X',
        'modalities': ['a', 'b'],
      });
      expect(fromStrings.modalities, ['a', 'b']);
    });

    test('rétrocompat : domaine legacy sans les nouveaux champs', () {
      final legacy = Domain.from({
        'id': 'd1',
        'name': 'Travail',
        'goalMinDay': 120,
        'autoGoal': true,
      });
      expect(legacy.name, 'Travail');
      expect(legacy.intention, isNull);
      expect(legacy.vitalMinimum, isEmpty);
      expect(legacy.definitionStatus, 'none');
      expect(legacy.isDefined, isFalse);
      // Et le round-trip ne casse rien.
      final back = Domain.from(legacy.toJson());
      expect(back.goalMinDay, 120);
    });
  });
}
