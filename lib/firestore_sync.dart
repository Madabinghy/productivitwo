import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:productivitwo_v1/models.dart';

/// Synchronisation via Firebase Realtime Database.
/// Structure : users/{uid}/appstate  (JSON complet de AppState)
///
/// Avantages vs Firestore :
/// - Pas de gRPC / BoringSSL → pas de problème de compilation en CI
/// - AppState déjà sérialisé en JSON localement → zero refactoring
/// - Parfait pour un seul utilisateur avec sync complète
class FirestoreSync {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseDatabase get _db => FirebaseDatabase.instance;

  String? get uid => _auth.currentUser?.uid;
  DatabaseReference get _stateRef => _db.ref('users/$uid/appstate');

  // ── Auth ────────────────────────────────────────────────────────────────────

  Future<String> signInAnonymously() async {
    if (_auth.currentUser != null) return _auth.currentUser!.uid;
    final cred = await _auth.signInAnonymously();
    return cred.user!.uid;
  }

  // ── Push (local → Firebase) ─────────────────────────────────────────────────

  Future<void> pushAll(AppState st) => _push(st);
  Future<void> pushDeltas(AppState st) => _push(st);

  Future<void> _push(AppState st) async {
    if (uid == null) return;
    try {
      final json = st.toJson();
      // Realtime Database n'accepte pas les valeurs null dans les maps
      final cleaned = _removeNulls(json);
      await _stateRef.set(cleaned);
    } catch (_) {
      // Silencieux si offline — Firebase queue la mise à jour automatiquement
    }
  }

  // ── Pull (Firebase → local) ─────────────────────────────────────────────────

  Future<AppState?> pull() async {
    if (uid == null) return null;
    try {
      final snapshot = await _stateRef.get();
      if (!snapshot.exists || snapshot.value == null) return null;
      final raw = snapshot.value;
      // Realtime Database retourne des Maps<Object?, Object?> — on convertit
      final json = _toStringKeyedMap(raw);
      return AppState.from(json);
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  // Supprime les valeurs null récursivement (non supportées par RTDB)
  dynamic _removeNulls(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      final result = <String, dynamic>{};
      value.forEach((k, v) {
        final cleaned = _removeNulls(v);
        if (cleaned != null) result[k.toString()] = cleaned;
      });
      return result;
    }
    if (value is List) {
      return value.map(_removeNulls).where((e) => e != null).toList();
    }
    return value;
  }

  // Convertit les Map<Object?, Object?> de RTDB en Map<String, dynamic>
  dynamic _toStringKeyedMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.fromEntries(
        value.entries.map((e) =>
            MapEntry(e.key.toString(), _toStringKeyedMap(e.value))),
      );
    }
    if (value is List) {
      return value.map(_toStringKeyedMap).toList();
    }
    return value;
  }
}
