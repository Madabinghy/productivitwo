// Merge des sessions de temps (FirestoreSync.mergeSessions) : un chrono arrêté
// ou supprimé ailleurs ne doit jamais revenir ouvert depuis la copie locale.
// Pur Dart (aucun appel Firebase).

import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

void main() {
  final now = DateTime(2026, 8, 3, 10);
  Session s(String id, DateTime start, [DateTime? end, bool deleted = false]) =>
      Session(id: id, activityId: 'a', startAt: start, endAt: end, deleted: deleted);

  test('arrêté sur le web, encore ouvert en local → la version fermée gagne', () {
    final start = now.subtract(const Duration(hours: 30));
    final end = start.add(const Duration(hours: 1));
    final r = FirestoreSync.mergeSessions([s('x', start)], [s('x', start, end)], now);
    expect(r.single.endAt, end);
  });

  test('supprimé à distance → retiré, même si le local le garde', () {
    final start = now.subtract(const Duration(hours: 2));
    final r = FirestoreSync.mergeSessions(
        [s('x', start, now)], [s('x', start, now, true)], now);
    expect(r, isEmpty);
  });

  test('chrono ouvert fantôme absent du remote (> 12 h) → abandonné', () {
    final r = FirestoreSync.mergeSessions(
        [s('x', now.subtract(const Duration(hours: 40)))], [], now);
    expect(r, isEmpty);
  });

  test('session récente créée hors ligne → conservée', () {
    final r = FirestoreSync.mergeSessions(
        [s('x', now.subtract(const Duration(minutes: 20)))], [], now);
    expect(r.single.id, 'x');
    final closed = FirestoreSync.mergeSessions([
      s('y', now.subtract(const Duration(days: 3)), now.subtract(const Duration(days: 3, hours: -1)))
    ], [], now);
    expect(closed.single.id, 'y');
  });

  test('édition locale d\'une session fermée → le local gagne', () {
    final start = now.subtract(const Duration(hours: 5));
    final r = FirestoreSync.mergeSessions([s('x', start, start.add(const Duration(minutes: 30)))],
        [s('x', start, start.add(const Duration(hours: 4)))], now);
    expect(r.single.endAt, start.add(const Duration(minutes: 30)));
  });

  test('deleted survit au toJson / from', () {
    final j = s('x', now, null, true).toJson();
    expect(j['deleted'], true);
    expect(Session.from(j).deleted, true);
    expect(s('y', now).toJson().containsKey('deleted'), false);
  });
}
