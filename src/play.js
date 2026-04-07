import {
  decideDeployment,
  loadCredentials,
  loadRuntime,
  loadStrategy,
  saveRuntime,
  readJson,
} from "./lib/game.js";

const statePath = process.argv[2];
const responsePath = process.argv[3];

const credentials = await loadCredentials();
if (!credentials?.apiKey || !credentials?.agentName) {
  console.error("Missing config/credentials.json. Run: npm run register -- <agent-name>");
  process.exit(1);
}

if (!statePath) {
  console.error("Missing state path. Usage: node src/play.js <state.json> [response.json]");
  process.exit(1);
}

const [strategy, runtime, state, response] = await Promise.all([
  loadStrategy(),
  loadRuntime(),
  readJson(statePath),
  responsePath ? readJson(responsePath, {}) : {},
]);

const decision = decideDeployment(state, credentials, strategy, runtime);

if (responsePath) {
  await saveRuntime({
    ...runtime,
    ...decision.runtimeUpdate,
    lastGameId: response.gameId ?? runtime.lastGameId ?? 1,
    lastPlayedAt: new Date().toISOString(),
    lastDecision: decision.summary,
  });
}

console.log(JSON.stringify({
  agentName: credentials.agentName,
  decision: decision.summary,
  payload: decision.payload,
  response,
}, null, 2));
