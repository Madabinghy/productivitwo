import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';

void main() {
  test('deep work = chronos terminés de 60 min et plus, triés', () {
    final s = [
      Session(activityId: 'a', startAt: DateTime(2026, 10, 20, 9), endAt: DateTime(2026, 10, 20, 10, 30)),
      Session(activityId: 'a', startAt: DateTime(2026, 10, 19, 9), endAt: DateTime(2026, 10, 19, 9, 45)),
      Session(activityId: 'b', startAt: DateTime(2026, 10, 18, 14), endAt: DateTime(2026, 10, 18, 15)),
      Session(activityId: 'b', startAt: DateTime(2026, 10, 21, 14)),
      Session(activityId: 'b', startAt: DateTime(2026, 10, 17, 14), endAt: DateTime(2026, 10, 17, 16))..deleted = true,
    ];
    final d = deepWorkSessions(s);
    expect(d, [DateTime(2026, 10, 18, 15), DateTime(2026, 10, 20, 10, 30)]);
    final deck = computeBadges(
        activities: const [], habitHits: const [], schedules: const [], projects: const [], objectives: const [], sessions: s, now: DateTime(2026, 10, 27));
    final b = deck.byId('deep-work')!;
    expect(b.value, 2);
    expect(b.level, 0);
    expect(b.nextTarget, 3);
  });
}
