#!/bin/bash
# Récupère les logs du dernier build Codemagic raté
# Usage : ./scripts/check_build.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/.env"

# Dernier build (tous statuts)
BUILD=$(curl -s \
  -H "x-auth-token: $CODEMAGIC_API_KEY" \
  "https://api.codemagic.io/builds?appId=$CODEMAGIC_APP_ID&branch=main&limit=1" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); b=d['builds'][0]; print(b['_id']+'|'+b['status']+'|'+b.get('workflowName','?'))")

BUILD_ID=$(echo "$BUILD" | cut -d'|' -f1)
STATUS=$(echo "$BUILD" | cut -d'|' -f2)
WORKFLOW=$(echo "$BUILD" | cut -d'|' -f3)

echo "=== Dernier build : $WORKFLOW | Statut : $STATUS ==="
echo "ID : $BUILD_ID"
echo ""

if [ "$STATUS" = "finished" ]; then
  echo "✅ Build réussi."
  exit 0
fi

# Récupère les logs
echo "=== Logs d'erreur ==="
curl -s \
  -H "x-auth-token: $CODEMAGIC_API_KEY" \
  "https://api.codemagic.io/builds/$BUILD_ID/logs" \
  | python3 -c "
import sys
logs = sys.stdin.read()
# Cherche la section d'erreur
lines = logs.split('\n')
in_error = False
error_lines = []
for i, line in enumerate(lines):
    if any(x in line for x in ['What went wrong', 'FAILURE:', 'error:', 'e: file://', 'BUILD FAILED', 'Exception']):
        in_error = True
    if in_error:
        error_lines.append(line)
    if in_error and len(error_lines) > 60:
        break
print('\n'.join(error_lines) if error_lines else 'Aucune erreur trouvée dans les logs.')
"
