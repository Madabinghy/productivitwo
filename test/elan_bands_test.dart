import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/elan_bands.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';

MoodMark m(String ymd, int h, int min, int v) {
  final p = ymd.split('-').map(int.parse).toList();
  return MoodMark(at: DateTime(p[0], p[1], p[2], h, min), ymd: ymd, kind: kMoodElan, value: v);
}

void main() {
  test('modes des valeurs', () {
    expect(bandModeOf(null), isNull);
    expect(bandModeOf(0), BandMode.recharge);
    expect(bandModeOf(2), BandMode.low);
    expect(bandModeOf(3), BandMode.normal);
    expect(bandModeOf(5), BandMode.high);
  });

  test('cellules d\'un jour passé : du pointage à la fin', () {
    final marks = [m('2026-10-30', 9, 0, 3), m('2026-10-30', 12, 0, 1), m('2026-10-30', 14, 0, 3)];
    final cells = elanCellsOfDay(marks, '2026-10-30', DateTime(2026, 11, 1), 300);
    // 5 h → 9 h : rien de dit (16 quarts d'heure).
    expect(cells.take(16).every((c) => c == null), isTrue);
    expect(cells[16], 3); // 9:00
    expect(cells[28], 1); // 12:00
    expect(cells[36], 3); // 14:00
    final share = modeShareOf([cells]);
    expect(share.low, 8); // 12:00 → 14:00
    expect(share.dominant, BandMode.normal);
  });

  test('phrase de la semaine', () {
    final low = List<int?>.filled(96, null)..fillRange(10, 30, 1);
    final normal = List<int?>.filled(96, null)..fillRange(10, 60, 3);
    expect(weekBandSentence([('2026-10-26', normal), ('2026-10-30', low)], 3),
        'Surtout Normal. La flemme surtout le vendredi, et tu as démarré quand même 3 fois.');
    expect(weekBandSentence([('2026-10-26', normal)], 0), 'Surtout Normal. Pas de flemme cette semaine.');
    expect(weekBandSentence([('2026-10-26', List<int?>.filled(96, null))], 0), startsWith('Rien de dit'));
  });

  test('jours dits et flemmes gagnées', () {
    final days = [
      const ElanDay('2026-10-30', [ElanMarkView('matin', 2, true), ElanMarkView('aprem', 3, false)], null),
      const ElanDay('2026-10-31', [], null),
    ];
    expect(saidDays(days), 1);
    expect(lowWinsOf(days.first), 1);
  });

  test('ce que ça t\'apprend : creux, fenêtres, guérillas, tendance', () {
    // Flemme de 13 h à 15 h (dayStart 5 h : index 32 → 40).
    final d = List<int?>.filled(96, null)..fillRange(32, 40, 1)..fillRange(4, 8, 2);
    final by = lowByMoment([d], 300);
    expect(by['aprem'], 8);
    expect(by['matin'], 4);
    expect(hardestMoment(by), 'aprem');
    expect(bandMomentOf(80, 300), 'soir'); // 01:00 la nuit → soir
    expect(lowWindowsOf([const ElanDay('x', [ElanMarkView('matin', 1, true), ElanMarkView('soir', 2, false), ElanMarkView('aprem', 3, true)], null)]),
        (won: 1, total: 2));
    final now = DateTime(2026, 10, 31);
    final runs = [
      ChainRun(date: '2026-10-31', startedAt: now, endedAt: now, doneCount: 3, total: 3, completed: true, kind: 'guerilla', bodyBefore: 2, bodyAfter: 4),
      ChainRun(date: '2026-10-31', startedAt: now, endedAt: now, doneCount: 3, total: 3, completed: true, kind: 'guerilla', bodyBefore: 3, bodyAfter: 3),
      ChainRun(date: '2026-10-31', startedAt: now, endedAt: now, doneCount: 3, total: 3, completed: true),
    ];
    expect(guerillaRebound(runs, now.subtract(const Duration(days: 30))), (up: 1, total: 2));
    final normal = List<int?>.filled(96, 3);
    final w = weeklyLowPct([for (var i = 0; i < 21; i++) normal, for (var i = 0; i < 7; i++) d]);
    expect(w.length, 4);
    expect(w.first, 0);
    expect(w.last, 100);
  });
}

