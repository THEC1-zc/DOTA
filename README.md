# DOTA Agent

Small Node.js bot for [Defense of the Agents](https://www.defenseoftheagents.com/).

## What it does

- Registers an agent and saves credentials locally
- Reads the current battlefield state
- Chooses a lane, ability, and optional recall action
- Posts a deployment update to the live game API

## Local quick start

```bash
bash scripts/register.sh THEC1-BOT
bash scripts/play.sh
bash scripts/stats.sh
```

To run it on a schedule:

```bash
*/2 * * * * cd /Users/fabio/workspace/DOTA && bash scripts/play.sh >> /tmp/dota-agent.log 2>&1
```

## GitHub Actions

This repo includes a workflow that runs automatically every 5 minutes and can also be started manually.

Important: GitHub Actions cron does not support 2-minute intervals. To compensate, each scheduled workflow run performs multiple in-run check-ins roughly every 2 minutes.

### Repository secrets

Add this secret in GitHub:

- `DOTA_API_KEY`: the API key for `THEC1-BOT`

Optional:

- `DOTA_STRATEGY_JSON`: full JSON strategy override

Example `DOTA_STRATEGY_JSON`:

```json
{"preferredHeroClass":"mage","laneFocus":"mid","behavior":"Defend weak lanes first, then pressure the best push lane."}
```

### Enable the bot

1. Push this repo to GitHub
2. Add the `DOTA_API_KEY` repository secret
3. Open the `DOTA Agent` workflow in GitHub Actions
4. Run it once with `Run workflow`
5. Leave Actions enabled and it will continue every 5 minutes

## Dashboard

A small browser dashboard lives in [`docs/index.html`](/Users/fabio/workspace/DOTA/docs/index.html).

It fetches:

- AI leaderboard stats for the bot
- live hero state by scanning active game slots

The `Publish Dashboard` workflow deploys it to GitHub Pages on push.

## Strategy

Edit [`config/strategy.example.json`](/Users/fabio/workspace/DOTA/config/strategy.example.json) and save your own copy as `config/strategy.json`.

The bot uses a simple heuristic:

- if your hero is missing, it performs an initial deployment
- if your hero is very low, it recalls
- if your side is under pressure, it rotates to defend the weakest lane
- otherwise it pressures the best lane to push
- when an ability choice is available, it picks the highest-ranked option for your class

## Files

- [`src/play.js`](/Users/fabio/workspace/DOTA/src/play.js): one full observe-think-act cycle
- [`scripts/register.sh`](/Users/fabio/workspace/DOTA/scripts/register.sh): registers and stores credentials
- [`scripts/play.sh`](/Users/fabio/workspace/DOTA/scripts/play.sh): runs a live check-in against the API
- [`scripts/stats.sh`](/Users/fabio/workspace/DOTA/scripts/stats.sh): shows aggregate stats and current live hero state
- [`src/lib/game.js`](/Users/fabio/workspace/DOTA/src/lib/game.js): API + decision helpers
- [`.github/workflows/dota-agent.yml`](/Users/fabio/workspace/DOTA/.github/workflows/dota-agent.yml): scheduled GitHub Actions runner
- [`.github/workflows/pages.yml`](/Users/fabio/workspace/DOTA/.github/workflows/pages.yml): GitHub Pages deployment for the dashboard
- [`docs/index.html`](/Users/fabio/workspace/DOTA/docs/index.html): web dashboard for bot stats
