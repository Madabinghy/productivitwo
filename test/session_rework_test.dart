import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/intervention_builder.dart';
import 'package:productivitwo_v1/utils/interventions.dart';
import 'package:productivitwo_v1/utils/session_rework.dart';

void main() {
  final day = DateTime(2026, 11, 19);

  Intervention build() {
    final iv = ProjectIntervention(id: 'i1', title: 'Quadrillage', date: day, startTime: '07:45', endTime: '09:30');
    final prep = ProjectTask(
        id: 'tp',
        title: prepTitle('Quadrillage'),
        groupLabel: 'Quadrillage',
        startDate: day,
        actions: [
          TaskAction(id: 'p1', title: 'Adapter au bilan précédent', done: true),
          TaskAction(id: 'p2', title: 'Produire les supports quadrillage'),
          TaskAction(id: 'p3', title: 'Imprimer'),
        ])
      ..interventionId = 'i1'
      ..interventionRole = 'prep';
    final session = ProjectTask(id: 'ts', title: sessionTitle('Quadrillage', day), groupLabel: 'Quadrillage', startDate: day, actions: [
      TaskAction(id: 's1', title: 'Dérouler la séance (7h45–9h30)', checklist: [
        ChecklistItem(id: 'c1', title: '7h45 Accueil', done: true),
        ChecklistItem(id: 'c2', title: '8h00 Fiche quadrillage'),
        ChecklistItem(id: 'c3', title: '9h00 Bilan'),
      ]),
    ])
      ..interventionId = 'i1'
      ..interventionRole = 'session';
    final closure = ProjectTask(id: 'tc', title: closureTitle('Quadrillage'), groupLabel: 'Quadrillage', startDate: day)
      ..interventionId = 'i1'
      ..interventionRole = 'closure';
    final p = Project(id: 'p', title: 'Maths 6e', startDate: day, createdBy: 'user', tasks: [prep, session, closure], interventions: [iv]);
    return Intervention(project: p, groupLabel: 'Quadrillage', milestone: session, prep: prep, closure: closure, native: iv);
  }

  test('les lignes : actions ouvertes de la prépa, étapes pas encore cochées', () {
    final s = build();
    expect([for (final l in prepLinesOf(s)) l.id], ['p2', 'p3']);
    expect([for (final l in stepLinesOf(s)) l.id], ['c2', 'c3']);
    expect(sessionTaskIds(s), {'tp', 'ts', 'tc'});
  });

  test('changer le thème renomme la séance et ses trois tâches', () {
    final s = build();
    expect(applySessionRework(s, title: '  Soustraction posée '), isTrue);
    expect(s.native!.title, 'Soustraction posée');
    expect(s.prep!.title, '📝 Préparer — Soustraction posée');
    expect(s.milestone.title, sessionTitle('Soustraction posée', day));
    expect(s.closure!.title, '✅ Clôturer — Soustraction posée');
    expect(s.prep!.groupLabel, 'Soustraction posée');
  });

  test('la prépa suit les lignes : renommer, retirer, ajouter — le fait reste', () {
    final s = build();
    final changed = applySessionRework(s, prep: const [
      ReworkLine('p2', 'Produire les supports soustraction'),
      ReworkLine(null, 'Préparer le matériel de manipulation'),
      ReworkLine(null, '   '),
    ]);
    expect(changed, isTrue);
    expect([for (final a in s.prep!.actions) a.title],
        ['Adapter au bilan précédent', 'Produire les supports soustraction', 'Préparer le matériel de manipulation']);
    expect(s.prep!.actions.first.done, isTrue);
    expect(s.prep!.actions.last.estimatedMin, isNotNull);
  });

  test('le déroulé suit les lignes, une étape cochée ne bouge pas', () {
    final s = build();
    applySessionRework(s, steps: const [
      ReworkLine('c2', '8h00 Fiche soustraction'),
      ReworkLine(null, '8h45 Jeu de calcul'),
    ]);
    final steps = s.milestone.actions.first.checklist;
    expect([for (final c in steps) c.title], ['7h45 Accueil', '8h00 Fiche soustraction', '8h45 Jeu de calcul']);
    expect(steps.first.done, isTrue);
  });

  test('rien de changé : false, et une séance d’avant le natif ne se renomme pas ici', () {
    final s = build();
    expect(applySessionRework(s, title: 'Quadrillage', prep: prepLinesOf(s), steps: stepLinesOf(s)), isFalse);
    final legacy = Intervention(project: s.project, groupLabel: 'Ancienne', milestone: s.milestone, prep: s.prep);
    expect(applySessionRework(legacy, title: 'Autre'), isFalse);
    expect(s.milestone.title, sessionTitle('Quadrillage', day));
  });
}
