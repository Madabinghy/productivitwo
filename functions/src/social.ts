// ── Couche sociale (Phase 1) : pseudos + classement XP global ────────────────
// claimPseudo (réservation unique + opt-in) · recomputeLeaderboards (cron).
// L'XP de classement est RECALCULÉ CÔTÉ SERVEUR depuis les données réelles de
// l'utilisateur (anti-triche) — miroir de app_logic.actionXp/xpForDay.
import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import Anthropic from "@anthropic-ai/sdk";
import { MODELS, logTokenUsage } from "./models";
import { db, FieldValue } from "./db";

const BANNED = ["admin", "fuck", "shit", "putain", "merde", "connard", "nazi"];

// YYYYMMDD en heure de Paris (cohérent avec yyyymmdd côté app).
function parisYmd(d: Date): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Paris",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  })
    .format(d)
    .replace(/-/g, "");
}

function lastYmds(n: number): string[] {
  const out: string[] = [];
  const now = Date.now();
  for (let i = 0; i < n; i++) {
    out.push(parisYmd(new Date(now - i * 86400000)));
  }
  return out;
}

const LEVEL_THRESHOLDS = [0, 30, 80, 200, 450, 800, 1500, 2500, 4000, 7000];
function levelOf(xp: number): number {
  if (xp >= 7000) return 10 + Math.floor((xp - 7000) / 2000);
  let level = 1;
  for (let i = LEVEL_THRESHOLDS.length - 1; i >= 0; i--) {
    if (xp >= LEVEL_THRESHOLDS[i]) {
      level = i + 1;
      break;
    }
  }
  return level;
}

interface XpResult {
  xpTotal: number;
  xpWeek: number;
  xpMonth: number;
  level: number;
}

// XP « activité » serveur : temps 1/h · routine complétée 2 · défi 5 · action Gantt 1.
async function computeUserXp(uid: string): Promise<XpResult> {
  const base = db.collection("users").doc(uid);
  const [sessSnap, hpSnap, actSnap, metaSnap] = await Promise.all([
    base.collection("sessions").get(),
    base.collection("habitProgress").get(),
    base.collection("activities").get(),
    base.collection("data").doc("meta").get(),
  ]);

  // Cibles routines (approx : habitTarget brut, défaut 1).
  const habitTarget = new Map<string, number>();
  for (const a of actSnap.docs) {
    if ((a.get("type") ?? "time") === "habit") {
      habitTarget.set(a.id, (a.get("habitTarget") as number) ?? 1);
    }
  }

  // Temps loggué : total + par jour (Paris).
  let totalMin = 0;
  const minByDay = new Map<string, number>();
  for (const s of sessSnap.docs) {
    const startStr = s.get("startAt") as string | undefined;
    const endStr = s.get("endAt") as string | undefined;
    if (!startStr) continue;
    const start = new Date(startStr);
    const end = endStr ? new Date(endStr) : new Date();
    const min = Math.max(0, Math.round((end.getTime() - start.getTime()) / 60000));
    totalMin += min;
    const ymd = parisYmd(start);
    minByDay.set(ymd, (minByDay.get(ymd) ?? 0) + min);
  }

  // Routines complétées : total + par jour.
  let routinesTotal = 0;
  const routinesByDay = new Map<string, number>();
  for (const hp of hpSnap.docs) {
    const aid = hp.get("activityId") as string | undefined;
    const tgt = aid ? habitTarget.get(aid) : undefined;
    if (tgt === undefined || tgt <= 0) continue;
    const val = (hp.get("value") as number) ?? 0;
    if (val >= tgt) {
      routinesTotal++;
      const ymd = (hp.get("yyyymmdd") as string) ?? "";
      routinesByDay.set(ymd, (routinesByDay.get(ymd) ?? 0) + 1);
    }
  }

  const meta = metaSnap.data() ?? {};
  const challengesDone = (meta.challengesDone as number) ?? 0;
  const ganttByDay = (meta.ganttActionsByDay as Record<string, number>) ?? {};
  const challengeWinsByDay = (meta.challengeWinsByDay as Record<string, number>) ?? {};
  const ganttTotal = Object.values(ganttByDay).reduce((a, b) => a + b, 0);

  const xpTotal =
    Math.floor(totalMin / 60) +
    routinesTotal * 2 +
    challengesDone * 5 +
    ganttTotal;

  const xpForDay = (ymd: string): number =>
    Math.floor((minByDay.get(ymd) ?? 0) / 60) +
    (routinesByDay.get(ymd) ?? 0) * 2 +
    (challengeWinsByDay[ymd] ?? 0) * 5 +
    (ganttByDay[ymd] ?? 0);

  const xpWeek = lastYmds(7).reduce((s, y) => s + xpForDay(y), 0);
  const xpMonth = lastYmds(30).reduce((s, y) => s + xpForDay(y), 0);

  return { xpTotal, xpWeek, xpMonth, level: levelOf(xpTotal) };
}

// Puissance de deck d'invasion = Σ tierStrength(tier) × roster de rouges DISPONIBLES.
// Miroir serveur EXACT de GoldEngine.invasionDeckPower (redPower == tierStrength).
// Source = users/{uid}/data/meta.redRoster (posé par setInvasionArsenal). Les rouges
// déployés sortent du roster → leur puissance disparaît du ladder (auto-équilibrage #6).
function invasionDeckPower(meta: Record<string, unknown> | undefined): number {
  const roster = (meta?.redRoster as Record<string, number> | undefined) ?? {};
  let p = 0;
  for (const tier of Object.keys(roster)) {
    p += tierStrength(tier) * (Number(roster[tier]) || 0);
  }
  return p;
}

