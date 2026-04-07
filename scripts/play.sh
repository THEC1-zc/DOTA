#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT/config"
TMP_DIR="${TMPDIR:-/tmp}"
STATE_FILE="$TMP_DIR/dota-agent-state.json"
DECISION_FILE="$TMP_DIR/dota-agent-decision.json"
RESPONSE_FILE="$TMP_DIR/dota-agent-response.json"
GAME_ID="$(jq -r '.lastGameId // empty' "$CONFIG_DIR/runtime.json" 2>/dev/null || true)"
STATE_URL_BASE="https://wc2-agentic-dev-3o6un.ondigitalocean.app/api/game/state"
STATE_URL="$STATE_URL_BASE"

if [[ ! -f "$CONFIG_DIR/credentials.json" ]]; then
  echo "Missing config/credentials.json. Run: npm run register -- <agent-name>" >&2
  exit 1
fi

if [[ -n "$GAME_ID" ]]; then
  STATE_URL="$STATE_URL?game=$GAME_ID"
fi

curl -sS --max-time 20 "$STATE_URL" > "$STATE_FILE"

if ! jq -e 'type == "object" and (.heroes | type == "array") and (.towers | type == "array") and (.lanes | type == "object") and (.bases | type == "object")' "$STATE_FILE" >/dev/null 2>&1; then
  echo "Cached game state was invalid, falling back to default game feed." >&2
  curl -sS --max-time 20 "$STATE_URL_BASE" > "$STATE_FILE"
fi

node "$ROOT/src/play.js" "$STATE_FILE" > "$DECISION_FILE"

API_KEY="$(jq -r '.apiKey' "$CONFIG_DIR/credentials.json")"
PAYLOAD="$(jq -c '.payload' "$DECISION_FILE")"

curl -sS -X POST https://wc2-agentic-dev-3o6un.ondigitalocean.app/api/strategy/deployment \
  --max-time 20 \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" > "$RESPONSE_FILE"

node "$ROOT/src/play.js" "$STATE_FILE" "$RESPONSE_FILE"
