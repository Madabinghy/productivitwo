part of '../models.dart';

/// Crédit de « reconquête » : effort fourni AUJOURD'HUI imputé à un jour passé
/// en dette, dans un registre SÉPARÉ des sessions/hits réels.
///
/// Le relevé factuel (`sessions` / `habitHits`) reste immuable et n'est jamais
/// réécrit : on ne ment pas sur le passé. Ces crédits n'existent que pour la
/// couche jeu (PV des ennemis, standard du jardin) et **ne fuient jamais** dans
/// le rapport temps / budgets / ORION.
///
/// Collection : `users/{uid}/redemptions/{id}`.
class Redemption {
  String id;
  String activityId;
  String type; // "habit" (hits) | "time" (minutes)
  String targetDate; // clé-jour yyyymmdd (ex. 20260620) : le jour passé reconquis
  int amount; // habit → hits · time → minutes
  String sourceDate; // clé-jour yyyymmdd : le jour de l'effort (= aujourd'hui)
  DateTime createdAt;
  String status; // "active" | "deleted" (soft-delete réversible)

  Redemption({
    String? id,
    required this.activityId,
    required this.type,
    required this.targetDate,
    required this.amount,
    required this.sourceDate,
    DateTime? createdAt,
    this.status = 'active',
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  bool get active => status == 'active';

  Map<String, dynamic> toJson() => {
        'id': id,
        'activityId': activityId,
        'type': type,
        'targetDate': targetDate,
        'amount': amount,
        'sourceDate': sourceDate,
        'createdAt': createdAt.toIso8601String(),
        'status': status,
      };

  static Redemption from(Map j) => Redemption(
        id: j['id'],
        activityId: j['activityId'] ?? '',
        type: j['type'] ?? 'time',
        targetDate: j['targetDate'] ?? '',
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        sourceDate: j['sourceDate'] ?? '',
        createdAt: _parseDate(j['createdAt']),
        status: j['status'] ?? 'active',
      );
}