async function writeLeaderboardEntry(uid: string, pseudo: string): Promise<void> {
  const xp = await computeUserXp(uid);
  // Or disponible : sert de départage secondaire quand l'XP est à égalité.
  const meta = await db.doc(`users/${uid}/data/meta`).get();
  const gold = (meta.data()?.gold as number) ?? 0;
  const deckPower = invasionDeckPower(meta.data());
  await db.collection("leaderboard_entries").doc(uid).set(
    { pseudo, optedIn: true, ...xp, gold, deckPower, updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
}

// POST { pseudo, optedIn }  ·  Authorization: Bearer <firebase-id-token>
export const claimPseudo = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

    const authHeader = (req.headers.authorization as string | undefined) ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing Authorization header" }); return;
    }
    let uid: string;
    try {
      uid = (await admin.auth().verifyIdToken(authHeader.slice(7).trim())).uid;
    } catch {
      res.status(401).json({ error: "Token invalide ou expiré" }); return;
    }

    const { pseudo, optedIn } = req.body as { pseudo?: string; optedIn?: boolean };
    const raw = (pseudo ?? "").trim();
    if (!/^[a-zA-Z0-9_]{3,20}$/.test(raw)) {
      res.status(400).json({ error: "Pseudo invalide (3-20 caractères : lettres, chiffres, _)" });
      return;
    }
    const lower = raw.toLowerCase();
    if (BANNED.some((w) => lower.includes(w))) {
      res.status(400).json({ error: "Pseudo non autorisé" }); return;
    }

    const pseudoRef = db.collection("pseudos").doc(lower);
    const profileRef = db.collection("profiles").doc(uid);
    try {
      await db.runTransaction(async (tx) => {
        const existing = await tx.get(pseudoRef);
        if (existing.exists && existing.get("uid") !== uid) {
          throw new Error("taken");
        }
        const prof = await tx.get(profileRef);
        const oldLower = prof.get("pseudoLower") as string | undefined;
        if (oldLower && oldLower !== lower) {
          tx.delete(db.collection("pseudos").doc(oldLower));
        }
        tx.set(pseudoRef, { uid });
        tx.set(
          profileRef,
          {
            pseudo: raw,
            pseudoLower: lower,
            optedIn: optedIn === true,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      });
    } catch (e) {
      if ((e as Error).message === "taken") {
        res.status(409).json({ error: "Ce pseudo est déjà pris" }); return;
      }
      console.error("claimPseudo failed", e);
      res.status(500).json({ error: "Erreur serveur" }); return;
    }

    // Entrée de classement immédiate (ou retrait si opt-out).
    try {
      if (optedIn === true) {
        await writeLeaderboardEntry(uid, raw);
      } else {
        await db.collection("leaderboard_entries").doc(uid).set(
          { optedIn: false, updatedAt: FieldValue.serverTimestamp() },
          { merge: true },
        );
      }
    } catch (e) {
      console.error("leaderboard entry failed (non bloquant)", e);
    }

    res.status(200).json({ success: true, pseudo: raw });
  },
);

// Recalcule les classements de tous les profils opt-in (anti-triche serveur).
export const recomputeLeaderboards = onSchedule(
  { schedule: "every 3 hours", timeZone: "Europe/Paris" },
  async () => {
    const profs = await db.collection("profiles").where("optedIn", "==", true).get();
    for (const p of profs.docs) {
      try {
        await writeLeaderboardEntry(p.id, (p.get("pseudo") as string) ?? "");
      } catch (e) {
        console.error("recompute failed", p.id, e);
      }
    }
    console.log(`recomputeLeaderboards: ${profs.size} profils`);
  },
);

// ── Phase 2 : bibliothèque de challenges + super-Orion ───────────────────────

async function authUid(req: { headers: { authorization?: string } }): Promise<string | null> {
  const h = (req.headers.authorization as string | undefined) ?? "";
  if (!h.startsWith("Bearer ")) return null;
  try {
    return (await admin.auth().verifyIdToken(h.slice(7).trim())).uid;
  } catch {
    return null;
  }
}

// POST { title, description } · soumet un challenge à la modération super-Orion.
export const submitChallenge = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }
    const uid = await authUid(req);
    if (!uid) { res.status(401).json({ error: "Non autorisé" }); return; }

    const { title, description } = req.body as { title?: string; description?: string };
    const t = (title ?? "").trim();
    const d = (description ?? "").trim();
    if (t.length < 3 || t.length > 80) {
      res.status(400).json({ error: "Titre : 3 à 80 caractères" }); return;
    }
    if (d.length > 300) {
      res.status(400).json({ error: "Description : 300 caractères max" }); return;
    }

    const profSnap = await db.collection("profiles").doc(uid).get();
    const pseudo = (profSnap.get("pseudo") as string | undefined) ?? "Anonyme";

    await db.collection("challenge_submissions").add({
      uid,
      pseudo,
      title: t,
      description: d,
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
    });
    res.status(200).json({ success: true });
  },
);

// POST { libraryId, subscribe } · (dé)abonnement à un challenge de la bibliothèque.
export const subscribeChallenge = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }
    const uid = await authUid(req);
    if (!uid) { res.status(401).json({ error: "Non autorisé" }); return; }

    const { libraryId, subscribe } = req.body as { libraryId?: string; subscribe?: boolean };
    if (!libraryId) { res.status(400).json({ error: "libraryId requis" }); return; }
    const libRef = db.collection("challenge_library").doc(libraryId);
    const lib = await libRef.get();
    if (!lib.exists) { res.status(404).json({ error: "Challenge introuvable" }); return; }

    const subRef = db.collection("users").doc(uid).collection("challenge_subs").doc(libraryId);
    const already = (await subRef.get()).exists;
    if (subscribe === false) {
      if (already) {
        await subRef.delete();
        await libRef.update({ subscriberCount: FieldValue.increment(-1) });
      }
    } else {
      if (!already) {
        await subRef.set({
          libraryId,
          title: lib.get("title"),
          subscribedAt: FieldValue.serverTimestamp(),
        });
        await libRef.update({ subscriberCount: FieldValue.increment(1) });
      }
    }
    res.status(200).json({ success: true });
  },
);

