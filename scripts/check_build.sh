#!/bin/bash
# Attend la fin du dernier build Codemagic (ou déclenche un nouveau)
# Usage : ! ./scripts/check_build.sh [workflow_id]
# Ex : ! ./scripts/check_build.sh android-release

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/.env"

WORKFLOW_ID="${1:-}"

# Si un workflow est spécifié, déclencher un nouveau build
if [ -n "$WORKFLOW_ID" ]; then
  echo "🚀 Déclenchement du build $WORKFLOW_ID..."
  BUILD_RESP=$(curl -s -X POST \
    -H "x-auth-token: $CODEMAGIC_API_KEY" \
    -H "Content-Type: application/json" \
    "https://api.codemagic.io/builds" \
    -d "{\"appId\":\"$CODEMAGIC_APP_ID\",\"workflowId\":\"$WORKFLOW_ID\",\"branch\":\"main\"}")
  BUILD_ID=$(echo "$BUILD_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('buildId','error'))" 2>/dev/null)
  echo "🔨 Build ID : $BUILD_ID"
else
  # Prendre le dernier build
  echo "⏳ Récupération du dernier build..."
  BUILD_DATA=$(curl -s \
    -H "x-auth-token: $CODEMAGIC_API_KEY" \
    "https://api.codemagic.io/builds?appId=$CODEMAGIC_APP_ID&branch=main&limit=1")
  BUILD_ID=$(echo "$BUILD_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['builds'][0]['_id'])" 2>/dev/null)
  WORKFLOW=$(echo "$BUILD_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['builds'][0].get('workflowName','?'))" 2>/dev/null)
  echo "🔨 Workflow : $WORKFLOW | ID : $BUILD_ID"
fi

echo "⏳ Attente de la fin du build (max 20 min)..."

# Attendre la fin
for i in $(seq 1 120); do
  BUILD_DATA=$(curl -s \
    -H "x-auth-token: $CODEMAGIC_API_KEY" \
    "https://api.codemagic.io/builds/$BUILD_ID")

  STATUS=$(echo "$BUILD_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['build']['status'])" 2>/dev/null)
  echo "   [$((i*10))s] $STATUS"

  if [[ "$STATUS" == "finished" ]]; then
    echo "✅ Build réussi !"
    echo "Lien : https://codemagic.io/app/$CODEMAGIC_APP_ID/build/$BUILD_ID"
    exit 0
  fi

  if [[ "$STATUS" == "failed" || "$STATUS" == "error" || "$STATUS" == "canceled" ]]; then
    echo "❌ Build $STATUS"
    echo ""

    # Message d'erreur global
    MSG=$(echo "$BUILD_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['build'].get('message',''))" 2>/dev/null)
    [ -n "$MSG" ] && echo "Message : $MSG"

    # Étapes échouées
    echo ""
    echo "══════════════ ÉTAPES ÉCHOUÉES ══════════════"
    echo "$BUILD_DATA" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for action in d['build'].get('buildActions', []):
    if action.get('status') == 'failed':
        print(f\"❌ {action['name']}\")
        # Lire les logs si disponible
        log_url = action.get('logUrl')
        if log_url:
            print(f\"   Log URL : {log_url}\")
"
    echo ""
    echo "Lien direct : https://codemagic.io/app/$CODEMAGIC_APP_ID/build/$BUILD_ID"

    # Essaie de lire les logs des étapes qui en ont
    echo ""
    echo "══════════════ LOGS DISPONIBLES ══════════════"
    echo "$BUILD_DATA" | python3 -c "
import sys, json, urllib.request, urllib.error

d = json.load(sys.stdin)
api_key = '$CODEMAGIC_API_KEY'

for action in d['build'].get('buildActions', []):
    log_url = action.get('logUrl')
    if not log_url:
        continue
    try:
        req = urllib.request.Request(log_url, headers={'x-auth-token': api_key})
        with urllib.request.urlopen(req, timeout=10) as resp:
            logs = resp.read().decode('utf-8', errors='ignore')
            lines = logs.split('\n')
            errors = [l for l in lines if any(x in l for x in ['error:', 'Error:', 'FAILED', 'Exception', 'What went wrong'])]
            if errors:
                print(f'--- {action[\"name\"]} ---')
                for e in errors[:20]:
                    print(e)
    except Exception as e:
        pass
" 2>/dev/null
    echo "══════════════════════════════════════════════"
    exit 1
  fi

  sleep 10
done

echo "⏱️ Timeout 20 min — build toujours en cours"
echo "Lien : https://codemagic.io/app/$CODEMAGIC_APP_ID/build/$BUILD_ID"
