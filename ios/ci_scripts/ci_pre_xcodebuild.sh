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

echo "=== Installing CocoaPods dependencies ==="
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
pod repo add trunk https://cdn.cocoapods.org/ 2>/dev/null || pod repo update trunk 2>/dev/null || true
pod install --repo-update

echo "=== Pre-build done ==="
