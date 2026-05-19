import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
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

  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? true;
  String? get appleEmail => _auth.currentUser?.email;

  Future<String> signInAnonymously() async {
    if (_auth.currentUser != null) return _auth.currentUser!.uid;
    final cred = await _auth.signInAnonymously();
    return cred.user!.uid;
  }

  // Retourne true si c'est une nouvelle connexion (compte créé),
  // false si c'est une reconnexion (données Firestore existantes à télécharger).
  Future<({bool isNew, String uid})> signInWithApple() async {
    final rawNonce = _generateNonce();
    final nonce = _sha256(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email],
      nonce: nonce,
    );

    final idToken = appleCredential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'apple-token-null',
        message: 'Apple n\'a pas retourné de token d\'identité. Réessaie.',
      );
    }

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: idToken,
      rawNonce: rawNonce,
    );

    // Connexion directe sans linkWithCredential :
    // linkWithCredential "consomme" le token Apple même en cas d'échec,
    // rendant tout appel suivant invalide. La migration des données locales
    // est gérée dans apple_sign_in_button.dart via pushAll/pull.
    final cred = await _auth.signInWithCredential(oauthCredential);
    final isNew = cred.additionalUserInfo?.isNewUser ?? false;
    return (isNew: isNew, uid: cred.user!.uid);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _auth.signInAnonymously();
  }

  static String _generateNonce([int length = 32]) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';
    final rng = Random.secure();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  static String _sha256(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
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

  // ── Merge local + remote ───────────────────────────────────────────────────
  // Stratégie : union par ID pour toutes les collections.
  // En cas de conflit sur le même ID, on préfère l'état le plus "avancé"
  // (done=true pour dayPlan, valeur max pour habitProgress).
  // Les métadonnées scalaires (préférences) viennent du device local.
  static AppState merge(AppState local, AppState remote) {
    // Helpers
    Map<String, T> byId<T>(List<T> items, String Function(T) id) =>
        {for (final i in items) id(i): i};

    // Union simple : remote en base, local écrase par ID
    List<T> union<T>(List<T> localList, List<T> remoteList, String Function(T) id) {
      final map = byId(remoteList, id);
      for (final item in localList) map[id(item)] = item;
      return map.values.toList();
    }

    // dayPlan : préférer done=true ou archived=true du serveur (MCP clear/delete)
    final remotePlan = byId(remote.dayPlan, (i) => i.id);
    final mergedPlan = byId(local.dayPlan, (i) => i.id);
    for (final entry in remotePlan.entries) {
      final loc = mergedPlan[entry.key];
      if (loc == null) {
        mergedPlan[entry.key] = entry.value;
      } else if (!loc.done && entry.value.done) {
        mergedPlan[entry.key] = entry.value;
      } else if (!loc.archived && entry.value.archived) {
        // Le serveur a archivé cet item (ex: clear_day_plan ou delete_action via MCP)
        mergedPlan[entry.key] = entry.value;
      }
    }

    // habitProgress : garder la valeur max par activityId
    final remoteHp = byId(remote.habitProgress, (h) => h.activityId);
    final mergedHp = byId(local.habitProgress, (h) => h.activityId);
    for (final entry in remoteHp.entries) {
      final loc = mergedHp[entry.key];
      if (loc == null || entry.value.value > loc.value) {
        mergedHp[entry.key] = entry.value;
      }
    }

    return AppState(
      // Domains : remote gagne (MCP peut soft-delete via deleted:true)
      domains: () {
        final remoteMap = byId(remote.domains, (d) => d.id);
        final merged = Map.of(remoteMap);
        for (final d in local.domains) {
          if (!remoteMap.containsKey(d.id)) merged[d.id] = d;
        }
        return merged.values.toList();
      }(),
      activities:    union(local.activities,    remote.activities,    (a) => a.id),
      sessions:      union(local.sessions,      remote.sessions,      (s) => s.id),
      habitHits:     union(local.habitHits,     remote.habitHits,     (h) => h.id),
      // Goals : remote est la source de vérité (MCP peut archiver/supprimer)
      // On garde en plus les goals locaux absents du remote (créés offline)
      goals: () {
        final remoteMap = byId(remote.goals, (g) => g.id);
        final merged = Map.of(remoteMap); // remote en base
        for (final goal in local.goals) {
          if (!remoteMap.containsKey(goal.id)) {
            // Créé localement offline → on le garde
            merged[goal.id] = goal;
          }
          // Si présent dans les deux : remote gagne (MCP a la priorité)
        }
        return merged.values.toList();
      }(),
      blocks:        union(local.blocks,        remote.blocks,        (b) => b.id),
      earnedBadges:  union(local.earnedBadges,  remote.earnedBadges,  (b) => b.id.name),
      // Merge spécifique
      dayPlan:       mergedPlan.values.toList(),
      habitProgress: mergedHp.values.toList(),
      // Méta scalaire : valeurs locales (préférences de l'appareil actif)
      onboardingDone:        local.onboardingDone,
      weeklyScoreTarget:     local.weeklyScoreTarget,
      notifHour:             local.notifHour,
      notifMinute:           local.notifMinute,
      notifEnabled:          local.notifEnabled,
      reviewNotifHour:       local.reviewNotifHour,
      reviewNotifMinute:     local.reviewNotifMinute,
      reviewNotifEnabled:    local.reviewNotifEnabled,
    );
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

  // ── Projects ────────────────────────────────────────────────────────────────

  Future<List<Project>> fetchProjects() async {
    if (uid == null) return [];
    final snap = await _col('projects').get();
    return snap.docs.map((d) => Project.from(d.data() as Map)).toList();
  }

  Future<void> saveProject(Project project) async {
    if (uid == null) return;
    await _col('projects').doc(project.id).set(project.toJson());
  }

  Future<void> deleteProject(String projectId) async {
    if (uid == null) return;
    await _col('projects').doc(projectId).delete();
  }

  /// Met à jour uniquement le tableau de tâches d'un projet.
  Future<void> saveProjectTasks(String projectId, List<ProjectTask> tasks) async {
    if (uid == null) return;
    await _col('projects').doc(projectId).update({
      'tasks': tasks.map((t) => t.toJson()).toList(),
    });
  }

  // ── Strategic objectives ────────────────────────────────────────────────────

  Future<List<StrategicObjective>> fetchStrategicObjectives() async {
    if (uid == null) return [];
    try {
      final snap = await _col('strategic_objectives')
          .orderBy('createdAt', descending: true)
          .get();
      return snap.docs
          .map((d) => StrategicObjective.from(d.data() as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveStrategicObjective(StrategicObjective obj) async {
    if (uid == null) return;
    await _col('strategic_objectives').doc(obj.id).set(obj.toJson());
  }

  Future<void> deleteStrategicObjective(String id) async {
    if (uid == null) return;
    await _col('strategic_objectives').doc(id).delete();
  }

  // ── API tokens ───────────────────────────────────────────────────────────────

  Future<List<ApiToken>> fetchApiTokens() async {
    if (uid == null) return [];
    try {
      final snap = await _col('api_tokens').get();
      return snap.docs
          .map((d) => ApiToken.from(d.data() as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Crée un token, le persiste et le retourne (valeur brute visible une seule fois).
  Future<ApiToken> createApiToken(String label) async {
    final token = ApiToken(label: label);
    await _col('api_tokens').doc(token.id).set(token.toJson());
    return token;
  }

  Future<void> revokeApiToken(String tokenId) async {
    if (uid == null) return;
    await _col('api_tokens').doc(tokenId).update({'active': false});
  }
}
