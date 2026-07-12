import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/free_moment.dart';

void main() {
  group('freeIntentsFor', () {
    test('« Dormir » n\'existe que le soir (20 h → 5 h)', () {
      expect(freeIntentsFor(DateTime(2026, 7, 10, 22, 0)).first,
          FreeIntent.sleep);
      expect(freeIntentsFor(DateTime(2026, 7, 10, 0, 30)).first,
          FreeIntent.sleep);
      expect(freeIntentsFor(DateTime(2026, 7, 10, 14, 0)),
          isNot(contains(FreeIntent.sleep)));
    });

    test('en journée, le projet passe en premier', () {
      expect(freeIntentsFor(DateTime(2026, 7, 10, 10, 0)).first,
          FreeIntent.project);
    });
  });

  group('projectProposals', () {
    Project proj(String title, List<ProjectTask> tasks) =>
        Project(title: title, startDate: DateTime(2026, 7, 1), createdBy: 'test', tasks: tasks);
    ProjectTask task(String title,
            {DateTime? end, String status = 'pending', bool today = false}) =>
        ProjectTask(
            title: title,
            startDate: DateTime(2026, 7, 1),
            endDate: end,
            status: status,
            todayFlag: today);

    test('en retard d\'abord, puis deadline proche, puis priorité du jour',
        () {
      final now = DateTime(2026, 7, 10, 15, 0);
      final props = projectProposals(now, [
        proj('P', [
          task('Sans date'),
          task('Deadline proche', end: DateTime(2026, 7, 20)),
          task('En retard', end: DateTime(2026, 7, 5)),
          task('Prio du jour', today: true),
        ]),
      ]);
      expect(props.map((p) => p.task.title).toList(),
          ['En retard', 'Prio du jour', 'Deadline proche']);
      expect(props.first.subtitle, contains('en retard'));
    });

    test('les tâches faites/sautées et jalons sont exclus', () {
      final now = DateTime(2026, 7, 10, 15, 0);
      final props = projectProposals(now, [
        proj('P', [
          task('Faite', status: 'done'),
          task('Sautée', status: 'skipped'),
          ProjectTask(
              title: 'Jalon',
              startDate: DateTime(2026, 7, 1),
              isMilestone: true),
        ]),
      ]);
      expect(props, isEmpty);
    });
  });

  group('routineProposals', () {
    test('routines non tenues, intention du domaine citée quand définie', () {
      final st = AppState(
        domains: [
          Domain(
              id: 'd1',
              name: 'Santé',
              definitionStatus: 'active',
              intention: 'un corps qui suit'),
        ],
        activities: [
          Activity(
              id: 'r1',
              name: 'Marche',
              domainId: 'd1',
              type: 'habit',
              order: 1),
          Activity(
              id: 'r2',
              name: 'Lecture',
              domainId: 'd2',
              type: 'habit',
              order: 0),
          Activity(
              id: 'r3',
              name: 'Faite',
              domainId: 'd1',
              type: 'habit',
              order: 2),
        ],
        sessions: [],
        habitProgress: [],
      );
      final props = routineProposals(st, (a) => a.id == 'r3');
      expect(props.map((p) => p.routine.name).toList(),
          ['Lecture', 'Marche']); // ordre utilisateur
      expect(props[1].subtitle, 'Santé — « un corps qui suit »');
      expect(props[0].subtitle, isNull); // domaine inconnu → rien d'inventé
    });

    test('élan réel dans le sous-titre (série ≥ 3) + domaine non défini signalé',
        () {
      final now = DateTime(2026, 7, 10, 10, 0);
      final st = AppState(
        domains: [
          Domain(
              id: 'd1',
              name: 'Santé',
              definitionStatus: 'active',
              intention: 'un corps qui suit'),
          Domain(id: 'd2', name: 'Business', definitionStatus: 'named'),
        ],
        activities: [
          Activity(
              id: 'r1', name: 'Marche', domainId: 'd1', type: 'habit', order: 0),
          Activity(
              id: 'r2',
              name: 'Prospection',
              domainId: 'd2',
              type: 'habit',
              order: 1),
        ],
        sessions: [],
        habitProgress: [],
        habitHits: [
          for (var i = 1; i <= 4; i++)
            HabitHit(
                habitId: 'r1',
                ts: DateTime(2026, 7, 10 - i, 9, 0)), // 4 jours d'affilée
          HabitHit(habitId: 'r2', ts: DateTime(2026, 7, 9, 14, 0)), // 1 seul
        ],
      );
      final props = routineProposals(st, (_) => false, now: now);
      // Marche : intention + élan, joints par « · ».
      expect(props[0].subtitle, contains('un corps qui suit'));
      expect(props[0].subtitle, contains('4 j d\'affilée — on continue ?'));
      expect(props[0].undefinedDomain, isNull);
      // Prospection : domaine nommé mais non défini → lien « définir », et
      // série de 1 jour = pas un élan (rien d'affiché).
      expect(props[1].undefinedDomain, 'Business');
      expect(props[1].subtitle, isNull);
    });
  });
}
