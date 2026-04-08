#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT/config"
DOCS_DIR="$ROOT/docs"
STATUS_FILE="$DOCS_DIR/status.json"
PREVIOUS_STATUS_FILE="${TMPDIR:-/tmp}/dota-status-previous.json"
AGENT_NAME="$(jq -r '.agentName' "$CONFIG_DIR/credentials.json")"
GAME_ID="$(jq -r '.lastGameId // empty' "$CONFIG_DIR/runtime.json" 2>/dev/null || true)"
LEADERBOARD_FILE="$(mktemp)"
STATE_FILE="$(mktemp)"
PREV_ACTIVE_STATE_FILE="$(mktemp)"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cleanup() {
  rm -f "$LEADERBOARD_FILE" "$STATE_FILE" "$PREV_ACTIVE_STATE_FILE"
}
trap cleanup EXIT

mkdir -p "$DOCS_DIR"

if [[ -f "$STATUS_FILE" ]]; then
  cp "$STATUS_FILE" "$PREVIOUS_STATUS_FILE"
else
  printf '{}\n' > "$PREVIOUS_STATUS_FILE"
fi

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

PREV_ACTIVE_GAME_ID="$(jq -r '.tracked.active_game_id // empty' "$PREVIOUS_STATUS_FILE" 2>/dev/null || true)"
if [[ -n "$PREV_ACTIVE_GAME_ID" ]]; then
  curl -sS --max-time 20 "https://wc2-agentic-dev-3o6un.ondigitalocean.app/api/game/state?game=$PREV_ACTIVE_GAME_ID" > "$PREV_ACTIVE_STATE_FILE" || true
fi

if [[ ! -s "$LEADERBOARD_FILE" ]]; then
  printf '[]\n' > "$LEADERBOARD_FILE"
fi

if [[ ! -s "$STATE_FILE" ]]; then
  printf '{}\n' > "$STATE_FILE"
fi

if [[ ! -s "$PREV_ACTIVE_STATE_FILE" ]]; then
  printf '{}\n' > "$PREV_ACTIVE_STATE_FILE"
fi

jq -n \
  --arg agentName "$AGENT_NAME" \
  --arg updatedAt "$TIMESTAMP" \
  --arg gameId "${GAME_ID:-}" \
  --slurpfile leaderboardFile "$LEADERBOARD_FILE" \
  --slurpfile stateFile "$STATE_FILE" \
  --slurpfile runtimeFile "$CONFIG_DIR/runtime.json" \
  --slurpfile previousFile "$PREVIOUS_STATUS_FILE" \
  --slurpfile prevActiveStateFile "$PREV_ACTIVE_STATE_FILE" '
    ($leaderboardFile[0] // []) as $leaderboard
    | ($stateFile[0] // {}) as $state
    | ($runtimeFile[0] // {}) as $runtime
    | ($previousFile[0] // {}) as $previous
    | ($prevActiveStateFile[0] // {}) as $prevActiveState
    |
    def leaderboard_entry($name):
      ($leaderboard | map(select(.name == $name)) | .[0]) // {
        name: $name,
        games_won: 0,
        games_played: 0,
        note: "Not yet present in AI leaderboard"
      };

    def live_hero($name):
      ($state.heroes // [] | map(select(.name == $name)) | .[0]) // null;

    def tracked_base:
      ($previous.tracked // {
        tracked_games_played: 0,
        tracked_games_won: 0,
        tracked_games_lost: 0,
        completed_game_ids: [],
        active_game_id: null,
        active_faction: null
      });

    ($agentName) as $name
    | (leaderboard_entry($name)) as $entry
    | (live_hero($name)) as $hero
    | tracked_base as $tracked0
    | ($tracked0.active_game_id) as $prevGameId
    | ($tracked0.active_faction) as $prevFaction
    | ($tracked0.completed_game_ids // []) as $completed
    | (if ($prevGameId != null and ($completed | index($prevGameId) | not) and ($prevActiveState.winner // null) != null)
        then ($tracked0 + {
          tracked_games_played: (($tracked0.tracked_games_played // 0) + 1),
          tracked_games_won: (($tracked0.tracked_games_won // 0) + (if $prevActiveState.winner == $prevFaction then 1 else 0 end)),
          tracked_games_lost: (($tracked0.tracked_games_lost // 0) + (if $prevActiveState.winner != $prevFaction then 1 else 0 end)),
          completed_game_ids: ($completed + [$prevGameId]),
          active_game_id: null,
          active_faction: null
        })
        else $tracked0
      end) as $tracked1
    | (if $hero != null
        then ($tracked1 + {
          active_game_id: (if $gameId == "" then null else ($gameId | tonumber) end),
          active_faction: $hero.faction
        })
        else $tracked1
      end) as $tracked2
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
        runtime: $runtime,
        tracked: ($tracked2 + {
          tracked_win_rate: (if ($tracked2.tracked_games_played // 0) > 0
            then (((($tracked2.tracked_games_won // 0) / ($tracked2.tracked_games_played // 0)) * 1000 | round) / 10)
            else null
          end)
        })
      }
  ' > "$STATUS_FILE"
