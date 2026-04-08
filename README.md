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

By default, active game discovery scans game slots in descending order (`10 9 8 ... 1`). You can override this with `DOTA_GAME_SCAN_ORDER` if you want to prefer a narrower range such as `5 4 3 2`.

The scheduled workflow currently runs a longer session of 6 check-ins with 110 seconds between them, so the bot keeps playing with much smaller gaps.

### Repository secrets

Add this secret in GitHub:

- `DOTA_API_KEY`: the API key for `THEC1-BOT`

Optional:

- `DOTA_STRATEGY_JSON`: full JSON strategy override

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

Default strategy lives in [`config/strategy.json`](/Users/fabio/workspace/DOTA/config/strategy.json). You can override it locally or through `DOTA_STRATEGY_JSON`.

The current default strategy is:

- `melee`: tank-first build with `divine_shield`, `fortitude`, `thorns`, then damage
- `ranged`: `volley`, `critical_strike`, `bloodlust`, then damage
- `mage`: direct damage first with `fireball`, then `tornado`
- recall under 50% HP whenever recall is available
- on respawn, prefer the lane with fewer enemy heroes, then the lane the enemy is pushing hardest
- during live play, rotate to a different lane if that lane is suffering more than the current one
- when no urgent defense is needed, push the best lane with the fewest enemy hero blockers

## Files

- [`src/play.js`](/Users/fabio/workspace/DOTA/src/play.js): one full observe-think-act cycle
- [`scripts/register.sh`](/Users/fabio/workspace/DOTA/scripts/register.sh): registers and stores credentials
- [`scripts/play.sh`](/Users/fabio/workspace/DOTA/scripts/play.sh): runs a live check-in against the API
- [`scripts/stats.sh`](/Users/fabio/workspace/DOTA/scripts/stats.sh): shows aggregate stats and current live hero state
- [`config/strategy.json`](/Users/fabio/workspace/DOTA/config/strategy.json): default class priorities and lane/recall behavior
- [`src/lib/game.js`](/Users/fabio/workspace/DOTA/src/lib/game.js): API + decision helpers
- [`.github/workflows/dota-agent.yml`](/Users/fabio/workspace/DOTA/.github/workflows/dota-agent.yml): scheduled GitHub Actions runner
- [`.github/workflows/pages.yml`](/Users/fabio/workspace/DOTA/.github/workflows/pages.yml): GitHub Pages deployment for the dashboard
- [`docs/index.html`](/Users/fabio/workspace/DOTA/docs/index.html): web dashboard for bot stats
