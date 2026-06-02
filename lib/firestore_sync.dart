import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
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
      weeklyScoreTarget:     local.weeklyScoreTarget,
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
}
