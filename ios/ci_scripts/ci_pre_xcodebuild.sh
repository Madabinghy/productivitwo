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

echo "=== Forcer le build number AU-DESSUS de 437 (plafond hérité de l'ancien Codemagic) ==="
# Xcode Cloud numérote avec son propre compteur (CI_BUILD_NUMBER ≈ 346), SOUS le plus
# haut build déjà sur TestFlight (437, issu de Codemagic). Un build qui ne dépasse pas
# ce plafond n'apparaît jamais comme « le dernier » → invisible aux testeurs. On force
# donc FLUTTER_BUILD_NUMBER (= CFBundleVersion via Info.plist) bien au-dessus, de façon
# MONOTONE (CI_BUILD_NUMBER croît à chaque run).
BN=$(( ${CI_BUILD_NUMBER:-1} + 500 ))
XCFG="$CI_PRIMARY_REPOSITORY_PATH/ios/Flutter/Generated.xcconfig"
if grep -q '^FLUTTER_BUILD_NUMBER=' "$XCFG"; then
  sed -i '' "s/^FLUTTER_BUILD_NUMBER=.*/FLUTTER_BUILD_NUMBER=${BN}/" "$XCFG"
else
  echo "FLUTTER_BUILD_NUMBER=${BN}" >> "$XCFG"
fi
echo "→ CFBundleVersion forcé à ${BN} (CI_BUILD_NUMBER=${CI_BUILD_NUMBER:-?})"

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
