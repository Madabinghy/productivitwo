import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/long_haul.dart';

void main() {
  test('heures, total et coches au long cours', () {
    final now = DateTime(2026, 11, 2, 20);
    final lecture = Activity(name: 'Lecture', domainId: 'd');
    final vaisselle = Activity(name: 'Vaisselle', domainId: 'd', type: 'habit');
    final sessions = [
      for (var i = 0; i < 6; i++) Session(activityId: lecture.id, startAt: DateTime(2026, 10, 20 + i, 9), endAt: DateTime(2026, 10, 20 + i, 10)),
    ];
    final hits = [for (var i = 0; i < 12; i++) HabitHit(habitId: vaisselle.id, ts: DateTime(2026, 10, 20, 8).add(Duration(hours: i * 12)))];
    final out = longHaulBadges(activities: [lecture, vaisselle], habitHits: hits, sessions: sessions, now: now);
    final h = out.firstWhere((b) => b.def.id == 'heures-${lecture.id}');
    expect(h.value, 6.0);
    expect(h.level, 1);
    expect(h.tierDates.first, DateTime(2026, 10, 24));
    expect(out.any((b) => b.def.id == 'heures-total'), isTrue);
    final f = out.firstWhere((b) => b.def.id == 'fois-${vaisselle.id}');
    expect(f.value, 12);
    expect(f.level, 1);
    final sommeil = Activity(name: 'Sommeil', domainId: 'd');
    final out2 = longHaulBadges(activities: [sommeil], habitHits: const [], sessions: [Session(activityId: sommeil.id, startAt: DateTime(2026, 10, 30, 23), endAt: DateTime(2026, 10, 31, 7))], now: now);
    expect(out2, isEmpty);
  });
}
