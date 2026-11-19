import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

void main() {
  Activity pompes({bool rolling = false, int? minPerHit, int target = 20}) => Activity(
        id: 'pompes',
        domainId: 'sport',
        name: 'Pompes',
        type: 'habit',
        habitFreq: HabitFreq.daily,
        habitTarget: target,
        rolling: rolling,
        minPerHit: minPerHit,
        createdAt: DateTime(2026, 1, 1),
      );

  /// Le document tel qu'une version plus ancienne de l'app l'écrit : sans les champs récents.
  Map<String, dynamic> oldDoc(Activity a) => a.toJson()
    ..remove('rolling')
    ..remove('minPerHit');

  AppState stateOf(List<Activity> acts) => AppState(domains: [], activities: acts, sessions: [], habitProgress: []);

  test('un champ absent du document distant garde la valeur de l\'appareil', () {
    final local = pompes(rolling: true, minPerHit: 5);
    final remote = Activity.from(oldDoc(pompes(target: 25)));
    final m = Activity.keepLocalFields(local, remote);
    expect(m.rolling, isTrue);
    expect(m.minPerHit, 5);
    // Le reste vient du serveur.
    expect(m.habitTarget, 25);
  });

  test('un champ présent sur le serveur gagne, même à faux', () {
    final local = pompes(rolling: true);
    final remote = Activity.from(pompes(rolling: false).toJson());
    expect(Activity.keepLocalFields(local, remote).rolling, isFalse);
  });

  test('le réglage posé ailleurs arrive sur l\'appareil', () {
    final local = pompes();
    final remote = Activity.from(pompes(rolling: true).toJson());
    expect(Activity.keepLocalFields(local, remote).rolling, isTrue);
  });

  test('la fusion du lancement garde « sur 7 jours » face à un document d\'avant', () {
    final local = stateOf([pompes(rolling: true)]);
    final remote = stateOf([Activity.from(oldDoc(pompes()))]);
    final merged = FirestoreSync.merge(local, remote);
    expect(merged.activities.single.rolling, isTrue);
    // Le document renvoyé au serveur porte de nouveau le champ.
    expect(merged.activities.single.toJson()['rolling'], isTrue);
  });

  test('une routine supprimée ailleurs reste supprimée', () {
    final local = stateOf([pompes(rolling: true)]);
    final gone = oldDoc(pompes())..['deleted'] = true;
    final merged = FirestoreSync.merge(local, stateOf([Activity.from(gone)]));
    expect(merged.activities, isEmpty);
  });

  test('une routine connue du seul appareil est gardée telle quelle', () {
    final merged = FirestoreSync.merge(stateOf([pompes(rolling: true)]), stateOf([]));
    expect(merged.activities.single.rolling, isTrue);
  });
}
