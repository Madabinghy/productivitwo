#!/usr/bin/env bash
# Setup de l'environnement Claude Code « web » (VM cloud Anthropic, Ubuntu/Linux)
# pour Productivitwo (Flutter + Cloud Functions Firebase).
#
# À coller dans le champ « Setup script » de l'environment sur claude.ai/code,
# ou à invoquer depuis ce champ via :  bash scripts/cloud-setup.sh
#
# Node 20 est déjà présent sur la VM ; Flutter ne l'est PAS → on l'installe.
set -uo pipefail

echo "── Installation Flutter SDK ───────────────────────────────"
if [ ! -d "$HOME/flutter" ]; then
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter"
fi
export PATH="$HOME/flutter/bin:$PATH"
# Persister le PATH pour toutes les commandes des sessions suivantes
grep -q 'flutter/bin' "$HOME/.bashrc" 2>/dev/null \
  || echo 'export PATH="$HOME/flutter/bin:$PATH"' >> "$HOME/.bashrc"

flutter config --no-analytics >/dev/null 2>&1 || true
# Précache uniquement le toolchain web (pas d'iOS/Android possible en cloud)
flutter precache --web --no-android --no-ios --no-linux --no-windows --no-macos >/dev/null 2>&1 || true

echo "── Dépendances Dart du projet ─────────────────────────────"
flutter pub get || true

echo "── Firebase CLI (pour deploy éventuel depuis le cloud) ────"
command -v firebase >/dev/null 2>&1 || npm install -g firebase-tools

echo "── Dépendances Cloud Functions ───────────────────────────"
( cd functions && npm install )

echo "✅ Setup terminé : $(flutter --version 2>/dev/null | head -1)"
