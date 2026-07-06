/// Coupe-circuit de l'ANCIENNE gamification (moteur « or » / combat / monde /
/// expéditions / donjon / arène). false = accès retirés de l'app ; le code et
/// les données Firestore restent intacts (repasser à true pour tout réactiver).
///
/// `final` (et non `const`) volontairement : le code gaté reste compilé (code
/// mort conservé, réactivable) et l'analyseur ne le signale pas comme `dead_code`.
final bool kOldGamificationEnabled = false;

/// Coupe-circuit de la NOUVELLE couche jeu mobile (Manoir d'Ombrelune,
/// compteur de nuisibles, mise du jour). false = UI retirée de l'app mobile ;
/// le code et les données Firestore restent intacts (repasser à true pour
/// tout réactiver). Même principe `final` que ci-dessus : code mort conservé.
final bool kGameLayerEnabled = false;
