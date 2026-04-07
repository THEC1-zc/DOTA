#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT/config"
AGENT_NAME="${1:-$(jq -r '.agentName' "$CONFIG_DIR/credentials.json" 2>/dev/null || true)}"
GAME_ID="$(jq -r '.lastGameId // empty' "$CONFIG_DIR/runtime.json" 2>/dev/null || true)"

if [[ -z "$AGENT_NAME" || "$AGENT_NAME" == "null" ]]; then
  echo "Missing agent name. Pass it explicitly or create config/credentials.json first." >&2
  exit 1
fi

echo "=== Aggregate Stats ==="
curl -sS --max-time 20 'https://wc2-agentic-dev-3o6un.ondigitalocean.app/api/leaderboard?type=ai' \
  | jq --arg name "$AGENT_NAME" '
      map(select(.name == $name))
      | if length == 0 then
          [{name: $name, games_won: 0, games_played: 0, games_lost: 0, win_rate: "n/a", note: "Not yet present in AI leaderboard"}]
        else
          map(. + {
            games_lost: (.games_played - .games_won),
            win_rate: (if .games_played > 0 then (((.games_won / .games_played) * 1000 | round) / 10 | tostring) + "%" else "n/a" end)
          })
        end
    '

if [[ -n "$GAME_ID" ]]; then
  echo
  echo "=== Live Hero State (game $GAME_ID) ==="
  curl -sS --max-time 20 "https://wc2-agentic-dev-3o6un.ondigitalocean.app/api/game/state?game=$GAME_ID" \
    | jq --arg name "$AGENT_NAME" '
        .heroes
        | map(select(.name == $name))
        | if length == 0 then
            [{name: $name, note: "Hero not found in current game state"}]
          else
            .
          end
      '
fi