// Cron quotidien : super-Orion modère/catégorise/dédoublonne les soumissions
// (LLM Haiku) → écrit les challenges approuvés dans challenge_library.
export const superOrionCron = onSchedule(
  { schedule: "every 24 hours", timeZone: "Europe/Paris", secrets: ["ANTHROPIC_API_KEY"] },
  async () => {
    const pending = await db.collection("challenge_submissions")
      .where("status", "==", "pending")
      .limit(30)
      .get();
    if (pending.empty) { console.log("superOrion: rien à traiter"); return; }

    const lib = await db.collection("challenge_library")
      .where("status", "==", "approved")
      .limit(200)
      .get();
    const existing = lib.docs.map((d) => ({ id: d.id, title: d.get("title") as string }));

    const subs = pending.docs.map((d) => ({
      id: d.id,
      title: d.get("title") as string,
      description: (d.get("description") as string) ?? "",
    }));

    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) { console.error("superOrion: ANTHROPIC_API_KEY manquante"); return; }
    const client = new Anthropic({ apiKey });

    const prompt = `Tu es "super-Orion", le curateur d'une bibliothèque de défis de productivité partagée entre utilisateurs.
Pour chaque soumission, décide :
- "approve" : défi clair, sain, utile → fournis title (nettoyé, <60 car.), description (<200 car.), category (parmi: sport, focus, bien-être, apprentissage, social, créativité, autre), durationMin (5-90), xp (5-50 selon difficulté/effort).
- "reject" : inapproprié, spam, dangereux, vide de sens.
- "merge" : quasi-doublon d'un défi existant → fournis mergeId (l'id existant).

Soumissions :
${JSON.stringify(subs)}

Bibliothèque existante (pour détecter les doublons) :
${JSON.stringify(existing)}

Réponds UNIQUEMENT avec un tableau JSON, un objet par soumission :
[{"id":"<submissionId>","action":"approve|reject|merge","title":"","description":"","category":"","durationMin":0,"xp":0,"mergeId":""}]`;

    const response = await client.messages.create({
      model: MODELS.HAIKU,
      max_tokens: 4096,
      messages: [{ role: "user", content: prompt }],
    });
    logTokenUsage("super_orion", MODELS.HAIKU, response.usage as Parameters<typeof logTokenUsage>[2]);

    const text = response.content
      .filter((b): b is Anthropic.TextBlock => b.type === "text")
      .map((b) => b.text)
      .join("");
    const jsonStr = text.slice(text.indexOf("["), text.lastIndexOf("]") + 1);
    let decisions: Array<Record<string, unknown>>;
    try {
      decisions = JSON.parse(jsonStr);
    } catch (e) {
      console.error("superOrion: parse JSON échoué", e, text.slice(0, 200));
      return;
    }

    const subById = new Map(pending.docs.map((d) => [d.id, d]));
    let approved = 0, merged = 0, rejected = 0;
    for (const dec of decisions) {
      const subId = dec.id as string;
      const subDoc = subById.get(subId);
      if (!subDoc) continue;
      const action = dec.action as string;
      if (action === "approve") {
        await db.collection("challenge_library").add({
          title: (dec.title as string) ?? subDoc.get("title"),
          description: (dec.description as string) ?? "",
          category: (dec.category as string) ?? "autre",
          suggestedDurationMin: (dec.durationMin as number) ?? 15,
          xpReward: (dec.xp as number) ?? 10,
          createdByPseudo: subDoc.get("pseudo") ?? "Anonyme",
          status: "approved",
          subscriberCount: 0,
          createdAt: FieldValue.serverTimestamp(),
        });
        await subDoc.ref.update({ status: "approved" });
        approved++;
      } else if (action === "merge") {
        const mergeId = dec.mergeId as string | undefined;
        await subDoc.ref.update({ status: "merged", mergedInto: mergeId ?? null });
        merged++;
      } else {
        await subDoc.ref.update({ status: "rejected" });
        rejected++;
      }
    }
    console.log(`superOrion: ${approved} approuvés, ${merged} fusionnés, ${rejected} rejetés`);
  },
);

// ── « Le Monde » : relâcher / suivre des nuisibles-routines ──────────────────

// POST { id, routineId, name, freq, target, unit?, iconCode?, domainName?, hp, streak }
// Crée un nuisible public (routine relâchée). Le jeton de relâche est consommé
// côté client (modèle « trust client » de la v1). Le pseudo vient du profil.
export const releaseNuisible = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }
    const uid = await authUid(req);
    if (!uid) { res.status(401).json({ error: "Non autorisé" }); return; }

    const b = req.body as Record<string, unknown>;
    const id = ((b.id as string | undefined) ?? "").trim();
    const name = ((b.name as string | undefined) ?? "").trim();
    const freq = (b.freq as string | undefined) ?? "daily";
    if (!id) { res.status(400).json({ error: "id requis" }); return; }
    if (name.length < 2 || name.length > 60) {
      res.status(400).json({ error: "Nom : 2 à 60 caractères" }); return;
    }
    if (!["daily", "weekly", "monthly"].includes(freq)) {
      res.status(400).json({ error: "freq invalide" }); return;
    }

    const profSnap = await db.collection("profiles").doc(uid).get();
    const pseudo = (profSnap.get("pseudo") as string | undefined) ?? "Anonyme";

    const hp = Math.max(1, Math.min(40, Math.floor(Number(b.hp ?? 3))));
    const target = Math.max(1, Math.floor(Number(b.target ?? 1)));
    const streak = Math.max(0, Math.floor(Number(b.streak ?? 0)));

    await db.collection("world_nuisibles").doc(id).set({
      id,
      ownerUid: uid,
      ownerPseudo: pseudo,
      routineId: (b.routineId as string | undefined) ?? "",
      name,
      freq,
      target,
      unit: (b.unit as string | undefined) ?? null,
      iconCode: (b.iconCode as number | undefined) ?? null,
      domainName: (b.domainName as string | undefined) ?? null,
      hp,
      streak,
      spectatorCount: 0,
      active: true,
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    res.status(200).json({ success: true, id });
  },
);

// POST { nuisibleId, follow } · suivre/ne plus suivre une routine relâchée.
// Le « droit de suivre » s'obtient en battant le nuisible côté client (v1
// trust client) ; ici on enregistre le suivi + maj le compteur de spectateurs.
export const followNuisible = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }
    const uid = await authUid(req);
    if (!uid) { res.status(401).json({ error: "Non autorisé" }); return; }

    const { nuisibleId, follow } = req.body as { nuisibleId?: string; follow?: boolean };
    if (!nuisibleId) { res.status(400).json({ error: "nuisibleId requis" }); return; }
    const nRef = db.collection("world_nuisibles").doc(nuisibleId);
    const n = await nRef.get();
    if (!n.exists) { res.status(404).json({ error: "Nuisible introuvable" }); return; }
    if (n.get("ownerUid") === uid) {
      res.status(400).json({ error: "On ne suit pas sa propre routine" }); return;
    }

    const fRef = db.collection("users").doc(uid).collection("world_follows").doc(nuisibleId);
    const already = (await fRef.get()).exists;
    if (follow === false) {
      if (already) {
        await fRef.delete();
        await nRef.update({ spectatorCount: FieldValue.increment(-1) });
      }
    } else {
      if (!already) {
        await fRef.set({
          nuisibleId,
          ownerUid: n.get("ownerUid"),
          ownerPseudo: n.get("ownerPseudo"),
          name: n.get("name"),
          followedAt: FieldValue.serverTimestamp(),
        });
        await nRef.update({ spectatorCount: FieldValue.increment(1) });
      }
    }
    res.status(200).json({ success: true });
  },
);

