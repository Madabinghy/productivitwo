import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badge_texts.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';

void main() {
  final now = DateTime(2026, 10, 26, 10);
  Activity routine(String id) => Activity(id: id, domainId: 'd', name: 'Méditation', role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 1, 1));

  test('textes : chaque badge dit à quoi il correspond et comment l\'obtenir', () {
    for (final id in ['premiere-cible', 'trajectoire', 'releve-fidele', 'cible-atteinte', 'journee-parfaite', 'semaine-solide', 'mois-solide', 'malgre-tout', 'vent-contraire', 'maree-haute', 'barometre', 'enchaineur', 'plein-jour', 'actions']) {
      final t = badgeTexts(id);
      expect(t.what, isNotEmpty, reason: id);
      expect(t.how, isNotEmpty, reason: id);
    }
    expect(badgeTexts('serie-x', name: 'Méditation').what, contains('Méditation'));
    expect(badgeTexts('temps-x', name: 'Le livre').how, contains('1 000'));
    expect(badgeTexts('inconnu').what, isEmpty);
  });

  test('série : bande des 30 derniers jours, atteint / manqué / neutre avant le premier hit, aujourd\'hui en cours', () {
    final hits = [for (var d = 16; d <= 25; d++) HabitHit(habitId: 'med', ts: DateTime(2026, 10, d, 8))];
    final deck = computeBadges(activities: [routine('med')], habitHits: hits, schedules: const [], projects: const [], objectives: const [], sessions: const [], now: now);
    final t = deck.byId('serie-med')!.track!;
    expect(t.cells.length, 30);
    expect(t.cells.last, TrackCell.current, reason: 'aujourd\'hui pas encore atteint');
    expect(t.cells[t.cells.length - 2], TrackCell.hit); // hier
    expect(t.cells[t.cells.length - 11], TrackCell.hit); // le 16
    expect(t.cells[t.cells.length - 12], TrackCell.neutral, reason: 'avant le premier hit');
    expect(t.hits, 10);
    expect(t.caption, '30 derniers jours · 10 jours atteints');
    expect(deck.byId('serie-med')!.def.what, contains('Méditation'));
  });

  test('actions : jours avec une action faite et total du mois ; Enchaîner : sessions', () {
    final p = Project(id: 'p', title: 'P', createdBy: 't', startDate: DateTime(2026, 1, 1), tasks: [
      ProjectTask(title: 't', startDate: DateTime(2026, 1, 1), actions: [
        TaskAction(title: 'a', done: true, doneAt: DateTime(2026, 10, 25, 9)),
        TaskAction(title: 'b', done: true, doneAt: DateTime(2026, 10, 25, 10)),
        TaskAction(title: 'c', done: true, doneAt: DateTime(2026, 9, 1)),
      ]),
    ]);
    final runs = [
      ChainRun(date: '2026-10-24', startedAt: DateTime(2026, 10, 24, 8), endedAt: DateTime(2026, 10, 24, 18), doneCount: 3, total: 3, completed: true),
      ChainRun(date: '2026-10-25', startedAt: DateTime(2026, 10, 25, 8), endedAt: DateTime(2026, 10, 25, 12), doneCount: 1, total: 3, completed: false),
    ];
    final deck = computeBadges(activities: const [], habitHits: const [], schedules: const [], projects: [p], objectives: const [], sessions: const [], chainRuns: runs, now: now);
    final a = deck.byId('actions')!.track!;
    expect(a.cells[a.cells.length - 2], TrackCell.hit);
    expect(a.caption, '30 derniers jours · 2 actions faites');
    final e = deck.byId('enchaineur')!.track!;
    expect(e.cells, [TrackCell.hit, TrackCell.miss]);
    expect(deck.byId('premiere-cible')!.track, isNull);
  });
}
