#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT/config"
AGENT_NAME="${1:-codex-dota-agent-$(date +%s | tail -c 7)}"

mkdir -p "$CONFIG_DIR"

response="$(curl -sS -X POST https://wc2-agentic-dev-3o6un.ondigitalocean.app/api/agents/register \
  --max-time 20 \
  -H "Content-Type: application/json" \
  -d "{\"agentName\":\"$AGENT_NAME\"}")"

printf '%s\n' "$response" | jq --arg agent_name "$AGENT_NAME" '. + {agentName: $agent_name, registeredAt: (now | todate)}' > "$CONFIG_DIR/credentials.json"

printf '%s\n' "$response" | jq --arg agent_name "$AGENT_NAME" '{agentName: $agent_name, credentialsSaved: true}'