// ── Bataille de nuisibles (PvP async 1v1) ────────────────────────────────────
// Moteur DÉTERMINISTE mirroir de lib/battle_sim.dart. Aucune tâche serveur :
// une partie = un journal d'events de dépôt ; position = ticks écoulés depuis le
// dépôt ; collisions/croisements/flammes/victoire recalculés. resolveBattle
// re-simule côté serveur pour créditer la victoire (autoritatif, anti-triche).

type BEv = { id: string; side: number; lane: number; kind: string; tier: string; tick: number };

function simulateBattle(
  events: BEv[], width: number, lanes: number, nowTick: number,
): { winnerSide: number | null; winTick: number | null } {
  const camp = (s: number) => (s === 0 ? 0 : width - 1);
  const dir = (s: number) => (s === 0 ? 1 : -1);
  const strength = (t: string) => (t === "serpent" ? 3 : t === "scorpion" ? 2 : 1);
  const below = (t: string): string | null =>
    t === "serpent" ? "scorpion" : t === "scorpion" ? "spider" : null;

  const byTick = new Map<number, BEv[]>();
  for (const e of events) {
    const a = byTick.get(e.tick) ?? [];
    a.push(e);
    byTick.set(e.tick, a);
  }

  type U = { id: string; side: number; lane: number; isFlame: boolean; tier: string; alive: boolean; cell: number };
  const units: U[] = [];
  let winnerSide: number | null = null;
  let winTick: number | null = null;

  for (let t = 0; t <= nowTick; t++) {
    const prev = new Map<string, number>();
    for (const u of units) {
      if (!u.alive) continue;
      prev.set(u.id, u.cell);
      u.cell += dir(u.side);
    }
    const arr = byTick.get(t);
    if (arr) {
      for (const e of arr) {
        const u: U = { id: e.id, side: e.side, lane: e.lane, isFlame: e.kind === "flame", tier: e.tier, alive: true, cell: camp(e.side) };
        prev.set(u.id, u.cell);
        units.push(u);
      }
    }
    const meet = (a: U, b: U): boolean => {
      if (a.cell === b.cell) return true;
      const pa = prev.get(a.id);
      const pb = prev.get(b.id);
      if (pa == null || pb == null) return false;
      return pa === b.cell && pb === a.cell;
    };
    for (let i = 0; i < units.length; i++) {
      const a = units[i];
      if (!a.alive) continue;
      for (let j = i + 1; j < units.length; j++) {
        const b = units[j];
        if (!b.alive) continue;
        if (a.side === b.side || a.lane !== b.lane) continue;
        if (!meet(a, b)) continue;
        if (a.isFlame && b.isFlame) continue;
        if (a.isFlame) { b.alive = false; continue; }
        if (b.isFlame) { a.alive = false; break; }
        const sa = strength(a.tier);
        const sb = strength(b.tier);
        if (sa === sb) { a.alive = false; b.alive = false; break; }
        else if (sa > sb) { b.alive = false; const d = below(a.tier); if (d) a.tier = d; }
        else { a.alive = false; const d = below(b.tier); if (d) b.tier = d; break; }
      }
    }
    let s0: number | null = null;
    let s1: number | null = null;
    for (const u of units) {
      if (!u.alive || u.isFlame) continue;
      const crossed = u.side === 0 ? u.cell >= width : u.cell < 0;
      if (crossed) { if (u.side === 0) s0 = 0; else s1 = 1; }
    }
    if (s0 !== null || s1 !== null) { winnerSide = s0 !== null ? s0 : s1; winTick = t; break; }
  }
  return { winnerSide, winTick };
}

// ── Invasion : moteur de tower-defense ASYMÉTRIQUE (mirroir de lib/battle_sim.dart
// `simulateInvasion`). Envahisseur = side 0 (force figée, avance, franchit à cell≥width
// = territoire tenu). Défenseur = side 1 (dépose des bloqueurs `pest` + tire des flèches
// `arrow`). Le défenseur gagne UNIQUEMENT par élimination totale (pas de franchissement
// gagnant). Flèche = dégrade d'un cran l'envahisseur le plus avancé de la lane.
const tierStrength = (t: string): number =>
  t === "serpent" ? 3 : t === "scorpion" ? 2 : 1;
const tierBelow = (t: string): string | null =>
  t === "serpent" ? "scorpion" : t === "scorpion" ? "spider" : null;

type SimU = {
  id: string; side: number; lane: number; isFlame: boolean;
  tier: string; alive: boolean; cell: number;
};

// Dégrade d'un cran l'envahisseur (side 0) le plus avancé vivant de `lane`
// (cell max ; égalité → id le plus petit). Spider → mort. No-op si lane vide.
function applyArrow(units: SimU[], lane: number): void {
  let best: SimU | null = null;
  for (const u of units) {
    if (!u.alive || u.isFlame || u.side !== 0 || u.lane !== lane) continue;
    if (best === null) { best = u; continue; }
    if (u.cell > best.cell || (u.cell === best.cell && u.id < best.id)) best = u;
  }
  if (best === null) return;
  const d = tierBelow(best.tier);
  if (d === null) best.alive = false;
  else best.tier = d;
}

