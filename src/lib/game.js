import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const ROOT = process.cwd();
const CONFIG_DIR = path.join(ROOT, "config");
const CREDENTIALS_PATH = path.join(CONFIG_DIR, "credentials.json");
const STRATEGY_PATH = path.join(CONFIG_DIR, "strategy.json");
const RUNTIME_PATH = path.join(CONFIG_DIR, "runtime.json");

const CLASS_ABILITIES = {
  melee: ["divine_shield", "cleave", "thorns", "fortitude", "fury"],
  ranged: ["volley", "critical_strike", "bloodlust", "fortitude", "fury"],
  mage: ["tornado", "fireball", "raise_skeleton", "fortitude", "fury"],
};

export async function ensureConfigDir() {
  await mkdir(CONFIG_DIR, { recursive: true });
}

export async function readJson(filePath, fallback = null) {
  try {
    const raw = await readFile(filePath, "utf8");
    return JSON.parse(raw);
  } catch (error) {
    if (error.code === "ENOENT") {
      return fallback;
    }

    throw error;
  }
}

export async function writeJson(filePath, value) {
  await ensureConfigDir();
  await writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

export async function loadCredentials() {
  return readJson(CREDENTIALS_PATH);
}

export async function loadStrategy() {
  return readJson(STRATEGY_PATH, {});
}

export async function loadRuntime() {
  return readJson(RUNTIME_PATH, {});
}

export async function saveRuntime(runtime) {
  return writeJson(RUNTIME_PATH, runtime);
}

export async function saveCredentials(credentials) {
  return writeJson(CREDENTIALS_PATH, credentials);
}

function laneEntries(state, faction) {
  const enemyFaction = faction === "human" ? "orc" : "human";
  return Object.entries(state.lanes).map(([lane, info]) => {
    const allyUnits = info[faction] ?? 0;
    const enemyUnits = info[enemyFaction] ?? 0;
    const alliedTower = state.towers.find((tower) => tower.faction === faction && tower.lane === lane);
    const enemyTower = state.towers.find((tower) => tower.faction === enemyFaction && tower.lane === lane);
    const towerRatio = alliedTower?.maxHp ? alliedTower.hp / alliedTower.maxHp : 1;
    const enemyTowerRatio = enemyTower?.maxHp ? enemyTower.hp / enemyTower.maxHp : 1;

    return {
      lane,
      allyUnits,
      enemyUnits,
      frontline: info.frontline ?? 0,
      alliedTower,
      enemyTower,
      towerRatio,
      enemyTowerRatio,
    };
  });
}

function chooseAbility(heroClass, choices, learned) {
  if (!Array.isArray(choices) || choices.length === 0) {
    return undefined;
  }

  const ranking = CLASS_ABILITIES[heroClass] ?? ["fortitude", "fury"];
  const levels = new Map((learned ?? []).map((ability) => [ability.id, ability.level]));

  return [...choices].sort((left, right) => {
    const leftRank = ranking.indexOf(left);
    const rightRank = ranking.indexOf(right);
    const leftScore = leftRank === -1 ? 999 : leftRank;
    const rightScore = rightRank === -1 ? 999 : rightRank;
    if (leftScore !== rightScore) {
      return leftScore - rightScore;
    }

    return (levels.get(left) ?? 0) - (levels.get(right) ?? 0);
  })[0];
}

function chooseInitialLane(strategy) {
  return strategy.laneFocus ?? "mid";
}

function chooseInitialClass(strategy) {
  return strategy.preferredHeroClass ?? "mage";
}

function chooseLaneForHero(state, hero, strategy) {
  const lanes = laneEntries(state, hero.faction);
  const defendCandidate = [...lanes].sort((a, b) => {
    const aPressure = bPressureScore(a);
    const bPressure = bPressureScore(b);
    return bPressure - aPressure;
  })[0];

  const pushCandidate = [...lanes].sort((a, b) => {
    const aValue = pushScore(a);
    const bValue = pushScore(b);
    return bValue - aValue;
  })[0];

  const ownBaseRatio = state.bases[hero.faction].hp / state.bases[hero.faction].maxHp;
  if (ownBaseRatio < 0.45 || bPressureScore(defendCandidate) > 18) {
    return defendCandidate.lane;
  }

  if (strategy.laneFocus) {
    const focused = lanes.find((lane) => lane.lane === strategy.laneFocus);
    if (focused && bPressureScore(focused) < 10) {
      return focused.lane;
    }
  }

  return pushCandidate.lane;
}

function bPressureScore(lane) {
  const deficit = lane.enemyUnits - lane.allyUnits;
  const frontlinePenalty = lane.frontline < 0 ? Math.abs(lane.frontline) / 4 : 0;
  const towerPenalty = lane.alliedTower?.alive === false ? 12 : (1 - lane.towerRatio) * 10;
  return deficit * 3 + frontlinePenalty + towerPenalty;
}

function pushScore(lane) {
  const unitLead = lane.allyUnits - lane.enemyUnits;
  const frontlineBonus = lane.frontline > 0 ? lane.frontline / 5 : lane.frontline / 10;
  const enemyTowerBonus = lane.enemyTower?.alive === false ? 8 : (1 - lane.enemyTowerRatio) * 10;
  return unitLead * 2 + frontlineBonus + enemyTowerBonus;
}

function shouldRecall(hero, runtime) {
  if (!hero.alive || hero.maxHp <= 0) {
    return false;
  }

  const hpRatio = hero.hp / hero.maxHp;
  const lastRecallAt = runtime.lastRecallAt ?? 0;
  const cooldownMs = 120000;
  return hpRatio <= 0.22 && Date.now() - lastRecallAt > cooldownMs;
}

export function decideDeployment(state, credentials, strategy, runtime = {}) {
  const hero = state.heroes.find((candidate) => candidate.name === credentials.agentName);

  if (!hero) {
    const heroLane = chooseInitialLane(strategy);
    const heroClass = chooseInitialClass(strategy);
    return {
      payload: {
        heroClass,
        heroLane,
        message: `Joining ${heroLane} as ${heroClass}`,
      },
      runtimeUpdate: runtime,
      summary: `Initial deployment to ${heroLane} as ${heroClass}`,
    };
  }

  const abilityChoice = chooseAbility(hero.class, hero.abilityChoices, hero.abilities);
  const heroLane = chooseLaneForHero(state, hero, strategy);
  const runtimeUpdate = { ...runtime };

  if (shouldRecall(hero, runtime)) {
    runtimeUpdate.lastRecallAt = Date.now();
    return {
      payload: {
        heroClass: hero.class,
        heroLane,
        abilityChoice,
        action: "recall",
        message: `Recalling from ${hero.lane} at ${hero.hp}/${hero.maxHp} HP`,
      },
      runtimeUpdate,
      summary: `Recall from ${hero.lane} with ${hero.hp}/${hero.maxHp} HP`,
    };
  }

  const actionBits = [];
  if (hero.lane !== heroLane) {
    actionBits.push(`rotate ${hero.lane} -> ${heroLane}`);
  } else {
    actionBits.push(`hold ${heroLane}`);
  }
  if (abilityChoice) {
    actionBits.push(`skill ${abilityChoice}`);
  }

  return {
    payload: {
      heroClass: hero.class,
      heroLane,
      ...(abilityChoice ? { abilityChoice } : {}),
      message: actionBits.join(" | "),
    },
    runtimeUpdate,
    summary: actionBits.join(", "),
    hero,
  };
}

export { CREDENTIALS_PATH, STRATEGY_PATH, RUNTIME_PATH };
