import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:productivitwo_v1/models.dart';

/// Synchronisation Firestore.
/// Structure : users/{uid}/<collection>/{id}
class FirestoreSync {
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

  // ── Push ────────────────────────────────────────────────────────────────────

  Future<void> pushAll(AppState st) => pushDeltas(st);

  Future<void> pushDeltas(AppState st) async {
    if (uid == null) return;
    try {
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
    } catch (_) {}
  }

  Future<void> _pushCollection(
      List<Map<String, dynamic>> items, String name) async {
    final col = _col(name);
    final batch = _db.batch();
    final existing = await col.get();
    final localIds = items.map((e) => e['id'] as String).toSet();
    for (final doc in existing.docs) {
      if (!localIds.contains(doc.id)) batch.delete(doc.reference);
    }
    for (final item in items) {
      batch.set(col.doc(item['id'] as String), item);
    }
    await batch.commit();
  }

  // ── Pull ────────────────────────────────────────────────────────────────────

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
      if (!metaDoc.exists) return null;

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
    } catch (_) {
      return null;
    }
  }

  // ── Suppression de compte ───────────────────────────────────────────────────

  Future<void> deleteAccount() async {
    if (uid == null) return;
    // 1) Supprime toutes les données Firestore
    for (final col in [
      'domains', 'activities', 'sessions', 'habitProgress',
      'habitHits', 'dayPlan', 'goals', 'blocks', 'badges'
    ]) {
      final docs = await _col(col).get();
      final batch = _db.batch();
      for (final d in docs.docs) batch.delete(d.reference);
      await batch.commit();
    }
    await _meta().delete();
    // 2) Supprime le compte Firebase Auth
    await _auth.currentUser?.delete();
  }

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
