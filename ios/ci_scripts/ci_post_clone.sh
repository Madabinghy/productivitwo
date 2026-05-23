#!/bin/sh

# Fix Xcode Cloud proxy issue avec BoringSSL-GRPC / CocoaPods
git config --global --unset-all http.proxy  2>/dev/null || true
git config --global --unset-all https.proxy 2>/dev/null || true
# Ne PAS remettre http.proxy / https.proxy à "" — ça crée une valeur vide
# qui interfère avec les clones HTTPS lors du pod install.

# Assure que CocoaPods utilise le CDN (pas git direct)
gem install cocoapods --no-document 2>/dev/null || true

exit 0
