import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

/// Les reports d'une routine à un moment survivent à la fusion local + distant.
void main() {
  test('routinePushedByYmd : fusionné, le local prime pour une même routine', () {
    final ymd = yyyymmdd(DateTime.now());
    final local = AppState(domains: [], activities: [], sessions: [], habitProgress: [], routinePushedByYmd: {
      ymd: ['repas:evening'],
    });
    final remote = AppState(domains: [], activities: [], sessions: [], habitProgress: [], routinePushedByYmd: {
      ymd: ['repas:afternoon', 'lecture:evening'],
    });
    final merged = FirestoreSync.merge(local, remote);
    expect(merged.routinePushedByYmd[ymd], ['repas:evening', 'lecture:evening']);
  });
}
