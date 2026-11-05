import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_widget.dart';
import 'package:productivitwo_v1/utils/week_stats.dart';

DomainWeek week({int done = 0, int goal = 0, int days = 4, int reached = 0, int total = 0, String? rest}) => DomainWeek(
    domain: Domain(id: 'd', name: 'D'), doneMin: done, goalMinDay: goal, daysElapsed: days, routinesReached: reached, routinesTotal: total, restUntil: rest);

void main() {
  test('rythme : le plus bas des deux, veille et rien à mesurer à la fin', () {
    expect(domainPace(week(done: 60, goal: 30, days: 4)), .5);
    expect(domainPace(week(done: 120, goal: 30, days: 4, reached: 1, total: 4)), .25);
    expect(domainPace(week(rest: '2026-11-10', done: 0, goal: 30)), 9);
    expect(domainPace(week()), 5);
    expect(domainPace(null), 9);
  });

  test('JSON : ordre d\'Organisation gardé, rang de « Choisir pour moi », images', () {
    final j = domainsWidgetJson([
      const WidgetDomain(id: 'a', name: 'Business', color: 0xFFF2A33A, link: 'domain/a', pace: 1.2),
      const WidgetDomain(id: 'b/x', name: 'Maison', color: 0xFFE9896F, link: 'domain/b/x', pace: .4, wide: true),
    ], bg: 0xFF0C1C14, at: DateTime(2026, 11, 5));
    final ds = (j['domains'] as List).cast<Map>();
    expect(ds.map((d) => d['id']), ['a', 'b/x']);
    expect(ds.map((d) => d['rank']), [1, 0]);
    expect(ds[0]['color'], 0xF2A33A);
    expect(j['bg'], 0x0C1C14);
    expect(ds[1]['img'], 'dom_b_x');
    expect(ds[1]['imgWide'], 'dom_b_x_wide');
    expect(ds[0].containsKey('imgWide'), isFalse);
  });
}
