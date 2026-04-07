#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT/config"
DOCS_DIR="$ROOT/docs"
STATUS_FILE="$DOCS_DIR/status.json"
AGENT_NAME="$(jq -r '.agentName' "$CONFIG_DIR/credentials.json")"
GAME_ID="$(jq -r '.lastGameId // empty' "$CONFIG_DIR/runtime.json" 2>/dev/null || true)"
LEADERBOARD_FILE="$(mktemp)"
STATE_FILE="$(mktemp)"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cleanup() {
  rm -f "$LEADERBOARD_FILE" "$STATE_FILE"
}
trap cleanup EXIT

mkdir -p "$DOCS_DIR"

curl -sS --max-time 20 'https://wc2-agentic-dev-3o6un.ondigitalocean.app/api/leaderboard?type=ai' > "$LEADERBOARD_FILE"

if [[ -n "$GAME_ID" ]]; then
  curl -sS --max-time 20 "https://wc2-agentic-dev-3o6un.ondigitalocean.app/api/game/state?game=$GAME_ID" > "$STATE_FILE" || true
fi

if [[ ! -s "$STATE_FILE" ]] || ! jq -e --arg name "$AGENT_NAME" 'type == "object" and (.heroes | type == "array") and any(.heroes[]?; .name == $name)' "$STATE_FILE" >/dev/null 2>&1; then
  for candidate_game in 1 2 3 4 5 6 7 8 9 10; do
    curl -sS --max-time 20 "https://wc2-agentic-dev-3o6un.ondigitalocean.app/api/game/state?game=$candidate_game" > "$STATE_FILE" || true
    if jq -e --arg name "$AGENT_NAME" 'type == "object" and (.heroes | type == "array") and any(.heroes[]?; .name == $name)' "$STATE_FILE" >/dev/null 2>&1; then
      GAME_ID="$candidate_game"
      break
    fi
  done
fi

jq -n \
  --arg agentName "$AGENT_NAME" \
  --arg updatedAt "$TIMESTAMP" \
  --arg gameId "${GAME_ID:-}" \
  --argjson leaderboard "$(cat "$LEADERBOARD_FILE" 2>/dev/null || echo '[]')" \
  --argjson state "$(cat "$STATE_FILE" 2>/dev/null || echo '{}')" \
  --argjson runtime "$(cat "$CONFIG_DIR/runtime.json" 2>/dev/null || echo '{}')" '
    def leaderboard_entry($name):
      ($leaderboard | map(select(.name == $name)) | .[0]) // {
        name: $name,
        games_won: 0,
        games_played: 0,
        note: "Not yet present in AI leaderboard"
      };

    def live_hero($name):
      ($state.heroes // [] | map(select(.name == $name)) | .[0]) // null;

    ($agentName) as $name
    | (leaderboard_entry($name)) as $entry
    | (live_hero($name)) as $hero
    | {
        agentName: $name,
        updatedAt: $updatedAt,
        leaderboard: ($entry + {
          games_lost: (($entry.games_played // 0) - ($entry.games_won // 0)),
          win_rate: (if ($entry.games_played // 0) > 0
            then (((($entry.games_won // 0) / ($entry.games_played // 0)) * 1000 | round) / 10)
            else null
          end)
        }),
        live: {
          gameId: (if $gameId == "" then null else ($gameId | tonumber) end),
          hero: $hero
        },
        runtime: $runtime
      }
  ' > "$STATUS_FILE"
