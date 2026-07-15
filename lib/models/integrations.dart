part of '../models.dart';

class ApiToken {
  String id;
  String tokenHash; // sha256 du token brut — seule valeur persistée
  String? rawToken; // valeur brute en mémoire uniquement, jamais sérialisée vers Firestore
  String label; // ex: "Claude MCP", "Coach Antoine"
  bool active;
  DateTime createdAt;
  DateTime? lastUsedAt;

  ApiToken({
    String? id,
    required this.tokenHash,
    this.rawToken,
    required this.label,
    this.active = true,
    DateTime? createdAt,
    this.lastUsedAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'tokenHash': tokenHash,
        'label': label,
        'active': active,
        'createdAt': createdAt.toIso8601String(),
        'lastUsedAt': lastUsedAt?.toIso8601String(),
      };

  static ApiToken from(Map j) => ApiToken(
        id: j['id'],
        tokenHash: j['tokenHash'] ?? '',
        label: j['label'] ?? '',
        active: j['active'] as bool? ?? true,
        createdAt: j['createdAt'] != null
            ? (j['createdAt'] is String
                ? DateTime.tryParse(j['createdAt']) ?? DateTime.now()
                : (j['createdAt'] as dynamic).toDate() as DateTime)
            : DateTime.now(),
        lastUsedAt: j['lastUsedAt'] == null
            ? null
            : (j['lastUsedAt'] is String
                ? DateTime.tryParse(j['lastUsedAt'])
                : (j['lastUsedAt'] as dynamic).toDate() as DateTime),
      );
}

// ── Captures (idées rapides traitées par ORION) ───────────────────────────────

class CaptureItem {
  String id;
  String text;
  DateTime createdAt;
  String status; // pending | proposed (dans « À valider ») | processed
  String? orionNote;
  DateTime? processedAt;

  CaptureItem({
    String? id,
    required this.text,
    required this.createdAt,
    this.status = 'pending',
    this.orionNote,
    this.processedAt,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'status': status,
        'orionNote': orionNote,
        'processedAt': processedAt?.toIso8601String(),
      };

  static CaptureItem from(Map j) => CaptureItem(
        id: j['id'] ?? _uuid.v4(),
        text: j['text'] ?? '',
        createdAt: _parseDate(j['createdAt']),
        status: j['status'] ?? 'pending',
        orionNote: j['orionNote'],
        processedAt: _parseDateOrNull(j['processedAt']),
      );
}

/// Proposition de réorganisation émise par ORION autonome (file « À valider »).
/// L'utilisateur accepte/refuse/redirige ; l'acceptation applique la mutation
/// côté client (déterministe, sans LLM). Voir `FirestoreSync.applyProposal`.
class OrionProposal {
  String id;
  String kind; // new_project | attach_idea_as_task | create_subproject | archive_project | add_phase | attach_action_to_task
  String title; // résumé humain
  String rationale; // justification
  String? sourceCaptureId;
  Map<String, dynamic> payload;
  String status; // pending | accepted | rejected
  DateTime? createdAt;

  OrionProposal({
    String? id,
    required this.kind,
    required this.title,
    this.rationale = '',
    this.sourceCaptureId,
    Map<String, dynamic>? payload,
    this.status = 'pending',
    this.createdAt,
  })  : id = id ?? _uuid.v4(),
        payload = payload ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'rationale': rationale,
        'sourceCaptureId': sourceCaptureId,
        'payload': payload,
        'status': status,
        'createdAt': createdAt?.toIso8601String(),
      };

  static OrionProposal from(Map j) => OrionProposal(
        id: j['id'] ?? _uuid.v4(),
        kind: j['kind'] ?? '',
        title: j['title'] ?? '',
        rationale: j['rationale'] ?? '',
        sourceCaptureId: j['sourceCaptureId'],
        payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? {},
        status: j['status'] ?? 'pending',
        createdAt: _parseDateOrNull(j['createdAt']),
      );
}

/// Entrée du grand livre d'Or (append-only) : un gain, une perte ou une dépense.
/// Stockée dans `users/{uid}/gold_ledger/{id}`. Alimente l'historique de la sheet.
class GoldLedgerEntry {
  String id;
  DateTime ts;
  int delta;          // +gain / −perte / −dépense
  String category;    // gain | loss | spend
  String reasonCode;  // ex: routine_met, routine_missed, late_task, delete_project…
  String label;       // libellé humain affichable
  String? refType;    // ex: activity | project | task
  String? refId;

  GoldLedgerEntry({
    String? id,
    DateTime? ts,
    required this.delta,
    required this.category,
    required this.reasonCode,
    required this.label,
    this.refType,
    this.refId,
  })  : id = id ?? _uuid.v4(),
        ts = ts ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'ts': ts.toIso8601String(),
        'delta': delta,
        'category': category,
        'reasonCode': reasonCode,
        'label': label,
        'refType': refType,
        'refId': refId,
      };

  static GoldLedgerEntry from(Map j) => GoldLedgerEntry(
        id: j['id'] ?? _uuid.v4(),
        ts: _parseDate(j['ts']),
        delta: (j['delta'] as num?)?.toInt() ?? 0,
        category: j['category'] ?? 'gain',
        reasonCode: j['reasonCode'] ?? '',
        label: j['label'] ?? '',
        refType: j['refType'],
        refId: j['refId'],
      );
}
