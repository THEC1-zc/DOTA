#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT/config"
TMP_DIR="${TMPDIR:-/tmp}"
STATE_FILE="$TMP_DIR/dota-agent-state.json"
DECISION_FILE="$TMP_DIR/dota-agent-decision.json"
RESPONSE_FILE="$TMP_DIR/dota-agent-response.json"
GAME_ID="$(jq -r '.lastGameId // empty' "$CONFIG_DIR/runtime.json" 2>/dev/null || true)"
OBSERVED_GAME_ID=""
STATE_URL_BASE="https://wc2-agentic-dev-3o6un.ondigitalocean.app/api/game/state"
STATE_URL="$STATE_URL_BASE"
AGENT_NAME="$(jq -r '.agentName' "$CONFIG_DIR/credentials.json")"

if [[ ! -f "$CONFIG_DIR/credentials.json" ]]; then
  echo "Missing config/credentials.json. Run: npm run register -- <agent-name>" >&2
  exit 1
fi

if [[ -n "$GAME_ID" ]]; then
  STATE_URL="$STATE_URL?game=$GAME_ID"
  OBSERVED_GAME_ID="$GAME_ID"
fi

curl -sS --max-time 20 "$STATE_URL" > "$STATE_FILE"

if ! jq -e 'type == "object" and (.heroes | type == "array") and (.towers | type == "array") and (.lanes | type == "object") and (.bases | type == "object")' "$STATE_FILE" >/dev/null 2>&1; then
  echo "Cached game state was invalid, falling back to default game feed." >&2
  curl -sS --max-time 20 "$STATE_URL_BASE" > "$STATE_FILE"
fi

if ! jq -e --arg name "$AGENT_NAME" '(.heroes | type == "array") and any(.heroes[]?; .name == $name)' "$STATE_FILE" >/dev/null 2>&1; then
  for candidate_game in 1 2 3 4 5 6 7 8 9 10; do
    CANDIDATE_STATE_FILE="$TMP_DIR/dota-agent-state-$candidate_game.json"
    curl -sS --max-time 20 "$STATE_URL_BASE?game=$candidate_game" > "$CANDIDATE_STATE_FILE"

    if ! jq -e 'type == "object" and (.heroes | type == "array") and (.towers | type == "array") and (.lanes | type == "object") and (.bases | type == "object")' "$CANDIDATE_STATE_FILE" >/dev/null 2>&1; then
      continue
    fi

    if jq -e --arg name "$AGENT_NAME" 'any(.heroes[]?; .name == $name)' "$CANDIDATE_STATE_FILE" >/dev/null 2>&1; then
      mv "$CANDIDATE_STATE_FILE" "$STATE_FILE"
      OBSERVED_GAME_ID="$candidate_game"
      break
    fi
  done
fi

node "$ROOT/src/play.js" "$STATE_FILE" > "$DECISION_FILE"

API_KEY="$(jq -r '.apiKey' "$CONFIG_DIR/credentials.json")"
PAYLOAD="$(jq -c '.payload' "$DECISION_FILE")"

curl -sS -X POST https://wc2-agentic-dev-3o6un.ondigitalocean.app/api/strategy/deployment \
  --max-time 20 \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" > "$RESPONSE_FILE"

node "$ROOT/src/play.js" "$STATE_FILE" "$RESPONSE_FILE" "$OBSERVED_GAME_ID"
