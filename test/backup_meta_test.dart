import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/backup.dart';

void main() {
  test('les données récentes sont dans le Coffre', () {
    expect(kBackupCollections, containsAll(['mood_marks', 'chain_runs']));
    expect(kBackupMetaKeys, containsAll(['dayStartMin', 'paroles', 'emberSpends', 'seasons', 'restPeriods', 'momentWindows']));
    expect(kBackupMetaKeys, isNot(contains('gold')));
  });

  test('meta : Fusionner garde le courant, Remplacer prend le fichier, l’or jamais', () {
    final file = {'dayStartMin': 300, 'paroles': {'2026-10-31': {'ids': ['a']}}, 'gold': 999, 'autoPlan': true};
    final current = {'dayStartMin': 360};
    expect(metaFieldsToRestore(file, current, replace: false), {
      'paroles': {'2026-10-31': {'ids': ['a']}},
      'autoPlan': true,
    });
    final all = metaFieldsToRestore(file, current, replace: true);
    expect(all['dayStartMin'], 300);
    expect(all.containsKey('gold'), isFalse);
  });
}
