/// Écriture/partage du fichier de sauvegarde — implémentation par plateforme.
/// Mobile/desktop : fichier temporaire + feuille de partage (share_plus).
/// Web : téléchargement direct (ancre + Blob), sans dépendance.
export 'backup_saver_io.dart'
    if (dart.library.html) 'backup_saver_web.dart';
