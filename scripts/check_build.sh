#!/bin/bash
# Attend la fin du dernier build Codemagic et affiche les logs si erreur
# Usage : ! ./scripts/check_build.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/.env"

echo "⏳ Récupération du dernier build..."

# Dernier build
get_build() {
  curl -s \
    -H "x-auth-token: $CODEMAGIC_API_KEY" \
    "https://api.codemagic.io/builds?appId=$CODEMAGIC_APP_ID&branch=main&limit=1"
}

BUILD_DATA=$(get_build)
BUILD_ID=$(echo "$BUILD_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['builds'][0]['_id'])")
WORKFLOW=$(echo "$BUILD_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['builds'][0].get('workflowName','?'))")

echo "🔨 Workflow : $WORKFLOW | ID : $BUILD_ID"
echo "⏳ Attente de la fin du build..."

# Attendre que le build soit terminé (max 15 min)
for i in $(seq 1 90); do
  sleep 10
  STATUS=$(curl -s \
    -H "x-auth-token: $CODEMAGIC_API_KEY" \
    "https://api.codemagic.io/builds/$BUILD_ID" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['build']['status'])" 2>/dev/null)

  echo "   [$((i*10))s] Statut : $STATUS"

  if [[ "$STATUS" == "finished" ]]; then
    echo "✅ Build réussi !"
    exit 0
  fi

  if [[ "$STATUS" == "failed" || "$STATUS" == "error" || "$STATUS" == "canceled" ]]; then
    echo "❌ Build $STATUS — récupération des logs..."
    break
  fi
done

# Récupère et filtre les logs d'erreur
echo ""
echo "══════════════ ERREURS ══════════════"
curl -s \
  -H "x-auth-token: $CODEMAGIC_API_KEY" \
  "https://api.codemagic.io/builds/$BUILD_ID/logs" \
  | python3 -c "
import sys
logs = sys.stdin.read()
lines = logs.split('\n')
in_error = False
error_lines = []
for line in lines:
    clean = line
    # Supprime les timestamps Codemagic
    if 'Z\t' in line:
        clean = line.split('Z\t', 1)[-1]
    if any(x in clean for x in ['What went wrong', 'FAILURE:', 'error:', 'e: file://', 'BUILD FAILED', 'Task failed', 'Exception in thread']):
        in_error = True
    if in_error:
        error_lines.append(clean)
    if in_error and len(error_lines) > 80:
        break
print('\n'.join(error_lines) if error_lines else 'Aucune erreur extraite — consulte les logs manuellement.')
"
echo "══════════════════════════════════════"
echo "Lien direct : https://codemagic.io/app/$CODEMAGIC_APP_ID/build/$BUILD_ID"
