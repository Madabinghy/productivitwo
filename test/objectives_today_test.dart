import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/objective_day.dart';
import 'package:productivitwo_v1/utils/objectives_today.dart';

void main() {
  final courir = Activity(id: 'c', name: 'Courir', domainId: 'd', type: 'time');
  final pompes = Activity(id: 'p', name: 'Pompes', domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 20);
  final bible = Activity(id: 'b', name: 'Lire la Bible', domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1);
  final kg = StrategicObjective(id: 'kg', title: 'Atteindre 90 kg');
  final foi = StrategicObjective(id: 'foi', title: 'Lire la Bible chaque jour');

  ObjectivesToday build({int pompesDone = 0}) => buildObjectivesToday(
        [
          ObjectiveDay(
            objective: kg,
            times: [ObjectiveTimeToday(activity: courir, activityId: 'c', weeklyMin: 490, doneTodayMin: 45, doneWeekMin: 200)],
            routines: [pompes],
            blocks: const [],
            nextActions: const [],
          ),
          ObjectiveDay(objective: foi, times: const [], routines: [bible], blocks: const [], nextActions: const []),
        ],
        routineProgress: (a) => a.id == 'p' ? (pompesDone, 20) : (1, 1),
        readingDue: (o) => o.id == 'kg',
        pctOf: (o) => o.id == 'kg' ? 61 : 100,
      );

  test('chiffre du jour, statuts et file classée', () {
    final v = build();
    // Courir (70 attendues, 45 faites), Pompes, relevé = à faire ; la Bible = faite.
    expect((v.doneCount, v.total, v.remaining, v.lateCount), (1, 4, 3, 1));
    expect(v.statuses.first.objective.id, 'kg');
    expect(v.statuses.first.left, ['25 min de Courir', 'Pompes', 'relevé']);
    expect(v.statuses.last.heldToday, isTrue);
    expect(v.todo.map((t) => t.kind).toList(), [ObjTodoKind.reading, ObjTodoKind.time, ObjTodoKind.routine]);
    expect(v.todo[1].title, 'Courir · encore 25 min');
  });

  test('une routine atteinte passe dans les faites', () {
    final v = build(pompesDone: 20);
    expect(v.done.map((t) => t.activity?.id).toSet(), {'p', 'b'});
  });
}
