{{flutter_js}}

{{flutter_build_config}}

// Pas de service worker (build `--pwa-strategy=none`) : Firebase Hosting sert
// index.html, flutter_bootstrap.js et main.dart.js sans cache, donc chaque
// ouverture charge la version en ligne. Avant, le SW « offline-first » de
// Flutter gardait l'ancienne build jusqu'à fermeture de tous les onglets.
_flutter.loader.load({
  serviceWorkerSettings: null,
  config: {
    // Force le chargement local de CanvasKit (évite le CDN gstatic bloqué par COEP sur Firefox/Safari)
    canvasKitBaseUrl: "/canvaskit/"
  }
});