// `export` : utilisé par resolveInvasion (Phase 2) ; évite l'erreur noUnusedLocals
// en attendant. Helper pur — n'est PAS une Cloud Function (index.ts n'exporte que les
// onRequest nommés), donc inerte côté déploiement.
export function simulateInvasion(
  events: BEv[], width: number, lanes: number, nowTick: number,
): { winner: "invader" | "defender" | null; winTick: number | null } {
  const camp = (s: number) => (s === 0 ? 0 : width - 1);
  const dir = (s: number) => (s === 0 ? 1 : -1);

  const byTick = new Map<number, BEv[]>();
  for (const e of events) {
    const a = byTick.get(e.tick) ?? [];
    a.push(e);
    byTick.set(e.tick, a);
  }

  const units: SimU[] = [];
  let anyInvader = false;
  let winner: "invader" | "defender" | null = null;
  let winTick: number | null = null;

  for (let t = 0; t <= nowTick; t++) {
    const prev = new Map<string, number>();
    for (const u of units) {
      if (!u.alive) continue;
      prev.set(u.id, u.cell);
      u.cell += dir(u.side);
    }
    const arrows: BEv[] = [];
    const arr = byTick.get(t);
    if (arr) {
      for (const e of arr) {
        if (e.kind === "arrow") { arrows.push(e); continue; }
        const u: SimU = {
          id: e.id, side: e.side, lane: e.lane, isFlame: e.kind === "flame",
          tier: e.tier, alive: true, cell: camp(e.side),
        };
        prev.set(u.id, u.cell);
        units.push(u);
        if (e.side === 0 && e.kind !== "flame") anyInvader = true;
      }
    }
    arrows.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
    for (const a of arrows) applyArrow(units, a.lane);

    const meet = (a: SimU, b: SimU): boolean => {
      if (a.cell === b.cell) return true;
      const pa = prev.get(a.id);
      const pb = prev.get(b.id);
      if (pa == null || pb == null) return false;
      return pa === b.cell && pb === a.cell;
    };
    for (let i = 0; i < units.length; i++) {
      const a = units[i];
      if (!a.alive) continue;
      for (let j = i + 1; j < units.length; j++) {
        const b = units[j];
        if (!b.alive) continue;
        if (a.side === b.side || a.lane !== b.lane) continue;
        if (!meet(a, b)) continue;
        if (a.isFlame && b.isFlame) continue;
        if (a.isFlame) { b.alive = false; continue; }
        if (b.isFlame) { a.alive = false; break; }
        const sa = tierStrength(a.tier);
        const sb = tierStrength(b.tier);
        if (sa === sb) { a.alive = false; b.alive = false; break; }
        else if (sa > sb) { b.alive = false; const d = tierBelow(a.tier); if (d) a.tier = d; }
        else { a.alive = false; const d = tierBelow(b.tier); if (d) b.tier = d; break; }
      }
    }

    let invaderCrossed = false;
    for (const u of units) {
      if (!u.alive || u.isFlame) continue;
      if (u.side === 0 && u.cell >= width) { invaderCrossed = true; break; }
    }
    if (invaderCrossed) { winner = "invader"; winTick = t; break; }
    if (anyInvader) {
      const invadersAlive = units.some((u) => u.alive && !u.isFlame && u.side === 0);
      if (!invadersAlive) { winner = "defender"; winTick = t; break; }
    }
  }
  return { winner, winTick };
}

const clampInt = (v: unknown, lo: number, hi: number, def: number): number => {
  const n = Math.floor(Number(v ?? def));
  if (!Number.isFinite(n)) return def;
  return n < lo ? lo : n > hi ? hi : n;
};

// POST { width?, lanes?, tickMinutes? } → crée une partie en attente d'adversaire.
export const createBattle = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }
    const uid = await authUid(req);
    if (!uid) { res.status(401).json({ error: "Non autorisé" }); return; }
    const b = req.body as Record<string, unknown>;
    const width = clampInt(b.width, 3, 12, 7);
    const lanes = clampInt(b.lanes, 1, 8, 5);
    const tickMinutes = clampInt(b.tickMinutes, 1, 1440, 60);
    const prof = await db.collection("profiles").doc(uid).get();
    const pseudo = (prof.get("pseudo") as string | undefined) ?? "Anonyme";
    const ref = db.collection("battles").doc();
    await ref.set({
      id: ref.id, width, lanes, tickMinutes,
      status: "waiting", players: [uid], sides: { [uid]: 0 },
      pseudos: { [uid]: pseudo }, startAt: null, winnerUid: null,
      createdAt: FieldValue.serverTimestamp(),
    });
    res.status(200).json({ battleId: ref.id });
  },
);

// POST { battleId } → rejoint une partie en attente (lance l'horloge).
export const joinBattle = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }
    const uid = await authUid(req);
    if (!uid) { res.status(401).json({ error: "Non autorisé" }); return; }
    const battleId = ((req.body?.battleId as string | undefined) ?? "").trim();
    if (!battleId) { res.status(400).json({ error: "battleId requis" }); return; }
    const ref = db.collection("battles").doc(battleId);
    const out = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { err: "Bataille introuvable", code: 404 };
      const data = snap.data() as Record<string, unknown>;
      const players = (data.players as string[]) ?? [];
      if (players.includes(uid)) return { ok: true };
      if (data.status !== "waiting" || players.length >= 2) {
        return { err: "Bataille déjà complète", code: 400 };
      }
      const prof = await tx.get(db.collection("profiles").doc(uid));
      const pseudo = (prof.get("pseudo") as string | undefined) ?? "Anonyme";
      tx.update(ref, {
        players: [...players, uid],
        [`sides.${uid}`]: 1,
        [`pseudos.${uid}`]: pseudo,
        status: "active",
        startAt: FieldValue.serverTimestamp(),
      });
      return { ok: true };
    });
    if ("err" in out) { res.status(out.code ?? 400).json({ error: out.err }); return; }
    res.status(200).json({ success: true });
  },
);

