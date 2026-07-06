// Tests de l'encodage canonique du push delta (FirestoreSync.stableJson) :
// c'est l'empreinte qui décide si un doc est réécrit dans Firestore ou non.
// Un faux « différent » = écritures inutiles ; un faux « identique » = perte
// de données. Pur Dart (aucun appel Firebase).

import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

void main() {
  group('FirestoreSync.stableJson — empreinte canonique', () {
    test('même contenu, ordre de clés différent → même empreinte', () {
      // Le remote (Firestore) ne garantit pas l'ordre des clés du toJson.
      final a = {'id': 'x', 'name': 'Sport', 'deleted': false};
      final b = {'deleted': false, 'id': 'x', 'name': 'Sport'};
      expect(FirestoreSync.stableJson(a), FirestoreSync.stableJson(b));
    });

    test('maps imbriquées et listes : ordre de clés neutralisé, ordre de liste significatif', () {
      final a = {
        'id': 'x',
        'checklist': {'h1': ['eau', 'vaisselle'], 'h2': ['lit']},
      };
      final b = {
        'checklist': {'h2': ['lit'], 'h1': ['eau', 'vaisselle']},
        'id': 'x',
      };
      expect(FirestoreSync.stableJson(a), FirestoreSync.stableJson(b));

      final swapped = {
        'id': 'x',
        'checklist': {'h1': ['vaisselle', 'eau'], 'h2': ['lit']},
      };
      expect(FirestoreSync.stableJson(a),
          isNot(FirestoreSync.stableJson(swapped)));
    });

    test('un champ modifié → empreinte différente', () {
      final before = {'id': 's1', 'endAt': null};
      final after = {'id': 's1', 'endAt': '2026-07-06T10:00:00.000'};
      expect(FirestoreSync.stableJson(before),
          isNot(FirestoreSync.stableJson(after)));
    });

    test('types non-JSON (DateTime) tolérés et déterministes', () {
      final d = DateTime(2026, 7, 6, 10);
      final a = {'id': 'x', 'ts': d};
      final b = {'ts': DateTime(2026, 7, 6, 10), 'id': 'x'};
      expect(FirestoreSync.stableJson(a), FirestoreSync.stableJson(b));
    });

    test('toJson des modèles réels → round-trip stable (Session, HabitHit)', () {
      final s = Session(
          activityId: 'act-1',
          startAt: DateTime(2026, 7, 6, 9),
          endAt: DateTime(2026, 7, 6, 10),
          taskId: 't1');
      // Deux appels à toJson produisent la même empreinte (pas de champ volatil).
      expect(FirestoreSync.stableJson(s.toJson()),
          FirestoreSync.stableJson(s.toJson()));

      final h = HabitHit(habitId: 'h1', ts: DateTime(2026, 7, 6, 8));
      expect(FirestoreSync.stableJson(h.toJson()),
          FirestoreSync.stableJson(h.toJson()));
    });
  });
}
