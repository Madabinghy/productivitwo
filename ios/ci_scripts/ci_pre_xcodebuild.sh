#!/bin/sh

set -e

echo "=== Installing Flutter ==="
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

echo "=== Flutter version ==="
flutter --version

echo "=== Installing Flutter dependencies ==="
cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter pub get

echo "=== Precaching Flutter iOS artifacts ==="
flutter precache --ios

echo "=== Configuring git for CocoaPods (bypass proxy for BoringSSL) ==="
git config --global --unset http.proxy || true
git config --global --unset https.proxy || true
git config --global url."https://github.com/".insteadOf "git://github.com/"
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy

echo "=== Installing CocoaPods dependencies ==="
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
pod repo add trunk https://cdn.cocoapods.org/ 2>/dev/null || pod repo update trunk 2>/dev/null || true
pod install --repo-update

echo "=== Pre-build done ==="
