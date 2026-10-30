import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/notif_digest.dart';

void main() {
  test('morningDigest : parties non nulles, accords, journée vide', () {
    expect(morningDigest(blocks: 4, routines: 12, focused: 2, series: 1), '4 blocs · 12 routines · 2 actions visées · 🔥 1 série à tenir');
    expect(morningDigest(blocks: 1, routines: 0, focused: 1, series: 0), '1 bloc · 1 action visée');
    expect(morningDigest(blocks: 0, routines: 0, focused: 0, series: 0), 'Rien de prévu : pose ta journée.');
  });

  test('eveningDigest : rien ne manque → null ; séries en tête', () {
    expect(eveningDigest(routines: 0, blocks: 0, seriesAtRisk: const []), isNull);
    final d = eveningDigest(routines: 2, blocks: 1, seriesAtRisk: const ['Pompes', 'Lecture', 'Eau'])!;
    expect(d.title, 'Journée parfaite : il manque 3');
    expect(d.body, '🔥 Pompes, Lecture +1 à tenir ce soir · 2 routines · 1 bloc');
  });
}
