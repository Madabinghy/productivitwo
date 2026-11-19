import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';

/// Une seule durée par routine : le ⏱ de la ligne et, si le chrono coche, le temps d'une coche.
void main() {
  Activity routine({int? timerMin, int? minPerHit}) => Activity(
      id: 'r', domainId: 'd', name: 'Vaisselle', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, timerMin: timerMin, minPerHit: minPerHit, linkedActivityId: 'menage');

  test('la durée d\'une fois : celle du chrono qui coche, sinon celle du minuteur', () {
    expect(routine().onceMin, isNull);
    expect(routine(timerMin: 15).onceMin, 15);
    expect(routine(minPerHit: 10).onceMin, 10);
    expect(routine(timerMin: 15, minPerHit: 10).onceMin, 10);
  });

  test('régler la durée règle le minuteur et la coche du chrono si elle est allumée', () {
    final off = routine(timerMin: 15)..setOnceMin(20);
    expect((off.timerMin, off.minPerHit), (20, null));
    final on = routine(timerMin: 10, minPerHit: 10)..setOnceMin(20);
    expect((on.timerMin, on.minPerHit), (20, 20));
    // Aucune durée : plus de minuteur, et le chrono ne coche plus.
    on.setOnceMin(0);
    expect((on.timerMin, on.minPerHit), (null, null));
  });

  test('allumer « le chrono coche » prend la durée d\'une fois, l\'éteindre garde le minuteur', () {
    final a = routine(timerMin: 10)..setChronoHits(true);
    expect((a.timerMin, a.minPerHit), (10, 10));
    a.setChronoHits(false);
    expect((a.timerMin, a.minPerHit), (10, null));
  });

  test('à la lecture, deux durées différentes : celle du chrono gagne', () {
    final a = Activity.from({'id': 'r', 'name': 'Vaisselle', 'type': 'habit', 'timerMin': 15, 'minPerHit': 10});
    expect((a.timerMin, a.minPerHit, a.onceMin), (10, 10, 10));
    // Sans « le chrono coche », le minuteur reste tel quel.
    expect(Activity.from({'id': 'r', 'name': 'X', 'type': 'habit', 'timerMin': 15}).timerMin, 15);
    // Une activité de temps n'est pas concernée.
    expect(Activity.from({'id': 't', 'name': 'Lecture', 'type': 'time', 'timerMin': 25, 'minPerHit': 10}).timerMin, 25);
  });
}
