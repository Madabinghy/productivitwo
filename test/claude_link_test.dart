import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/claude_link.dart';

void main() {
  final now = DateTime(2026, 9, 30, 12, 14);
  final blocks = [
    ScheduleBlock(startTime: '08:30', durationMin: 240, title: 'Cléa Numérique', gcalEventId: 'g1'),
    ScheduleBlock(startTime: '12:00', durationMin: 120, title: 'Contenu'),
    ScheduleBlock(startTime: '14:00', durationMin: 45, title: 'Pause', status: 'deleted'),
    ScheduleBlock(startTime: '19:30', durationMin: 75, title: 'Dîner'),
  ];

  test('URL claude.ai/new avec le prompt encodé', () {
    final u = claudeNewUri('Réorganise ma journée');
    expect(u.host, 'claude.ai');
    expect(u.path, '/new');
    expect(u.queryParameters['q'], 'Réorganise ma journée');
  });

  test('prompt après parenthèse : décalage, agenda protégé, fin de journée réelle', () {
    final p = reorganizeAfterAsidePrompt(
        date: '2026-09-30', now: now, block: blocks[1], activityName: 'Vaisselle',
        todayBlocks: blocks, shiftedTo: '12:30');
    expect(p, contains('Il est 12:14'));
    expect(p, contains('décaler « Contenu » (120 min) à 12:30'));
    expect(p, contains('Cléa Numérique 08:30 → 12:30'));
    expect(p, contains('jusqu\'à 20:45'));
    expect(p, isNot(contains('Pause'))); // bloc supprimé ignoré
  });

  test('prompt retards : liste + échéances', () {
    final p = replanOverduePrompt(date: '2026-09-30', now: now, todayBlocks: const [], overdue: [
      (task: 'Réserver la salle', project: 'Séminaire', due: DateTime(2026, 9, 25)),
    ]);
    expect(p, contains('« Réserver la salle » (Séminaire, échéance 25/09)'));
    expect(p, contains('pas de rendez-vous Google Agenda'));
  });
}
