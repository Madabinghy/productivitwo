import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/elan_view.dart';

void main() {
  final now = DateTime(2026, 10, 28, 14, 30); // mercredi, après-midi
  MoodMark elan(DateTime at, int v) => MoodMark(
      at: at,
      ymd: '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}',
      kind: kMoodElan,
      value: v,
      moment: elanBucket(at.hour * 60 + at.minute));
  Activity routine(String id) => Activity(id: id, domainId: 'd', name: id, role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 1, 1));

  test('todayElanSlots : matin pointé avec une chose faite ensuite, aprem courant pointé, soir pas commencé', () {
    final marks = [elan(DateTime(2026, 10, 28, 7, 12), 2), elan(DateTime(2026, 10, 28, 13, 40), 3)];
    final hits = [HabitHit(habitId: 'lit', ts: DateTime(2026, 10, 28, 8, 0))];
    final slots = todayElanSlots(marks: marks, schedule: null, hits: hits, activities: [routine('lit')], now: now);
    expect(slots.map((s) => s.bucket).toList(), ['matin', 'aprem', 'soir']);
    expect(slots[0].value, 2);
    expect(slots[0].wins, 1);
    expect(slots[1].value, 3);
    expect(slots[1].current, isTrue);
    expect(slots[2].pointed, isFalse);
    expect(slots[2].started, isFalse);
    expect(slots[2].startHour, 18);
  });

  test('hardestBucket : le créneau le plus souvent pointé bas', () {
    final days = [
      const ElanDay('2026-10-26', [ElanMarkView('matin', 2, false), ElanMarkView('aprem', 3, false)], null),
      const ElanDay('2026-10-27', [ElanMarkView('matin', 1, true), ElanMarkView('soir', 2, false)], null),
    ];
    expect(hardestBucket(days), 'matin');
    expect(hardestBucket(const [ElanDay('2026-10-26', [ElanMarkView('matin', 4, false)], null)]), isNull);
  });

  test('elanMonth : 30 derniers jours, jours de flemme gagnés, en forme, tendance vs 30 j d\'avant', () {
    final days = <ElanDay>[];
    for (var i = 0; i < 60; i++) {
      final d = DateTime(2026, 8, 30).add(Duration(days: i));
      final ymd = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final v = i < 30 ? 2 : (i % 5 == 0 ? 4 : 3);
      days.add(ElanDay(ymd, [ElanMarkView('matin', v, i.isEven)], null));
    }
    days[59] = ElanDay(days[59].ymd, const [], null); // aujourd'hui pas encore pointé
    final m = elanMonth(days);
    expect(m.days.length, 30);
    expect(m.pointedDays, 29);
    expect(m.previousMean, 2.0);
    expect(m.mean! > 3.0 && m.mean! < 3.3, isTrue);
    expect(m.highDays, 6);
    expect(m.lowDays, 0);
    expect(trendLabel(m), startsWith('↗ +1,'));
    expect(m.pointedStreak, 29);
    final low = elanMonth(days.sublist(0, 30));
    expect(low.lowDays, 30);
    expect(low.lowDaysWon, 15);
    expect(low.previousMean, isNull);
    expect(trendLabel(low), isNull);
  });

  test('weeklyMeans : une moyenne par semaine calendaire, dans l\'ordre', () {
    final days = [
      const ElanDay('2026-10-25', [ElanMarkView('matin', 2, false)], null), // dimanche, semaine du 19
      const ElanDay('2026-10-26', [ElanMarkView('matin', 4, false), ElanMarkView('soir', 2, false)], null),
      const ElanDay('2026-10-27', [], null),
    ];
    final w = weeklyMeans(days);
    expect(w.map((x) => x.monday).toList(), ['2026-10-19', '2026-10-26']);
    expect(w.last.mean, 3.0);
    expect(w.last.count, 2);
  });

  test('todayElanValues : trois valeurs (null = pas pointé) et le créneau courant', () {
    final marks = [elan(DateTime(2026, 10, 28, 7, 12), 2), elan(DateTime(2026, 10, 28, 13, 40), 3)];
    final t = todayElanValues(marks, now, 5 * 60);
    expect(t.values, [2, 3, null]);
    expect(t.current, 1);
    expect(todayElanValues(const [], DateTime(2026, 10, 28, 21), 5 * 60).values, [null, null, null]);
  });

  test('elanTimeline : l\'élan en vigueur par quart d\'heure, vide avant le premier pointage et après maintenant', () {
    final marks = [elan(DateTime(2026, 10, 28, 7, 12), 2), elan(DateTime(2026, 10, 28, 9, 0), 3)];
    final t = elanTimeline(marks, now, 5 * 60); // journée vécue depuis 5 h
    expect(t.length, 96);
    expect(t[0], isNull); // 5:00
    expect(t[8], isNull); // 7:00, avant 7:12
    expect(t[9], 2); // 7:15
    expect(t[16], 3); // 9:00
    expect(t[38], 3); // 14:30 = maintenant
    expect(t[39], isNull); // 14:45, futur
    final slots = todayElanSlots(marks: marks, schedule: null, hits: const [], activities: const [], now: now);
    expect(slots[0].value, 3); // dominant du matin : 3 tenu de 9 h à 12 h > 2 tenu 1 h 48
    expect(slots[0].changes, 2);
    expect(slots[0].at, DateTime(2026, 10, 28, 7, 12));
  });
}