// POST { battleId, lane, kind, tier } → dépose un nuisible/flamme (tick serveur).
// Valide : partie active, joueur, couloir, max 3 flammes, VERROU de couloir
// (une flamme exige un couloir libre de tes unités ; pas de pose dans le couloir
// d'une de tes flammes en transit). La masse est débitée côté client (trust v1).
export const deployUnit = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }
    const uid = await authUid(req);
    if (!uid) { res.status(401).json({ error: "Non autorisé" }); return; }
    const b = req.body as Record<string, unknown>;
    const battleId = ((b.battleId as string | undefined) ?? "").trim();
    const lane = Math.floor(Number(b.lane ?? -1));
    const kind = (b.kind as string | undefined) ?? "pest";
    const tier = (b.tier as string | undefined) ?? "spider";
    if (!battleId) { res.status(400).json({ error: "battleId requis" }); return; }
    if (kind !== "pest" && kind !== "flame") { res.status(400).json({ error: "kind invalide" }); return; }

    const ref = db.collection("battles").doc(battleId);
    const out = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { err: "Bataille introuvable", code: 404 };
      const data = snap.data() as Record<string, unknown>;
      if (data.status !== "active") return { err: "Bataille non active", code: 400 };
      const players = (data.players as string[]) ?? [];
      if (!players.includes(uid)) return { err: "Tu n'es pas dans cette bataille", code: 403 };
      const sides = (data.sides as Record<string, number>) ?? {};
      const side = sides[uid] ?? (players[0] === uid ? 0 : 1);
      const width = Number(data.width ?? 7);
      const lanes = Number(data.lanes ?? 5);
      const tickMinutes = Number(data.tickMinutes ?? 60);
      if (lane < 0 || lane >= lanes) return { err: "Couloir invalide", code: 400 };
      const startMs = (data.startAt as admin.firestore.Timestamp | null)?.toMillis?.() ?? Date.now();
      const nowTick = Math.max(0, Math.floor((Date.now() - startMs) / (tickMinutes * 60000)));

      const evSnap = await tx.get(ref.collection("events").where("uid", "==", uid));
      const mine = evSnap.docs.map((d) => d.data() as Record<string, unknown>);
      const masseCost = (t: string) => (t === "serpent" ? 15 : t === "scorpion" ? 10 : 5);
      if (kind === "flame") {
        const flames = mine.filter((e) => e.kind === "flame");
        if (flames.length >= 3) return { err: "Plus de flammes (3 max)", code: 400 };
        // 1 flamme par tick (pas de triple-flamme d'un coup).
        if (flames.some((e) => Number(e.tick) === nowTick)) {
          return { err: "Une seule flamme par tick", code: 429 };
        }
      } else {
        // Anti-déluge : ≤ 15 de masse déployée par tick (= 1 serpent, ou
        // 1 scorpion + 1 araignée, ou 3 araignées). La réserve à vie = ENDURANCE
        // (combien de vagues), pas une frappe instantanée. Empêche
        // « 50 araignées balancées d'un coup en serpents ».
        const spentThisTick = mine
          .filter((e) => e.kind === "pest" && Number(e.tick) === nowTick)
          .reduce((s, e) => s + masseCost(String(e.tier ?? "spider")), 0);
        if (spentThisTick + masseCost(tier) > 15) {
          return { err: "Budget de masse du tick atteint (15 max) — attends le prochain tour", code: 429 };
        }
      }
      // « encore en transit » = sur-approximation sûre (durée de vie max = width).
      const liveInLane = mine.filter(
        (e) => Number(e.lane) === lane && Number(e.tick) + width > nowTick,
      );
      if (kind === "flame") {
        if (liveInLane.length > 0) {
          return { err: "Couloir occupé par tes unités — la flamme exige un couloir libre", code: 400 };
        }
      } else if (liveInLane.some((e) => e.kind === "flame")) {
        return { err: "Une de tes flammes traverse ce couloir", code: 400 };
      }

      const evRef = ref.collection("events").doc();
      tx.set(evRef, {
        id: evRef.id, uid, side, lane, kind,
        tier: kind === "pest" ? tier : "",
        deployedAt: FieldValue.serverTimestamp(), tick: nowTick,
      });
      return { ok: true, tick: nowTick, eventId: evRef.id };
    });
    if ("err" in out) { res.status(out.code ?? 400).json({ error: out.err }); return; }
    res.status(200).json(out);
  },
);

// ── Invasion / Territoires : les 4 Cloud Functions ───────────────────────────
// release (compose la force + matchmaking ladder), engage (défenseur lance
// l'horloge), deployDefense (bloqueurs + flèches), resolve (re-simule, autoritatif).
// Économie trust-client v1 : le client compose sa force depuis son deck vert et
// décrémente son propre redRoster ; le serveur valide les plafonds et tranche.
const INV_WIDTH = 7;
const INV_LANES = 5;
const INV_TICK_MINUTES = 60;
const invMasseCost = (t: string): number =>
  t === "serpent" ? 15 : t === "scorpion" ? 10 : 5;
const levelOfTier = (t: string): number =>
  t === "serpent" ? 5 : t === "scorpion" ? 3 : 1;
const INV_TIERS = ["serpent", "scorpion", "spider"];

// POST { redTier, force:[{id,tier,lane,tick}], forceMasse } → crée une invasion
// `pending` contre une cible du ladder (~3 rangs au-dessus, sinon wrap). La force
// est FIGÉE inline (side 0). Le rouge (ticket) est décrémenté côté client.
export const releaseInvasion = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }
    const uid = await authUid(req);
    if (!uid) { res.status(401).json({ error: "Non autorisé" }); return; }
    const b = req.body as Record<string, unknown>;
    const redTier = (b.redTier as string | undefined) ?? "";
    if (!INV_TIERS.includes(redTier)) { res.status(400).json({ error: "redTier invalide" }); return; }
    const capStrength = tierStrength(redTier);

    // Force : copie du deck vert ≤ palier du rouge, métrée en vagues (trust-client).
    const rawForce = Array.isArray(b.force) ? (b.force as unknown[]) : [];
    if (rawForce.length === 0) { res.status(400).json({ error: "force vide" }); return; }
    if (rawForce.length > 400) { res.status(400).json({ error: "force trop grande (400 max)" }); return; }
    const force: { id: string; tier: string; lane: number; tick: number }[] = [];
    let i = 0;
    for (const u of rawForce) {
      const o = (u ?? {}) as Record<string, unknown>;
      const tier = (o.tier as string | undefined) ?? "spider";
      if (!INV_TIERS.includes(tier)) { res.status(400).json({ error: "tier d'unité invalide" }); return; }
      if (tierStrength(tier) > capStrength) {
        res.status(400).json({ error: "une unité dépasse le palier du rouge" }); return;
      }
      const lane = clampInt(o.lane, 0, INV_LANES - 1, 0);
      const tick = clampInt(o.tick, 0, 9999, 0);
      const id = ((o.id as string | undefined) ?? `f${i}`).slice(0, 40);
      force.push({ id, tier, lane, tick });
      i++;
    }
    const forceMasse = force.reduce((s, u) => s + invMasseCost(u.tier), 0);

    // Puissance live de l'attaquant = Σ tierStrength × redRoster (état courant).
    const myMeta = await db.doc(`users/${uid}/data/meta`).get();
    const myPower = invasionDeckPower(myMeta.data());

    // Matchmaking ladder : ~3 rangs au-dessus ; si l'attaquant est en tête, wrap
    // vers les plus forts juste en dessous. Exclut soi-même + cibles saturées
    // (≥ 3 invasions pending/active déjà reçues).
    const pickAbove = await db.collection("leaderboard_entries")
      .where("optedIn", "==", true)
      .where("deckPower", ">", myPower)
      .orderBy("deckPower", "asc").limit(5).get();
    let cands = pickAbove.docs.map((d) => d.id).filter((u) => u !== uid);
    if (cands.length === 0) {
      const wrap = await db.collection("leaderboard_entries")
        .where("optedIn", "==", true)
        .where("deckPower", "<", myPower)
        .orderBy("deckPower", "desc").limit(5).get();
      cands = wrap.docs.map((d) => d.id).filter((u) => u !== uid);
    }
    // Filtre anti-concentration (max 3 invasions actives reçues).
    const valid: string[] = [];
    for (const c of cands) {
      if (valid.length >= 3) break;
      const recv = await db.collection("invasions")
        .where("defenderUid", "==", c)
        .where("status", "in", ["pending", "active"]).get();
      if (recv.size < 3) valid.push(c);
    }
    if (valid.length === 0) { res.status(200).json({ ok: false, reason: "no_target" }); return; }
    const defenderUid = valid[Math.floor(Math.random() * valid.length)];

    const [myProf, defProf] = await Promise.all([
      db.collection("profiles").doc(uid).get(),
      db.collection("profiles").doc(defenderUid).get(),
    ]);
    const ref = db.collection("invasions").doc();
    await ref.set({
      id: ref.id,
      invaderUid: uid,
      invaderPseudo: (myProf.get("pseudo") as string | undefined) ?? "Anonyme",
      defenderUid,
      defenderPseudo: (defProf.get("pseudo") as string | undefined) ?? "Anonyme",
      redTier, level: levelOfTier(redTier), pestType: redTier,
      status: "pending",
      force, forceMasse,
      width: INV_WIDTH, lanes: INV_LANES, tickMinutes: INV_TICK_MINUTES,
      startAt: null, winner: null, revealedToDefender: false,
      defenderReward: null, resolvedAt: null,
      createdAt: FieldValue.serverTimestamp(),
    });
    res.status(200).json({
      ok: true, invasionId: ref.id,
      defenderUid, defenderPseudo: (defProf.get("pseudo") as string | undefined) ?? "Anonyme",
    });
  },
);

