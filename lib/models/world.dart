part of '../models.dart';

/// Routine relâchée dans « Le Monde » (social, audience-accountability).
/// Document public `world_nuisibles/{id}` : les autres l'engagent, la combattent
/// (à l'arme) puis suivent la progression de [ownerPseudo] sur cette routine.
/// La difficulté ([hp]) est dérivée à la relâche de la série/niveau de l'émetteur
/// (plus l'émetteur est régulier, plus son nuisible est dur → prestige à suivre).
class WorldNuisible {
  final String id;
  final String ownerUid;
  final String ownerPseudo;
  final String routineId; // id de la routine source chez l'émetteur
  final String name;
  final String freq; // 'daily' | 'weekly' | 'monthly'
  final int target;
  final String? unit;
  final int? iconCode;
  final String? domainName;
  final int hp; // points de vie = difficulté (dérivée série/niveau émetteur)
  final int spectatorCount;
  final int streak; // série actuelle de l'émetteur (snapshot d'affichage)
  final bool active;
  final DateTime createdAt;

  const WorldNuisible({
    required this.id,
    required this.ownerUid,
    required this.ownerPseudo,
    required this.routineId,
    required this.name,
    required this.freq,
    required this.target,
    this.unit,
    this.iconCode,
    this.domainName,
    required this.hp,
    this.spectatorCount = 0,
    this.streak = 0,
    this.active = true,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'ownerUid': ownerUid,
        'ownerPseudo': ownerPseudo,
        'routineId': routineId,
        'name': name,
        'freq': freq,
        'target': target,
        'unit': unit,
        'iconCode': iconCode,
        'domainName': domainName,
        'hp': hp,
        'spectatorCount': spectatorCount,
        'streak': streak,
        'active': active,
        'createdAt': createdAt.toIso8601String(),
      };

  static WorldNuisible from(Map j) => WorldNuisible(
        id: j['id'] as String,
        ownerUid: (j['ownerUid'] ?? '') as String,
        ownerPseudo: (j['ownerPseudo'] ?? '?') as String,
        routineId: (j['routineId'] ?? '') as String,
        name: (j['name'] ?? 'Routine') as String,
        freq: (j['freq'] ?? 'daily') as String,
        target: (j['target'] as num?)?.toInt() ?? 1,
        unit: j['unit'] as String?,
        iconCode: (j['iconCode'] as num?)?.toInt(),
        domainName: j['domainName'] as String?,
        hp: (j['hp'] as num?)?.toInt() ?? 1,
        spectatorCount: (j['spectatorCount'] as num?)?.toInt() ?? 0,
        streak: (j['streak'] as num?)?.toInt() ?? 0,
        active: j['active'] as bool? ?? true,
        createdAt: DateTime.tryParse((j['createdAt'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}
