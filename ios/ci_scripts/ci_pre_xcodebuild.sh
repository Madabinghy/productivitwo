#!/bin/sh

set -e

echo "=== Installing Flutter ==="
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

echo "=== Flutter version ==="
flutter --version

echo "=== Installing Flutter dependencies ==="
cd "$CI_WORKSPACE"
flutter pub get

echo "=== Installing CocoaPods dependencies ==="
cd "$CI_WORKSPACE/ios"
pod install

echo "=== Pre-build done ==="
