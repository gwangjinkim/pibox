import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { getModels } from "@earendil-works/pi-ai";

// Live model sync for opencode + opencode-go.
//
// Problem: pi's built-in catalog is a build-time snapshot. Models the gateway
// retires stay listed (selection then fails at request time) and models it
// adds stay invisible until the next pi release.
//
// This extension replaces both providers' model lists with the gateway's own
// live `/v1/models` index at session start:
//   opencode    <- https://opencode.ai/zen/v1/models
//   opencode-go <- https://opencode.ai/zen/go/v1/models
//
// Notes:
// - The endpoints answer without auth, so the sync runs before/without keys.
// - Transient failures keep the bundled catalog (never break startup).
// - Variants map 1:1 onto pi APIs: chat-completions -> openai-completions,
//   responses -> openai-responses, messages -> anthropic-messages,
//   generate-content -> google-generative-ai.
// - Cost: live index already carries USD per 1M tokens for text (e.g. 0.1 in / 0.2 out
//   for muse-spark, 10 in / 50 out for claude-fable). Pass through rounded to 6dp;
//   cache.write is present for some models, absent (0) for others.
// - Reasoning compat (thinkingFormat / requiresReasoningContentOnAssistant-
//   Messages) and thinkingLevelMap can't be derived from the live feed, so
//   entries inherit them from the bundled model with the same id when one
//   exists. Unknown new models get a safe default (reasoning flag from the
//   live capabilities, no thinking map).

const SOURCES: Record<string, { url: string; baseUrl: string; apiKey: string }> = {
  opencode: {
    url: "https://opencode.ai/zen/v1/models",
    baseUrl: "https://opencode.ai/zen/v1",
    apiKey: "$OPENCODE_API_KEY",
  },
  "opencode-go": {
    url: "https://opencode.ai/zen/go/v1/models",
    baseUrl: "https://opencode.ai/zen/go/v1",
    apiKey: "$OPENCODE_API_KEY",
  },
};

const VARIANT_TO_API: Record<string, string> = {
  "chat-completions": "openai-completions",
  responses: "openai-responses",
  messages: "anthropic-messages",
  "generate-content": "google-generative-ai",
};

interface LiveEntry {
  id: string;
  name?: string;
  api?: Record<string, unknown>;
  capabilities?: { reasoning?: { supported?: boolean } };
  modalities?: { input?: string[] };
  cost?: { text?: { input?: { price?: number; cache?: { read?: number; write?: number } }; output?: { price?: number } } };
  limit?: { context?: number; output?: number };
}

interface BundledEntry {
  id: string;
  reasoning?: boolean;
  thinkingLevelMap?: Record<string, string | null>;
  compat?: Record<string, unknown>;
  contextWindow?: number;
  maxTokens?: number;
}

function toPer1M(pricePer1M: number | undefined): number {
  if (typeof pricePer1M !== "number" || !Number.isFinite(pricePer1M)) return 0;
  return Math.round(pricePer1M * 1e6) / 1e6;
}

interface LiveModel {
  id: string;
  name: string;
  api: string;
  baseUrl: string;
  reasoning: boolean;
  thinkingLevelMap?: Record<string, string | null>;
  input: string[];
  cost: { input: number; output: number; cacheRead: number; cacheWrite: number };
  contextWindow: number;
  maxTokens: number;
  compat?: Record<string, unknown>;
}
function buildEntry(providerId: string, baseUrl: string, live: LiveEntry, bundledById: Map<string, BundledEntry>): LiveModel | null {
  const variant = Object.keys(live.api ?? {})[0];
  const api = variant ? VARIANT_TO_API[variant] : undefined;
  if (!api) return null;
  const bundled = bundledById.get(live.id);
  const text = live.cost?.text;
  const modalities: string[] = live.modalities?.input ?? [];
  const root = baseUrl.replace(/\/v1$/, "");
  const entryBaseUrl = api === "google-generative-ai" ? root : `${root}/v1`;
  const thinkingLevelMap = bundled?.thinkingLevelMap;

  return {
    id: live.id,
    name: live.name ?? live.id,
    api,
    baseUrl: entryBaseUrl,
    reasoning: live.capabilities?.reasoning?.supported ?? bundled?.reasoning ?? false,
    ...(thinkingLevelMap ? { thinkingLevelMap } : {}),
    input: modalities.some((m) => m === "image" || m.startsWith("image/")) ? ["text", "image"] : ["text"],
    cost: {
      input: toPer1M(text?.input?.price),
      output: toPer1M(text?.output?.price),
      cacheRead: toPer1M(text?.input?.cache?.read),
      cacheWrite: toPer1M(text?.input?.cache?.write),
    },
    contextWindow: live.limit?.context ?? bundled?.contextWindow ?? 128000,
    maxTokens: live.limit?.output ?? bundled?.maxTokens ?? 16384,
    ...(bundled?.compat ? { compat: bundled.compat } : {}),
  };
}

