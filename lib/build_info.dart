// Infos de build injectées par le CI au moment du `flutter build web`
// (cf. .github/workflows/deploy-web-functions.yml : flags --dart-define).
// En dev local (sans dart-define) → valeurs par défaut ('dev').
//
// Permet de vérifier d'un coup d'œil quelle build tourne en prod (cache du
// service worker Flutter web : utile pour confirmer qu'un déploiement est servi).
const String kBuildSha = String.fromEnvironment('GIT_SHA', defaultValue: 'dev');
const String kBuildTime = String.fromEnvironment('BUILD_TIME', defaultValue: '');

/// Libellé court de version pour l'UI : `build <sha>` (+ heure si dispo).
String get kBuildLabel =>
    kBuildTime.isEmpty ? 'build $kBuildSha' : 'build $kBuildSha · $kBuildTime';