// POST { invasionId } → le DÉFENSEUR engage : pending → active, lance l'horloge.
export const engageInvasion = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }
    const uid = await authUid(req);
    if (!uid) { res.status(401).json({ error: "Non autorisé" }); return; }
    const invasionId = ((req.body?.invasionId as string | undefined) ?? "").trim();
    if (!invasionId) { res.status(400).json({ error: "invasionId requis" }); return; }
    const ref = db.collection("invasions").doc(invasionId);
    const out = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { err: "Invasion introuvable", code: 404 };
      const data = snap.data() as Record<string, unknown>;
      if (data.defenderUid !== uid) return { err: "Tu n'es pas le défenseur", code: 403 };
      if (data.status === "active") return { ok: true, already: true };
      if (data.status !== "pending") return { err: "Invasion déjà résolue", code: 400 };
      tx.update(ref, { status: "active", startAt: FieldValue.serverTimestamp() });
      return { ok: true };
    });
    if ("err" in out) { res.status(out.code ?? 400).json({ error: out.err }); return; }
    res.status(200).json(out);
  },
);

// POST { invasionId, lane, kind('pest'|'arrow'), tier } → le DÉFENSEUR dépose un
// bloqueur ou tire une flèche (tick serveur). Budget 15 masse/tick (pest) ; cap
// 3 flèches/tick. Stock débité côté client (trust v1).
export const deployDefense = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }
    const uid = await authUid(req);
    if (!uid) { res.status(401).json({ error: "Non autorisé" }); return; }
    const b = req.body as Record<string, unknown>;
    const invasionId = ((b.invasionId as string | undefined) ?? "").trim();
    const lane = Math.floor(Number(b.lane ?? -1));
    const kind = (b.kind as string | undefined) ?? "pest";
    const tier = (b.tier as string | undefined) ?? "spider";
    if (!invasionId) { res.status(400).json({ error: "invasionId requis" }); return; }
    if (kind !== "pest" && kind !== "arrow") { res.status(400).json({ error: "kind invalide" }); return; }
    if (kind === "pest" && !INV_TIERS.includes(tier)) { res.status(400).json({ error: "tier invalide" }); return; }

    const ref = db.collection("invasions").doc(invasionId);
    const out = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { err: "Invasion introuvable", code: 404 };
      const data = snap.data() as Record<string, unknown>;
      if (data.defenderUid !== uid) return { err: "Tu n'es pas le défenseur", code: 403 };
      if (data.status !== "active") return { err: "Invasion non active", code: 400 };
      const lanes = Number(data.lanes ?? INV_LANES);
      const tickMinutes = Number(data.tickMinutes ?? INV_TICK_MINUTES);
      if (lane < 0 || lane >= lanes) return { err: "Couloir invalide", code: 400 };
      const startMs = (data.startAt as admin.firestore.Timestamp | null)?.toMillis?.() ?? Date.now();
      const nowTick = Math.max(0, Math.floor((Date.now() - startMs) / (tickMinutes * 60000)));

      const evSnap = await tx.get(ref.collection("events"));
      const mine = evSnap.docs.map((d) => d.data() as Record<string, unknown>);
      if (kind === "arrow") {
        const arrowsThisTick = mine.filter(
          (e) => e.kind === "arrow" && Number(e.tick) === nowTick).length;
        if (arrowsThisTick >= 3) {
          return { err: "Plus de flèches ce tour (3 max) — attends le prochain", code: 429 };
        }
      } else {
        const spentThisTick = mine
          .filter((e) => e.kind === "pest" && Number(e.tick) === nowTick)
          .reduce((s, e) => s + invMasseCost(String(e.tier ?? "spider")), 0);
        if (spentThisTick + invMasseCost(tier) > 15) {
          return { err: "Budget de masse du tick atteint (15 max) — attends le prochain tour", code: 429 };
        }
      }
      const evRef = ref.collection("events").doc();
      tx.set(evRef, {
        id: evRef.id, side: 1, lane, kind,
        tier: kind === "pest" ? tier : "",
        deployedAt: FieldValue.serverTimestamp(), tick: nowTick,
      });
      return { ok: true, tick: nowTick, eventId: evRef.id };
    });
    if ("err" in out) { res.status(out.code ?? 400).json({ error: out.err }); return; }
    res.status(200).json(out);
  },
);