async function fetchLive(url: string): Promise<LiveEntry[] | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15000);
  try {
    const res = await fetch(url, {
      headers: { accept: "application/json", "accept-encoding": "identity" },
      signal: controller.signal,
    });
    if (!res.ok) return null;
    const json: unknown = await res.json();
    const data =
      Array.isArray(json) ? json : json && typeof json === "object" && "data" in json && Array.isArray(json.data) ? json.data : null;
    if (!data) return null;
    return data.filter(
      (e): e is LiveEntry => !!e && typeof e === "object" && "id" in e && typeof e.id === "string",
    );
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

function modelsFromLive(providerId: string, baseUrl: string, live: LiveEntry[]): LiveModel[] {
  const bundledById = new Map<string, BundledEntry>();
  try {
    for (const m of getModels(providerId)) bundledById.set(m.id, m as BundledEntry);
  } catch {
    // No bundled fallback; new models still register with safe defaults.
  }
  const models: LiveModel[] = [];
  for (const entry of live) {
    const model = buildEntry(providerId, baseUrl, entry, bundledById);
    if (model) models.push(model);
  }
  return models;
}

const CACHE_PATH = join(homedir(), ".pi", "agent", "cache", "live-opencode-models.json");

interface LiveCache {
  fetchedAt: string;
  models: Record<string, LiveModel[]>;
}

function readCache(): LiveCache | null {
  try {
    if (!existsSync(CACHE_PATH)) return null;
    const parsed: unknown = JSON.parse(readFileSync(CACHE_PATH, "utf8"));
    if (!parsed || typeof parsed !== "object") return null;
    if (!("models" in parsed) || !parsed.models || typeof parsed.models !== "object") return null;
    return parsed as LiveCache;
  } catch {
    return null;
  }
}

function writeCache(models: Record<string, LiveModel[]>) {
  try {
    mkdirSync(join(homedir(), ".pi", "agent", "cache"), { recursive: true });
    writeFileSync(CACHE_PATH, `${JSON.stringify({ fetchedAt: new Date().toISOString(), models }, null, 2)}\n`, "utf8");
  } catch {
    // Cache is best-effort; live registration already happened.
  }
}

function applyModels(pi: ExtensionAPI, providerId: string, models: LiveModel[]) {
  const source = SOURCES[providerId];
  if (!source || models.length === 0) return;
  pi.registerProvider(providerId, {
    baseUrl: source.baseUrl,
    apiKey: source.apiKey,
    models: models as Parameters<ExtensionAPI["registerProvider"]>[1]["models"],
  });
}

async function refreshLive(pi: ExtensionAPI): Promise<{ notes: string[]; models: Record<string, LiveModel[]> }> {
  const notes: string[] = [];
  const models: Record<string, LiveModel[]> = {};
  await Promise.all(
    ["opencode", "opencode-go"].map(async (providerId) => {
      const source = SOURCES[providerId];
      const live = await fetchLive(source.url);
      if (!live) return;
      const built = modelsFromLive(providerId, source.baseUrl, live);
      if (built.length === 0) return;
      models[providerId] = built;
    }),
  );
  for (const [providerId, built] of Object.entries(models)) {
    applyModels(pi, providerId, built);
    notes.push(`${providerId}: ${built.length} live models`);
  }
  return { notes, models };
}

// Disk cache: last good live list, applied synchronously at extension load so
// --list-models and model resolution see live data in the same startup (no
// waiting on a fetch during startup).
// Refreshed on every session start (15s fetch timeout, awaited by emit) and
// via /live-models; entries carry fetchedAt so staleness is visible.
export default function liveOpencodeModels(pi: ExtensionAPI) {
  // Load-time: apply last good list synchronously. registerProvider calls made
  // during extension load are queued and flushed before --list-models runs,
  // so even the very first startup lists live models.
  try {
    const cached = readCache();
    if (cached) {
      for (const [providerId, models] of Object.entries(cached.models)) applyModels(pi, providerId, models);
    }
  } catch {
    // Corrupt cache is ignored; bundled catalog stays in place.
  }

  // Session start: refresh, then persist the new list for the next cold startup.
  pi.on("session_start", async (_event, ctx) => {
    try {
      const { notes, models } = await refreshLive(pi);
      if (notes.length > 0) {
        writeCache(models);
        ctx.ui.notify(`live models — ${notes.join("; ")}`, "info");
      }
    } catch {
      // Best-effort: bundled or cached catalog stays in place.
    }
  });

  pi.registerCommand("live-models", {
    description: "Refresh opencode + opencode-go model lists from the live gateway index",
    handler: async (_args, ctx) => {
      const { notes, models } = await refreshLive(pi);
      if (notes.length > 0) writeCache(models);
      ctx.ui.notify(
        notes.length > 0 ? `live models — ${notes.join("; ")}` : "live model sync failed; kept bundled catalog",
        notes.length > 0 ? "info" : "error",
      );
    },
  });
}
