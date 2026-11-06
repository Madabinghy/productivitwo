import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/hard_days.dart';

void main() {
  test('une fois tous les 14 jours', () {
    expect(canDeclareHardDay(const [], '2026-11-05'), isTrue);
    final d = withHardDay(const [], '2026-11-05');
    expect(canDeclareHardDay(d, '2026-11-05'), isFalse, reason: 'déjà déclarée');
    expect(canDeclareHardDay(d, '2026-11-18'), isFalse);
    expect(canDeclareHardDay(d, '2026-11-19'), isTrue);
    expect(nextHardDayAfter('2026-11-05'), '2026-11-19');
    expect(lastHardDayBefore(d, '2026-11-10'), '2026-11-05');
  });

  test('lecture, retrait, jamais à l’avance', () {
    expect(parseHardDays(['2026-11-05', 'x', '2026-11-01', '2026-11-05']), ['2026-11-01', '2026-11-05']);
    expect(withoutHardDay(['2026-11-01', '2026-11-05'], '2026-11-05'), ['2026-11-01']);
    expect(hardDaysUpTo(['2026-11-01', '2026-11-09'], '2026-11-06'), {'2026-11-01'});
  });
}
