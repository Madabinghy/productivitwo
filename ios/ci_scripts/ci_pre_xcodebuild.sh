#!/bin/sh

set -e

# Retry réseau : Xcode Cloud a parfois des coupures DNS transitoires pendant le
# téléchargement du Dart SDK / des artefacts (curl: Could not resolve host
# storage.googleapis.com — cf. build 330 échoué). On retente avant d'abandonner.
retry() {
  n=0
  until "$@"; do
    n=$((n + 1))
    if [ "$n" -ge 6 ]; then
      echo "❌ Échec après 6 tentatives : $*"
      return 1
    fi
    echo "⚠️ Échec réseau (tentative $n/6) — nouvel essai dans 15 s : $*"
    sleep 15
  done
}

echo "=== Installing Flutter ==="
retry sh -c 'rm -rf "$HOME/flutter" && git clone https://github.com/flutter/flutter.git --depth 1 -b 3.35.6 "$HOME/flutter"'
export PATH="$PATH:$HOME/flutter/bin"

echo "=== Flutter version (télécharge le Dart SDK — avec retry) ==="
retry flutter --version

echo "=== Installing Flutter dependencies ==="
cd "$CI_PRIMARY_REPOSITORY_PATH"
retry flutter pub get

echo "=== Precaching Flutter iOS artifacts (avec retry) ==="
retry flutter precache --ios

echo "=== Configuring git for CocoaPods ==="
git config --global --unset http.proxy || true
git config --global --unset https.proxy || true
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy

# Forcer HTTPS pour tous les URLs GitHub (git:// et http://)
git config --global url."https://github.com/".insteadOf "git://github.com/"
git config --global url."https://github.com/".insteadOf "http://github.com/"

# Désactiver osxkeychain — n'a pas accès au Keychain dans la VM Xcode Cloud
# et réinterprète https:// en http://, causant "Device not configured"
git config --global credential.helper ""

echo "=== Installing CocoaPods dependencies ==="
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
pod repo add trunk https://cdn.cocoapods.org/ 2>/dev/null || pod repo update trunk 2>/dev/null || true
pod install --repo-update

echo "=== Pre-build done ==="
