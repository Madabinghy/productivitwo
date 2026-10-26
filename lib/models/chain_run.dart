part of '../models.dart';

/// Session du mode Enchaîner (badges, 2026-10) : écrite une fois, quand le
/// récap s'affiche. `completed` = la file s'est vidée (pas « Sortir »).
/// `fullDay` = du premier au dernier bloc du programme du jour. Collection
/// `users/{uid}/chain_runs/{id}`. Alimente les badges Enchaîneur et Plein jour.
class ChainRun {
  String id;
  String date; // jour vécu, YYYY-MM-DD
  DateTime startedAt;
  DateTime endedAt;
  int doneCount;
  int total;
  bool completed;
  String? firstBlockId; // premier bloc réel de la file au départ
  String? lastBlockId; // dernier bloc réel épuisé
  String? programFirstBlockId; // premier bloc du programme du jour
  String? programLastBlockId; // dernier bloc du programme du jour

  ChainRun({
    String? id,
    required this.date,
    required this.startedAt,
    required this.endedAt,
    required this.doneCount,
    required this.total,
    required this.completed,
    this.firstBlockId,
    this.lastBlockId,
    this.programFirstBlockId,
    this.programLastBlockId,
  }) : id = id ?? _uuid.v4();

  /// Un Enchaîner du premier au dernier bloc du programme, mené au bout.
  bool get fullDay =>
      completed &&
      firstBlockId != null &&
      lastBlockId != null &&
      firstBlockId == programFirstBlockId &&
      lastBlockId == programLastBlockId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'doneCount': doneCount,
        'total': total,
        'completed': completed,
        if (firstBlockId != null) 'firstBlockId': firstBlockId,
        if (lastBlockId != null) 'lastBlockId': lastBlockId,
        if (programFirstBlockId != null) 'programFirstBlockId': programFirstBlockId,
        if (programLastBlockId != null) 'programLastBlockId': programLastBlockId,
      };

  static ChainRun from(Map j) => ChainRun(
        id: j['id'] as String?,
        date: (j['date'] ?? '').toString(),
        startedAt: _parseDate(j['startedAt']),
        endedAt: _parseDate(j['endedAt']),
        doneCount: (j['doneCount'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        completed: j['completed'] == true,
        firstBlockId: j['firstBlockId'] as String?,
        lastBlockId: j['lastBlockId'] as String?,
        programFirstBlockId: j['programFirstBlockId'] as String?,
        programLastBlockId: j['programLastBlockId'] as String?,
      );
}
