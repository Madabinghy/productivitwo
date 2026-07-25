import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:productivitwo_v1/build_info.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/storage.dart';

/// Sauvegarde « Coffre » (spec : docs/specs/export-import-donnees/README.md).
/// Construction du fichier d'export, lecture/validation d'un fichier de
/// restauration, application Fusionner/Remplacer. Logique sans UI.

/// Version du schéma du FICHIER de sauvegarde. Un fichier d'une version
/// SUPÉRIEURE est refusé sans décodage partiel (spec : « Schema trop recent »).
const int kBackupSchemaVersion = 1;

/// Collections Firestore embarquées EN PLUS de AppState (qui couvre déjà
/// domaines, activités, sessions, routines, blocs, inbox, réglages).
/// `api_tokens` et consentements coach : JAMAIS — la sauvegarde est un
/// document utilisateur, pas un état d'authentification.
const List<String> kBackupCollections = [
  'projects',
  'strategic_objectives',
  'daily_schedules',
  'artifacts',
  'recipes',
  'captures',
  'session_templates',
  'assistant_messages',
];

/// Collection optionnelle (« Inclure les documents et livrables »).
const String kBackupDocumentsCollection = 'documents';

/// JSON-safe : Firestore renvoie des Timestamp que jsonEncode ne sait pas
/// sérialiser — tout devient ISO8601, récursivement.
dynamic jsonSafe(dynamic v) {
  if (v is Timestamp) return v.toDate().toIso8601String();
  if (v is DateTime) return v.toIso8601String();
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), jsonSafe(val)));
  }
  if (v is List) return v.map(jsonSafe).toList();
  return v;
}

/// Une sauvegarde construite, prête à écrire : json + taille réelle.
class BackupBundle {
  final Map<String, dynamic> json;
  final String encoded;

  BackupBundle(this.json) : encoded = jsonEncode(json);

  int get sizeBytes => utf8.encode(encoded).length;

  /// « 1,4 Mo » / « 320 Ko » — format FR de la maquette.
  String get sizeLabel => formatBytes(sizeBytes);

  String get fileName {
    final now = DateTime.now();
    final ymd = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return 'productivitwo-$ymd.json';
  }
}

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    final mo = bytes / (1024 * 1024);
    return '${mo.toStringAsFixed(1).replaceAll('.', ',')} Mo';
  }
  return '${(bytes / 1024).ceil()} Ko';
}

/// Construit la sauvegarde complète. Les collections sont récupérées une
/// fois puis le bundle est dérivable avec/sans documents (estimation de
/// taille AVANT écriture, spec 3.2).
class BackupBuilder {
  final AppState state;
  final FirestoreSync sync;

  Map<String, List<Map<String, dynamic>>> _collections = {};
  List<Map<String, dynamic>> _documents = [];
  Map<String, dynamic> _meta = {};
  bool _fetched = false;

  BackupBuilder({required this.state, required this.sync});

  Future<void> fetch() async {
    if (_fetched) return;
    for (final col in kBackupCollections) {
      _collections[col] =
          (jsonSafe(await sync.dumpCollection(col)) as List)
              .cast<Map<String, dynamic>>();
    }
    _documents =
        (jsonSafe(await sync.dumpCollection(kBackupDocumentsCollection))
                as List)
            .cast<Map<String, dynamic>>();
    _meta = jsonSafe(await sync.fetchMetaDocRaw()) as Map<String, dynamic>;
    _fetched = true;
  }

  /// Compteurs pour l'inventaire de la sheet Exporter + l'en-tête du fichier.
  Map<String, int> counts() => {
        'domains': state.domains.where((d) => !d.deleted).length,
        'activities': state.activities.where((a) => !a.deleted).length,
        'sessions': state.sessions.length,
        'habitHits': state.habitHits.length,
        'projects': _collections['projects']?.length ?? 0,
        'objectives': _collections['strategic_objectives']?.length ?? 0,
        'dailySchedules': _collections['daily_schedules']?.length ?? 0,
        'documents': _documents.length,
      };

