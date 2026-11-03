import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badge_today.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/card_quests.dart';
import 'package:productivitwo_v1/utils/long_haul.dart';

void main() {
  final aspi = Activity(id: 'aspi', name: 'Passer l’aspirateur', domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 9, 1));
  final lecture = Activity(id: 'lec', name: 'Lecture', domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 9, 1));
  final cuisiner = Activity(id: 'cui', name: 'Cuisiner', domainId: 'd', type: 'time', createdAt: DateTime(2026, 9, 1));
  final acts = [aspi, lecture, cuisiner];
  final now = DateTime(2026, 11, 2, 21);

  BadgeState b(String id, String name, List<int> tiers, int level, num value, {String? subject, BadgeFamily f = BadgeFamily.actions}) =>
      BadgeState(def: BadgeDef(id: id, family: f, name: name, symbol: 'x', tiers: tiers, subjectId: subject), level: level, value: value);

  test('compteur de coches : il manque 1 passage, un tir de +1', () {
    final q = cardQuestOf(b('fois-aspi', 'Passer l’aspirateur', kRoutineCountTiers, 0, 9, subject: 'aspi'), activities: acts)!;
    expect(q.kind, QuestKind.reps);
    expect(q.need, startsWith('Il manque 1 fois'));
    expect(q.steps.single.key, 'routine:aspi');
    expect(q.steps.single.amount, 1);
  });

  test('compteur d’heures : les minutes qui manquent, un tir de 60 min au plus', () {
    final q = cardQuestOf(b('heures-cui', 'Cuisiner', kActivityHourTiers, 1, 19.1, subject: 'cui', f: BadgeFamily.time), activities: acts)!;
    expect(q.need, 'Il manque 54 min de chrono sur Cuisiner');
    expect(q.steps.single.minutes, isTrue);
    expect(q.steps.single.amount, 54);
    final far = cardQuestOf(b('heures-cui', 'Cuisiner', kActivityHourTiers, 2, 30, subject: 'cui', f: BadgeFamily.time), activities: acts);
    expect(far, isNull, reason: '20 h qui manquent : pas à portée');
    final mid = cardQuestOf(b('heures-cui', 'Cuisiner', kActivityHourTiers, 1, 18.5, subject: 'cui', f: BadgeFamily.time), activities: acts)!;
    expect(mid.steps.single.amount, 60);
  });

  test('série : le +1 du jour si la routine n’est pas faite', () {
    final serie = b('serie-lec', 'Lecture', kRoutineTiers, 2, 20, subject: 'lec', f: BadgeFamily.routines);
    final todo = TodayFacts(ymd: '2026-11-02', now: now, routines: [RoutineToday(lecture, 0, 1)]);
    final q = cardQuestOf(serie, activities: acts, facts: todo)!;
    expect(q.days, 1);
    expect(q.steps.single.amount, 1);
    final done = TodayFacts(ymd: '2026-11-02', now: now, routines: [RoutineToday(lecture, 1, 1)]);
    expect(cardQuestOf(serie, activities: acts, facts: done)!.steps, isEmpty);
  });

  test('Métronome : les routines qui manquent ce soir', () {
    final metro = b('metronome', 'Métronome', const [5, 20, 50, 100], 0, 3, f: BadgeFamily.days);
    final f = TodayFacts(ymd: '2026-11-02', now: now, routines: [RoutineToday(lecture, 0, 1), RoutineToday(aspi, 1, 1)]);
    final q = cardQuestOf(metro, activities: acts, facts: f)!;
    expect(q.days, 2);
    expect(q.steps.map((s) => s.activity.id), ['lec']);
  });

  test('mode : une session de plus, pas de tir', () {
    final q = cardQuestOf(b('guerilla', 'Guérilla', const [1, 5, 15], 1, 4, f: BadgeFamily.discipline), activities: acts)!;
    expect(q.kind, QuestKind.mode);
    expect(q.modeKind, 'guerilla');
    expect(q.sniperable, isFalse);
  });

  test('classement : ce qui tombe aujourd’hui avec le moins d’effort d’abord', () {
    final deck = BadgeDeck([
      b('metronome', 'Métronome', const [5, 20, 50, 100], 0, 3, f: BadgeFamily.days),
      b('heures-cui', 'Cuisiner', kActivityHourTiers, 1, 19.1, subject: 'cui', f: BadgeFamily.time),
      b('fois-aspi', 'Passer l’aspirateur', kRoutineCountTiers, 0, 9, subject: 'aspi'),
      b('actions', 'Actions accomplies', const [10, 50, 100, 250, 500], 4, 319),
    ]);
    final qs = cardQuests(deck, activities: acts, limit: 3);
    expect(qs.map((q) => q.badge.def.id), ['fois-aspi', 'heures-cui', 'metronome']);
  });
}
