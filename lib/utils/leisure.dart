/// Temps de DÉTENTE (2026-11-18) : les activités des domaines de nature
/// « Détente » (loisirs, jeux, repos choisi). Posées par l'app
/// (`AppLogic.refreshLeisure`) : la nature d'un domaine vit sur l'appareil.
/// Vide = rien n'est traité comme de la détente (web, tests).
Set<String> leisureActivityIds = const {};

bool isLeisureId(String? activityId) => activityId != null && leisureActivityIds.contains(activityId);
