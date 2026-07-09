part of '../models.dart';

class DayBlock {
  String id;
  String name;
  String? emoji;
  int order;
  List<String> activityIds;
  int? startHour;   // heure de début du bloc (null = pas de rappel)
  int? startMinute;

  DayBlock({
    String? id,
    required this.name,
    this.emoji,
    this.order = 0,
    List<String>? activityIds,
    this.startHour,
    this.startMinute,
  })  : id = id ?? _uuid.v4(),
        activityIds = activityIds ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'order': order,
        'activityIds': activityIds,
        'startHour': startHour,
        'startMinute': startMinute,
      };

  static DayBlock from(Map j) => DayBlock(
        id: j['id'],
        name: j['name'] ?? '',
        emoji: j['emoji'],
        order: (j['order'] as num?)?.toInt() ?? 0,
        activityIds:
            (j['activityIds'] as List?)?.cast<String>() ?? <String>[],
        startHour: j['startHour'] as int?,
        startMinute: j['startMinute'] as int?,
      );
}

class ActivityLog {
  final String id;
  final String activityId;
  final DateTime start;
  final DateTime? end;

  ActivityLog({
    required this.id,
    required this.activityId,
    required this.start,
    this.end,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'activityId': activityId,
        'start': start.toIso8601String(),
        'end': end?.toIso8601String(),
      };

  static ActivityLog from(Map<String, dynamic> j) => ActivityLog(
        id: j['id'],
        activityId: j['activityId'],
        start: _parseDate(j['start']),
        end: _parseDateOrNull(j['end']),
      );
}

class InboxItem {
  String id;
  String title;
  DateTime createdAt;
  InboxItem({String? id, required this.title, DateTime? createdAt})
      : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
      };
  static InboxItem from(Map j) => InboxItem(
        id: j['id'],
        title: j['title'],
        createdAt: _parseDate(j['createdAt']),
      );
}


/// --- DOMAINES ---

/// Un élément du minimum vital d'un domaine — mesurable, vérifiable par les
/// données (jamais un vœu invérifiable). Ex : « 2 séances / sem »
/// (metric: sessions_week, target: 2).
class VitalMinimum {
  String label;
  String metric; // petit enum ouvert : sessions_week | sessions_day | …
  num target;
  String period; // "week" | "day"

  VitalMinimum({
    required this.label,
    this.metric = '',
    this.target = 0,
    this.period = 'week',
  });

  Map<String, dynamic> toJson() =>
      {'label': label, 'metric': metric, 'target': target, 'period': period};

  static VitalMinimum from(Map j) => VitalMinimum(
        label: j['label'] ?? '',
        metric: j['metric'] ?? '',
        target: (j['target'] as num?) ?? 0,
        period: j['period'] ?? 'week',
      );
}

class Domain {
  String id, name;
  int? goalMinDay;
  bool autoGoal;
  int? colorValue;
  bool deleted; // true = supprimé via MCP, ignoré dans l'UI
  // ── Intention & minimum vital (session de définition Orion) ────────────────
  // Tous optionnels et rétrocompatibles : un domaine sans intention se comporte
  // exactement comme avant. L'intention est LES MOTS DU USER — citée telle
  // quelle partout, jamais reformulée par l'UI.
  String? intention;
  List<VitalMinimum> vitalMinimum;
  List<String> modalities; // ce que la renégociation fait évoluer
  List<String> artifactIds; // refs vers la collection documents
  List<String> wantedArtifacts; // artefacts voulus (génération = handoff suivant)
  // "named" (onboarding : nommé mais pas défini — N'EXISTE PAS pour le coach :
  // ignoré par la proposition, la carte et le rapport, aucun vital inventé).
  String definitionStatus; // "none" | "named" | "draft" | "active" | "suspended"
  DateTime? definedAt;
  DateTime? renegotiatedAt;
  List<Map<String, dynamic>> history; // { date, field, from, to, reason }
  // Suspension assumée (renégociation 12b) : jusqu'à cette date incluse, le
  // coach ne pose RIEN sur ce domaine — puis il redevient actif tout seul.
  String? suspendedUntil; // YYYY-MM-DD

  Domain({
    String? id,
    required this.name,
    this.goalMinDay,
    this.autoGoal = true,
    this.colorValue,
    this.deleted = false,
    this.intention,
    List<VitalMinimum>? vitalMinimum,
    List<String>? modalities,
    List<String>? artifactIds,
    List<String>? wantedArtifacts,
    this.definitionStatus = 'none',
    this.definedAt,
    this.renegotiatedAt,
    List<Map<String, dynamic>>? history,
    this.suspendedUntil,
  })  : id = id ?? _uuid.v4(),
        vitalMinimum = vitalMinimum ?? [],
        modalities = modalities ?? [],
        artifactIds = artifactIds ?? [],
        wantedArtifacts = wantedArtifacts ?? [],
        history = history ?? [];

  bool get isDefined => definitionStatus == 'active' && intention != null;

  /// Suspendu à la date [ymd] (YYYY-MM-DD) — comparaison lexicale ISO.
  bool suspendedOn(String ymd) =>
      suspendedUntil != null && suspendedUntil!.compareTo(ymd) >= 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'goalMinDay': goalMinDay,
        'autoGoal': autoGoal,
        'colorValue': colorValue,
        'deleted': deleted,
        'intention': intention,
        'vitalMinimum': vitalMinimum.map((v) => v.toJson()).toList(),
        // Spec fiche domaine : modalités stockées en [{label}] (enum ouvert).
        'modalities': modalities.map((m) => {'label': m}).toList(),
        'artifactIds': artifactIds,
        'wantedArtifacts': wantedArtifacts,
        'definitionStatus': definitionStatus,
        'definedAt': definedAt?.toIso8601String(),
        'renegotiatedAt': renegotiatedAt?.toIso8601String(),
        'history': history,
        'suspendedUntil': suspendedUntil,
      };

  static Domain from(Map j) => Domain(
        id: j['id'],
        name: j['name'],
        goalMinDay: j['goalMinDay'],
        autoGoal: j['autoGoal'] ?? true,
        colorValue: j['colorValue'] as int?,
        deleted: j['deleted'] as bool? ?? false,
        intention: j['intention'],
        vitalMinimum: (j['vitalMinimum'] as List?)
                ?.whereType<Map>()
                .map(VitalMinimum.from)
                .toList() ??
            [],
        // Accepte [{label}] (spec) ET ["…"] (tolérance).
        modalities: (j['modalities'] as List?)
                ?.map((m) =>
                    m is Map ? (m['label']?.toString() ?? '') : m.toString())
                .where((s) => s.isNotEmpty)
                .toList() ??
            [],
        artifactIds: (j['artifactIds'] as List?)?.cast<String>() ?? [],
        wantedArtifacts:
            (j['wantedArtifacts'] as List?)?.map((e) => e.toString()).toList() ??
                [],
        definitionStatus: j['definitionStatus']?.toString() ?? 'none',
        definedAt: _parseDateOrNull(j['definedAt']),
        renegotiatedAt: _parseDateOrNull(j['renegotiatedAt']),
        history: (j['history'] as List?)
                ?.whereType<Map>()
                .map((h) => Map<String, dynamic>.from(h))
                .toList() ??
            [],
        suspendedUntil: j['suspendedUntil']?.toString(),
      );
}
