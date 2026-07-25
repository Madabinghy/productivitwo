part of '../models.dart';

/// Lien coach-coaché (Espace Coach V1.1, US-1).
/// Doc Firestore : `coach_links/{id}` où **l'id EST le code d'invitation**
/// (capability : connaître le code = pouvoir rejoindre). Un utilisateur peut
/// être coach de N coachés et avoir AU PLUS un coach (garde côté client à
/// l'acceptation).
///
/// RGPD par conception : le coach ne lit JAMAIS les données brutes du
/// coaché — seulement le doc `coach_links/{id}/data/summary`, écrit par
/// l'app du coaché et limité au périmètre consenti. Tout changement de
/// consentement est journalisé dans [consentLog].
class CoachLink {
  String id; // = code d'invitation
  String coachUid;
  String? coacheeUid;
  String? coachName;
  String? coacheeName;
  String status; // invited | active | revoked
  List<String> sharedDomainIds; // opt-in : vide par défaut
  String granularity; // 'status' (engagements tenus/en retard) | 'detail'
  DateTime createdAt;
  DateTime? acceptedAt;
  DateTime? revokedAt;
  List<Map<String, dynamic>> consentLog;

  CoachLink({
    required this.id,
    required this.coachUid,
    this.coacheeUid,
    this.coachName,
    this.coacheeName,
    this.status = 'invited',
    List<String>? sharedDomainIds,
    this.granularity = 'status',
    DateTime? createdAt,
    this.acceptedAt,
    this.revokedAt,
    List<Map<String, dynamic>>? consentLog,
  })  : sharedDomainIds = sharedDomainIds ?? [],
        createdAt = createdAt ?? DateTime.now(),
        consentLog = consentLog ?? [];

  bool get isActive => status == 'active';

  Map<String, dynamic> toJson() => {
        'id': id,
        'coachUid': coachUid,
        'coacheeUid': coacheeUid,
        'coachName': coachName,
        'coacheeName': coacheeName,
        'status': status,
        'sharedDomainIds': sharedDomainIds,
        'granularity': granularity,
        'createdAt': createdAt.toIso8601String(),
        'acceptedAt': acceptedAt?.toIso8601String(),
        'revokedAt': revokedAt?.toIso8601String(),
        'consentLog': consentLog,
      };

  static CoachLink from(Map j) => CoachLink(
        id: j['id'] ?? '',
        coachUid: j['coachUid'] ?? '',
        coacheeUid: j['coacheeUid'] as String?,
        coachName: j['coachName'] as String?,
        coacheeName: j['coacheeName'] as String?,
        status: j['status'] ?? 'invited',
        sharedDomainIds:
            (j['sharedDomainIds'] as List?)?.cast<String>() ?? <String>[],
        granularity: j['granularity'] ?? 'status',
        createdAt: j['createdAt'] != null
            ? DateTime.tryParse(j['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        acceptedAt: j['acceptedAt'] != null
            ? DateTime.tryParse(j['acceptedAt'].toString())
            : null,
        revokedAt: j['revokedAt'] != null
            ? DateTime.tryParse(j['revokedAt'].toString())
            : null,
        consentLog: (j['consentLog'] as List?)
                ?.whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList() ??
            <Map<String, dynamic>>[],
      );
}
