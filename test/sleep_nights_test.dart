import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/sleep_nights.dart';

void main() {
  final sleep = Activity(id: 's', domainId: 'd', name: 'Sommeil', type: 'time');
  final work = Activity(id: 'w', domainId: 'd', name: 'Contenu', type: 'time');
  Session ses(String act, DateTime a, DateTime? b) => Session(activityId: act, startAt: a, endAt: b);

  test('une valeur par nuit, la plus ancienne d\'abord ; sieste et autres activités exclues', () {
    final n = sleepNights(
      sessions: [
        ses('s', DateTime(2026, 10, 30, 22, 40), DateTime(2026, 10, 31, 5, 52)),
        ses('s', DateTime(2026, 10, 30, 14), DateTime(2026, 10, 30, 14, 30)), // sieste : hors fenêtre
        ses('s', DateTime(2026, 10, 28, 23), DateTime(2026, 10, 29, 6)),
        ses('w', DateTime(2026, 10, 30, 23), DateTime(2026, 10, 31, 0)),
      ],
      activities: [sleep, work],
      now: DateTime(2026, 10, 31, 9),
      dayStartMin: 5 * 60,
      nights: 3,
    );
    expect(n, [420, null, 432]);
    expect(fmtSleep(432), '7 h 12');
    expect(fmtSleep(45), '45 min');
  });

  test('la nuit qui vient prend la dernière case dès qu\'un chrono y a commencé', () {
    final sessions = [
      ses('s', DateTime(2026, 10, 30, 22), DateTime(2026, 10, 31, 6)),
      ses('s', DateTime(2026, 10, 31, 23), null),
    ];
    final n = sleepNights(sessions: sessions, activities: [sleep], now: DateTime(2026, 11, 1, 1), dayStartMin: 300, nights: 2);
    expect(n, [480, 120]);
    expect(sleepRunning(sessions, [sleep]), isTrue);
    expect(sleepNights(sessions: const [], activities: [work], now: DateTime(2026, 11, 1, 9), dayStartMin: 300, nights: 2), [null, null]);
  });
}