  /// Premier jour de données — « tout ton historique depuis le … ».
  DateTime? firstDataDay() {
    DateTime? min;
    for (final s in state.sessions) {
      if (min == null || s.startAt.isBefore(min)) min = s.startAt;
    }
    for (final h in state.habitHits) {
      final ts = h.ts;
      if (min == null || ts.isBefore(min)) min = ts;
    }
    return min;
  }

  BackupBundle build({required bool includeDocuments}) {
    assert(_fetched, 'fetch() d\'abord');
    return BackupBundle({
      'schemaVersion': kBackupSchemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'buildTag': kBuildLabel,
      'uid': sync.uid,
      'counts': counts(),
      'appState': state.toJson(),
      // Section dédiée (spec) : un doc par jour, hors AppState.
      'dailySchedules': _collections['daily_schedules'] ?? [],
      'collections': {
        for (final e in _collections.entries)
          if (e.key != 'daily_schedules') e.key: e.value,
        if (includeDocuments) kBackupDocumentsCollection: _documents,
      },
      // Doc meta (customContexts…). L'or y est ignoré à la restauration
      // (autoritatif serveur, écrit par transaction uniquement).
      'meta': _meta,
    });
  }
}

// ── Restauration ─────────────────────────────────────────────────────────────

enum BackupParseError { invalid, schemaTooRecent }

/// Aperçu d'un fichier lu — AVANT toute écriture (spec 3.3).
class BackupPreview {
  final Map<String, dynamic> raw;
  final int schemaVersion;
  final DateTime? exportedAt;
  final String? uid;
  final AppState state;
  final Map<String, List<Map<String, dynamic>>> collections;
  final List<Map<String, dynamic>> dailySchedules;
  final Map<String, dynamic> meta;

  BackupPreview({
    required this.raw,
    required this.schemaVersion,
    required this.exportedAt,
    required this.uid,
    required this.state,
    required this.collections,
    required this.dailySchedules,
    required this.meta,
  });

  int get domainCount => state.domains.where((d) => !d.deleted).length;
  int get activityCount => state.activities.where((a) => !a.deleted).length;
  int get sessionCount => state.sessions.length;
  int get projectCount => collections['projects']?.length ?? 0;

  /// « Du 03/01/2026 au 12/08/2026 » — plage réelle des données du fichier.
  ({DateTime? first, DateTime? last}) dateRange() {
    DateTime? min, max;
    void see(DateTime d) {
      if (min == null || d.isBefore(min!)) min = d;
      if (max == null || d.isAfter(max!)) max = d;
    }

    for (final s in state.sessions) {
      see(s.startAt);
    }
    for (final h in state.habitHits) {
      see(h.ts);
    }
    return (first: min, last: max);
  }
}

/// Lit et valide un fichier. Ne modifie RIEN. Lève [BackupParseError].
BackupPreview parseBackup(String rawText) {
  Map<String, dynamic> root;
  try {
    final decoded = jsonDecode(rawText);
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    root = decoded;
  } catch (_) {
    throw BackupParseError.invalid;
  }
  final schema = root['schemaVersion'];
  final appState = root['appState'];
  if (schema is! int || appState is! Map) throw BackupParseError.invalid;
  // « Elle vient d'une version plus récente » : refus explicite, sans
  // décodage partiel.
  if (schema > kBackupSchemaVersion) throw BackupParseError.schemaTooRecent;

  AppState state;
  try {
    state = AppState.from(appState);
  } catch (_) {
    throw BackupParseError.invalid;
  }

  List<Map<String, dynamic>> listOf(dynamic v) => v is List
      ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : <Map<String, dynamic>>[];

  final rawCols = root['collections'];
  final collections = <String, List<Map<String, dynamic>>>{
    if (rawCols is Map)
      for (final e in rawCols.entries) e.key.toString(): listOf(e.value),
  };

  return BackupPreview(
    raw: root,
    schemaVersion: schema,
    exportedAt: DateTime.tryParse(root['exportedAt']?.toString() ?? ''),
    uid: root['uid']?.toString(),
    state: state,
    collections: collections,
    dailySchedules: listOf(root['dailySchedules']),
    meta: root['meta'] is Map
        ? Map<String, dynamic>.from(root['meta'] as Map)
        : <String, dynamic>{},
  );
}

