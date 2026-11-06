import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/minimum.dart';

void main() {
  test('ouvrir, geler les non gardées, finir hier', () {
    var p = withMinimumStarted(const [], '2026-11-05', ['eau', 'repas'], '2026-11-06');
    expect(currentMinimum(p, '2026-11-06')?.keep, ['eau', 'repas']);
    expect(minimumFrozenDaysOf('vaisselle', p, '2026-11-06'), {'2026-11-05', '2026-11-06'});
    expect(minimumFrozenDaysOf('eau', p, '2026-11-06'), isEmpty);
    expect(minimumCheckDue(p.last, '2026-11-08'), isFalse);
    expect(minimumCheckDue(p.last, '2026-11-09'), isTrue);
    p = withMinimumExtended(p, '2026-11-09');
    expect(p.last.checkAt, '2026-11-12');
    p = withMinimumEnded(p, '2026-11-10');
    expect(p.last.to, '2026-11-09');
    expect(currentMinimum(p, '2026-11-10'), isNull);
    expect(minimumFrozenDaysOf('vaisselle', p, '2026-11-12').length, 5);
  });

  test('commencée aujourd’hui puis « ça va mieux » : disparaît', () {
    final p = withMinimumEnded(withMinimumStarted(const [], '2026-11-06', ['eau'], '2026-11-06'), '2026-11-06');
    expect(p, isEmpty);
  });

  test('journées tenues au minimum et propositions', () {
    final p = [const MinimumPeriod(from: '2026-11-04', keep: ['eau', 'repas'], checkAt: '2026-11-07')];
    final reached = {
      'eau': {'2026-11-04', '2026-11-05'},
      'repas': {'2026-11-04'},
      'lecture': {'2026-11-01', '2026-11-02', '2026-11-03'},
    };
    expect(minimumHeldDays(p, reached, '2026-11-06'), ['2026-11-04']);
    expect(suggestMinimum(reached, '2026-11-06', count: 2), ['lecture', 'eau']);
    expect(parseMinimumPeriods(minimumPeriodsToJson(p)).single.keep, ['eau', 'repas']);
  });
}
