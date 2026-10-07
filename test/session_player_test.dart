import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/session_player_screen.dart';

void main() {
  test('stepPlannedMin / stepLabel : heure de tête lue puis retirée', () {
    expect(stepPlannedMin('13h45 Fiche 01 RECTO'), 13 * 60 + 45);
    expect(stepPlannedMin('9h Accueil'), 9 * 60);
    expect(stepPlannedMin('Bilan'), isNull);
    expect(stepPlannedMin('25h00 x'), isNull);
    expect(stepLabel('13h45 — Fiche 01 RECTO'), 'Fiche 01 RECTO');
    expect(stepLabel('14h00 Kahoot'), 'Kahoot');
    expect(stepLabel('Bilan'), 'Bilan');
  });

  test('sessionScriptAction : « Dérouler » d\'abord, sinon l\'action avec étapes', () {
    final t = ProjectTask(title: '🎯 S', startDate: DateTime(2026, 10, 12), actions: [
      TaskAction(title: 'Émargement'),
      TaskAction(title: 'Déroulé', checklist: [ChecklistItem(title: 'a')]),
    ]);
    expect(sessionScriptAction(t)!.title, 'Déroulé');
    t.actions.insert(0, TaskAction(title: 'Dérouler la séance (8h30–16h30)'));
    expect(sessionScriptAction(t)!.title, startsWith('Dérouler'));
    expect(sessionScriptAction(ProjectTask(title: 'x', startDate: DateTime(2026, 1, 1))), isNull);
  });
}
