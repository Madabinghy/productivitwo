{{flutter_js}}

{{flutter_build_config}}

// Safari : désactive le service worker (évite les ressources obsolètes en cache)
var _isSafari = /apple/i.test(navigator.vendor);

_flutter.loader.load({
  serviceWorkerSettings: _isSafari ? null : {
    serviceWorkerVersion: {{flutter_service_worker_version}}
  },
  config: {
    // Force le chargement local de CanvasKit (évite le CDN gstatic bloqué par COEP sur Firefox/Safari)
    canvasKitBaseUrl: "/canvaskit/"
  }
});
