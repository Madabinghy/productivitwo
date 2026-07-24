import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:productivitwo_v1/gold_economy.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/battle_sim.dart';
import 'package:productivitwo_v1/territory.dart';
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
  //
  // Push DELTA réel : on garde en mémoire l'empreinte JSON du dernier état
  // poussé (ou lu du remote) par doc, et on n'écrit QUE les docs nouveaux ou
  // modifiés. Avant : chaque save débouncé réécrivait les 8 collections
  // ENTIÈRES (sessions + activités + routines + hits…) → des dizaines de
  // milliers d'écritures Firestore par jour pour de simples coches.
  //
  // Au premier push d'une session (cache vide), la collection distante est lue
  // une fois : elle sert à la réconciliation des hard-deletes ET à amorcer le
  // cache (un doc identique au remote n'est pas réécrit — les lectures coûtent
  // ~10× moins cher que les écritures).

  final Map<String, Map<String, String>> _pushedJson = {};
  final Set<String> _reconciledCollections = {};
  String? _pushedMetaJson;
  String? _pushCacheUid;

  /// Encodage canonique (clés triées récursivement) pour comparer deux
  /// versions d'un doc — l'ordre des clés du remote peut différer du toJson.
  static Object? _canon(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: _canon(v[k])};
    }
    if (v is List) return v.map(_canon).toList();
    if (v is num || v is bool || v is String || v == null) return v;
    return v.toString(); // DateTime, Timestamp… — seule l'égalité compte
  }

  @visibleForTesting
  static String stableJson(Map m) => jsonEncode(_canon(m));

  static String _stableJson(Map m) => stableJson(m);

  void _resetPushCacheIfUserChanged() {
    if (_pushCacheUid == uid) return;
    _pushedJson.clear();
    _reconciledCollections.clear();
    _pushedMetaJson = null;
    _pushedSnapshotJson = null;
    _pushCacheUid = uid;
  }

  /// Push complet forcé (connexion, seed de compte) : invalide le cache delta
  /// puis re-diffe tout contre le remote.
  Future<void> pushAll(AppState st) {
    _pushedJson.clear();
    _reconciledCollections.clear();
    _pushedMetaJson = null;
    return pushDeltas(st);
  }

  Future<void> pushDeltas(AppState st) async {
    if (uid == null) return;
    _resetPushCacheIfUserChanged();
    try {
      await Future.wait([
        _pushCollection(st.domains.map((e) => e.toJson()).toList(), 'domains'),
        _pushCollection(st.activities.map((e) => e.toJson()).toList(), 'activities'),
        _pushCollection(st.sessions.map((e) => e.toJson()).toList(), 'sessions'),
        _pushCollection(st.habitProgress.map((e) => e.toJson()).toList(), 'habitProgress'),
        _pushCollection(st.habitHits.map((e) => e.toJson()).toList(), 'habitHits'),
        _pushCollection(st.redemptions.map((e) => e.toJson()).toList(), 'redemptions'),
        _pushCollection(st.blocks.map((e) => e.toJson()).toList(), 'blocks'),
        _pushCollection(st.earnedBadges.map((e) => e.toJson()).toList(), 'badges'),
        _pushMeta(st),
      ]);
    } catch (_) {}
  }

  /// Le doc meta n'est réécrit que si son contenu a changé. `lastSync`
  /// (serverTimestamp, jamais lu nulle part) est exclu de l'empreinte.
  Future<void> _pushMeta(AppState st) async {
    final metaMap = _encodeMeta(st);
    final probe = Map<String, dynamic>.from(metaMap)..remove('lastSync');
    final json = _stableJson(probe);
    if (json == _pushedMetaJson) return;
    await _meta().set(metaMap, SetOptions(merge: true));
    _pushedMetaJson = json;
  }

  Future<void> _pushCollection(
      List<Map<String, dynamic>> items, String name) async {
    final col = _col(name);
    final cache = _pushedJson.putIfAbsent(name, () => <String, String>{});

    // Premier push de la session : lecture unique du remote pour (1) réconcilier
    // les hard-deletes, (2) amorcer le cache — un doc local identique au remote
    // ne sera pas réécrit. Ensuite, plus aucune lecture : les suppressions
    // passent par le soft-delete (deleted:true), qui est un delta normal.
    final deletes = <DocumentReference>[];
    if (!_reconciledCollections.contains(name)) {
      final existing = await col.get();
      final localIds = items.map((e) => e['id'] as String).toSet();
      for (final doc in existing.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (localIds.contains(doc.id)) {
          if (data != null) cache[doc.id] = _stableJson(data);
        } else if (data?['deleted'] == true) {
          // Item soft-deleted que le local n'a plus : hard-delete. Sinon (créé
          // par MCP pendant que l'app tournait) : laisser, mergé au prochain pull.
          deletes.add(doc.reference);
        }
      }
      _reconciledCollections.add(name);
    }

    // Ne garde que les docs nouveaux ou réellement modifiés.
    final changed = <String, Map<String, dynamic>>{};
    final encoded = <String, String>{};
    for (final item in items) {
      final id = item['id'] as String;
      final json = _stableJson(item);
      if (cache[id] == json) continue;
      changed[id] = item;
      encoded[id] = json;
    }
    if (deletes.isEmpty && changed.isEmpty) return;

    // Batches ≤ 450 opérations (limite Firestore : 500 — l'ancien code plantait
    // silencieusement au-delà). Le cache n'est mis à jour qu'après commit réussi.
    var batch = _db.batch();
    var ops = 0;
    var pendingIds = <String>[];
    Future<void> flush() async {
      if (ops == 0) return;
      await batch.commit();
      for (final id in pendingIds) {
        cache[id] = encoded[id]!;
      }
      pendingIds = <String>[];
      batch = _db.batch();
      ops = 0;
    }

    for (final ref in deletes) {
      batch.delete(ref);
      ops++;
      if (ops >= 450) await flush();
    }
    for (final entry in changed.entries) {
      batch.set(col.doc(entry.key), entry.value);
      pendingIds.add(entry.key);
      ops++;
      if (ops >= 450) await flush();
    }
    await flush();
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
        _col('redemptions').get(),
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
        redemptions: docs(8).map(Redemption.from).toList(),
        onboardingDone: meta['onboardingDone'] ?? false,
        challengesDone: meta['challengesDone'] ?? 0,
        challengeStreak: meta['challengeStreak'] ?? 0,
        lastChallengeYmd: meta['lastChallengeYmd'] as String?,
        ganttActionsByDay: (meta['ganttActionsByDay'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        dailyStakeByDay: (meta['dailyStakeByDay'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        dailyStakeSettledDays:
            (meta['dailyStakeSettledDays'] as List?)?.cast<String>(),
        challengeWinsByDay: (meta['challengeWinsByDay'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        battleShurikensByDay: (meta['battleShurikensByDay'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        gold: (meta['gold'] as num?)?.toInt() ?? 0,
        goldLifetime: (meta['goldLifetime'] as num?)?.toInt() ?? 0,
        goldLastProcessedDay: meta['goldLastProcessedDay'] as String?,
        goldInventory: (meta['goldInventory'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        goldGelDays: (meta['goldGelDays'] as List?)?.cast<String>(),
        goldTaskShieldDays:
            (meta['goldTaskShieldDays'] as List?)?.cast<String>(),
        goldBoostDays: (meta['goldBoostDays'] as List?)?.cast<String>(),
        cosmeticsOwned: (meta['cosmeticsOwned'] as List?)?.cast<String>(),
        activeTitle: meta['activeTitle'] as String?,
        activeAvatar: meta['activeAvatar'] as String?,
        unlockedLevel: (meta['unlockedLevel'] as num?)?.toInt() ?? 0,
        expeditionCleared:
            (meta['expeditionCleared'] as List?)?.cast<String>(),
        bossInvasions:
            (meta['bossInvasions'] as List?)?.cast<String>(),
        expeditionRevealed:
            (meta['expeditionRevealed'] as List?)?.cast<String>(),
        expeditionPos: meta['expeditionPos'] as String?,
        unifiedRevealed:
            (meta['unifiedRevealed'] as List?)?.cast<String>(),
        unifiedPos: meta['unifiedPos'] as String?,
        snoozedUntil: (meta['snoozedUntil'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), v.toString())),
        expeditionPicked:
            (meta['expeditionPicked'] as List?)?.cast<String>(),
        expeditionEntities:
            (meta['expeditionEntities'] as List?)?.cast<String>(),
        expeditionChallenges:
            (meta['expeditionChallenges'] as List?)?.cast<String>(),
        expeditionDonjonLevel:
            (meta['expeditionDonjonLevel'] as num?)?.toInt() ?? 0,
        expeditionGuardianKilledLevel:
            (meta['expeditionGuardianKilledLevel'] as num?)?.toInt() ?? 0,
        weaponsSpent: (meta['weaponsSpent'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        pestKills: (meta['pestKills'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        redRoster: (meta['redRoster'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        craftSpent: (meta['craftSpent'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        releaseTokensUsed: (meta['releaseTokensUsed'] as num?)?.toInt() ?? 0,
        battleMasseEarned: (meta['battleMasseEarned'] as num?)?.toInt() ?? 0,
        battleMasseUsed: (meta['battleMasseUsed'] as num?)?.toInt() ?? 0,
        battleMasseToday: (meta['battleMasseToday'] as num?)?.toInt() ?? 0,
        battleMasseTodayYmd: (meta['battleMasseTodayYmd'] as String?) ?? '',
        deckResetYmd: (meta['deckResetYmd'] as String?) ?? '',
        turretRangeLevel: (meta['turretRangeLevel'] as num?)?.toInt() ?? 0,
        domTurretPos: (meta['domTurretPos'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), v.toString())),
        engagedEnemies: (meta['engagedEnemies'] as List?)?.cast<String>(),
        weaponPickups: (meta['weaponPickups'] as Map?)?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        collection: (meta['collection'] as List?)?.cast<String>(),
        collectionMeta: (meta['collectionMeta'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())),
        lastFreeStepYmd: meta['lastFreeStepYmd'] as String?,
        lastPestDrainAt: meta['lastPestDrainAt'] as String?,
        goldTodayGain: (meta['goldTodayGain'] as num?)?.toInt() ?? 0,
        goldTodayGainYmd: meta['goldTodayGainYmd'] as String?,
        goldEpochYmd: meta['goldEpochYmd'] as String?,
        lastQuestClaimedYmd: meta['lastQuestClaimedYmd'] as String?,
        questStreak: (meta['questStreak'] as num?)?.toInt() ?? 0,
        donjonKeysUsed:
            (meta['donjonKeysUsed'] as List?)?.map((e) => e.toString()).toList(),
        donjonKeysYmd: meta['donjonKeysYmd'] as String?,
        weeklyScoreTarget: meta['weeklyScoreTarget'] ?? 80,
        notifHour: meta['notifHour'] ?? 9,
        notifMinute: meta['notifMinute'] ?? 0,
        notifEnabled: meta['notifEnabled'] ?? true,
        reviewNotifHour: meta['reviewNotifHour'] ?? 21,
        reviewNotifMinute: meta['reviewNotifMinute'] ?? 0,
        reviewNotifEnabled: meta['reviewNotifEnabled'] ?? true,
        habitChecklistByHabitId: (meta['habitChecklistByHabitId'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(),
                (v as List?)?.map((e) => e.toString()).toList() ?? <String>[])),
        habitChecklistDone: (meta['habitChecklistDone'] as Map?)?.map(
            (k, v) => MapEntry(
                k.toString(),
                (v as Map?)?.map((pk, pv) => MapEntry(pk.toString(),
                        (pv as List?)?.map((e) => (e as num).toInt()).toList() ??
                            <int>[])) ??
                    <String, List<int>>{})),
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
      redemptions:   union(local.redemptions,   remote.redemptions,   (r) => r.id),
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
      goldTaskShieldDays:    local.goldLifetime >= remote.goldLifetime ? local.goldTaskShieldDays : remote.goldTaskShieldDays,
      goldBoostDays:         local.goldLifetime >= remote.goldLifetime ? local.goldBoostDays : remote.goldBoostDays,
      unlockedLevel:         local.unlockedLevel >= remote.unlockedLevel ? local.unlockedLevel : remote.unlockedLevel,
      expeditionCleared:     local.goldLifetime >= remote.goldLifetime ? local.expeditionCleared : remote.expeditionCleared,
      bossInvasions:         local.goldLifetime >= remote.goldLifetime ? local.bossInvasions : remote.bossInvasions,
      expeditionRevealed:    local.goldLifetime >= remote.goldLifetime ? local.expeditionRevealed : remote.expeditionRevealed,
      expeditionPos:         local.goldLifetime >= remote.goldLifetime ? local.expeditionPos : remote.expeditionPos,
      unifiedRevealed:       local.goldLifetime >= remote.goldLifetime ? local.unifiedRevealed : remote.unifiedRevealed,
      unifiedPos:            local.goldLifetime >= remote.goldLifetime ? local.unifiedPos : remote.unifiedPos,
      expeditionPicked:      local.goldLifetime >= remote.goldLifetime ? local.expeditionPicked : remote.expeditionPicked,
      expeditionEntities:    local.goldLifetime >= remote.goldLifetime ? local.expeditionEntities : remote.expeditionEntities,
      // Défis : écrits par Orion (serveur) → on garde la version distante dès qu'elle existe.
      expeditionChallenges:  remote.expeditionChallenges.isNotEmpty ? remote.expeditionChallenges : local.expeditionChallenges,
      expeditionDonjonLevel: local.expeditionDonjonLevel >= remote.expeditionDonjonLevel ? local.expeditionDonjonLevel : remote.expeditionDonjonLevel,
      expeditionGuardianKilledLevel: local.expeditionGuardianKilledLevel >= remote.expeditionGuardianKilledLevel ? local.expeditionGuardianKilledLevel : remote.expeditionGuardianKilledLevel,
      // Compteurs monotones (dépenses d'armes / captures) → on garde le plus avancé.
      weaponsSpent:          _mapSum(local.weaponsSpent) >= _mapSum(remote.weaponsSpent) ? local.weaponsSpent : remote.weaponsSpent,
      pestKills:             _mapSum(local.pestKills) >= _mapSum(remote.pestKills) ? local.pestKills : remote.pestKills,
      // Arsenal d'invasion : craftSpent monotone (somme) fait autorité ; le roster
      // (qui peut baisser à l'upgrade/déploiement) suit le même côté que craftSpent.
      craftSpent:            _mapSum(local.craftSpent) >= _mapSum(remote.craftSpent) ? local.craftSpent : remote.craftSpent,
      redRoster:             _mapSum(local.craftSpent) >= _mapSum(remote.craftSpent) ? local.redRoster : remote.redRoster,
      // Dégâts boss au deck : monotone (somme) fait autorité, comme craftSpent.
      deckDamage:            _mapSum(local.deckDamage) >= _mapSum(remote.deckDamage) ? local.deckDamage : remote.deckDamage,
      releaseTokensUsed:     local.releaseTokensUsed >= remote.releaseTokensUsed ? local.releaseTokensUsed : remote.releaseTokensUsed,
      battleMasseEarned:     local.battleMasseEarned >= remote.battleMasseEarned ? local.battleMasseEarned : remote.battleMasseEarned,
      battleMasseUsed:       local.battleMasseUsed >= remote.battleMasseUsed ? local.battleMasseUsed : remote.battleMasseUsed,
      battleMasseTodayYmd:   local.battleMasseTodayYmd.compareTo(remote.battleMasseTodayYmd) >= 0 ? local.battleMasseTodayYmd : remote.battleMasseTodayYmd,
      battleMasseToday:      local.battleMasseTodayYmd == remote.battleMasseTodayYmd ? (local.battleMasseToday >= remote.battleMasseToday ? local.battleMasseToday : remote.battleMasseToday) : (local.battleMasseTodayYmd.compareTo(remote.battleMasseTodayYmd) > 0 ? local.battleMasseToday : remote.battleMasseToday),
      deckResetYmd:          local.deckResetYmd.compareTo(remote.deckResetYmd) >= 0 ? local.deckResetYmd : remote.deckResetYmd,
      turretRangeLevel:      local.turretRangeLevel >= remote.turretRangeLevel ? local.turretRangeLevel : remote.turretRangeLevel,
      domTurretPos:          local.domTurretPos.length >= remote.domTurretPos.length ? local.domTurretPos : remote.domTurretPos,
      engagedEnemies:        local.goldLifetime >= remote.goldLifetime ? local.engagedEnemies : remote.engagedEnemies,
      weaponPickups:         _mapSum(local.weaponPickups) >= _mapSum(remote.weaponPickups) ? local.weaponPickups : remote.weaponPickups,
      collection:            local.collection.length >= remote.collection.length ? local.collection : remote.collection,
      collectionMeta:        local.collection.length >= remote.collection.length ? local.collectionMeta : remote.collectionMeta,
      lastFreeStepYmd:       local.goldLifetime >= remote.goldLifetime ? local.lastFreeStepYmd : remote.lastFreeStepYmd,
      lastPestDrainAt:       local.goldLifetime >= remote.goldLifetime ? local.lastPestDrainAt : remote.lastPestDrainAt,
      goldTodayGain:         local.goldLifetime >= remote.goldLifetime ? local.goldTodayGain : remote.goldTodayGain,
      goldTodayGainYmd:      local.goldLifetime >= remote.goldLifetime ? local.goldTodayGainYmd : remote.goldTodayGainYmd,
      dailyStakeByDay:       local.goldLifetime >= remote.goldLifetime ? local.dailyStakeByDay : remote.dailyStakeByDay,
      dailyStakeSettledDays: local.goldLifetime >= remote.goldLifetime ? local.dailyStakeSettledDays : remote.dailyStakeSettledDays,
      goldEpochYmd:          local.goldLifetime >= remote.goldLifetime ? local.goldEpochYmd : remote.goldEpochYmd,
      lastQuestClaimedYmd:   local.goldLifetime >= remote.goldLifetime ? local.lastQuestClaimedYmd : remote.lastQuestClaimedYmd,
      questStreak:           local.goldLifetime >= remote.goldLifetime ? local.questStreak : remote.questStreak,
      donjonKeysUsed:        local.goldLifetime >= remote.goldLifetime ? local.donjonKeysUsed : remote.donjonKeysUsed,
      donjonKeysYmd:         local.goldLifetime >= remote.goldLifetime ? local.donjonKeysYmd : remote.donjonKeysYmd,
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
      // Checklist routines : union pour ne rien perdre entre appareils.
      // Template (habitId -> items) : on garde la liste la plus longue par habitId.
      habitChecklistByHabitId: () {
        final out = <String, List<String>>{};
        for (final k in {
          ...local.habitChecklistByHabitId.keys,
          ...remote.habitChecklistByHabitId.keys
        }) {
          final l = local.habitChecklistByHabitId[k] ?? const <String>[];
          final r = remote.habitChecklistByHabitId[k] ?? const <String>[];
          out[k] = l.length >= r.length ? l : r;
        }
        return out;
      }(),
      // Coches (habitId -> periodKey -> indices) : union des indices par période.
      habitChecklistDone: () {
        final out = <String, Map<String, List<int>>>{};
        for (final hid in {
          ...local.habitChecklistDone.keys,
          ...remote.habitChecklistDone.keys
        }) {
          final lp = local.habitChecklistDone[hid] ?? const <String, List<int>>{};
          final rp = remote.habitChecklistDone[hid] ?? const <String, List<int>>{};
          final periods = <String, List<int>>{};
          for (final pk in {...lp.keys, ...rp.keys}) {
            final s = <int>{...(lp[pk] ?? const []), ...(rp[pk] ?? const [])};
            periods[pk] = s.toList()..sort();
          }
          out[hid] = periods;
        }
        return out;
      }(),
    );
  }

  // ── Suppression de compte ───────────────────────────────────────────────────

  Future<void> deleteAccount() async {
    // 1) Supprime toutes les données Firestore — toujours, même pour les anonymes
    if (uid != null) {
      for (final col in [
        'domains', 'activities', 'sessions', 'habitProgress',
        'habitHits', 'redemptions', 'dayPlan', 'goals', 'blocks', 'badges',
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
        'snoozedUntil': st.snoozedUntil, // activités désactivées jusqu'à une date
        // Checklist des routines : template (habitId -> items) + coches (habitId ->
        // periodKey -> indices). Synchronisé pour que le dashboard web la voie.
        'habitChecklistByHabitId': st.habitChecklistByHabitId,
        'habitChecklistDone': st.habitChecklistDone,
        'challengesDone': st.challengesDone,
        'challengeStreak': st.challengeStreak,
        'lastChallengeYmd': st.lastChallengeYmd,
        'ganttActionsByDay': st.ganttActionsByDay,
        'dailyStakeByDay': st.dailyStakeByDay,
        'dailyStakeSettledDays': st.dailyStakeSettledDays,
        'challengeWinsByDay': st.challengeWinsByDay,
        'battleShurikensByDay': st.battleShurikensByDay,
        // Clés du donjon : état quotidien éphémère, pas or-autoritatif → miroir OK.
        'donjonKeysUsed': st.donjonKeysUsed,
        'donjonKeysYmd': st.donjonKeysYmd,
        'bossInvasions': st.bossInvasions, // boss de donjon en cours (jusqu'à victoire)
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

  Stream<Map<String, dynamic>> streamMetaDoc() {
    if (uid == null) return const Stream.empty();
    return _meta().snapshots().map((s) => s.exists ? s.data() as Map<String, dynamic> : {});
  }

  Stream<List<Project>> streamProjects() {
    if (uid == null) return const Stream.empty();
    return _col('projects').snapshots().map(
      (snap) => snap.docs.map((d) => Project.from(d.data() as Map)).toList(),
    );
  }

  // Temps réel : tous les incréments de routine (HabitHit). Le web s'en sert pour
  // déclencher le voyage de l'avatar dès qu'une routine est validée (y compris
  // depuis le mobile — Firestore synchronise entre appareils).
  Stream<List<HabitHit>> streamHabitHits() {
    if (uid == null) return const Stream.empty();
    return _col('habitHits').snapshots().map(
        (snap) => snap.docs.map((d) => HabitHit.from(d.data() as Map)).toList());
  }

  // Temps réel : toutes les sessions de temps. Le web s'en sert pour détecter un
  // MINUTEUR EN COURS (session ouverte, endAt == null) lancé depuis le mobile et
  // déclencher la cinématique d'assaut sur l'activité correspondante.
  Stream<List<Session>> streamSessions() {
    if (uid == null) return const Stream.empty();
    return _col('sessions').snapshots().map(
        (snap) => snap.docs.map((d) => Session.from(d.data() as Map)).toList());
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

  // ── Artefacts structurés (plan, menu) — sources de blocs ────────────────────

  Stream<List<Artifact>> streamArtifacts() {
    if (uid == null) return const Stream.empty();
    return _col('artifacts').snapshots().map((snap) => snap.docs
        .map((d) => Artifact.from(d.data() as Map))
        .where((a) => !a.deleted)
        .toList());
  }

  Future<Artifact?> fetchArtifact(String id) async {
    if (uid == null) return null;
    final snap = await _col('artifacts').doc(id).get();
    return snap.exists ? Artifact.from(snap.data() as Map) : null;
  }

  Future<List<Artifact>> fetchArtifacts() async {
    if (uid == null) return [];
    try {
      final snap = await _col('artifacts').get();
      return snap.docs
          .map((d) => Artifact.from(d.data() as Map))
          .where((a) => !a.deleted)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveArtifact(Artifact artifact) async {
    if (uid == null) return;
    await _col('artifacts').doc(artifact.id).set(artifact.toJson());
  }

  // ── Bibliothèque de plats (menu déterministe) ───────────────────────────────

  Stream<List<Recipe>> streamRecipes() {
    if (uid == null) return const Stream.empty();
    return _col('recipes').snapshots().map((snap) => snap.docs
        .map((d) => Recipe.from(d.data() as Map))
        .where((r) => !r.deleted)
        .toList());
  }

  Future<List<Recipe>> fetchRecipes() async {
    if (uid == null) return [];
    try {
      final snap = await _col('recipes').get();
      return snap.docs
          .map((d) => Recipe.from(d.data() as Map))
          .where((r) => !r.deleted)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRecipe(Recipe recipe) async {
    if (uid == null) return;
    await _col('recipes').doc(recipe.id).set(recipe.toJson());
  }

  /// Plat MANGÉ → archive : incrémente le compteur du plat (créé s'il
  /// n'existe pas — tout ce qui est cuisiné entre dans la bibliothèque).
  Future<void> recordMealCooked(String title,
      {List<ShoppingItem>? ingredients}) async {
    final t = title.trim();
    if (t.isEmpty || uid == null) return;
    final all = await fetchRecipes();
    Recipe? existing;
    for (final r in all) {
      if (r.title.toLowerCase() == t.toLowerCase()) existing = r;
    }
    final r = existing ?? Recipe(title: t, ingredients: ingredients);
    r.timesCooked += 1;
    r.lastCookedAt = DateTime.now();
    await saveRecipe(r);
  }

  // ── Rapport hebdo ────────────────────────────────────────────────────────

  Future<WeeklyReport?> fetchWeeklyReport(String weekStart) async {
    if (uid == null) return null;
    final snap = await _col('weekly_reports').doc(weekStart).get();
    return snap.exists ? WeeklyReport.from(snap.data() as Map) : null;
  }

  /// Réponse binaire d'un vital « déclaré » (tour 20) — écrite sur le doc du
  /// rapport (clé "domainId|label"), SEUL endroit où ce vital existe.
  Future<void> setWeeklyReportDeclaredAnswer(
      String weekStart, String key, bool value) async {
    if (uid == null) return;
    await _col('weekly_reports')
        .doc(weekStart)
        .set({'declaredAnswers': {key: value}}, SetOptions(merge: true));
  }

  /// Statut de la décision du rapport (pending → applied | declined).
  Future<void> setWeeklyReportDecision(String weekStart, String status) async {
    if (uid == null) return;
    await _col('weekly_reports')
        .doc(weekStart)
        .set({'decisionStatus': status}, SetOptions(merge: true));
  }

  /// Mode de la semaine À VENIR (17b) : 'minimal' (le rush est fini, on repart
  /// au minimum — le plan se recale) ou 'vital' (encore une semaine de rush —
  /// on protège juste le vital). Lu par proposeDayPlan. Trace aussi le choix
  /// sur le rapport (weekModeChosen) — le rapport suivant détecte la 2ᵉ semaine
  /// minimale d'affilée.
  Future<void> setWeekMode(
      String reportWeekStart, String nextWeekStart, String mode) async {
    if (uid == null) return;
    await _meta().set({
      'weekMode': {'weekStart': nextWeekStart, 'mode': mode},
    }, SetOptions(merge: true));
    await _col('weekly_reports')
        .doc(reportWeekStart)
        .set({'weekModeChosen': mode}, SetOptions(merge: true));
  }

  /// Fait « point fait » : posé quand le check-in du soir atteint son verdict
  /// — la carte du soir se tait ensuite.
  Future<void> markDayReviewed(String date) async {
    if (uid == null) return;
    await _col('daily_schedules').doc(date).set(
        {'reviewedAt': DateTime.now().toIso8601String()}, SetOptions(merge: true));
  }

  /// « Où on va » (24d) : ordre des priorités réordonné par le user (⇅),
  /// écrit sur le doc du rapport dont la stratégie est issue — le rapport
  /// suivant repart de l'ordre du user, pas du sien.
  Future<void> setWeeklyReportStrategyOrder(
      String weekStart, List<String> order) async {
    if (uid == null) return;
    await _col('weekly_reports')
        .doc(weekStart)
        .set({'strategyOrder': order}, SetOptions(merge: true));
  }

  /// Fait « rapport lu » : posé à la première ouverture de l'écran du rapport
  /// — le teaser du dimanche soir se tait ensuite, la carte reprend son cours.
  Future<void> markWeeklyReportRead(String weekStart) async {
    if (uid == null) return;
    await _col('weekly_reports').doc(weekStart).set(
        {'readAt': DateTime.now().toIso8601String()}, SetOptions(merge: true));
  }

  /// Heure de lever PRÉVUE (« HH:mm ») — demandée à chaque planification
  /// (les jours ne se ressemblent pas), la dernière valeur sert de
  /// présélection. Contrainte dure de proposeDayPlan (rien avant le lever).
  Future<String?> fetchWakeTime() async {
    if (uid == null) return null;
    try {
      final snap = await _meta().get();
      final v = (snap.data() as Map?)?['wakeTime'];
      return v is String && RegExp(r'^\d{2}:\d{2}$').hasMatch(v) ? v : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setWakeTime(String hm) async {
    if (uid == null) return;
    await _meta().set({'wakeTime': hm}, SetOptions(merge: true));
  }

  /// Fuseau du TÉLÉPHONE = fait (`data/meta.tzOffsetMin`, minutes à ajouter à
  /// l'UTC — ex : -240 en Guadeloupe). Posé à chaque ouverture : le serveur
  /// (agenda Google, proposition, assistant) raisonne dans l'heure VÉCUE de
  /// l'utilisateur, jamais dans un « Europe/Paris » supposé. Suit aussi les
  /// voyages et les changements d'heure.
  Future<void> setDeviceTimezone() async {
    if (uid == null) return;
    final now = DateTime.now();
    await _meta().set({
      'tzOffsetMin': now.timeZoneOffset.inMinutes,
      'tzName': now.timeZoneName,
    }, SetOptions(merge: true));
  }

  Future<void> deleteSession(String sessionId) async {
    if (uid == null) return;
    await _col('sessions').doc(sessionId).delete();
  }

  Future<void> saveSession(Session s) async {
    if (uid == null) return;
    await _col('sessions').doc(s.id).set(s.toJson());
  }

  // Persistance CIBLÉE d'une validation de routine (le web ne pushe pas via onChange).
  Future<void> saveHabitHit(HabitHit h) async {
    if (uid == null) return;
    await _col('habitHits').doc(h.id).set(h.toJson());
  }

  // Reconquête : persiste un crédit (registre découplé du relevé factuel).
  Future<void> saveRedemption(Redemption r) async {
    if (uid == null) return;
    await _col('redemptions').doc(r.id).set(r.toJson());
  }

  // Temps réel : crédits de reconquête (le web s'en sert pour rafraîchir les PV).
  Stream<List<Redemption>> streamRedemptions() {
    if (uid == null) return const Stream.empty();
    return _col('redemptions').snapshots().map((snap) =>
        snap.docs.map((d) => Redemption.from(d.data() as Map)).toList());
  }

  Future<void> saveHabitProgress(HabitProgress hp) async {
    if (uid == null) return;
    await _col('habitProgress').doc(hp.id).set(hp.toJson());
  }

  // Persistance CIBLÉE du snooze (activités désactivées jusqu'à une date).
  Future<void> saveSnoozedUntil(Map<String, String> snoozedUntil) async {
    if (uid == null) return;
    await _meta().set({'snoozedUntil': snoozedUntil}, SetOptions(merge: true));
  }

  // Persistance CIBLÉE de la checklist des routines (le web ne pushe pas via onChange).
  Future<void> saveHabitChecklist(
      Map<String, List<String>> template,
      Map<String, Map<String, List<int>>> done) async {
    if (uid == null) return;
    await _meta().set({
      'habitChecklistByHabitId': template,
      'habitChecklistDone': done,
    }, SetOptions(merge: true));
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

  // ── Déroulés réutilisables (session_templates) ──────────────────────────────
  // Playlist ordonnée d'une séance sur UNE activité-temps — créés/édités dans
  // la fiche activité, lancés par ▶ (chrono + player). Soft-delete (archived).

  Stream<List<SessionTemplate>> streamSessionTemplates() {
    if (uid == null) return const Stream.empty();
    return _col('session_templates').snapshots().map((snap) => snap.docs
        .map((d) => SessionTemplate.from(
            Map<String, dynamic>.from(d.data() as Map)))
        .where((t) => !t.archived)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
  }

  Future<List<SessionTemplate>> fetchSessionTemplates(
      {String? activityId}) async {
    if (uid == null) return [];
    try {
      final snap = await _col('session_templates').get();
      return snap.docs
          .map((d) => SessionTemplate.from(
              Map<String, dynamic>.from(d.data() as Map)))
          .where((t) =>
              !t.archived &&
              (activityId == null || t.activityId == activityId))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } catch (_) {
      return [];
    }
  }

  Future<SessionTemplate?> fetchSessionTemplate(String id) async {
    if (uid == null) return null;
    try {
      final snap = await _col('session_templates').doc(id).get();
      if (!snap.exists) return null;
      final t = SessionTemplate.from(
          Map<String, dynamic>.from(snap.data() as Map));
      return t.archived ? null : t;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSessionTemplate(SessionTemplate t) async {
    if (uid == null) return;
    await _col('session_templates').doc(t.id).set(t.toJson());
  }

  Future<void> archiveSessionTemplate(String id) async {
    if (uid == null) return;
    await _col('session_templates')
        .doc(id)
        .set({'archived': true}, SetOptions(merge: true));
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
        // Applique le plan proposé par ORION : phases + tâches (niveau Gantt,
        // sans sous-actions générées) + la PROCHAINE ACTION GTD contextualisée
        // sur la première tâche. Anciens payloads sans ces champs → projet nu.
        final phases = ((payload['phases'] as List?) ?? const [])
            .map((ph) => ProjectPhase.from(Map<String, dynamic>.from(ph as Map)))
            .toList();
        final tasks = ((payload['tasks'] as List?) ?? const [])
            .map((t) => ProjectTask.from(Map<String, dynamic>.from(t as Map)))
            .toList();
        final fa = payload['firstAction'];
        if (fa is Map && tasks.isNotEmpty) {
          final title = (fa['title'] ?? '').toString().trim();
          if (title.isNotEmpty) {
            tasks.first.actions.add(TaskAction(
              title: title,
              context: fa['context']?.toString(),
            ));
          }
        }
        final start =
            DateTime.tryParse(payload['startDate']?.toString() ?? '') ??
                DateTime.now();
        final end = DateTime.tryParse(payload['endDate']?.toString() ?? '');
        final project = Project(
          title: (payload['projectTitle'] ?? p.title).toString(),
          description: payload['description']?.toString(),
          domainId: payload['domainId']?.toString(),
          strategicObjectiveId: payload['objectiveId']?.toString(),
          startDate: start,
          endDate: end,
          phases: phases,
          tasks: tasks,
          createdBy: uid!,
          source: 'orion',
          status: 'draft',
          originIdeas: origin != null ? [origin] : [],
        );
        await saveProject(project);
        // Back-link objectif → projet (même convention que push_gantt).
        final objectiveId = payload['objectiveId']?.toString();
        if (objectiveId != null && objectiveId.isNotEmpty) {
          try {
            await _col('strategic_objectives').doc(objectiveId).update({
              'projectIds': FieldValue.arrayUnion([project.id]),
            });
          } catch (_) {}
        }
        break;
      case 'create_subproject':
        await saveProject(Project(
          title: (payload['projectTitle'] ?? p.title).toString(),
          domainId: payload['domainId']?.toString(),
          parentProjectId: payload['parentProjectId']?.toString(),
          startDate: DateTime.now(),
          createdBy: uid!,
          source: 'orion',
          status: 'draft',
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
      case 'add_phase':
        final projectId = payload['projectId']?.toString();
        if (projectId != null) {
          final target = await _loadProject(projectId);
          if (target != null) {
            final start =
                DateTime.tryParse(payload['startDate']?.toString() ?? '') ??
                    DateTime.now();
            final end =
                DateTime.tryParse(payload['endDate']?.toString() ?? '') ??
                    start.add(const Duration(days: 14));
            target.phases.add(ProjectPhase(
              label: (payload['phaseLabel'] ?? p.title).toString(),
              color: payload['color']?.toString(),
              startDate: start,
              endDate: end,
            ));
            await saveProject(target);
          }
        }
        break;
      case 'attach_action_to_task':
        final projectId = payload['projectId']?.toString();
        final taskId = payload['taskId']?.toString();
        if (projectId != null && taskId != null) {
          final target = await _loadProject(projectId);
          if (target != null) {
            final idx = target.tasks.indexWhere((t) => t.id == taskId);
            if (idx >= 0) {
              target.tasks[idx].actions.add(TaskAction(
                  title: (payload['actionLabel'] ?? p.title).toString(),
                  context: payload['context']?.toString()));
              await saveProjectTasks(projectId, target.tasks);
            }
          }
        }
        break;
      case 'add_own_action':
        // Action simple sans projet → ownAction d'une activité-temps (chrono
        // ciblé + programmation déjà câblés côté schedule_day).
        final activityId = payload['activityId']?.toString();
        if (activityId != null && activityId.isNotEmpty) {
          await addOwnActionToActivity(
            activityId,
            (payload['actionLabel'] ?? p.title).toString(),
            context: payload['context']?.toString(),
          );
        }
        break;
      case 'restructure_project':
        // Direction C.3 : le diff validé s'applique d'un coup — tâches
        // hors-sujet sautées (jamais supprimées : l'historique reste),
        // reformulations, ajouts enchaînés après la dernière fin.
        final projectId = payload['projectId']?.toString();
        if (projectId != null) {
          final target = await _loadProject(projectId);
          if (target != null) {
            final archiveIds = ((payload['archiveTaskIds'] as List?) ?? [])
                .map((e) => e.toString())
                .toSet();
            for (final t in target.tasks) {
              if (archiveIds.contains(t.id) && t.status != 'done') {
                t.status = 'skipped';
              }
            }
            for (final r in (payload['reword'] as List?) ?? const []) {
              final m = Map<String, dynamic>.from(r as Map);
              final idx = target.tasks
                  .indexWhere((t) => t.id == m['taskId'].toString());
              if (idx >= 0 && target.tasks[idx].status != 'done') {
                target.tasks[idx].title = (m['title'] ?? '').toString();
              }
            }
            var cursor = DateTime.now();
            for (final t in target.tasks) {
              final e = t.endDate;
              if (e != null && e.isAfter(cursor) && t.status == 'pending') {
                cursor = e;
              }
            }
            for (final a in (payload['addTasks'] as List?) ?? const []) {
              final m = Map<String, dynamic>.from(a as Map);
              final dur = ((m['durationDays'] as num?) ?? 3)
                  .toInt()
                  .clamp(1, 15);
              final start = cursor.add(const Duration(days: 1));
              final end = start.add(Duration(days: dur));
              cursor = end;
              target.tasks.add(ProjectTask(
                title: (m['title'] ?? '').toString(),
                startDate: start,
                endDate: end,
                actions: [
                  for (final act in (m['actions'] as List?) ?? const [])
                    TaskAction(title: act.toString()),
                ],
              ));
            }
            await saveProjectTasks(projectId, target.tasks);
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
      'goldTaskShieldDays':
          (d['goldTaskShieldDays'] as List?)?.cast<String>() ?? <String>[],
      'goldBoostDays':
          (d['goldBoostDays'] as List?)?.cast<String>() ?? <String>[],
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
      // LECTURES D'ABORD (règle des transactions Firestore) : meta + chaque
      // entrée de ledger. Une entrée DÉJÀ présente (id déterministe, ex.
      // `gantt_2026-06-11`) ne re-crédite pas → idempotence multi-appareil :
      // deux appareils qui matérialisent le même jour ne doublent pas le solde.
      final snap = await tx.get(metaRef);
      final ledgerRefs =
          entries.map((e) => _col('gold_ledger').doc(e.id)).toList();
      final alreadyApplied = <bool>[];
      for (final ref in ledgerRefs) {
        alreadyApplied.add((await tx.get(ref)).exists);
      }
      final data = snap.data() as Map<String, dynamic>? ?? {};
      var gold = (data['gold'] as num?)?.toInt() ?? 0;
      var lifetime = (data['goldLifetime'] as num?)?.toInt() ?? 0;
      final unlocked = (data['unlockedLevel'] as num?)?.toInt() ?? 1;
      for (var i = 0; i < entries.length; i++) {
        if (alreadyApplied[i]) continue; // déjà au ledger → ne pas re-créditer
        final e = entries[i];
        gold += e.delta;
        if (gold < 0) gold = 0; // plancher pardonnant
        // XP plafonnée au prochain niveau ; le surplus déborde en or seul.
        if (e.delta > 0) {
          lifetime += GoldEconomy.cappedLifetimeAdd(e.delta, lifetime, unlocked);
        }
      }
      final update = <String, dynamic>{
        'gold': gold,
        'goldLifetime': lifetime,
        if (newCursor != null) 'goldLastProcessedDay': newCursor,
        ...?extraMeta,
      };
      tx.set(metaRef, update, SetOptions(merge: true));
      for (var i = 0; i < entries.length; i++) {
        if (alreadyApplied[i]) continue;
        tx.set(ledgerRefs[i], entries[i].toJson());
      }
      return {'gold': gold, 'goldLifetime': lifetime};
    });
  }

  /// Applique un seul événement d'or (raccourci).
  Future<Map<String, int>> applyGold(GoldLedgerEntry entry) =>
      applyGoldBatch([entry]);

  /// Réconcilie EN TEMPS RÉEL le solde pour que le flottant du jour [ymd] vaille
  /// [earned] (gains du jour, dépensables de suite). Le delta est calculé DANS la
  /// transaction depuis le flottant SERVEUR (`goldTodayGain`), pas un flottant
  /// local → juste en multi-appareil : un 2e appareil qui réconcilie le même jour
  /// calcule un delta nul. Gère le changement de jour (retire l'ancien flottant,
  /// banké à part par `materializeGoldUpTo`). Ne touche NI lifetime/XP NI ledger.
  /// Renvoie le solde autoritatif (null si pas d'uid).
  Future<int?> reconcileLiveGoldTx(int earned, String ymd) async {
    if (uid == null) return null;
    final metaRef = _meta();
    return _db.runTransaction((tx) async {
      final data = (await tx.get(metaRef)).data() as Map<String, dynamic>? ?? {};
      var gold = (data['gold'] as num?)?.toInt() ?? 0;
      final serverYmd = data['goldTodayGainYmd'] as String?;
      final serverGain = (data['goldTodayGain'] as num?)?.toInt() ?? 0;
      // Changement de jour : retire le flottant de la veille (sera banké à part).
      if (serverYmd != null && serverYmd != ymd) gold -= serverGain;
      final base = serverYmd == ymd ? serverGain : 0;
      // Garde-fou multi-appareil : si le serveur sait déjà plus que nous (earned
      // calculé sur données incomplètes/périmées), on ne rétrograde pas l'or.
      // Un appareil ne peut qu'apporter de l'info, jamais en retirer.
      if (serverYmd == ymd && earned <= serverGain) return gold;
      gold += earned - base;
      if (gold < 0) gold = 0;
      tx.set(metaRef, {
        'gold': gold,
        'goldTodayGain': earned,
        'goldTodayGainYmd': ymd,
      }, SetOptions(merge: true));
      return gold;
    });
  }

  /// Provenance des collectibles (id → 'ymd|texte'). Stocké dans le meta.
  Future<void> setCollectionMeta(Map<String, String> meta) async {
    if (uid == null) return;
    await _meta().set({'collectionMeta': meta}, SetOptions(merge: true));
  }

  static int _mapSum(Map<String, int> m) =>
      m.values.fold(0, (a, b) => a + b);

  /// Persiste les stats de combat (armes dépensées + captures par type).
  Future<void> setCombatStats(
      Map<String, int> weaponsSpent, Map<String, int> pestKills) async {
    if (uid == null) return;
    await _meta().set(
        {'weaponsSpent': weaponsSpent, 'pestKills': pestKills},
        SetOptions(merge: true));
  }

  /// Persiste le placement des tours de défense de domaine (clé domainId~routineId → x_y).
  Future<void> setDomTurretPos(Map<String, String> pos) async {
    if (uid == null) return;
    await _meta().set({'domTurretPos': pos}, SetOptions(merge: true));
  }

  /// Reset du deck : pose la date de reset + remet à zéro les captures de chasse.
  Future<void> setDeckReset(String ymd, Map<String, int> pestKills) async {
    if (uid == null) return;
    await _meta().set(
        {'deckResetYmd': ymd, 'pestKills': pestKills}, SetOptions(merge: true));
  }

  /// Persiste la liste des combats engagés (épinglés).
  Future<void> setEngagedEnemies(List<String> engaged) async {
    if (uid == null) return;
    await _meta().set({'engagedEnemies': engaged}, SetOptions(merge: true));
  }

  /// Persiste le nombre de jetons de relâche consommés (social « Le Monde »).
  Future<void> setReleaseTokensUsed(int used) async {
    if (uid == null) return;
    await _meta().set({'releaseTokensUsed': used}, SetOptions(merge: true));
  }

  /// Persiste l'arsenal d'invasion : roster de rouges dispo + captures dépensées
  /// au craft (Invasion / Territoires). Trust-client v1.
  Future<void> setInvasionArsenal(
      Map<String, int> redRoster, Map<String, int> craftSpent) async {
    if (uid == null) return;
    await _meta().set(
        {'redRoster': redRoster, 'craftSpent': craftSpent},
        SetOptions(merge: true));
  }

  /// Persiste les dégâts de boss au deck vert (monotone, récupérable en farmant).
  Future<void> setDeckDamage(Map<String, int> deckDamage) async {
    if (uid == null) return;
    await _meta().set({'deckDamage': deckDamage}, SetOptions(merge: true));
  }

  /// Persiste la masse de bataille DÉPENSÉE (le gagné est dérivé de habitProgress).
  Future<void> setBattleMasseUsed(int used) async {
    if (uid == null) return;
    await _meta().set({'battleMasseUsed': used}, SetOptions(merge: true));
  }

  Future<void> setWeaponPickups(Map<String, int> pickups) async {
    if (uid == null) return;
    await _meta().set({'weaponPickups': pickups}, SetOptions(merge: true));
  }

  /// Écrit les défis du donjon (générés côté app). Stockés dans le meta.
  Future<void> setExpeditionChallenges(List<String> challenges) async {
    if (uid == null) return;
    await _meta()
        .set({'expeditionChallenges': challenges}, SetOptions(merge: true));
  }

  /// Régénère les défis du donjon ET remet le parcours à zéro (nœuds franchis
  /// vidés) — utilisé quand un défi est devenu obsolète (cible disparue).
  Future<void> resetExpeditionProgress(List<String> challenges) async {
    if (uid == null) return;
    await _meta().set(
        {'expeditionChallenges': challenges, 'expeditionCleared': <String>[]},
        SetOptions(merge: true));
  }

  /// Mémorise le niveau dont le gardien a été vaincu.
  Future<void> setExpeditionGuardianKilled(int level) async {
    if (uid == null) return;
    await _meta()
        .set({'expeditionGuardianKilledLevel': level}, SetOptions(merge: true));
  }

  /// Mémorise le niveau dont le donjon a été ouvert (entrée auto ensuite).
  Future<void> setExpeditionDonjonLevel(int level) async {
    if (uid == null) return;
    await _meta().set({'expeditionDonjonLevel': level}, SetOptions(merge: true));
  }

  /// Walk state de l'avatar sur le Monde unifié (position + brouillard). Hors du
  /// doc territoire spectatable : c'est l'état personnel de marche, persisté dans
  /// le doc meta de l'user (comme l'expédition).
  Future<void> setUnifiedWorldState(String? pos, List<String> revealed) async {
    if (uid == null) return;
    await _meta().set(
        {'unifiedPos': pos, 'unifiedRevealed': revealed},
        SetOptions(merge: true));
  }

  /// Persiste les tours TD posées (état perso de la grande map).
  Future<void> setUnifiedTurrets(List<String> turrets) async {
    if (uid == null) return;
    await _meta().set({'unifiedTurrets': turrets}, SetOptions(merge: true));
  }

  /// Coffre de la quête du jour : crédite l'or (lifetime plafonné), ajoute le
  /// butin éventuel à la collection, et marque le jour comme réclamé (anti-rejeu).
  Future<void> claimDailyQuest(
      {required int gold, String? collectibleId, required String ymd, required int questStreak}) async {
    if (uid == null) return;
    final metaRef = _meta();
    await _db.runTransaction((tx) async {
      final data = (await tx.get(metaRef)).data() as Map<String, dynamic>? ?? {};
      var bal = (data['gold'] as num?)?.toInt() ?? 0;
      var lifetime = (data['goldLifetime'] as num?)?.toInt() ?? 0;
      final unlocked = (data['unlockedLevel'] as num?)?.toInt() ?? 1;
      bal += gold;
      lifetime += GoldEconomy.cappedLifetimeAdd(gold, lifetime, unlocked);
      final coll =
          (data['collection'] as List?)?.cast<String>().toList() ?? <String>[];
      if (collectibleId != null && !coll.contains(collectibleId)) {
        coll.add(collectibleId);
      }
      tx.set(
          metaRef,
          {
            'gold': bal,
            'goldLifetime': lifetime,
            'collection': coll,
            'lastQuestClaimedYmd': ymd,
            'questStreak': questStreak,
          },
          SetOptions(merge: true));
    });
  }

  /// Vrai si AU MOINS un des docs ledger [ids] existe. Sert à l'auto-heal :
  /// les ids étant déterministes (`time_$ymd`, `rmet_<id>_$ymd`…), leur absence
  /// prouve qu'un jour n'a jamais été matérialisé (curseur empoisonné par reset).
  Future<bool> ledgerHasAny(List<String> ids) async {
    if (uid == null || ids.isEmpty) return false;
    final snaps =
        await Future.wait(ids.map((id) => _col('gold_ledger').doc(id).get()));
    return snaps.any((s) => s.exists);
  }

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
    String? setActiveAvatar,
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
      if (setActiveAvatar != null) update['activeAvatar'] = setActiveAvatar;
      tx.set(metaRef, update, SetOptions(merge: true));
      tx.set(_col('gold_ledger').doc(ledgerId), GoldLedgerEntry(
        id: ledgerId, delta: -price, category: 'spend',
        reasonCode: 'shop', label: label,
      ).toJson());
      return true;
    });
  }

  /// Révèle (débloque) un niveau : débite [cost] du solde et fixe `unlockedLevel`
  /// au niveau révélé. Transaction : refuse si solde insuffisant ou si le niveau
  /// n'est pas exactement le suivant (gate séquentiel anti-skip).
  Future<bool> revealLevel({required int level, required int cost}) async {
    if (uid == null) return false;
    final metaRef = _meta();
    final ledgerId = '${DateTime.now().microsecondsSinceEpoch}';
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(metaRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final gold = (data['gold'] as num?)?.toInt() ?? 0;
      final current = (data['unlockedLevel'] as num?)?.toInt() ?? 0;
      final effective = current < 1 ? 1 : current;
      if (level != effective + 1) return false; // séquentiel uniquement
      if (gold < cost) return false;
      tx.set(metaRef, {'gold': gold - cost, 'unlockedLevel': level},
          SetOptions(merge: true));
      if (cost > 0) {
        tx.set(_col('gold_ledger').doc(ledgerId), GoldLedgerEntry(
          id: ledgerId, delta: -cost, category: 'spend',
          reasonCode: 'level_reveal', label: 'Révélation niveau $level',
        ).toJson());
      }
      return true;
    });
  }

  /// « Royaume » : achète un niveau de PORTÉE de tourelle (séquentiel, anti-skip),
  /// calqué sur [revealLevel]. Débite l'or et monte `turretRangeLevel` d'UN cran.
  /// L'or construit la machine ; les munitions restent gagnées par le travail.
  Future<bool> upgradeTurretRange(
      {required int newLevel, required int cost}) async {
    if (uid == null) return false;
    final metaRef = _meta();
    final ledgerId = '${DateTime.now().microsecondsSinceEpoch}';
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(metaRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final gold = (data['gold'] as num?)?.toInt() ?? 0;
      final current = (data['turretRangeLevel'] as num?)?.toInt() ?? 0;
      if (newLevel != current + 1) return false; // séquentiel uniquement
      if (gold < cost) return false;
      tx.set(metaRef, {'gold': gold - cost, 'turretRangeLevel': newLevel},
          SetOptions(merge: true));
      if (cost > 0) {
        tx.set(_col('gold_ledger').doc(ledgerId), GoldLedgerEntry(
          id: ledgerId, delta: -cost, category: 'spend',
          reasonCode: 'turret_range', label: 'Portée tourelles niv. $newLevel',
        ).toJson());
      }
      return true;
    });
  }

  /// « Mise du jour » : place une mise [amount] sur le jour [ymd] (YYYYMMDD).
  /// Débite l'or immédiatement (l'or « part en jeu »). Refuse si déjà placée ce jour
  /// ou solde insuffisant. Calquée sur [purchaseGold].
  Future<bool> placeDailyStake(
      {required String ymd, required int amount}) async {
    if (uid == null || amount <= 0) return false;
    final metaRef = _meta();
    final ledgerId = 'stake_place_$ymd';
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(metaRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final gold = (data['gold'] as num?)?.toInt() ?? 0;
      final stakes =
          Map<String, dynamic>.from(data['dailyStakeByDay'] as Map? ?? {});
      if (stakes.containsKey(ymd)) return false; // déjà misée ce jour
      if (gold < amount) return false;
      stakes[ymd] = amount;
      tx.set(metaRef, {'gold': gold - amount, 'dailyStakeByDay': stakes},
          SetOptions(merge: true));
      tx.set(_col('gold_ledger').doc(ledgerId), GoldLedgerEntry(
        id: ledgerId, delta: -amount, category: 'spend',
        reasonCode: 'stake_place', label: 'Mise du jour',
      ).toJson());
      return true;
    });
  }

  /// « Mise du jour » : règle la mise du jour [ymd] en créditant [payout] (≥ 0 :
  /// remboursement proportionnel au travail réel + bonus à 100 %). Ne touche PAS
  /// `goldLifetime` (pas de farm d'XP en cyclant l'or). Idempotent (jours réglés).
  Future<bool> settleDailyStake(
      {required String ymd, required int payout}) async {
    if (uid == null) return false;
    final metaRef = _meta();
    final ledgerId = 'stake_settle_$ymd';
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(metaRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final gold = (data['gold'] as num?)?.toInt() ?? 0;
      final settled = List<String>.from(
          (data['dailyStakeSettledDays'] as List?)?.cast<String>() ??
              const <String>[]);
      if (settled.contains(ymd)) return false; // déjà réglé
      settled.add(ymd);
      final newGold = (gold + payout) < 0 ? 0 : (gold + payout);
      tx.set(metaRef, {'gold': newGold, 'dailyStakeSettledDays': settled},
          SetOptions(merge: true));
      if (payout != 0) {
        tx.set(_col('gold_ledger').doc(ledgerId), GoldLedgerEntry(
          id: ledgerId, delta: payout, category: 'gain',
          reasonCode: 'stake_settle', label: 'Règlement de la mise',
        ).toJson());
      }
      return true;
    });
  }

  /// Backfill one-shot : fixe `unlockedLevel` (sans coût) pour les docs antérieurs
  /// au gate — on accorde le rang déjà acquis pour ne rétrograder personne.
  Future<void> setUnlockedLevel(int level) async {
    if (uid == null) return;
    await _meta().set({'unlockedLevel': level}, SetOptions(merge: true));
  }

  /// Franchit un nœud d'expédition : consomme l'outil [toolKey] (si requis) et
  /// ajoute [nodeId] aux nœuds franchis. Idempotent. Renvoie false si l'outil manque.
  Future<bool> advanceExpedition(
      {required String nodeId, String? toolKey}) async {
    if (uid == null) return false;
    final metaRef = _meta();
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(metaRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final cleared =
          (data['expeditionCleared'] as List?)?.cast<String>().toList() ??
              <String>[];
      if (cleared.contains(nodeId)) return true; // déjà franchi
      final update = <String, dynamic>{};
      if (toolKey != null) {
        final inv = (data['goldInventory'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
            <String, int>{};
        if ((inv[toolKey] ?? 0) < 1) return false;
        inv[toolKey] = inv[toolKey]! - 1;
        update['goldInventory'] = inv;
      }
      cleared.add(nodeId);
      update['expeditionCleared'] = cleared;
      tx.set(metaRef, update, SetOptions(merge: true));
      return true;
    });
  }

  /// Complète l'expédition : débloque [level] (séquentiel) et remet à zéro la
  /// carte pour le niveau suivant.
  Future<bool> completeExpedition(int level) async {
    if (uid == null) return false;
    final metaRef = _meta();
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(metaRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final current = (data['unlockedLevel'] as num?)?.toInt() ?? 0;
      final effective = current < 1 ? 1 : current;
      if (level != effective + 1) return false;
      tx.set(
          metaRef,
          {
            'unlockedLevel': level,
            'expeditionCleared': <String>[],
            'expeditionRevealed': <String>[],
            'expeditionPos': null,
            'expeditionPicked': <String>[],
            'expeditionEntities': <String>[],
          },
          SetOptions(merge: true));
      return true;
    });
  }

  /// Écriture atomique d'une action overworld (déplacement / révélation+spawn /
  /// ramassage / kill). [goldDelta] < 0 = dépense (pas/torche/arme), > 0 = gain
  /// (butin/bonus, crédite aussi le lifetime). [entities] remplace la liste si fourni.
  Future<void> expeditionWrite({
    String? newPos,
    List<String> revealAdd = const [],
    List<String>? entities,
    String? pickedAdd,
    String? collectionAdd,
    String? consumeInventory,
    int goldDelta = 0,
    bool useFreeStep = false,
    String reasonCode = 'expedition',
    String label = 'Expédition',
  }) async {
    if (uid == null) return;
    final metaRef = _meta();
    final ledgerId = '${DateTime.now().microsecondsSinceEpoch}';
    await _db.runTransaction((tx) async {
      final data = (await tx.get(metaRef)).data() as Map<String, dynamic>? ?? {};
      List<String> listOf(String k) =>
          (data[k] as List?)?.cast<String>().toList() ?? <String>[];
      final update = <String, dynamic>{};

      if (consumeInventory != null) {
        final inv = (data['goldInventory'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
            <String, int>{};
        if ((inv[consumeInventory] ?? 0) > 0) {
          inv[consumeInventory] = inv[consumeInventory]! - 1;
          update['goldInventory'] = inv;
        }
      }

      if (goldDelta != 0) {
        var gold = (data['gold'] as num?)?.toInt() ?? 0;
        var lifetime = (data['goldLifetime'] as num?)?.toInt() ?? 0;
        final unlocked = (data['unlockedLevel'] as num?)?.toInt() ?? 1;
        gold += goldDelta;
        if (gold < 0) gold = 0;
        if (goldDelta > 0) {
          lifetime += GoldEconomy.cappedLifetimeAdd(goldDelta, lifetime, unlocked);
        }
        update['gold'] = gold;
        update['goldLifetime'] = lifetime;
      }
      if (newPos != null) update['expeditionPos'] = newPos;
      if (revealAdd.isNotEmpty) {
        final r = listOf('expeditionRevealed');
        for (final t in revealAdd) {
          if (!r.contains(t)) r.add(t);
        }
        update['expeditionRevealed'] = r;
      }
      if (entities != null) update['expeditionEntities'] = entities;
      if (pickedAdd != null) {
        final p = listOf('expeditionPicked');
        if (!p.contains(pickedAdd)) p.add(pickedAdd);
        update['expeditionPicked'] = p;
      }
      if (collectionAdd != null) {
        final c = listOf('collection');
        if (!c.contains(collectionAdd)) c.add(collectionAdd);
        update['collection'] = c;
      }
      if (useFreeStep) {
        final now = DateTime.now();
        update['lastFreeStepYmd'] = '${now.year}'
            '${now.month.toString().padLeft(2, '0')}'
            '${now.day.toString().padLeft(2, '0')}';
      }
      tx.set(metaRef, update, SetOptions(merge: true));
      if (goldDelta != 0) {
        tx.set(
            _col('gold_ledger').doc(ledgerId),
            GoldLedgerEntry(
              id: ledgerId,
              delta: goldDelta,
              category: goldDelta > 0 ? 'gain' : 'spend',
              reasonCode: reasonCode,
              label: label,
            ).toJson());
      }
    });
  }

  // ── 🧪 DEV / TEST (temporaire — à supprimer après les tests) ────────────────
  /// Ajoute [n] à l'or dépensable (sans toucher au lifetime/XP).
  Future<void> devAddGold(int n) async {
    if (uid == null) return;
    final ref = _meta();
    await _db.runTransaction((tx) async {
      final d = (await tx.get(ref)).data() as Map<String, dynamic>? ?? {};
      final g = (d['gold'] as num?)?.toInt() ?? 0;
      tx.set(ref, {'gold': g + n}, SetOptions(merge: true));
    });
  }

  /// Ajoute [n] à l'XP (goldLifetime → niveau), sans toucher au solde.
  Future<void> devAddXp(int n) async {
    if (uid == null) return;
    final ref = _meta();
    await _db.runTransaction((tx) async {
      final d = (await tx.get(ref)).data() as Map<String, dynamic>? ?? {};
      final x = (d['goldLifetime'] as num?)?.toInt() ?? 0;
      tx.set(ref, {'goldLifetime': x + n}, SetOptions(merge: true));
    });
  }

  /// Remet l'économie à zéro (or, XP, niveau, expédition, inventaire). Le curseur
  /// est posé sur la VEILLE (pas le jour du reset) pour que les gains du jour de
  /// reset soient bien matérialisés demain — sinon ce jour-là serait perdu.
  Future<void> devReset() async {
    if (uid == null) return;
    String fmt(DateTime d) => '${d.year}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}';
    final today = DateTime.now();
    final yesterday = fmt(today.subtract(const Duration(days: 1)));
    await _meta().set({
      'gold': 0,
      'goldLifetime': 0,
      'unlockedLevel': 1,
      'expeditionCleared': <String>[],
      'expeditionRevealed': <String>[],
      'expeditionPos': null,
      'expeditionPicked': <String>[],
      'expeditionEntities': <String>[],
      'expeditionChallenges': <String>[],
      'collection': <String>[],
      'lastFreeStepYmd': null,
      'goldInventory': <String, int>{},
      'goldLastProcessedDay': yesterday, // gains du jour de reset matérialisés demain
      'goldTodayGain': 0,
      'goldTodayGainYmd': null,
      'goldEpochYmd': fmt(today), // l'historique d'or/XP repart d'aujourd'hui
      'expeditionDonjonLevel': 0, // repasse par l'overworld (pas d'entrée auto)
      'cosmeticsOwned': <String>[], // titres/skins re-verrouillés
      'activeTitle': null,
      'activeAvatar': null,
      'lastQuestClaimedYmd': null,
      'questStreak': 0,
      'donjonKeysUsed': <String>[],
      'donjonKeysYmd': null,
    }, SetOptions(merge: true));
    // Purge le ledger (liste « Historique ») pour repartir propre.
    final ledger = await _col('gold_ledger').get();
    for (var i = 0; i < ledger.docs.length; i += 400) {
      final batch = _db.batch();
      for (final doc in ledger.docs.skip(i).take(400)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  /// Achète ET applique un gel directement depuis la carte de combat (sans passer
  /// par l'inventaire) : débite [price] d'or + pose les entrées [ymds] dans
  /// goldGelDays. Atomic : si solde insuffisant, rien n'est modifié.
  Future<bool> buyAndApplyGelDirect(
      String activityId, List<String> ymds, int price) async {
    if (uid == null) return false;
    final metaRef = _meta();
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(metaRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final balance = (data['gold'] as num?)?.toInt() ?? 0;
      if (balance < price) return false;
      final gelDays =
          (data['goldGelDays'] as List?)?.cast<String>().toList() ?? <String>[];
      for (final ymd in ymds) {
        final key = '${activityId}_$ymd';
        if (!gelDays.contains(key)) gelDays.add(key);
      }
      tx.set(
          metaRef,
          {
            'gold': balance - price,
            'goldGelDays': gelDays,
          },
          SetOptions(merge: true));
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

  /// Réparation de série : pose un gel sur un jour PASSÉ manqué (consomme 1
  /// 'repair' d'inventaire). Réutilise `goldGelDays` (skippé par habitCurrentStreak).
  Future<bool> useRepair(String activityId, String ymd) async {
    if (uid == null) return false;
    final metaRef = _meta();
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(metaRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final inv = (data['goldInventory'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
          <String, int>{};
      if ((inv['repair'] ?? 0) < 1) return false;
      inv['repair'] = inv['repair']! - 1;
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

  /// Consomme 1 sursis (repousser une deadline sans coût). Renvoie false si vide.
  Future<bool> consumeSursis() async {
    if (uid == null) return false;
    final metaRef = _meta();
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(metaRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final inv = (data['goldInventory'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
          <String, int>{};
      if ((inv['sursis'] ?? 0) < 1) return false;
      inv['sursis'] = inv['sursis']! - 1;
      tx.set(metaRef, {'goldInventory': inv}, SetOptions(merge: true));
      return true;
    });
  }

  /// Pose un bouclier anti-retard sur une tâche pour plusieurs jours (consomme
  /// 1 bouclier d'inventaire). [ymds] = "taskId_YYYYMMDD".
  Future<bool> useShield(List<String> ymds) async {
    if (uid == null) return false;
    final metaRef = _meta();
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(metaRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final inv = (data['goldInventory'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
          <String, int>{};
      if ((inv['shield'] ?? 0) < 1) return false;
      inv['shield'] = inv['shield']! - 1;
      final days =
          (data['goldTaskShieldDays'] as List?)?.cast<String>().toList() ??
              <String>[];
      for (final k in ymds) {
        if (!days.contains(k)) days.add(k);
      }
      tx.set(metaRef, {'goldInventory': inv, 'goldTaskShieldDays': days},
          SetOptions(merge: true));
      return true;
    });
  }

  /// Active le multiplicateur ×2 des gains pour un jour (consomme 1 boost).
  /// Active le multiplicateur ×2 sur plusieurs jours (consomme 1 « boost »).
  Future<bool> useBoostDays(List<String> ymds) async {
    if (uid == null) return false;
    final metaRef = _meta();
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(metaRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final inv = (data['goldInventory'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
          <String, int>{};
      if ((inv['boost'] ?? 0) < 1) return false;
      inv['boost'] = inv['boost']! - 1;
      final days =
          (data['goldBoostDays'] as List?)?.cast<String>().toList() ??
              <String>[];
      for (final ymd in ymds) {
        if (!days.contains(ymd)) days.add(ymd);
      }
      tx.set(metaRef, {'goldInventory': inv, 'goldBoostDays': days},
          SetOptions(merge: true));
      return true;
    });
  }

  Future<bool> useBoost(String ymd) async {
    if (uid == null) return false;
    final metaRef = _meta();
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(metaRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final inv = (data['goldInventory'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
          <String, int>{};
      if ((inv['boost'] ?? 0) < 1) return false;
      inv['boost'] = inv['boost']! - 1;
      final days =
          (data['goldBoostDays'] as List?)?.cast<String>().toList() ??
              <String>[];
      if (!days.contains(ymd)) days.add(ymd);
      tx.set(metaRef, {'goldInventory': inv, 'goldBoostDays': days},
          SetOptions(merge: true));
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
    // Soft-delete : archive, jamais de delete() physique.
    await _col('strategic_objectives')
        .doc(id)
        .set({'status': 'archived'}, SetOptions(merge: true));
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

  /// Visibilité du Gantt côté WEB (le mobile lit AppState.hideProjectsTab).
  /// Champ `users/{uid}/data/meta.ganttVisible` — absent ⇒ false (masqué,
  /// pivot GTD opérationnel). Écrit par le toggle Paramètres mobile.
  Future<bool> fetchGanttVisible() async {
    if (uid == null) return false;
    try {
      final snap = await _meta().get();
      final data = snap.data() as Map<String, dynamic>?;
      return (data?['ganttVisible'] as bool?) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setGanttVisible(bool visible) async {
    if (uid == null) return;
    await _meta().set({'ganttVisible': visible}, SetOptions(merge: true));
  }

  /// Contextes GTD disponibles = défauts + personnalisés
  /// (`users/{uid}/data/meta.customContexts`, lisible aussi par les functions).
  Future<List<String>> fetchAvailableContexts() async {
    if (uid == null) return List.of(kDefaultGtdContexts);
    try {
      final snap = await _meta().get();
      final data = snap.data() as Map<String, dynamic>?;
      final customs = (data?['customContexts'] as List?)?.cast<String>() ?? [];
      return [
        ...kDefaultGtdContexts,
        ...customs.where((c) => !kDefaultGtdContexts.contains(c)),
      ];
    } catch (_) {
      return List.of(kDefaultGtdContexts);
    }
  }

  /// Ajoute une action PROPRE (ownAction) à une activité-temps — action simple
  /// GTD sans projet, programmable (schedule_day) et chronométrable (▶ ciblé).
  Future<void> addOwnActionToActivity(String activityId, String title,
      {String? context, List<String>? contexts}) async {
    if (uid == null) return;
    final t = title.trim();
    if (t.isEmpty) return;
    final multi = contexts ?? const <String>[];
    // arrayUnion SANS lecture préalable : le get() bloquait hors-ligne
    // (la création d'action simple moulinait sans réseau — constaté sur
    // build). L'écriture, elle, est mise en file par le SDK.
    await _col('activities').doc(activityId).update({
      'ownActions': FieldValue.arrayUnion([
        TaskAction(
          title: t,
          linkedActivityId: activityId,
          context: multi.isNotEmpty ? multi.first : context,
          contexts: multi,
        ).toJson()
      ]),
    });
  }

  /// Remplace les ownActions d'une activité (cocher/décocher une action
  /// simple depuis l'onglet Actions).
  Future<void> updateOwnActions(
      String activityId, List<TaskAction> actions) async {
    if (uid == null) return;
    await _col('activities')
        .doc(activityId)
        .update({'ownActions': actions.map((a) => a.toJson()).toList()});
  }

  Future<void> addCustomContext(String context) async {
    if (uid == null) return;
    final c = context.trim();
    if (c.isEmpty) return;
    final normalized = c.startsWith('@') ? c : '@$c';
    await _meta().set({
      'customContexts': FieldValue.arrayUnion([normalized]),
    }, SetOptions(merge: true));
  }

  /// Retire un contexte personnalisé (les défauts ne sont pas supprimables —
  /// les actions qui portaient ce contexte le gardent, simple tag orphelin).
  Future<void> removeCustomContext(String context) async {
    if (uid == null) return;
    await _meta().set({
      'customContexts': FieldValue.arrayRemove([context]),
    }, SetOptions(merge: true));
  }

  /// Renomme un contexte personnalisé dans la liste meta. La propagation aux
  /// actions qui le portent est faite par l'appelant (qui a l'état chargé).
  Future<void> renameCustomContext(String from, String to) async {
    if (uid == null) return;
    final snap = await _meta().get();
    final data = snap.data() as Map<String, dynamic>?;
    final customs = ((data?['customContexts'] as List?)?.cast<String>() ?? [])
        .map((c) => c == from ? to : c)
        .toSet()
        .toList();
    await _meta().set({'customContexts': customs}, SetOptions(merge: true));
  }

  /// Sessions des [days] derniers jours (web : progression des objectifs).
  Future<List<Session>> fetchRecentSessions(int days) async {
    if (uid == null) return [];
    try {
      final since =
          DateTime.now().subtract(Duration(days: days)).toIso8601String();
      final snap = await _col('sessions')
          .where('startAt', isGreaterThanOrEqualTo: since)
          .get();
      return snap.docs.map((d) => Session.from(d.data() as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Hits de routine des [days] derniers jours (web : progression objectifs).
  Future<List<HabitHit>> fetchRecentHabitHits(int days) async {
    if (uid == null) return [];
    try {
      final since = DateTime.now().subtract(Duration(days: days));
      final snap = await _col('habitHits')
          .where('ts', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .get();
      return snap.docs.map((d) => HabitHit.from(d.data() as Map)).toList();
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

  /// Lecture one-shot du programme d'un jour (check-in : historique 7 jours).
  Future<DailySchedule?> fetchDailySchedule(String date) async {
    if (uid == null) return null;
    final snap = await _db.doc('users/$uid/daily_schedules/$date').get();
    return snap.exists ? DailySchedule.from(snap.data() as Map) : null;
  }

  // ── Cache de la proposition de planification ─────────────────────────────
  // L'ouverture répétée de l'écran de planification doit coûter 0 appel LLM :
  // le brouillon est persisté par date cible sur le doc du jour et réutilisé
  // tant qu'il est frais et que le programme source n'a pas changé. schedule_day
  // et la validation remplacent le doc → le cache s'invalide naturellement.

  Future<Map<String, dynamic>?> fetchProposalDraft(String date) async {
    if (uid == null) return null;
    final snap = await _db.doc('users/$uid/daily_schedules/$date').get();
    if (!snap.exists) return null;
    final raw = (snap.data() as Map)['proposalDraft'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Future<void> saveProposalDraft(String date, Map<String, dynamic> draft) async {
    if (uid == null) return;
    await _db
        .doc('users/$uid/daily_schedules/$date')
        .set({'date': date, 'proposalDraft': draft}, SetOptions(merge: true));
  }

  /// Écrit le « pourquoi » d'un engagement rompu sur son bloc (check-in étape
  /// 2 ; renégociation). [reportReason] = raison donnée au moment du report
  /// (« pas sur place »…) — skipReason « reporte » garde son sens serveur.
  Future<void> updateBlockSkipReason(
      String date, String blockId, String reason,
      {String? reportReason}) async {
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
        b['skipReason'] = reason;
        if (reportReason != null) b['reportReason'] = reportReason;
        break;
      }
    }
    await ref.update({'blocks': blocks});
  }

  /// Renégociation tactique (12a) : repose le bloc à une autre heure / durée
  /// sans toucher au reste du programme.
  Future<void> updateScheduleBlockTime(String date, String blockId,
      {String? startTime, int? durationMin}) async {
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
        if (startTime != null) b['startTime'] = startTime;
        if (durationMin != null) b['durationMin'] = durationMin;
        break;
      }
    }
    await ref.update({'blocks': blocks});
  }

  /// Rappels d'un bloc-défi recalés après déplacement — n'écrit que la liste.
  Future<void> updateBlockReminders(
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

  /// Renommage d'un bloc (timeline) — n'écrit que le titre.
  Future<void> updateBlockTitle(
      String date, String blockId, String title) async {
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
        b['title'] = title;
        break;
      }
    }
    await ref.update({'blocks': blocks});
  }

  /// Mode soirée réversible (23c) : « Terminer l'après-midi » ↔ « Revenir ».
  /// N'écrit QUE le mode — les blocs ne sont jamais touchés par la bascule.
  Future<void> setDayMode(String date, String mode) async {
    if (uid == null) return;
    await _db.doc('users/$uid/daily_schedules/$date').set({
      'date': date,
      'dayMode': mode,
      'dayModeActivatedAt':
          mode == 'evening' ? DateTime.now().toIso8601String() : null,
    }, SetOptions(merge: true));
  }

  /// Disponibilité déclarée : « pas dispo avant [until] » — le coach suit le
  /// flow jusqu'à cette heure. null = « je suis dispo » (efface la fenêtre).
  Future<void> setUnavailability(String date, DateTime? until,
      {String? reason}) async {
    if (uid == null) return;
    await _db.doc('users/$uid/daily_schedules/$date').set({
      'date': date,
      'unavailableUntil': until?.toIso8601String(),
      'unavailableReason': until == null ? null : reason,
    }, SetOptions(merge: true));
  }

  /// État déclaré (24a) : « À fond / Correct / À plat » — un fait posé en
  /// 1 tap, TTL 3 h. N'écrit QUE l'état — la forme de l'onglet suit, les
  /// blocs ne sont jamais touchés. « ↩ Ça va mieux » repasse par ici avec
  /// level "ok" (fait répondu : pas de re-question avant 3 h).
  Future<void> setEnergyState(String date, String level,
      {String? note}) async {
    if (uid == null) return;
    await _db.doc('users/$uid/daily_schedules/$date').set({
      'date': date,
      'energyState': {
        'level': level,
        'at': DateTime.now().toIso8601String(),
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      },
    }, SetOptions(merge: true));
  }

  /// Remotivation (25) : état de la séquence du jour — machine à états écrite
  /// à chaque transition (constat → question → remontée → cap).
  Future<void> setRecoverySequence(String date, RecoverySequence seq) async {
    if (uid == null) return;
    await _db.doc('users/$uid/daily_schedules/$date').set({
      'date': date,
      'recoverySequence': seq.toJson(),
    }, SetOptions(merge: true));
  }

  /// Faits persistants de la remotivation (data/meta, clé `recovery`) :
  /// lastRecoveryAt (jamais rejoué avant 72 h) + la dernière variante de copy
  /// servie par étape (jamais resservie sur deux séquences consécutives).
  Future<Map<String, dynamic>> fetchRecoveryMeta() async {
    if (uid == null) return {};
    final snap = await _meta().get();
    final raw = (snap.data() as Map<String, dynamic>?)?['recovery'];
    return raw is Map ? Map<String, dynamic>.from(raw) : {};
  }

  Future<void> setRecoveryMeta(Map<String, dynamic> patch) async {
    if (uid == null) return;
    await _meta().set({'recovery': patch}, SetOptions(merge: true));
  }

  /// Cause globale d'une journée qui a déraillé (3+ engagements rompus).
  Future<void> setDayReason(String date, String reason) async {
    if (uid == null) return;
    await _db
        .doc('users/$uid/daily_schedules/$date')
        .set({'dayReason': reason}, SetOptions(merge: true));
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
  /// Report EFFECTIF au lendemain : copie le bloc dans le doc de demain
  /// (statut pending, même heure — ajustable là-bas), en plus de l'annotation
  /// `skipReason:'reporte'` posée sur l'original. Idempotent : pas de double
  /// copie si le bloc source a déjà été reporté (carriedFromDate + id source).
  Future<void> reportBlockToTomorrow(String fromDate, ScheduleBlock b) async {
    if (uid == null) return;
    final from = DateTime.tryParse(fromDate);
    if (from == null) return;
    final t = from.add(const Duration(days: 1));
    final tomorrow =
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

    final ref = _db.doc('users/$uid/daily_schedules/$tomorrow');
    final snap = await ref.get();
    final existing = snap.exists
        ? ((snap.data() as Map)['blocks'] as List?)
                ?.map((x) => Map<String, dynamic>.from(x as Map))
                .toList() ??
            <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[];

    // Déjà reporté ? (même bloc source, repérable par id — la copie garde
    // l'id d'origine dans carriedFromDate + un id neuf à elle.)
    final marker = '$fromDate:${b.id}';
    if (existing.any((x) => x['carriedFromDate'] == marker)) return;

    final copy = ScheduleBlock(
      startTime: b.startTime,
      durationMin: b.durationMin,
      title: b.title,
      category: b.category,
      projectId: b.projectId,
      taskId: b.taskId,
      activityId: b.activityId,
      actionId: b.actionId,
      challenge: b.challenge,
      kind: b.kind == 'normal' ? 'normal' : b.kind,
      domainId: b.domainId,
      sessionTemplateId: b.sessionTemplateId,
      carriedFromDate: marker,
    );

    if (!snap.exists) {
      await ref.set(DailySchedule(
        date: tomorrow,
        generatedBy: 'user',
        blocks: [copy],
      ).toJson());
    } else {
      existing.add(copy.toJson());
      await ref.update({'blocks': existing});
    }
  }

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

  /// Retire du programme d'un jour les blocs liés à une tâche de projet
  /// (utilisé quand on retire l'étoile « priorité du jour » d'une tâche).
  Future<void> removeTaskScheduleBlocks(
      String date, String projectId, String taskId) async {
    if (uid == null) return;
    final ref = _db.doc('users/$uid/daily_schedules/$date');
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data() as Map;
    final blocks = (data['blocks'] as List?)
            ?.map((b) => Map<String, dynamic>.from(b as Map))
            .where((b) =>
                !(b['projectId'] == projectId && b['taskId'] == taskId))
            .toList() ??
        [];
    await ref.update({'blocks': blocks});
  }

  /// Retire du programme d'un jour les blocs (NON-défi) liés à une activité —
  /// utilisé quand on retire l'étoile « planifier aujourd'hui » d'une routine.
  /// Les défis 🔥 programmés pour la même activité sont préservés.
  Future<void> removeActivityScheduleBlocks(
      String date, String activityId) async {
    if (uid == null) return;
    final ref = _db.doc('users/$uid/daily_schedules/$date');
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data() as Map;
    final blocks = (data['blocks'] as List?)
            ?.map((b) => Map<String, dynamic>.from(b as Map))
            .where((b) =>
                !(b['activityId'] == activityId && b['challenge'] != true))
            .toList() ??
        [];
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

  /// Renvoie les `taskId` (Gantt) portés par un bloc encore en attente,
  /// aujourd'hui ou dans le futur — l'étape est déjà PROGRAMMÉE à un moment
  /// choisi par le user : la carte coach ne re-propose pas la tâche.
  Future<Set<String>> fetchScheduledTaskIds() async {
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
          if (b.status == 'pending' && (b.taskId ?? '').isNotEmpty) {
            ids.add(b.taskId!);
          }
        }
      }
    } catch (_) {
      // pas de programme → aucune exclusion
    }
    return ids;
  }

  /// `activityId` de tout bloc encore en attente planifié d'aujourd'hui à
  /// aujourd'hui+`days`-1 inclus (tout type de bloc, pas seulement les défis).
  /// Sert à ne pas re-proposer dans le donjon une routine déjà programmée.
  Future<Set<String>> fetchPlannedActivityIds({int days = 30}) async {
    if (uid == null) return {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String ymd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final start = ymd(today);
    final end = ymd(today.add(Duration(days: days - 1)));
    final ids = <String>{};
    try {
      final snap = await _col('daily_schedules')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: start)
          .where(FieldPath.documentId, isLessThanOrEqualTo: end)
          .get();
      for (final doc in snap.docs) {
        final sched = DailySchedule.from(doc.data() as Map);
        for (final b in sched.blocks) {
          if (b.status == 'pending' && (b.activityId ?? '').isNotEmpty) {
            ids.add(b.activityId!);
          }
        }
      }
    } catch (_) {
      // index manquant / aucun programme → aucune exclusion
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
      final list = snap.docs.map((d) {
        final m = d.data();
        return {
          'uid': d.id,
          'pseudo': m['pseudo'] ?? '—',
          'xp': (m[field] as num?)?.toInt() ?? 0,
          'level': (m['level'] as num?)?.toInt() ?? 1,
          'gold': (m['gold'] as num?)?.toInt() ?? 0,
        };
      }).toList();
      // Départage à XP égale : par or disponible (décroissant).
      list.sort((a, b) {
        final byXp = (b['xp'] as int).compareTo(a['xp'] as int);
        if (byXp != 0) return byXp;
        return (b['gold'] as int).compareTo(a['gold'] as int);
      });
      return list;
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
        'platform': kIsWeb
            ? 'web'
            : (Platform.isIOS ? 'ios' : Platform.isAndroid ? 'android' : 'other'),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    ).ignore();
  }

  /// Snapshot productivité du jour → lu par ORION (Cloud Function) pour générer
  /// le « levier du jour » de son brief. Doc singleton, écrit en merge.
  String? _pushedSnapshotJson;

  void pushProductivitySnapshot(Map<String, dynamic> snap) {
    if (uid == null) return;
    _resetPushCacheIfUserChanged();
    // Garde d'empreinte (même principe que _pushMeta) : appelé sur CHAQUE
    // onChange + chaque event du stream projets, et `updatedAt` étant un
    // serverTimestamp, chaque écriture était « nouvelle » — 1 écriture
    // Firestore par tap (constaté : pic d'écritures quotidiennes). Le contenu
    // RÉEL ne change que quelques fois par jour : on n'écrit que là.
    final json = _stableJson(snap);
    if (json == _pushedSnapshotJson) return;
    _pushedSnapshotJson = json;
    _db.doc('users/$uid/data/productivity_today').set(
      {...snap, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    ).ignore();
  }

  // ── Social « Le Monde » : nuisibles-routines relâchés ─────────────────────
  static const _releaseNuisibleUrl =
      'https://releasenuisible-dzos75b65q-uc.a.run.app';
  static const _followNuisibleUrl =
      'https://follownuisible-dzos75b65q-uc.a.run.app';

  /// Relâche une routine dans Le Monde (le jeton est consommé côté appelant).
  /// Retourne null si OK, sinon un message d'erreur.
  Future<String?> releaseNuisible(WorldNuisible n) async {
    final user = _auth.currentUser;
    if (user == null) return 'Non connecté';
    try {
      final idToken = await user.getIdToken();
      final res = await http.post(
        Uri.parse(_releaseNuisibleUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'id': n.id,
          'routineId': n.routineId,
          'name': n.name,
          'freq': n.freq,
          'target': n.target,
          'unit': n.unit,
          'iconCode': n.iconCode,
          'domainName': n.domainName,
          'hp': n.hp,
          'streak': n.streak,
        }),
      );
      if (res.statusCode == 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['error'] as String?) ?? 'Erreur (${res.statusCode})';
    } catch (_) {
      return 'Erreur réseau';
    }
  }

  /// Feed « Le Monde » : nuisibles actifs, les plus récents d'abord.
  Future<List<WorldNuisible>> fetchWorldNuisibles({int limit = 50}) async {
    try {
      final snap = await _db
          .collection('world_nuisibles')
          .where('active', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs
          .map((d) => WorldNuisible.from(d.data() as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Routines que j'ai relâchées (pour voir mes spectateurs).
  Future<List<WorldNuisible>> fetchMyReleases() async {
    if (uid == null) return [];
    try {
      final snap = await _db
          .collection('world_nuisibles')
          .where('ownerUid', isEqualTo: uid)
          .get();
      return snap.docs
          .map((d) => WorldNuisible.from(d.data() as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Suivre / ne plus suivre une routine relâchée (maj compteur spectateurs).
  /// Retourne null si OK, sinon un message d'erreur.
  Future<String?> followNuisible(String nuisibleId, bool follow) async {
    final user = _auth.currentUser;
    if (user == null) return 'Non connecté';
    try {
      final idToken = await user.getIdToken();
      final res = await http.post(
        Uri.parse(_followNuisibleUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'nuisibleId': nuisibleId, 'follow': follow}),
      );
      if (res.statusCode == 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['error'] as String?) ?? 'Erreur (${res.statusCode})';
    } catch (_) {
      return 'Erreur réseau';
    }
  }

  /// Ids des nuisibles que je suis.
  Future<Set<String>> fetchMyFollows() async {
    if (uid == null) return {};
    try {
      final snap =
          await _col('world_follows').get();
      return snap.docs.map((d) => d.id).toSet();
    } catch (_) {
      return {};
    }
  }

  // ── Combats publics engagés (sous-collection perso, écriture directe) ──────
  /// Engage un nuisible public : l'épingle dans « Combats publics » avec ses PV.
  Future<void> engageWorldCombat(String nuisibleId, int hp) async {
    if (uid == null) return;
    await _col('world_combats').doc(nuisibleId).set({
      'nuisibleId': nuisibleId,
      'hpLeft': hp,
      'engagedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Met à jour les PV restants d'un combat public (le retire si vaincu).
  Future<void> setWorldCombatHp(String nuisibleId, int hpLeft) async {
    if (uid == null) return;
    final ref = _col('world_combats').doc(nuisibleId);
    if (hpLeft <= 0) {
      await ref.delete();
    } else {
      await ref.set({'hpLeft': hpLeft}, SetOptions(merge: true));
    }
  }

  /// Mes combats publics en cours : {nuisibleId: hpLeft}.
  Future<Map<String, int>> fetchWorldCombats() async {
    if (uid == null) return {};
    try {
      final snap = await _col('world_combats').get();
      return {
        for (final d in snap.docs)
          d.id: ((d.data() as Map)['hpLeft'] as num?)?.toInt() ?? 0
      };
    } catch (_) {
      return {};
    }
  }

  // ── Bataille de nuisibles (PvP async 1v1) ─────────────────────────────────
  static const _createBattleUrl =
      'https://createbattle-dzos75b65q-uc.a.run.app';
  static const _joinBattleUrl = 'https://joinbattle-dzos75b65q-uc.a.run.app';
  static const _deployUnitUrl = 'https://deployunit-dzos75b65q-uc.a.run.app';
  static const _resolveBattleUrl =
      'https://resolvebattle-dzos75b65q-uc.a.run.app';

  Future<String?> _postBattle(String url, Map<String, dynamic> body) async {
    final user = _auth.currentUser;
    if (user == null) return null;
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
      if (res.statusCode == 200) return res.body; // JSON brut en succès
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      return '__err__${(m['error'] as String?) ?? 'Erreur ${res.statusCode}'}';
    } catch (_) {
      return '__err__Erreur réseau';
    }
  }

  /// Crée une partie. Retourne le battleId, ou null en cas d'échec.
  Future<String?> createBattle(
      {int width = 7, int lanes = 5, int tickMinutes = 60}) async {
    final r = await _postBattle(_createBattleUrl,
        {'width': width, 'lanes': lanes, 'tickMinutes': tickMinutes});
    if (r == null || r.startsWith('__err__')) return null;
    return (jsonDecode(r) as Map<String, dynamic>)['battleId'] as String?;
  }

  /// Rejoint une partie. null = OK, sinon message d'erreur.
  Future<String?> joinBattle(String battleId) async {
    final r = await _postBattle(_joinBattleUrl, {'battleId': battleId});
    if (r == null) return 'Non connecté';
    if (r.startsWith('__err__')) return r.substring(7);
    return null;
  }

  /// Dépose une unité (la masse est débitée côté appelant). null = OK.
  Future<String?> deployUnit(
      String battleId, int lane, String kind, String tier) async {
    final r = await _postBattle(_deployUnitUrl,
        {'battleId': battleId, 'lane': lane, 'kind': kind, 'tier': tier});
    if (r == null) return 'Non connecté';
    if (r.startsWith('__err__')) return r.substring(7);
    return null;
  }

  /// Demande au serveur de trancher la partie (re-simule + crédite la victoire).
  /// Retourne l'uid vainqueur si la partie est finie, sinon null.
  Future<String?> resolveBattle(String battleId) async {
    final r = await _postBattle(_resolveBattleUrl, {'battleId': battleId});
    if (r == null || r.startsWith('__err__')) return null;
    return (jsonDecode(r) as Map<String, dynamic>)['winnerUid'] as String?;
  }

  Map<String, dynamic> _battleMap(Map<String, dynamic> d) {
    // Convertit le Timestamp startAt en millis pour le modèle pur Battle.
    final m = Map<String, dynamic>.from(d);
    final ts = d['startAt'];
    m['startAtMs'] = ts is Timestamp ? ts.millisecondsSinceEpoch : null;
    return m;
  }

  /// Stream d'une partie (config + état).
  Stream<Battle?> streamBattle(String battleId) => _db
      .collection('battles')
      .doc(battleId)
      .snapshots()
      .map((s) => s.exists ? Battle.from(_battleMap(s.data()!)) : null);

  /// Stream du journal d'événements d'une partie (dépôts).
  Stream<List<BattleEvent>> streamBattleEvents(String battleId) => _db
      .collection('battles')
      .doc(battleId)
      .collection('events')
      .snapshots()
      .map((s) => s.docs.map((d) => BattleEvent.from(d.data())).toList());

  /// Mes parties en cours ou en attente (créées ou rejointes).
  Future<List<Battle>> fetchMyBattles() async {
    if (uid == null) return [];
    try {
      final snap = await _db
          .collection('battles')
          .where('players', arrayContains: uid)
          .where('status', whereIn: ['waiting', 'active']).get();
      return snap.docs.map((d) => Battle.from(_battleMap(d.data()))).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Invasion / Territoires : Cloud Functions + streams ─────────────────────
  static const _releaseInvasionUrl =
      'https://releaseinvasion-dzos75b65q-uc.a.run.app';
  static const _engageInvasionUrl =
      'https://engageinvasion-dzos75b65q-uc.a.run.app';
  static const _deployDefenseUrl =
      'https://deploydefense-dzos75b65q-uc.a.run.app';
  static const _resolveInvasionUrl =
      'https://resolveinvasion-dzos75b65q-uc.a.run.app';

  /// Lance une invasion : `redTier` = ticket (plafond de palier), `force` = copie
  /// du deck vert ≤ palier, métrée en vagues (`[{id,tier,lane,tick}]`). Le rouge
  /// est décrémenté côté appelant (trust v1). Retourne {invasionId, defenderPseudo}
  /// ou null (échec / pas de cible).
  Future<Map<String, dynamic>?> releaseInvasion(
      String redTier, List<Map<String, dynamic>> force) async {
    final r = await _postBattle(_releaseInvasionUrl,
        {'redTier': redTier, 'force': force});
    if (r == null || r.startsWith('__err__')) return null;
    final m = jsonDecode(r) as Map<String, dynamic>;
    return (m['ok'] == true) ? m : null;
  }

  /// Le défenseur engage une invasion (lance l'horloge). null = OK.
  Future<String?> engageInvasion(String invasionId) async {
    final r = await _postBattle(_engageInvasionUrl, {'invasionId': invasionId});
    if (r == null) return 'Non connecté';
    if (r.startsWith('__err__')) return r.substring(7);
    return null;
  }

  /// Le défenseur dépose un bloqueur (`kind:'pest'`) ou tire une flèche
  /// (`kind:'arrow'`). Le stock est débité côté appelant (trust v1). null = OK.
  Future<String?> deployDefense(
      String invasionId, int lane, String kind, String tier) async {
    final r = await _postBattle(_deployDefenseUrl,
        {'invasionId': invasionId, 'lane': lane, 'kind': kind, 'tier': tier});
    if (r == null) return 'Non connecté';
    if (r.startsWith('__err__')) return r.substring(7);
    return null;
  }

  /// Demande au serveur de trancher (re-simule, autoritatif). Retourne le statut
  /// final ('repelled'|'held') si résolu, sinon null (en cours / erreur).
  Future<String?> resolveInvasion(String invasionId) async {
    final r = await _postBattle(_resolveInvasionUrl, {'invasionId': invasionId});
    if (r == null || r.startsWith('__err__')) return null;
    final m = jsonDecode(r) as Map<String, dynamic>;
    if (m['ongoing'] == true) return null;
    return m['status'] as String?;
  }

  Map<String, dynamic> _invasionMap(Map<String, dynamic> d) {
    final m = Map<String, dynamic>.from(d);
    final ts = d['startAt'];
    m['startAtMs'] = ts is Timestamp ? ts.millisecondsSinceEpoch : null;
    return m;
  }

  /// Stream d'une invasion (config + état + force figée).
  Stream<Invasion?> streamInvasion(String invasionId) => _db
      .collection('invasions')
      .doc(invasionId)
      .snapshots()
      .map((s) => s.exists ? Invasion.from(_invasionMap(s.data()!)) : null);

  /// Stream du journal d'événements défenseur (bloqueurs + flèches).
  Stream<List<BattleEvent>> streamInvasionEvents(String invasionId) => _db
      .collection('invasions')
      .doc(invasionId)
      .collection('events')
      .snapshots()
      .map((s) => s.docs.map((d) => BattleEvent.from(d.data())).toList());

  /// Invasions que je SUBIS (en attente ou actives) — à défendre.
  Future<List<Invasion>> fetchInvasionsAsDefender() async {
    if (uid == null) return [];
    try {
      final snap = await _db
          .collection('invasions')
          .where('defenderUid', isEqualTo: uid)
          .where('status', whereIn: ['pending', 'active']).get();
      return snap.docs
          .map((d) => Invasion.from(_invasionMap(d.data())))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Mes invasions en cours (spectateur live) — actives ou tenues.
  Future<List<Invasion>> fetchInvasionsAsInvader() async {
    if (uid == null) return [];
    try {
      final snap = await _db
          .collection('invasions')
          .where('invaderUid', isEqualTo: uid)
          .where('status', whereIn: ['pending', 'active', 'held']).get();
      return snap.docs
          .map((d) => Invasion.from(_invasionMap(d.data())))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Jeu de territoire : map persistée ──────────────────────────────────────
  /// Stream de la map d'un user (la sienne, ou celle qu'on envahit en spectateur).
  Stream<Territory?> streamTerritory(String tuid) => _db
      .collection('territories')
      .doc(tuid)
      .snapshots()
      .map((s) => s.exists ? Territory.from(s.data()!) : null);

  /// Crée ma map si elle n'existe pas encore (une grotte par domaine, brouillard).
  /// Idempotent. Trust-client v1 (CF-autoritatif au PvP plus tard).
  Future<void> ensureTerritory(String pseudo,
      {List<String> domainIds = const []}) async {
    if (uid == null) return;
    final ref = _db.collection('territories').doc(uid);
    final snap = await ref.get();
    if (snap.exists) return;
    await ref.set({
      ...initialTerritory(uid!, pseudo, domainIds: domainIds).toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Persiste un état de territoire (merge). Trust-client v1.
  Future<void> saveTerritory(Territory t) async {
    if (uid == null) return;
    await _db.collection('territories').doc(t.uid).set(
      {...t.toJson(), 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  // ── Invasion / Territoires : classement par puissance de deck ──────────────
  /// Classement par puissance de deck (roster de rouges). Trié décroissant.
  /// Sert au matchmaking ladder (cibler ~3 rangs au-dessus de soi) et à la vue
  /// classement. `deckPower` est posé serveur (writeLeaderboardEntry).
  Future<List<DeckLadderEntry>> fetchDeckLadder({int limit = 100}) async {
    try {
      final snap = await _db
          .collection('leaderboard_entries')
          .where('optedIn', isEqualTo: true)
          .orderBy('deckPower', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((d) {
        final m = d.data();
        return DeckLadderEntry(
          uid: d.id,
          pseudo: (m['pseudo'] as String?) ?? 'Anonyme',
          deckPower: (m['deckPower'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}

/// Une ligne du classement par puissance de deck d'invasion.
class DeckLadderEntry {
  final String uid;
  final String pseudo;
  final int deckPower;
  const DeckLadderEntry(
      {required this.uid, required this.pseudo, required this.deckPower});
}
