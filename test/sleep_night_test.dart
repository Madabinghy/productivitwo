import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/sleep_night.dart';

void main() {
  final sleep = Activity(id: 's', domainId: 'd', name: 'Sommeil', type: 'time');
  final work = Activity(id: 'w', domainId: 'd', name: 'Contenu', type: 'time');
  Session ses(String act, DateTime a, DateTime? b) => Session(activityId: act, startAt: a, endAt: b);

  test('la nuit autour de la bascule : chronos de sommeil seulement, sieste de l\'après-midi exclue', () {
    final now = DateTime(2026, 10, 31, 9);
    final r = lastNightSleep(
      sessions: [
        ses('s', DateTime(2026, 10, 30, 22, 40), DateTime(2026, 10, 31, 5, 52)),
        ses('s', DateTime(2026, 10, 30, 14), DateTime(2026, 10, 30, 14, 30)), // sieste de la veille : hors fenêtre
        ses('w', DateTime(2026, 10, 30, 23), DateTime(2026, 10, 31, 0)),
      ],
      activities: [sleep, work],
      now: now,
      dayStartMin: 5 * 60,
    )!;
    expect(r.minutes, 7 * 60 + 12);
    expect(r.running, isFalse);
    expect(fmtSleep(r.minutes), '7 h 12');
    expect(fmtSleep(45), '45 min');
  });

  test('chrono de sommeil en cours ; rien sans chrono de sommeil', () {
    final r = lastNightSleep(
      sessions: [ses('s', DateTime(2026, 10, 30, 23), null)],
      activities: [sleep],
      now: DateTime(2026, 10, 31, 1, 30),
      dayStartMin: 5 * 60,
    )!;
    expect(r.running, isTrue);
    expect(r.minutes, 150);
    expect(lastNightSleep(sessions: const [], activities: [sleep], now: DateTime(2026, 10, 31, 9), dayStartMin: 300), isNull);
    expect(lastNightSleep(sessions: const [], activities: [work], now: DateTime(2026, 10, 31, 9), dayStartMin: 300), isNull);
  });
}
