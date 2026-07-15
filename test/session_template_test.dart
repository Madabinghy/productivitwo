import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';

// ─── DÉROULÉS RÉUTILISABLES (session_templates) ──────────────────────────────

void main() {
  test('SessionTemplate round-trip JSON (étapes simples, routines, checklist)',
      () {
    final t = SessionTemplate(
      title: 'Séance A — haut du corps',
      activityId: 'act-musculation',
      steps: [
        SessionStep(title: 'Échauffement', checklist: ['Mobilité épaules']),
        SessionStep(title: 'Pompes', kind: 'routine', routineId: 'r-pompes'),
        SessionStep(title: 'Tractions', kind: 'routine', routineId: 'r-trac'),
      ],
    );
    final back = SessionTemplate.from(t.toJson());
    expect(back.id, t.id);
    expect(back.title, t.title);
    expect(back.activityId, 'act-musculation');
    expect(back.archived, isFalse);
    expect(back.steps, hasLength(3));
    expect(back.steps[0].kind, 'check');
    expect(back.steps[0].checklist, ['Mobilité épaules']);
    expect(back.steps[1].kind, 'routine');
    expect(back.steps[1].routineId, 'r-pompes');
    expect(back.steps[2].id, t.steps[2].id);
  });

  test('SessionTemplate.from tolère un doc minimal (rétrocompatibilité)', () {
    final t = SessionTemplate.from({'title': 'X', 'activityId': 'a1'});
    expect(t.steps, isEmpty);
    expect(t.archived, isFalse);
    expect(t.id, isNotEmpty);
  });
}
