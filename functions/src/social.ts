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

async function writeLeaderboardEntry(uid: string, pseudo: string): Promise<void> {
  const xp = await computeUserXp(uid);
  // Or disponible : sert de départage secondaire quand l'XP est à égalité.
  const meta = await db.doc(`users/${uid}/data/meta`).get();
  const gold = (meta.data()?.gold as number) ?? 0;
  await db.collection("leaderboard_entries").doc(uid).set(
    { pseudo, optedIn: true, ...xp, gold, updatedAt: FieldValue.serverTimestamp() },
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
