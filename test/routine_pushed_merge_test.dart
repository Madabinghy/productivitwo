import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
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

  test('Annuler un report : la routine revient, et la fusion ne le ressuscite pas', () {
    final ymd = yyyymmdd(DateTime.now());
    final st = AppState(domains: [], activities: [], sessions: [], habitProgress: [], routinePushedByYmd: {
      ymd: ['footing:evening', 'aspi:evening'],
    });
    final logic = AppLogic(st, () {});
    logic.clearRoutinePushed(ymd, 'footing');
    expect(logic.routinePushed(ymd), {'aspi': 'evening'});
    // Un autre report ensuite garde l'annulation.
    logic.setRoutinePushed(ymd, logic.routinePushed(ymd)..['lecture'] = 'evening');
    expect(st.routinePushedByYmd[ymd], contains('footing:${kPushCleared}'));
    final remote = AppState(domains: [], activities: [], sessions: [], habitProgress: [], routinePushedByYmd: {
      ymd: ['footing:evening', 'aspi:evening'],
    });
    final merged = FirestoreSync.merge(st, remote);
    final mergedLogic = AppLogic(merged, () {});
    expect(mergedLogic.routinePushed(ymd).containsKey('footing'), isFalse);
  });
}
