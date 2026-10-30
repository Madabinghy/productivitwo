import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/acquired.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/today_facts.dart';

Activity routine(String id) => Activity(id: id, name: id, domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 9, 1));
Set<String> nov(Iterable<int> days) => {for (final d in days) '2026-11-${d.toString().padLeft(2, '0')}'};

void main() {
  test('lecture et proposition au palier de 66 jours, une seule fois', () {
    final a = parseAcquired({'m': {'since': '2026-11-01', 'quietUntil': 'x'}, 'bad': {'since': 3}});
    expect(a.keys, ['m']);
    expect(a['m']!.quietUntil, isNull);
    expect(shouldProposeAcquire(id: 'p', longest: 66, acquired: const {}, asked: const {}), isTrue);
    expect(shouldProposeAcquire(id: 'p', longest: 65, acquired: const {}, asked: const {}), isFalse);
    expect(shouldProposeAcquire(id: 'p', longest: 80, acquired: const {}, asked: {'p'}), isFalse);
    expect(isAcquiredOn(a, 'm', '2026-10-31'), isFalse);
    expect(isAcquiredOn(a, 'm', '2026-11-01'), isTrue);
  });

  test('décroche : deux semaines closes sous 4 / 7, après le passage, hors silence', () {
    const acq = Acquired('2026-10-20');
    final today = DateTime(2026, 11, 18); // mercredi ; semaines closes : 2 → 8 et 9 → 15 nov.
    expect(isSlipping(acq, nov([3, 5, 10]), today), isTrue);
    expect(isSlipping(acq, nov([3, 4, 5, 6, 10]), today), isFalse);
    expect(isSlipping(const Acquired('2026-11-05'), nov([3]), today), isFalse); // passage trop récent
    expect(isSlipping(const Acquired('2026-10-20', quietUntil: '2026-12-01'), nov([3]), today), isFalse);
  });

  test('une acquise sort de la journée parfaite à partir de son passage, pas avant', () {
    final p = routine('p'), m = routine('m');
    final reached = {'p': {'2026-11-02', '2026-11-03'}, 'm': <String>{}};
    final acq = {'m': const Acquired('2026-11-03')};
    expect(scoreDay(DateTime(2026, 11, 2), activities: [p, m], reachedDaysByRoutine: reached, acquired: acq).perfect, isFalse);
    expect(scoreDay(DateTime(2026, 11, 3), activities: [p, m], reachedDaysByRoutine: reached, acquired: acq).perfect, isTrue);
  });

  test('faits du jour : une acquise n’est plus réclamée', () {
    final f = composeTodayFacts(
      ymd: '2026-11-03',
      now: DateTime(2026, 11, 3, 12),
      dayStartMin: 300,
      activities: [routine('p'), routine('m')],
      hits: const [],
      sessions: const [],
      moodMarks: const [],
      objectives: const [],
      projects: const [],
      acquired: {'m': const Acquired('2026-11-01')},
    );
    expect(f.routines.map((r) => r.activity.id), ['p']);
  });
}
