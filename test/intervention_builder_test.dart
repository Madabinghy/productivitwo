import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/intervention_builder.dart';

void main() {
  final phases = [
    ProjectPhase(id: 'p1', label: 'P1', startDate: DateTime(2026, 9, 1), endDate: DateTime(2026, 10, 20)),
    ProjectPhase(id: 'p2', label: 'P2', startDate: DateTime(2026, 11, 2), endDate: DateTime(2026, 12, 18)),
  ];
  final i = ProjectIntervention(
      id: 'i1', title: 'Séance — 12 oct', date: DateTime(2026, 10, 12), startTime: '13:15', endTime: '15:00');

  test('buildInterventionTasks : trois tâches taguées, fenêtres, phase par date, déroulé', () {
    final r = buildInterventionTasks(i, kDefaultInterventionTemplate,
        phases: phases, steps: ['13h15 Ramasser le DM', ' ', '13h20 Contrôle']);
    expect(r.prep.title, '📝 Préparer — Séance — 12 oct');
    expect(r.prep.startDate, DateTime(2026, 10, 5));
    expect(r.prep.endDate, DateTime(2026, 10, 11));
    expect(r.prep.phaseId, 'p1');
    expect(r.prep.interventionRole, 'prep');
    expect(r.prep.actions.length, 4);
    expect(r.prep.actions.last.allContexts, ['@impression']);
    expect(r.prep.estimatedMin, 85);
    expect(r.session.title, '🎯 Lun 12 oct. — Séance — 12 oct');
    expect(r.session.isMilestone, isTrue);
    expect(r.session.actions.single.title, 'Dérouler la séance (13h15–15h00)');
    expect(r.session.actions.single.estimatedMin, 105);
    expect(r.session.actions.single.checklist.length, 2);
    expect(r.closure.endDate, DateTime(2026, 10, 14));
    expect(r.closure.groupLabel, 'Séance — 12 oct');
    expect(r.closure.interventionId, 'i1');
  });

  test('parseInterventionTemplates : défaut en tête, parties absentes = défaut', () {
    final list = parseInterventionTemplates([
      {'id': 'cherubins', 'name': 'Séance Chérubins', 'startTime': '13:15', 'endTime': '15:00',
        'sessionContext': '@Chérubins', 'prep': {'daysBefore': 5}},
    ]);
    expect(list.first.id, 'default');
    expect(list[1].prepDaysBefore, 5);
    expect(list[1].prepActions.length, 4);
    expect(list[1].sessionContext, '@Chérubins');
    final r = buildInterventionTasks(i, list[1]);
    expect(r.session.actions.single.allContexts, ['@Chérubins']);
    expect(r.prep.startDate, DateTime(2026, 10, 7));
  });

  test('applyCarryOver : alimente la prépa de la séance suivante, sans doublon ; rouvre l\'action', () {
    final next = ProjectIntervention(
        id: 'i2', title: 'Séance — 19 oct', date: DateTime(2026, 10, 19), startTime: '13:15', endTime: '15:00');
    final built = buildInterventionTasks(next, kDefaultInterventionTemplate);
    built.prep.actions.first.done = true;
    final p = Project(id: 'P', title: 'P', startDate: DateTime(2026, 9, 1), createdBy: 'u',
        tasks: [built.prep, built.session, built.closure], interventions: [i, next]);
    expect(applyCarryOver(p, i, ['Reprendre les problèmes du tout', '']), same(next));
    final adapt = built.prep.actions.first;
    expect(adapt.checklist.single.title, 'Reprendre les problèmes du tout');
    expect(adapt.done, isFalse);
    applyCarryOver(p, i, ['reprendre les problèmes du tout', 'Revoir les retenues']);
    expect(adapt.checklist.length, 2);
    expect(applyCarryOver(p, next, ['x']), isNull);
  });
}