enum RestoreMode { merge, replace }

class RestoreReport {
  int added = 0;
  int alreadyThere = 0; // fusion : présents des deux côtés (rien de perdu)
  int overwritten = 0; // remplacement : docs réécrits
}

/// Applique une restauration. Retourne l'état final à sauvegarder + le bilan.
/// AUCUNE suppression, jamais (soft-delete only — convention du repo) :
/// - Fusionner : merge par ID via FirestoreSync.merge (rien n'est supprimé,
///   l'état courant garde la main sur les conflits d'ID) ; les docs de
///   collections déjà présents ne sont pas réécrits.
/// - Remplacer : l'AppState devient celui du fichier, tous les docs du
///   fichier sont réécrits ; les docs absents du fichier restent en place.
/// Idempotent : rejouer le même fichier ne duplique rien (tout est par ID).
Future<({AppState state, RestoreReport report})> applyRestore({
  required BackupPreview backup,
  required AppState current,
  required FirestoreSync sync,
  required FileStore store,
  required RestoreMode mode,
}) async {
  final report = RestoreReport();

  // 1) AppState.
  AppState next;
  if (mode == RestoreMode.merge) {
    // local = importé, remote = courant → le courant gagne sur les conflits
    // d'ID (domaines/activités), l'importé comble ce qui manque, les compteurs
    // monotones gardent le max.
    next = FirestoreSync.merge(backup.state, current);
    report.added += _countAdded(current, next);
  } else {
    next = backup.state;
  }

  // Migrations one-shot rejouées (idempotentes via leurs flags — un fichier
  // ancien sans flag est re-migré, un fichier déjà migré ne bouge pas).
  store.replayMigrations(next);

  // 2) Persistance locale + push Firestore complet.
  await store.save(next);
  await sync.pushAll(next);

  // 3) Collections hors AppState.
  final cols = <String, List<Map<String, dynamic>>>{
    ...backup.collections,
    'daily_schedules': backup.dailySchedules,
  };
  for (final e in cols.entries) {
    if (e.value.isEmpty) continue;
    final existing =
        mode == RestoreMode.merge ? await sync.collectionIds(e.key) : <String>{};
    for (final doc in e.value) {
      final id = (doc['id'] ?? doc['date'])?.toString();
      if (id == null || id.isEmpty) continue;
      if (mode == RestoreMode.merge && existing.contains(id)) {
        report.alreadyThere++;
        continue;
      }
      await sync.writeCollectionDoc(e.key, id, doc);
      if (mode == RestoreMode.merge) {
        report.added++;
      } else {
        report.overwritten++;
      }
    }
  }

  // 4) Contextes GTD personnalisés (doc meta). Le reste du meta n'est pas
  // réécrit tel quel : l'or est autoritatif serveur, et le miroir des
  // réglages passe déjà par pushAll.
  final ctxs = (backup.meta['customContexts'] as List?)?.cast<String>();
  if (ctxs != null && ctxs.isNotEmpty) {
    await sync.restoreCustomContexts(ctxs, replace: mode == RestoreMode.replace);
  }

  return (state: next, report: report);
}

int _countAdded(AppState before, AppState after) {
  int d(int a, int b) => (b - a).clamp(0, 1 << 31);
  return d(before.domains.length, after.domains.length) +
      d(before.activities.length, after.activities.length) +
      d(before.sessions.length, after.sessions.length) +
      d(before.habitHits.length, after.habitHits.length) +
      d(before.blocks.length, after.blocks.length) +
      d(before.habitProgress.length, after.habitProgress.length);
}
