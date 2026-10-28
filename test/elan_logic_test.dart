import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';

void main() {
  final now = DateTime(2026, 10, 26, 10);
  MoodMark elan(DateTime at, int v, {String? moment}) =>
      MoodMark(at: at, ymd: '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}', kind: kMoodElan, value: v, moment: moment ?? elanBucket(at.hour * 60 + at.minute));
  Activity routine(String id) => Activity(id: id, domainId: 'd', name: id, role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 1, 1));
  DailySchedule sched(String ymd, List<DateTime?> doneAts) => DailySchedule(
        date: ymd,
        generatedBy: 'claude',
        generatedAt: now,
        blocks: [
          for (final d in doneAts)
            ScheduleBlock(id: '$ymd-${doneAts.indexOf(d)}', startTime: '09:00', durationMin: 60, title: 'b', category: 'project', status: d == null ? 'pending' : 'done', doneAt: d),
        ],
      );

  test('créneaux : matin < 12 h, après-midi < 18 h, soir ensuite (minuit = soir)', () {
    expect(elanBucket(8 * 60), 'matin');
    expect(elanBucket(13 * 60), 'aprem');
    expect(elanBucket(21 * 60), 'soir');
    expect(elanBucket(24 * 60 + 30), 'soir');
  });

  test('l\'élan est dû une fois par créneau, « × » le passe', () {
    final marks = [elan(DateTime(2026, 10, 26, 8), 2)];
    expect(elanDue(marks, '2026-10-26', 'matin', {}), isFalse);
    expect(elanDue(marks, '2026-10-26', 'aprem', {}), isTrue);
    expect(elanDue(marks, '2026-10-26', 'aprem', {'2026-10-26:aprem'}), isFalse);
  });

  test('fenêtres : du pointage au suivant, puis jusqu\'à la bascule du jour vécu', () {
    final ws = elanWindows([elan(DateTime(2026, 10, 25, 8), 2), elan(DateTime(2026, 10, 25, 14), 4)], '2026-10-25');
    expect(ws.length, 2);
    expect(ws[0].end, DateTime(2026, 10, 25, 14));
    expect(ws[1].end, DateTime(2026, 10, 26, 5));
    expect(ws[0].low, isTrue);
    expect(ws[1].low, isFalse);
  });

  test('victoire sur la flemme : bloc terminé ou routine atteinte dans la fenêtre', () {
    final w = elanWindows([elan(DateTime(2026, 10, 25, 8), 1)], '2026-10-25').single;
    final wins = winsIn(
      w,
      blocks: sched('2026-10-25', [DateTime(2026, 10, 25, 9, 30), null]).blocks,
      hits: [HabitHit(habitId: 'med', ts: DateTime(2026, 10, 25, 10)), HabitHit(habitId: 'med', ts: DateTime(2026, 10, 25, 2))],
      activities: [routine('med')],
    );
    // le hit de 2 h appartient à la veille vécue ; celui de 10 h atteint la cible dans la fenêtre
    expect(wins.length, 2);
  });

  test('semaine et taux de discipline', () {
    final marks = [
      elan(DateTime(2026, 10, 24, 8), 1),
      elan(DateTime(2026, 10, 24, 15), 2),
      elan(DateTime(2026, 10, 25, 8), 4),
      MoodMark(at: DateTime(2026, 10, 25, 21), ymd: '2026-10-25', kind: kMoodMood, value: 2),
    ];
    final days = buildElanDays(
      marks: marks,
      schedulesByYmd: {'2026-10-24': sched('2026-10-24', [DateTime(2026, 10, 24, 9)])},
      hits: const [],
      activities: const [],
      now: now,
    );
    expect(days.length, 7);
    expect(days.last.ymd, '2026-10-26');
    final sat = days.firstWhere((d) => d.ymd == '2026-10-24');
    expect(sat.marks.map((m) => m.won), [true, false]);
    expect(days.firstWhere((d) => d.ymd == '2026-10-25').mood, 2);
    final m = elanMetrics(days);
    expect(m.count, 3);
    expect(m.lowCount, 2);
    expect(m.lowWon, 1);
    expect(m.discipline, closeTo(.5, 1e-9));
    expect(elanMetrics(days.where((d) => d.ymd == '2026-10-25').toList()).discipline, isNull);
  });

  test('badges Discipline : Malgré tout, Baromètre, Marée haute, Vent contraire', () {
    final a = routine('med');
    final marks = <MoodMark>[];
    final hits = <HabitHit>[];
    final schedules = <DailySchedule>[];
    // 12 jours : élan Flemme le matin, routine atteinte ensuite = 12 victoires ; élan 4 le soir.
    for (var d = 0; d < 12; d++) {
      final day = DateTime(2026, 10, 13 + d);
      marks.add(elan(DateTime(day.year, day.month, day.day, 8), 1));
      hits.add(HabitHit(habitId: 'med', ts: DateTime(day.year, day.month, day.day, 9)));
      schedules.add(sched('${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}', [DateTime(day.year, day.month, day.day, 11)]));
    }
    final deck = computeBadges(
      activities: [a],
      habitHits: hits,
      schedules: schedules,
      projects: const [],
      objectives: const [],
      sessions: const [],
      moodMarks: marks,
      now: now,
    );
    final mt = deck.byId('malgre-tout')!;
    expect(mt.def.measured, isTrue);
    expect(mt.value, 24, reason: '12 routines + 12 blocs faits en fenêtre de flemme');
    expect(mt.level, 1);
    expect(mt.obtained, DateTime(2026, 10, 17)); // 10e victoire : 5e jour
    expect(deck.byId('barometre')!.value, 12);
    expect(deck.byId('maree-haute')!.level, 0);
    // Vent contraire : 12 jours solides (routine + bloc faits chaque jour) à élan moyen 1 ≤ 2,5.
    expect(deck.byId('vent-contraire')!.level, 1);
    // Marée haute : 7 jours d'affilée à élan ≥ 4.
    final high = [for (var d = 0; d < 7; d++) elan(DateTime(2026, 10, 19 + d, 8), 5)];
    final deck2 = computeBadges(activities: const [], habitHits: const [], schedules: const [], projects: const [], objectives: const [], sessions: const [], moodMarks: high, now: now);
    expect(deck2.byId('maree-haute')!.level, 1);
    expect(deck2.byId('maree-haute')!.value, 7);
  });
  test('question d\'élan : une fois par jour par défaut, une fois par créneau sur demande', () {
    final marks = [elan(DateTime(2026, 10, 26, 8), 2)];
    expect(elanPromptDue(marks, '2026-10-26', 'aprem', {}), isFalse, reason: 'déjà pointé ce jour');
    expect(elanPromptDue(marks, '2026-10-26', 'aprem', {}, allMoments: true), isTrue);
    expect(elanPromptDue(const [], '2026-10-26', 'soir', {'2026-10-26:matin'}), isFalse, reason: 'passé ce jour');
    expect(elanPromptDue(const [], '2026-10-26', 'soir', {'2026-10-25:matin'}), isTrue);
  });

  test('dedupeMoodMarks : un pointage par créneau, le plus récent gagne ; les remplacés sont listés', () {
    final a = elan(DateTime(2026, 10, 26, 8, 0), 2);
    final b = elan(DateTime(2026, 10, 26, 8, 30), 4); // même créneau matin : remplace a
    final c = elan(DateTime(2026, 10, 26, 14, 0), 3);
    final d = elan(DateTime(2026, 10, 27, 8, 0), 3);
    final kept = dedupeMoodMarks([b, a, d, c]);
    expect(kept.map((m) => m.id).toList(), [b.id, c.id, d.id]);
    expect(supersededMoodMarks([a, b, c, d]).map((m) => m.id).toList(), [a.id]);
    // La semaine ne compte plus que les pointages gardés.
    final days = buildElanDays(marks: [a, b, c, d], schedulesByYmd: const {}, hits: const [], activities: const [], now: DateTime(2026, 10, 27, 10));
    expect(elanMetrics(days).count, 3);
  });
}
