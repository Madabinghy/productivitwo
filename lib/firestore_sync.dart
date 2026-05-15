import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:productivitwo_v1/models.dart';

/// Service de synchronisation Firestore.
/// Chaque collection AppState correspond à une sous-collection Firestore.
///
/// Structure :
///   users/{uid}/meta          (doc) — onboardingDone, settings, etc.
///   users/{uid}/domains       (collection)
///   users/{uid}/activities    (collection)
///   users/{uid}/sessions      (collection)
///   users/{uid}/habitProgress (collection)
///   users/{uid}/habitHits     (collection)
///   users/{uid}/dayPlan       (collection)
///   users/{uid}/goals         (collection)
///   users/{uid}/blocks        (collection)
///   users/{uid}/badges        (collection)
class FirestoreSync {
  // Lazy — accédés seulement après Firebase.initializeApp()
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  String? get uid => _auth.currentUser?.uid;

  DocumentReference _meta() => _db.doc('users/$uid/data/meta');
  CollectionReference _col(String name) =>
      _db.collection('users/$uid/$name');

  // ── Auth ────────────────────────────────────────────────────────────────────

  Future<String> signInAnonymously() async {
    if (_auth.currentUser != null) return _auth.currentUser!.uid;
    final cred = await _auth.signInAnonymously();
    return cred.user!.uid;
  }

  // ── Push (local → Firestore) ────────────────────────────────────────────────

  Future<void> pushAll(AppState st) async {
    if (uid == null) return;
    final batch = _db.batch();

    // Meta / settings
    batch.set(_meta(), _encodeMeta(st), SetOptions(merge: true));

    // Collections
    await _pushCollection(st.domains.map((e) => e.toJson()).toList(), 'domains');
    await _pushCollection(st.activities.map((e) => e.toJson()).toList(), 'activities');
    await _pushCollection(st.sessions.map((e) => e.toJson()).toList(), 'sessions');
    await _pushCollection(st.habitProgress.map((e) => e.toJson()).toList(), 'habitProgress');
    await _pushCollection(st.habitHits.map((e) => e.toJson()).toList(), 'habitHits');
    await _pushCollection(st.dayPlan.map((e) => e.toJson()).toList(), 'dayPlan');
    await _pushCollection(st.goals.map((e) => e.toJson()).toList(), 'goals');
    await _pushCollection(st.blocks.map((e) => e.toJson()).toList(), 'blocks');
    await _pushCollection(st.earnedBadges.map((e) => e.toJson()).toList(), 'badges');

    await batch.commit();
  }

  Future<void> _pushCollection(
      List<Map<String, dynamic>> items, String name) async {
    final col = _col(name);
    final batch = _db.batch();
    // Supprime les docs obsolètes (ids qui n'existent plus localement)
    final existing = await col.get();
    final localIds = items.map((e) => e['id'] as String).toSet();
    for (final doc in existing.docs) {
      if (!localIds.contains(doc.id)) batch.delete(doc.reference);
    }
    for (final item in items) {
      final id = item['id'] as String;
      batch.set(col.doc(id), item);
    }
    await batch.commit();
  }

  // ── Delta push (une seule collection) ──────────────────────────────────────
  // Appelé à chaque onChange() pour ne pousser que ce qui a changé.

  Future<void> pushDeltas(AppState st) async {
    if (uid == null) return;
    // Pour simplifier, on fait un push complet mais en parallèle
    // (Firestore ne facture que les docs effectivement écrits)
    await Future.wait([
      _pushCollection(st.domains.map((e) => e.toJson()).toList(), 'domains'),
      _pushCollection(st.activities.map((e) => e.toJson()).toList(), 'activities'),
      _pushCollection(st.sessions.map((e) => e.toJson()).toList(), 'sessions'),
      _pushCollection(st.habitProgress.map((e) => e.toJson()).toList(), 'habitProgress'),
      _pushCollection(st.habitHits.map((e) => e.toJson()).toList(), 'habitHits'),
      _pushCollection(st.dayPlan.map((e) => e.toJson()).toList(), 'dayPlan'),
      _pushCollection(st.goals.map((e) => e.toJson()).toList(), 'goals'),
      _pushCollection(st.blocks.map((e) => e.toJson()).toList(), 'blocks'),
      _pushCollection(st.earnedBadges.map((e) => e.toJson()).toList(), 'badges'),
      _meta().set(_encodeMeta(st), SetOptions(merge: true)),
    ]);
  }

  // ── Pull (Firestore → local) ────────────────────────────────────────────────

  Future<AppState?> pull() async {
    if (uid == null) return null;

    try {
      final results = await Future.wait([
        _meta().get(),
        _col('domains').get(),
        _col('activities').get(),
        _col('sessions').get(),
        _col('habitProgress').get(),
        _col('habitHits').get(),
        _col('dayPlan').get(),
        _col('goals').get(),
        _col('blocks').get(),
        _col('badges').get(),
      ]);

      final metaDoc = results[0] as DocumentSnapshot;
      if (!metaDoc.exists) return null; // premier lancement, pas encore de data

      final meta = metaDoc.data() as Map<String, dynamic>;

      List<Map<String, dynamic>> docs(int idx) =>
          (results[idx] as QuerySnapshot)
              .docs
              .map((d) => d.data() as Map<String, dynamic>)
              .toList();

      return AppState(
        domains: docs(1).map(Domain.from).toList(),
        activities: docs(2).map(Activity.from).toList(),
        sessions: docs(3).map(Session.from).toList(),
        habitProgress: docs(4).map(HabitProgress.from).toList(),
        habitHits: docs(5).map(HabitHit.from).toList(),
        dayPlan: docs(6).map(DayPlanItem.from).toList(),
        goals: docs(7).map(Goal.from).toList(),
        blocks: docs(8).map(DayBlock.from).toList(),
        earnedBadges: docs(9)
            .map(EarnedBadge.tryFrom)
            .whereType<EarnedBadge>()
            .toList(),
        onboardingDone: meta['onboardingDone'] ?? false,
        weeklyScoreTarget: meta['weeklyScoreTarget'] ?? 80,
        notifHour: meta['notifHour'] ?? 9,
        notifMinute: meta['notifMinute'] ?? 0,
        notifEnabled: meta['notifEnabled'] ?? true,
        reviewNotifHour: meta['reviewNotifHour'] ?? 21,
        reviewNotifMinute: meta['reviewNotifMinute'] ?? 0,
        reviewNotifEnabled: meta['reviewNotifEnabled'] ?? true,
      );
    } catch (e) {
      return null; // fallback sur données locales si Firestore inaccessible
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Map<String, dynamic> _encodeMeta(AppState st) => {
        'onboardingDone': st.onboardingDone,
        'weeklyScoreTarget': st.weeklyScoreTarget,
        'notifHour': st.notifHour,
        'notifMinute': st.notifMinute,
        'notifEnabled': st.notifEnabled,
        'reviewNotifHour': st.reviewNotifHour,
        'reviewNotifMinute': st.reviewNotifMinute,
        'reviewNotifEnabled': st.reviewNotifEnabled,
        'lastSync': FieldValue.serverTimestamp(),
      };
}
