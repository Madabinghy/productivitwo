import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/dev_logger.dart';

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
      // firebase_auth ≥ 5.2 exige aussi l'accessToken (= authorizationCode Apple) :
      // sans lui, Firebase rejette avec « Invalid OAuth response from apple.com ».
      accessToken: appleCredential.authorizationCode,
    );

    // Connexion directe sans linkWithCredential :
    // linkWithCredential "consomme" le token Apple même en cas d'échec,
    // rendant tout appel suivant invalide. La migration des données locales
    // est gérée dans apple_sign_in_button.dart via pushAll/pull.
    final cred = await _auth.signInWithCredential(oauthCredential);
    final isNew = cred.additionalUserInfo?.isNewUser ?? false;
    return (isNew: isNew, uid: cred.user!.uid);
  }

  // URL de continuation pour le magic link — doit être dans les domaines autorisés Firebase
  static const _emailLinkUrl = 'https://app.productivitwo.com/email-signin';

  Future<void> sendSignInLink(String email) async {
    final settings = ActionCodeSettings(
      url: _emailLinkUrl,
      handleCodeInApp: true,
      iOSBundleId: 'com.madabinghy.productivitwo',
      androidPackageName: 'com.madabinghy.productivitwo',
      androidInstallApp: true,
      androidMinimumVersion: '21',
    );
    await _auth.sendSignInLinkToEmail(email: email, actionCodeSettings: settings);
  }

  Future<({bool isNew, String uid})> signInWithEmailLink(String email, String link) async {
    if (!_auth.isSignInWithEmailLink(link)) {
      throw FirebaseAuthException(
        code: 'invalid-email-link',
        message: 'Ce lien de connexion n\'est pas valide.',
      );
    }
    final credential = EmailAuthProvider.credentialWithLink(email: email, emailLink: link);
    UserCredential cred;
    if (_auth.currentUser != null && _auth.currentUser!.isAnonymous) {
      try {
        cred = await _auth.currentUser!.linkWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        // Compte déjà créé en amont (webhook systeme.io → formation) : on ne peut
        // pas lier le compte anonyme, on bascule sur le compte existant qui porte
        // déjà les domaines/activités générés par la formation.
        if (e.code == 'email-already-in-use' || e.code == 'credential-already-in-use') {
          cred = await _auth.signInWithCredential(credential);
        } else {
          rethrow;
        }
      }
    } else {
      cred = await _auth.signInWithCredential(credential);
    }
    final isNew = cred.additionalUserInfo?.isNewUser ?? false;
    return (isNew: isNew, uid: cred.user!.uid);
  }

  String? get userEmail => _auth.currentUser?.email;
  bool isEmailSignInLink(String link) => _auth.isSignInWithEmailLink(link);

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
      if (!localIds.contains(doc.id)) {
        final data = doc.data() as Map<String, dynamic>?;
        final isDeleted = data?['deleted'] == true;
        if (isDeleted) {
          // Item soft-deleted : on peut hard-delete maintenant que le local ne l'a plus
          batch.delete(doc.reference);
        }
        // Sinon : item créé par MCP pendant que l'app tournait → laisser, sera mergé au prochain pull
      }
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
        _col('blocks').get(),
        _col('badges').get(),
      ]);

      final metaDoc = results[0] as DocumentSnapshot;
      // Si le meta n'existe pas encore, on continue avec des valeurs par défaut
      // (ne pas retourner null — sinon le merge ne se fait jamais)
      final meta = metaDoc.exists
          ? metaDoc.data() as Map<String, dynamic>
          : <String, dynamic>{};

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
        blocks: docs(6).map(DayBlock.from).toList(),
        earnedBadges: docs(7)
            .map(EarnedBadge.tryFrom)
            .whereType<EarnedBadge>()
            .toList(),
        onboardingDone: meta['onboardingDone'] ?? false,
        challengesDone: meta['challengesDone'] ?? 0,
        challengeStreak: meta['challengeStreak'] ?? 0,
        lastChallengeYmd: meta['lastChallengeYmd'] as String?,
        ganttActionsByDay: (meta['ganttActionsByDay'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        challengeWinsByDay: (meta['challengeWinsByDay'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        gold: (meta['gold'] as num?)?.toInt() ?? 0,
        goldLifetime: (meta['goldLifetime'] as num?)?.toInt() ?? 0,
        goldLastProcessedDay: meta['goldLastProcessedDay'] as String?,
        goldInventory: (meta['goldInventory'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        goldGelDays: (meta['goldGelDays'] as List?)?.cast<String>(),
        cosmeticsOwned: (meta['cosmeticsOwned'] as List?)?.cast<String>(),
        activeTitle: meta['activeTitle'] as String?,
        weeklyScoreTarget: meta['weeklyScoreTarget'] ?? 80,
        notifHour: meta['notifHour'] ?? 9,
        notifMinute: meta['notifMinute'] ?? 0,
        notifEnabled: meta['notifEnabled'] ?? true,
        reviewNotifHour: meta['reviewNotifHour'] ?? 21,
        reviewNotifMinute: meta['reviewNotifMinute'] ?? 0,
        reviewNotifEnabled: meta['reviewNotifEnabled'] ?? true,
      );
    } catch (e, stack) {
      devLog.error('pull() exception: $e\n${stack.toString().split('\n').take(5).join('\n')}', tag: 'FIREBASE');
      return null;
    }
  }

  // ── Merge local + remote ───────────────────────────────────────────────────
  // Stratégie : union par ID pour toutes les collections.
  // En cas de conflit sur le même (activité, jour) habitProgress, on garde la valeur max.
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

    // habitProgress : clé composite (activityId + yyyymmdd) pour préserver chaque jour.
    // En cas de conflit sur le même (activité, jour), on garde la valeur max.
    String hpKey(HabitProgress h) => '${h.activityId}_${h.yyyymmdd}';
    final remoteHp = byId(remote.habitProgress, hpKey);
    final mergedHp = byId(local.habitProgress, hpKey);
    for (final entry in remoteHp.entries) {
      final loc = mergedHp[entry.key];
      if (loc == null || entry.value.value > loc.value) {
        mergedHp[entry.key] = entry.value;
      }
    }

    return AppState(
      // Domains : remote gagne + déduplication par nom. deleted:true → retiré du local
      domains: () {
        final remoteMap = byId(remote.domains, (d) => d.id);
        final merged = Map.of(remoteMap);
        for (final d in local.domains) {
          if (!remoteMap.containsKey(d.id) &&
              !remoteMap.values.any((r) => r.name == d.name)) {
            merged[d.id] = d;
          }
        }
        merged.removeWhere((_, d) => d.deleted);
        return merged.values.toList();
      }(),
      // Activities : remote gagne. Si deleted:true → retiré de l'état local (suppression réelle)
      activities: () {
        final remoteMap = byId(remote.activities, (a) => a.id);
        final merged = Map.of(remoteMap);
        for (final a in local.activities) {
          if (!remoteMap.containsKey(a.id)) merged[a.id] = a;
        }
        // Supprimer physiquement les items marqués deleted:true → ils disparaissent du local
        merged.removeWhere((_, a) => a.deleted);
        return merged.values.toList();
      }(),
      sessions:      union(local.sessions,      remote.sessions,      (s) => s.id),
      habitHits:     union(local.habitHits,     remote.habitHits,     (h) => h.id),
      blocks:        union(local.blocks,        remote.blocks,        (b) => b.id),
      earnedBadges:  union(local.earnedBadges,  remote.earnedBadges,  (b) => '${b.id.name}_${b.habitId ?? ""}'),
      habitProgress: mergedHp.values.toList(),
      // Méta scalaire : valeurs locales (préférences de l'appareil actif)
      onboardingDone:        local.onboardingDone,
      // Défis : on garde la progression la plus avancée entre les appareils
      challengesDone:        local.challengesDone > remote.challengesDone
                                 ? local.challengesDone : remote.challengesDone,
      challengeStreak:       (local.lastChallengeYmd ?? '').compareTo(remote.lastChallengeYmd ?? '') >= 0
                                 ? local.challengeStreak : remote.challengeStreak,
      lastChallengeYmd:      (local.lastChallengeYmd ?? '').compareTo(remote.lastChallengeYmd ?? '') >= 0
                                 ? local.lastChallengeYmd : remote.lastChallengeYmd,
      weeklyScoreTarget:     local.weeklyScoreTarget,
      // Or : on garde le côté le plus avancé (goldLifetime monotone le plus élevé).
      gold:                  local.goldLifetime >= remote.goldLifetime ? local.gold : remote.gold,
      goldLifetime:          local.goldLifetime >= remote.goldLifetime ? local.goldLifetime : remote.goldLifetime,
      goldLastProcessedDay:  local.goldLifetime >= remote.goldLifetime ? local.goldLastProcessedDay : remote.goldLastProcessedDay,
      goldInventory:         local.goldLifetime >= remote.goldLifetime ? local.goldInventory : remote.goldInventory,
      goldGelDays:           local.goldLifetime >= remote.goldLifetime ? local.goldGelDays : remote.goldGelDays,
      notifHour:             local.notifHour,
      notifMinute:           local.notifMinute,
      notifEnabled:          local.notifEnabled,
      reviewNotifHour:       local.reviewNotifHour,
      reviewNotifMinute:     local.reviewNotifMinute,
      reviewNotifEnabled:    local.reviewNotifEnabled,
      // État éphémère local — non synchronisé Firestore
      todayItems:            local.todayItems,
      focusTodayIds:         local.focusTodayIds,
      snoozedUntil:          local.snoozedUntil,
    );
  }

  // ── Suppression de compte ───────────────────────────────────────────────────

  Future<void> deleteAccount() async {
    // 1) Supprime toutes les données Firestore — toujours, même pour les anonymes
    if (uid != null) {
      for (final col in [
        'domains', 'activities', 'sessions', 'habitProgress',
        'habitHits', 'dayPlan', 'goals', 'blocks', 'badges',
        'projects', 'strategic_objectives', 'documents', 'api_tokens',
        'captures', 'assistant_messages',
      ]) {
        try {
          final docs = await _col(col).get();
          if (docs.docs.isEmpty) continue;
          final batch = _db.batch();
          for (final d in docs.docs) batch.delete(d.reference);
          await batch.commit();
        } catch (_) {}
      }
      try { await _col('orion_subscription').doc('main').delete(); } catch (_) {}
      try { await _meta().delete(); } catch (_) {}
    }
    // 2) Supprime le compte Firebase Auth — séparé pour ne pas bloquer si ça échoue
    try {
      await _auth.currentUser?.delete();
    } catch (_) {
      // requires-recent-login ou autre erreur Auth : on continue quand même
      // (les données Firestore sont déjà supprimées)
    }
  }

  Map<String, dynamic> _encodeMeta(AppState st) => {
        'onboardingDone': st.onboardingDone,
        'challengesDone': st.challengesDone,
        'challengeStreak': st.challengeStreak,
        'lastChallengeYmd': st.lastChallengeYmd,
        'ganttActionsByDay': st.ganttActionsByDay,
        'challengeWinsByDay': st.challengeWinsByDay,
        // NB : l'or (gold/goldLifetime/…) est AUTORITATIF en Firestore et écrit
        // uniquement par transaction (applyGoldBatch) → jamais via ce miroir, pour
        // ne pas clobberer un coût appliqué côté web. (meta est écrit en merge.)
        'weeklyScoreTarget': st.weeklyScoreTarget,
        'notifHour': st.notifHour,
        'notifMinute': st.notifMinute,
        'notifEnabled': st.notifEnabled,
        'reviewNotifHour': st.reviewNotifHour,
        'reviewNotifMinute': st.reviewNotifMinute,
        'reviewNotifEnabled': st.reviewNotifEnabled,
        'lastSync': FieldValue.serverTimestamp(),
      };

  // ── Domains ─────────────────────────────────────────────────────────────────

  Future<List<Domain>> fetchDomains() async {
    if (uid == null) return [];
    try {
      final snap = await _col('domains').get();
      return snap.docs
          .map((d) => Domain.from(d.data() as Map))
          .where((d) => !d.deleted)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Projects ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchDocuments({String? projectId, String? taskId}) async {
    if (uid == null) return [];
    try {
      final snap = await _col('documents')
          .orderBy('createdAt', descending: true)
          .get();
      var docs = snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
      if (projectId != null) docs = docs.where((d) => d['projectId'] == projectId).toList();
      if (taskId != null) docs = docs.where((d) => d['taskId'] == taskId).toList();
      return docs;
    } catch (_) { return []; }
  }

  Future<void> saveDocument(Map<String, dynamic> doc) async {
    if (uid == null) return;
    await _col('documents').doc(doc['id'] as String).set(doc);
  }

  Future<void> deleteDocument(String docId) async {
    if (uid == null) return;
    await _col('documents').doc(docId).delete();
  }

  Future<List<Project>> fetchProjects() async {
    if (uid == null) return [];
    final snap = await _col('projects').get();
    return snap.docs.map((d) => Project.from(d.data() as Map)).toList();
  }

  Stream<List<Project>> streamProjects() {
    if (uid == null) return const Stream.empty();
    return _col('projects').snapshots().map(
      (snap) => snap.docs.map((d) => Project.from(d.data() as Map)).toList(),
    );
  }

  Stream<List<Domain>> streamDomains() {
    if (uid == null) return const Stream.empty();
    return _col('domains').snapshots().map((snap) => snap.docs
        .map((d) => Domain.from(d.data() as Map))
        .where((d) => !d.deleted)
        .toList());
  }

  Future<void> saveActivity(Activity activity) async {
    if (uid == null) return;
    await _col('activities').doc(activity.id).set(activity.toJson());
  }

  Future<void> saveDomain(Domain domain) async {
    if (uid == null) return;
    await _col('domains').doc(domain.id).set(domain.toJson());
  }

  Future<void> deleteSession(String sessionId) async {
    if (uid == null) return;
    await _col('sessions').doc(sessionId).delete();
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

  /// Bascule le todayFlag d'une tâche Gantt sans recharger tout le projet.
  Future<void> toggleTaskTodayFlag(
      String projectId, String taskId, bool value) async {
    if (uid == null) return;
    final snap = await _col('projects').doc(projectId).get();
    if (!snap.exists) return;
    final project = Project.from(snap.data() as Map);
    final tasks = project.tasks.map((t) {
      if (t.id == taskId) t.todayFlag = value;
      return t;
    }).toList();
    await _col('projects').doc(projectId).update({
      'tasks': tasks.map((t) => t.toJson()).toList(),
    });
  }

  /// Bascule le todayFlag d'une activité (routine).
  Future<void> toggleActivityTodayFlag(String activityId, bool value) async {
    if (uid == null) return;
    await _col('activities').doc(activityId).update({
      'todayFlag': value,
    });
  }

  // ── Opérations structurelles (hiérarchie & déplacements) ────────────────────
  // Manipulation directe : déplacer/promouvoir des tâches et actions entre
  // projets. Réutilisent saveProjectTasks/saveProject pour rester dans le pattern
  // local-first + merge par ID de FirestoreSync.

  Future<Project?> _loadProject(String projectId) async {
    if (uid == null) return null;
    final snap = await _col('projects').doc(projectId).get();
    if (!snap.exists) return null;
    return Project.from(snap.data() as Map);
  }

  /// (Dé)rattache un projet à un parent (null = projet racine).
  Future<void> setProjectParent(String projectId, String? parentId) async {
    if (uid == null) return;
    if (parentId == projectId) return; // un projet ne peut être son propre parent
    await _col('projects').doc(projectId).update({'parentProjectId': parentId});
  }

  /// Déplace une tâche d'un projet vers un autre (retire de la source, ajoute à
  /// la cible). La tâche perd son phaseId (les phases sont propres au projet).
  Future<void> moveTaskToProject(
      String fromProjectId, String toProjectId, String taskId) async {
    if (uid == null || fromProjectId == toProjectId) return;
    final from = await _loadProject(fromProjectId);
    final to = await _loadProject(toProjectId);
    if (from == null || to == null) return;
    final idx = from.tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final task = from.tasks.removeAt(idx);
    task.phaseId = null;
    to.tasks.add(task);
    await saveProjectTasks(fromProjectId, from.tasks);
    await saveProjectTasks(toProjectId, to.tasks);
  }

  /// Déplace une action d'une tâche vers une autre (même projet ou non).
  Future<void> moveActionToTask({
    required String fromProjectId,
    required String fromTaskId,
    required String toProjectId,
    required String toTaskId,
    required String actionId,
  }) async {
    if (uid == null) return;
    final from = await _loadProject(fromProjectId);
    final to = fromProjectId == toProjectId ? from : await _loadProject(toProjectId);
    if (from == null || to == null) return;
    final fromTask = from.tasks.firstWhereOrNull((t) => t.id == fromTaskId);
    final toTask = to.tasks.firstWhereOrNull((t) => t.id == toTaskId);
    if (fromTask == null || toTask == null) return;
    final idx = fromTask.actions.indexWhere((a) => a.id == actionId);
    if (idx < 0) return;
    final action = fromTask.actions.removeAt(idx);
    toTask.actions.add(action);
    if (fromProjectId == toProjectId) {
      await saveProjectTasks(fromProjectId, from.tasks);
    } else {
      await saveProjectTasks(fromProjectId, from.tasks);
      await saveProjectTasks(toProjectId, to.tasks);
    }
  }

  /// Promeut une action en sous-projet enfant du projet courant. L'action est
  /// retirée de sa tâche et devient le titre d'un nouveau projet (source "user").
  /// Retourne le projet créé.
  Future<Project?> promoteActionToSubproject({
    required String parentProjectId,
    required String taskId,
    required String actionId,
  }) async {
    if (uid == null) return null;
    final parent = await _loadProject(parentProjectId);
    if (parent == null) return null;
    final task = parent.tasks.firstWhereOrNull((t) => t.id == taskId);
    if (task == null) return null;
    final idx = task.actions.indexWhere((a) => a.id == actionId);
    if (idx < 0) return null;
    final action = task.actions.removeAt(idx);
    final now = DateTime.now();
    final child = Project(
      title: action.title,
      domainId: parent.domainId,
      parentProjectId: parentProjectId,
      startDate: now,
      createdBy: uid!,
      source: 'user',
    );
    await saveProject(child);
    await saveProjectTasks(parentProjectId, parent.tasks);
    return child;
  }

  // ── Propositions ORION (« À valider ») ──────────────────────────────────────
  // ORION autonome propose ; l'utilisateur dispose. L'acceptation applique la
  // mutation côté client via les helpers ci-dessus (déterministe, sans LLM).

  Stream<List<OrionProposal>> streamProposals() {
    if (uid == null) return const Stream.empty();
    return _col('orion_proposals')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => OrionProposal.from(d.data() as Map))
            .toList()
          ..sort((a, b) => (a.createdAt ?? DateTime(2000))
              .compareTo(b.createdAt ?? DateTime(2000))));
  }

  Future<void> _setProposalStatus(String id, String status) async {
    if (uid == null) return;
    await _col('orion_proposals').doc(id).update({'status': status});
  }

  /// Refuse une proposition et trace l'idée source dans l'historique inbox.
  Future<void> rejectProposal(OrionProposal p) async {
    if (uid == null) return;
    await _setProposalStatus(p.id, 'rejected');
    final cid = p.sourceCaptureId;
    if (cid != null) {
      await _col('captures').doc(cid).set({
        'status': 'processed',
        'orionNote': 'Proposition refusée : ${p.title}',
        'processedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    }
  }

  /// Accepte une proposition : applique la mutation puis consomme l'idée source.
  /// `overrides` permet la redirection (ex: changer projectId/parentProjectId) ;
  /// `kindOverride` permet de changer la nature (ex: « nouveau projet » → plutôt
  /// rattacher l'idée comme tâche d'un projet existant).
  Future<void> acceptProposal(OrionProposal p,
      {Map<String, dynamic>? overrides, String? kindOverride}) async {
    if (uid == null) return;
    final payload = {...p.payload, ...?overrides};
    final kind = kindOverride ?? p.kind;

    // Texte de l'idée source → provenance « origine » des projets (effet wow).
    ProjectOriginIdea? origin;
    final cid = p.sourceCaptureId;
    if (cid != null) {
      final snap = await _col('captures').doc(cid).get();
      if (snap.exists) {
        final c = CaptureItem.from(snap.data() as Map);
        origin = ProjectOriginIdea(
            text: c.text,
            date: c.createdAt.toIso8601String().substring(0, 10));
      }
    }

    switch (kind) {
      case 'new_project':
        await saveProject(Project(
          title: (payload['projectTitle'] ?? p.title).toString(),
          description: payload['description']?.toString(),
          domainId: payload['domainId']?.toString(),
          startDate: DateTime.now(),
          createdBy: uid!,
          source: 'orion',
          originIdeas: origin != null ? [origin] : [],
        ));
        break;
      case 'create_subproject':
        await saveProject(Project(
          title: (payload['projectTitle'] ?? p.title).toString(),
          domainId: payload['domainId']?.toString(),
          parentProjectId: payload['parentProjectId']?.toString(),
          startDate: DateTime.now(),
          createdBy: uid!,
          source: 'orion',
          originIdeas: origin != null ? [origin] : [],
        ));
        break;
      case 'attach_idea_as_task':
        final projectId = payload['projectId']?.toString();
        if (projectId != null) {
          final target = await _loadProject(projectId);
          if (target != null) {
            target.tasks.add(ProjectTask(
              title: (payload['taskTitle'] ?? p.title).toString(),
              description: payload['description']?.toString(),
              startDate: DateTime.now(),
            ));
            await saveProjectTasks(projectId, target.tasks);
          }
        }
        break;
      case 'archive_project':
        final projectId = payload['projectId']?.toString();
        if (projectId != null) {
          final target = await _loadProject(projectId);
          if (target != null) {
            target.status = 'archived';
            await saveProject(target);
          }
        }
        break;
    }

    await _setProposalStatus(p.id, 'accepted');
    // L'idée source est devenue un objet réel → on la retire de l'inbox.
    if (cid != null) {
      await _col('captures').doc(cid).delete();
    }
  }

  /// Déclenche une tâche déterministe ORION côté backend (ex: 'weekly_review',
  /// qui propose d'archiver les projets en sommeil dans la file « À valider »).
  Future<bool> triggerOrionTask(String taskId) async {
    if (uid == null) return false;
    final token = (await ensureOnboardingToken()).rawToken;
    if (token == null || token.isEmpty) return false;
    try {
      final resp = await http.post(
        Uri.parse('https://orionwebhook-dzos75b65q-uc.a.run.app'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uid': uid, 'token': token, 'taskId': taskId}),
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Économie d'Or — écriture AUTORITATIVE (transactions, web + mobile) ───────

  /// Lit l'état d'or autoritatif depuis Firestore (`data/meta`).
  Future<Map<String, dynamic>> fetchGold() async {
    if (uid == null) return {};
    final snap = await _meta().get();
    final d = snap.data() as Map<String, dynamic>? ?? {};
    return {
      'gold': (d['gold'] as num?)?.toInt() ?? 0,
      'goldLifetime': (d['goldLifetime'] as num?)?.toInt() ?? 0,
      'goldLastProcessedDay': d['goldLastProcessedDay'] as String?,
      'goldGelDays': (d['goldGelDays'] as List?)?.cast<String>() ?? <String>[],
      'goldInventory': (d['goldInventory'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
          <String, int>{},
    };
  }

  /// Applique une liste d'événements d'or en UNE transaction : solde clampé à 0,
  /// lifetime monotone (gains seuls), curseur optionnel, et écrit le ledger.
  /// Source de vérité unique partagée par le web et le mobile.
  Future<Map<String, int>> applyGoldBatch(
    List<GoldLedgerEntry> entries, {
    String? newCursor,
    Map<String, dynamic>? extraMeta,
  }) async {
    if (uid == null || (entries.isEmpty && newCursor == null && extraMeta == null)) {
      return {'gold': 0, 'goldLifetime': 0};
    }
    final metaRef = _meta();
    return _db.runTransaction((tx) async {
      final snap = await tx.get(metaRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      var gold = (data['gold'] as num?)?.toInt() ?? 0;
      var lifetime = (data['goldLifetime'] as num?)?.toInt() ?? 0;
      for (final e in entries) {
        gold += e.delta;
        if (gold < 0) gold = 0; // plancher pardonnant
        if (e.delta > 0) lifetime += e.delta; // lifetime monotone
      }
      final update = <String, dynamic>{
        'gold': gold,
        'goldLifetime': lifetime,
        if (newCursor != null) 'goldLastProcessedDay': newCursor,
        ...?extraMeta,
      };
      tx.set(metaRef, update, SetOptions(merge: true));
      for (final e in entries) {
        tx.set(_col('gold_ledger').doc(e.id), e.toJson());
      }
      return {'gold': gold, 'goldLifetime': lifetime};
    });
  }

  /// Applique un seul événement d'or (raccourci).
  Future<Map<String, int>> applyGold(GoldLedgerEntry entry) =>
      applyGoldBatch([entry]);

  // ── Boutique (achats / usages, transactionnels) ─────────────────────────────

  /// Achat boutique : débite l'or si solde suffisant, puis ajoute soit un
  /// consommable (`incInventory`), soit un cosmétique (`addCosmetic` + titre actif).
  /// Renvoie true si l'achat a réussi (solde suffisant).
  Future<bool> purchaseGold({
    required int price,
    required String label,
    String? incInventory,
    String? addCosmetic,
    String? setActiveTitle,
  }) async {
    if (uid == null) return false;
    final metaRef = _meta();
    final ledgerId = '${DateTime.now().microsecondsSinceEpoch}';
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(metaRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final gold = (data['gold'] as num?)?.toInt() ?? 0;
      if (gold < price) return false; // achat = il faut pouvoir payer
      final update = <String, dynamic>{'gold': gold - price};
      if (incInventory != null) {
        final inv = (data['goldInventory'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
            <String, int>{};
        inv[incInventory] = (inv[incInventory] ?? 0) + 1;
        update['goldInventory'] = inv;
      }
      if (addCosmetic != null) {
        final owned =
            (data['cosmeticsOwned'] as List?)?.cast<String>().toList() ??
                <String>[];
        if (!owned.contains(addCosmetic)) owned.add(addCosmetic);
        update['cosmeticsOwned'] = owned;
      }
      if (setActiveTitle != null) update['activeTitle'] = setActiveTitle;
      tx.set(metaRef, update, SetOptions(merge: true));
      tx.set(_col('gold_ledger').doc(ledgerId), GoldLedgerEntry(
        id: ledgerId, delta: -price, category: 'spend',
        reasonCode: 'shop', label: label,
      ).toJson());
      return true;
    });
  }

  /// Pose un gel de série sur une routine pour un jour (consomme 1 gel d'inventaire).
  Future<bool> useGel(String activityId, String ymd) async {
    if (uid == null) return false;
    final metaRef = _meta();
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(metaRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final inv = (data['goldInventory'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
          <String, int>{};
      if ((inv['gel'] ?? 0) < 1) return false;
      inv['gel'] = inv['gel']! - 1;
      final gelDays =
          (data['goldGelDays'] as List?)?.cast<String>().toList() ?? <String>[];
      final key = '${activityId}_$ymd';
      if (!gelDays.contains(key)) gelDays.add(key);
      tx.set(metaRef, {'goldInventory': inv, 'goldGelDays': gelDays},
          SetOptions(merge: true));
      return true;
    });
  }

  /// Consomme 1 joker d'inventaire (renvoie true si dispo) — annule un coût de suppression.
  Future<bool> consumeJoker() async {
    if (uid == null) return false;
    final metaRef = _meta();
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(metaRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final inv = (data['goldInventory'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
          <String, int>{};
      if ((inv['joker'] ?? 0) < 1) return false;
      inv['joker'] = inv['joker']! - 1;
      tx.set(metaRef, {'goldInventory': inv}, SetOptions(merge: true));
      return true;
    });
  }

  /// Historique d'or, plus récent d'abord (pour la sheet). Limité pour rester léger.
  Stream<List<GoldLedgerEntry>> streamGoldLedger({int limit = 100}) {
    if (uid == null) return const Stream.empty();
    return _col('gold_ledger')
        .orderBy('ts', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => GoldLedgerEntry.from(d.data() as Map)).toList());
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

  static String _rawTokenPrefsKey(String tokenId) => 'api_token_raw_$tokenId';

  Future<List<ApiToken>> fetchApiTokens() async {
    if (uid == null) return [];
    try {
      final snap = await _col('api_tokens').get();
      final prefs = await SharedPreferences.getInstance();
      return snap.docs.map((d) {
        final token = ApiToken.from(d.data() as Map);
        token.rawToken = prefs.getString(_rawTokenPrefsKey(token.id));
        return token;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Crée un token, le persiste et le retourne (rawToken disponible une seule fois).
  Future<ApiToken> createApiToken(String label) async {
    final rawToken = _generateNonce(32);
    final hash = _sha256(rawToken);
    final token = ApiToken(label: label, tokenHash: hash, rawToken: rawToken);
    await _col('api_tokens').doc(token.id).set(token.toJson());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rawTokenPrefsKey(token.id), rawToken);
    return token;
  }

  Future<void> revokeApiToken(String tokenId) async {
    if (uid == null) return;
    await _col('api_tokens').doc(tokenId).update({'active': false});
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rawTokenPrefsKey(tokenId));
  }

  /// Retourne le premier token actif UTILISABLE (secret brut dispo en local), ou
  /// en crée un silencieusement. Utilisé à l'onboarding et par ORION pour éviter
  /// de demander au user de configurer un token.
  ///
  /// Un token dont seul le hash existe en base mais dont le rawToken n'est pas
  /// dans le SharedPreferences de cet appareil (ex : connexion magic link sur un
  /// nouvel appareil, réinstall) est INUTILISABLE pour signer les appels ORION —
  /// on en régénère donc un frais plutôt que de le réutiliser à vide.
  Future<ApiToken> ensureOnboardingToken() async {
    final tokens = await fetchApiTokens();
    final usable = tokens
        .where((t) => t.active && (t.rawToken?.isNotEmpty ?? false))
        .toList();
    if (usable.isNotEmpty) return usable.first;
    return createApiToken('ORION');
  }

  /// Retourne (ou crée) le token dédié aux widgets iOS.
  /// Stocke automatiquement token + uid dans l'App Group UserDefaults via WidgetService.
  Future<ApiToken> ensureWidgetToken() async {
    final tokens = await fetchApiTokens();
    // Réutilisable seulement si le secret brut est présent en local (sinon le
    // widget recevrait un token vide). Voir ensureOnboardingToken.
    final existing = tokens
        .where((t) => t.active && t.label == 'Widget iOS' && (t.rawToken?.isNotEmpty ?? false))
        .firstOrNull;
    if (existing != null) return existing;
    return createApiToken('Widget iOS');
  }

  // ── Debug helpers ────────────────────────────────────────────────────────────

  /// Retourne TOUS les domaines y compris ceux avec deleted:true (usage debug).
  Future<List<Domain>> fetchAllDomains() async {
    if (uid == null) return [];
    try {
      final snap = await _col('domains').get();
      return snap.docs.map((d) => Domain.from(d.data() as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Activity>> fetchActivities() async {
    if (uid == null) return [];
    try {
      final snap = await _col('activities').get();
      return snap.docs.map((d) => Activity.from(d.data() as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> hardDelete(String collection, String docId) async {
    if (uid == null) return;
    await _col(collection).doc(docId).delete();
  }

  Future<void> restoreDeleted(String collection, String docId) async {
    if (uid == null) return;
    await _col(collection).doc(docId).update({'deleted': false});
  }

  Future<void> archiveItem(String collection, String docId) async {
    if (uid == null) return;
    await _col(collection).doc(docId).update({'deleted': true});
  }

  // ── Captures (idées rapides) ──────────────────────────────────────────────

  Future<void> saveOrionQueueItem({
    required String instruction,
    String? context,
  }) async {
    if (uid == null) return;
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await _col('orion_queue').doc(id).set({
      'id': id,
      'instruction': instruction,
      'context': context,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<CaptureItem>> streamCaptures() {
    if (uid == null) return const Stream.empty();
    return _col('captures')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => CaptureItem.from(d.data() as Map)).toList());
  }

  Future<void> saveCaptureItem(CaptureItem item) async {
    if (uid == null) return;
    await _col('captures').doc(item.id).set(item.toJson());
  }

  Future<void> updateCaptureItem(String id, Map<String, dynamic> data) async {
    if (uid == null) return;
    await _col('captures').doc(id).update(data);
  }

  Future<void> deleteCaptureItem(String id) async {
    if (uid == null) return;
    await _col('captures').doc(id).delete();
  }

  // ── Programme horaire journalier ────────────────────────────────────────────

  /// Stream temps réel du programme du jour (null si aucun programme généré).
  Stream<DailySchedule?> streamDailySchedule(String date) {
    if (uid == null) return const Stream.empty();
    return _db.doc('users/$uid/daily_schedules/$date').snapshots().map(
          (snap) => snap.exists
              ? DailySchedule.from(snap.data() as Map)
              : null,
        );
  }

  Future<void> saveDailySchedule(DailySchedule schedule) async {
    if (uid == null) return;
    await _db
        .doc('users/$uid/daily_schedules/${schedule.date}')
        .set(schedule.toJson());
  }

  /// Met à jour le status d'un bloc (pending → done | skipped) sans recharger le doc entier.
  Future<void> updateBlockStatus(
      String date, String blockId, String status) async {
    if (uid == null) return;
    final ref = _db.doc('users/$uid/daily_schedules/$date');
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data() as Map;
    final blocks = (data['blocks'] as List?)
            ?.map((b) => Map<String, dynamic>.from(b as Map))
            .toList() ??
        [];
    for (final b in blocks) {
      if (b['id'] == blockId) {
        b['status'] = status;
        if (status == 'done') b['doneAt'] = DateTime.now().toIso8601String();
        break;
      }
    }
    await ref.update({'blocks': blocks});
  }

  /// Met à jour la liste des rappels (dates ISO) d'un bloc (read-modify-write).
  Future<void> setChallengeReminders(
      String date, String blockId, List<String> reminders) async {
    if (uid == null) return;
    final ref = _db.doc('users/$uid/daily_schedules/$date');
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data() as Map;
    final blocks = (data['blocks'] as List?)
            ?.map((b) => Map<String, dynamic>.from(b as Map))
            .toList() ??
        [];
    for (final b in blocks) {
      if (b['id'] == blockId) {
        b['reminders'] = reminders;
        break;
      }
    }
    await ref.update({'blocks': blocks});
  }

  /// Ajoute un bloc au programme d'un jour (read-modify-write). Crée le doc
  /// `daily_schedules/{date}` s'il n'existe pas encore. Utilisé pour poser un
  /// défi programmé dans le plan du jour cible.
  Future<void> addScheduleBlock(String date, ScheduleBlock block) async {
    if (uid == null) return;
    final ref = _db.doc('users/$uid/daily_schedules/$date');
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set(DailySchedule(
        date: date,
        generatedBy: 'user',
        blocks: [block],
      ).toJson());
      return;
    }
    final data = snap.data() as Map;
    final blocks = (data['blocks'] as List?)
            ?.map((b) => Map<String, dynamic>.from(b as Map))
            .toList() ??
        [];
    blocks.add(block.toJson());
    await ref.update({'blocks': blocks});
  }

  /// Renvoie les `activityId` ayant un défi (challenge) encore en attente,
  /// programmé aujourd'hui ou dans le futur — pour que « Challenge me » ne
  /// re-propose pas une activité déjà planifiée. Doc id = date (YYYY-MM-DD),
  /// comparaison lexicographique = chronologique.
  Future<Set<String>> fetchScheduledChallengeActivityIds() async {
    if (uid == null) return {};
    final now = DateTime.now();
    final todayYmd =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final ids = <String>{};
    try {
      final snap = await _col('daily_schedules')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: todayYmd)
          .get();
      for (final doc in snap.docs) {
        final sched = DailySchedule.from(doc.data() as Map);
        for (final b in sched.blocks) {
          if (b.challenge &&
              b.status == 'pending' &&
              (b.activityId ?? '').isNotEmpty) {
            ids.add(b.activityId!);
          }
        }
      }
    } catch (_) {
      // pas de programme / index manquant → aucune exclusion
    }
    return ids;
  }

  /// Liste les défis programmés encore en attente (aujourd'hui/futur), triés par
  /// date puis heure. Pour l'écran « défis en cours » (bouton ⚡ de l'app bar).
  Future<List<({String date, ScheduleBlock block})>>
      fetchScheduledChallenges() async {
    if (uid == null) return [];
    final now = DateTime.now();
    final todayYmd =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final out = <({String date, ScheduleBlock block})>[];
    try {
      final snap = await _col('daily_schedules')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: todayYmd)
          .get();
      for (final doc in snap.docs) {
        final sched = DailySchedule.from(doc.data() as Map);
        for (final b in sched.blocks) {
          if (b.challenge && b.status == 'pending') {
            out.add((date: sched.date, block: b));
          }
        }
      }
    } catch (_) {
      // index manquant / aucun programme → liste vide
    }
    out.sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : a.block.startTime.compareTo(b.block.startTime);
    });
    return out;
  }

  // ── Social (Phase 1) : pseudo + classement XP ───────────────────────────────
  static const _claimPseudoUrl =
      'https://claimpseudo-dzos75b65q-uc.a.run.app';

  /// Réserve/définit un pseudo + opt-in classement. Retourne null si OK, sinon
  /// un message d'erreur (pseudo pris, invalide…).
  Future<String?> claimPseudo(String pseudo, bool optedIn) async {
    final user = _auth.currentUser;
    if (user == null) return 'Non connecté';
    try {
      final idToken = await user.getIdToken();
      final res = await http.post(
        Uri.parse(_claimPseudoUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'pseudo': pseudo, 'optedIn': optedIn}),
      );
      if (res.statusCode == 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['error'] as String?) ?? 'Erreur (${res.statusCode})';
    } catch (e) {
      return 'Erreur réseau';
    }
  }

  /// Profil public de l'utilisateur courant (pseudo + opt-in), ou null.
  Future<Map<String, dynamic>?> fetchMyProfile() async {
    if (uid == null) return null;
    try {
      final snap = await _db.doc('profiles/$uid').get();
      return snap.exists ? snap.data() as Map<String, dynamic> : null;
    } catch (_) {
      return null;
    }
  }

  /// Entrée de classement de l'utilisateur courant (son propre rang/XP).
  Future<Map<String, dynamic>?> fetchMyLeaderboardEntry() async {
    if (uid == null) return null;
    try {
      final snap = await _db.doc('leaderboard_entries/$uid').get();
      return snap.exists ? snap.data() as Map<String, dynamic> : null;
    } catch (_) {
      return null;
    }
  }

  /// Top 50 du classement pour une période : 'xpTotal' | 'xpWeek' | 'xpMonth'.
  /// Retourne [{uid, pseudo, xp, level}], trié décroissant.
  Future<List<Map<String, dynamic>>> fetchLeaderboard(String field) async {
    try {
      final snap = await _db
          .collection('leaderboard_entries')
          .where('optedIn', isEqualTo: true)
          .orderBy(field, descending: true)
          .limit(50)
          .get();
      return snap.docs.map((d) {
        final m = d.data();
        return {
          'uid': d.id,
          'pseudo': m['pseudo'] ?? '—',
          'xp': (m[field] as num?)?.toInt() ?? 0,
          'level': (m['level'] as num?)?.toInt() ?? 1,
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Social Phase 2 : bibliothèque de challenges ─────────────────────────────
  static const _submitChallengeUrl =
      'https://submitchallenge-dzos75b65q-uc.a.run.app';
  static const _subscribeChallengeUrl =
      'https://subscribechallenge-dzos75b65q-uc.a.run.app';

  Future<String?> _postAuthed(String url, Map<String, dynamic> body) async {
    final user = _auth.currentUser;
    if (user == null) return 'Non connecté';
    try {
      final idToken = await user.getIdToken();
      final res = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      if (res.statusCode == 200) return null;
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      return (m['error'] as String?) ?? 'Erreur (${res.statusCode})';
    } catch (_) {
      return 'Erreur réseau';
    }
  }

  /// Soumet un challenge à la bibliothèque (modération super-Orion). null = OK.
  Future<String?> submitChallenge(String title, String description) =>
      _postAuthed(_submitChallengeUrl, {'title': title, 'description': description});

  /// (Dé)abonnement à un challenge de la bibliothèque. null = OK.
  Future<String?> subscribeChallenge(String libraryId, bool subscribe) =>
      _postAuthed(_subscribeChallengeUrl,
          {'libraryId': libraryId, 'subscribe': subscribe});

  /// Challenges approuvés de la bibliothèque (triés par popularité côté client).
  Future<List<Map<String, dynamic>>> fetchChallengeLibrary() async {
    try {
      final snap = await _db
          .collection('challenge_library')
          .where('status', isEqualTo: 'approved')
          .limit(100)
          .get();
      final list = snap.docs.map((d) {
        final m = d.data();
        return {
          'id': d.id,
          'title': m['title'] ?? '',
          'description': m['description'] ?? '',
          'category': m['category'] ?? 'autre',
          'durationMin': (m['suggestedDurationMin'] as num?)?.toInt() ?? 15,
          'xp': (m['xpReward'] as num?)?.toInt() ?? 10,
          'pseudo': m['createdByPseudo'] ?? '',
          'subscribers': (m['subscriberCount'] as num?)?.toInt() ?? 0,
        };
      }).toList()
        ..sort((a, b) =>
            (b['subscribers'] as int).compareTo(a['subscribers'] as int));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Ids des challenges auxquels l'utilisateur est abonné.
  Future<Set<String>> fetchMySubscriptions() async {
    if (uid == null) return {};
    try {
      final snap = await _col('challenge_subs').get();
      return snap.docs.map((d) => d.id).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Inscrit l'utilisateur au cron ORION (fire-and-forget).
  /// Appelé au démarrage — permet au backend de l'inclure dans runOrionCycle
  /// même sans token MCP.
  void registerOrionSubscription() {
    if (uid == null) return;
    _col('orion_subscription').doc('main').set(
      {
        'enabled': true,
        'platform': Platform.isIOS ? 'ios' : Platform.isAndroid ? 'android' : 'other',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    ).ignore();
  }

  /// Snapshot productivité du jour → lu par ORION (Cloud Function) pour générer
  /// le « levier du jour » de son brief. Doc singleton, écrit en merge.
  void pushProductivitySnapshot(Map<String, dynamic> snap) {
    if (uid == null) return;
    _db.doc('users/$uid/data/productivity_today').set(
      {...snap, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    ).ignore();
  }
}
