/// Partage d'une image (carte de badge) — implémentation par plateforme.
/// Mobile : fichier PNG temporaire + feuille de partage. Web : téléchargement.
export 'image_share_io.dart' if (dart.library.html) 'image_share_web.dart';
