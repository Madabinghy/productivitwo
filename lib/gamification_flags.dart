/// Coupe-circuit de l'ANCIENNE gamification (moteur « or » / combat / monde /
/// expéditions / donjon / arène). false = accès retirés de l'app ; le code et
/// les données Firestore restent intacts (repasser à true pour tout réactiver).
///
/// `final` (et non `const`) volontairement : le code gaté reste compilé (code
/// mort conservé, réactivable) et l'analyseur ne le signale pas comme `dead_code`.
final bool kOldGamificationEnabled = false;
