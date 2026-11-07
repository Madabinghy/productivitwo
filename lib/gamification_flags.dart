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

/// Méta-collection des badges (audit 2026-11-07, décision user : « récompenser
/// le fait de jouer plutôt que le fait de vivre ») : points et badges de
/// collection, compteurs au long cours, piles de compteurs, récolte du matin,
/// retournement des cartes, cartes à aller chercher, Sniper ciblé, Chasseur de
/// cartes, partage. false = retirés de l'interface et du deck ; les badges
/// restent des cartes simples dans l'album. Même principe `final`.
final bool kCollectionMetaEnabled = false;

/// Braises (audit 2026-11-07, décision user : trop de filets pour les séries) :
/// false = plus de réserve à forger ni de série à rallumer dans l'interface ; la
/// journée difficile, le minimum et le gel restent. Les rallumages déjà faits
/// gardent leur jour comblé (le registre est toujours rejoué) : aucune série ne
/// casse rétroactivement. Même principe `final`.
final bool kEmbersEnabled = false;

/// Sniper allégé (audit 2026-11-07) : false = le viseur est une simple liste
/// « ce qui tombe, avec combien de temps » (on écarte d'un tap) — plus de
/// réglage − / + ni de mini-tirs, plus d'ordre à la main, plus de chiffres de
/// précision au bilan. Le calcul du temps exact et l'enchaînement des tirs
/// restent. Même principe `final`.
final bool kSniperTuningEnabled = false;