// POST { invasionId } → re-simule côté serveur (autoritatif). invader franchit →
// `held` (prestige, 0 revenu) ; défenseur élimine tout → `repelled` + révélation
// + récompense + grant de suivi + LEDGER de retour du rouge downgradé (idempotent
// par invasionId, appliqué 1× par le client de l'envahisseur). Idempotent.
export const resolveInvasion = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }
    const uid = await authUid(req);
    if (!uid) { res.status(401).json({ error: "Non autorisé" }); return; }
    const invasionId = ((req.body?.invasionId as string | undefined) ?? "").trim();
    if (!invasionId) { res.status(400).json({ error: "invasionId requis" }); return; }
    const ref = db.collection("invasions").doc(invasionId);
    const out = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { err: "Invasion introuvable", code: 404 };
      const data = snap.data() as Record<string, unknown>;
      const invaderUid = data.invaderUid as string;
      const defenderUid = data.defenderUid as string;
      if (uid !== invaderUid && uid !== defenderUid) {
        return { err: "Tu n'es pas dans cette invasion", code: 403 };
      }
      if (data.status === "repelled" || data.status === "held") {
        return { ok: true, status: data.status, winner: data.winner ?? null, already: true };
      }
      if (data.status !== "active") return { ok: true, ongoing: true, status: data.status };

      const width = Number(data.width ?? INV_WIDTH);
      const lanes = Number(data.lanes ?? INV_LANES);
      const tickMinutes = Number(data.tickMinutes ?? INV_TICK_MINUTES);
      const startMs = (data.startAt as admin.firestore.Timestamp | null)?.toMillis?.() ?? Date.now();
      const nowTick = Math.max(0, Math.floor((Date.now() - startMs) / (tickMinutes * 60000)));

      const force = (data.force as { id: string; tier: string; lane: number; tick: number }[]) ?? [];
      const evSnap = await tx.get(ref.collection("events"));
      const events: BEv[] = [
        ...force.map((u) => ({
          id: u.id, side: 0, lane: Number(u.lane ?? 0),
          kind: "pest", tier: (u.tier as string) || "spider", tick: Number(u.tick ?? 0),
        })),
        ...evSnap.docs.map((d) => {
          const e = d.data() as Record<string, unknown>;
          return {
            id: (e.id as string) ?? d.id, side: 1, lane: Number(e.lane ?? 0),
            kind: (e.kind as string) ?? "pest", tier: (e.tier as string) || "spider", tick: Number(e.tick ?? 0),
          };
        }),
      ];
      const sim = simulateInvasion(events, width, lanes, nowTick);
      if (sim.winner === null) return { ok: true, ongoing: true };

      if (sim.winner === "invader") {
        tx.update(ref, {
          status: "held", winner: "invader", winTick: sim.winTick,
          resolvedAt: FieldValue.serverTimestamp(),
        });
        return { ok: true, status: "held", winner: "invader" };
      }
      // défenseur : territoire libéré.
      const redTier = (data.redTier as string) || "spider";
      const forceMasse = Number(data.forceMasse ?? 0);
      const defenderReward = 20 * tierStrength(redTier) + Math.min(forceMasse, 100);
      tx.update(ref, {
        status: "repelled", winner: "defender", winTick: sim.winTick,
        revealedToDefender: true, defenderReward,
        resolvedAt: FieldValue.serverTimestamp(),
      });
      // Grant de suivi (droit de contre-envahir) — espace du défenseur.
      tx.set(db.collection("users").doc(defenderUid).collection("invasion_follows").doc(invaderUid), {
        invaderUid, invaderPseudo: (data.invaderPseudo as string) ?? "Anonyme",
        invasionId, followedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      // Ledger de retour du rouge downgradé (spider → mort, pas de retour).
      const returnTier = tierBelow(redTier);
      tx.set(db.collection("users").doc(invaderUid).collection("red_returns").doc(invasionId), {
        invasionId, tier: returnTier, fromTier: redTier,
        createdAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      return { ok: true, status: "repelled", winner: "defender", defenderReward };
    });
    if ("err" in out) { res.status(out.code ?? 400).json({ error: out.err }); return; }
    res.status(200).json(out);
  },
);

// POST { battleId } → re-simule côté serveur ; si victoire, fige la partie et
// crédite profiles/{winnerUid}.battleWins (idempotent). Appelé par un client
// quand sa simu locale détecte une victoire ; le serveur tranche.
export const resolveBattle = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }
    const uid = await authUid(req);
    if (!uid) { res.status(401).json({ error: "Non autorisé" }); return; }
    const battleId = ((req.body?.battleId as string | undefined) ?? "").trim();
    if (!battleId) { res.status(400).json({ error: "battleId requis" }); return; }
    const ref = db.collection("battles").doc(battleId);
    const out = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { err: "Bataille introuvable", code: 404 };
      const data = snap.data() as Record<string, unknown>;
      if (data.status === "finished") {
        return { ok: true, winnerUid: (data.winnerUid as string | null) ?? null, already: true };
      }
      const players = (data.players as string[]) ?? [];
      if (!players.includes(uid)) return { err: "Tu n'es pas dans cette bataille", code: 403 };
      const evSnap = await tx.get(ref.collection("events"));
      const events: BEv[] = evSnap.docs.map((d) => {
        const e = d.data() as Record<string, unknown>;
        return {
          id: (e.id as string) ?? d.id, side: Number(e.side ?? 0), lane: Number(e.lane ?? 0),
          kind: (e.kind as string) ?? "pest", tier: (e.tier as string) || "spider", tick: Number(e.tick ?? 0),
        };
      });
      const width = Number(data.width ?? 7);
      const lanes = Number(data.lanes ?? 5);
      const tickMinutes = Number(data.tickMinutes ?? 60);
      const startMs = (data.startAt as admin.firestore.Timestamp | null)?.toMillis?.() ?? Date.now();
      const nowTick = Math.max(0, Math.floor((Date.now() - startMs) / (tickMinutes * 60000)));
      const sim = simulateBattle(events, width, lanes, nowTick);
      if (sim.winnerSide === null) return { ok: true, winnerUid: null, ongoing: true };
      const sides = (data.sides as Record<string, number>) ?? {};
      const winnerUid = Object.keys(sides).find((u) => sides[u] === sim.winnerSide) ?? null;
      tx.update(ref, {
        status: "finished", winnerUid, winTick: sim.winTick,
        resolvedAt: FieldValue.serverTimestamp(),
      });
      if (winnerUid) {
        tx.set(db.collection("profiles").doc(winnerUid), { battleWins: FieldValue.increment(1) }, { merge: true });
      }
      return { ok: true, winnerUid };
    });
    if ("err" in out) { res.status(out.code ?? 400).json({ error: out.err }); return; }
    res.status(200).json(out);
  },
);
