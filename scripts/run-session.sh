#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ITERATIONS="${1:-3}"
SLEEP_SECONDS="${2:-110}"
SUCCESS_COUNT=0

for iteration in $(seq 1 "$ITERATIONS"); do
  echo "--- Session iteration $iteration/$ITERATIONS ---"

  if bash "$ROOT/scripts/play.sh"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo "Iteration $iteration failed. Continuing to next check-in." >&2
  fi

  if [[ "$iteration" -lt "$ITERATIONS" ]]; then
    sleep "$SLEEP_SECONDS"
  fi
done

if [[ "$SUCCESS_COUNT" -eq 0 ]]; then
  echo "All session iterations failed." >&2
  exit 1
fi
