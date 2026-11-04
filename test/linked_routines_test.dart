import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/linked_routines.dart';
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show routineTodayCount;

Activity _routine(String id, String name, {String? catalogId}) =>
    Activity(id: id, domainId: 'd', name: name, type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1)..catalogId = catalogId;

void main() {
  test('reconnaît Planifier ma journée et Boire de l\'eau', () {
    expect(isPlanRoutineName('Planifier ma journée'), isTrue);
    expect(isPlanRoutineName('Planifier demain'), isTrue);
    expect(isPlanRoutineName('Plan du jour'), isTrue);
    expect(isPlanRoutineName('Planifier les vacances'), isFalse);
    expect(isPlanRoutineName('Lecture'), isFalse);
    expect(isWaterRoutineName('Boire de l’eau'), isTrue);
    expect(isWaterRoutineName('Verre d\'eau'), isTrue);
    expect(isWaterRoutineName('Hydratation'), isTrue);
    expect(isWaterRoutineName('Beauté'), isFalse);
  });

  test('la carte du catalogue passe avant le nom', () {
    final acts = [_routine('a', 'Planifier demain'), _routine('b', 'Ma préparation', catalogId: kPlanRoutineCatalogId)];
    expect(planRoutineOf(acts)!.id, 'b');
    expect(planRoutineOf([_routine('c', 'Lecture')]), isNull);
    expect(isPlanRoutine(_routine('d', 'Planifier ma journée', catalogId: 'lecture')), isFalse);
  });

  test('journée posée : +1 une seule fois sur la routine', () {
    final r = _routine('p', 'Planifier ma journée', catalogId: kPlanRoutineCatalogId);
    final logic = AppLogic(AppState(domains: [], activities: [r], sessions: [], habitProgress: []), () {});
    expect(logic.countPlannedDay(), isTrue);
    expect(logic.countPlannedDay(), isFalse);
    expect(routineTodayCount(logic, r), 1);
  });

  test('sans la routine, rien ne se passe', () {
    final logic = AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {});
    expect(logic.countPlannedDay(), isFalse);
  });
}
