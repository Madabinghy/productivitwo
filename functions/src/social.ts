// ── Couche sociale (Phase 1) : pseudos + classement XP global ────────────────
// claimPseudo (réservation unique + opt-in) · recomputeLeaderboards (cron).
// L'XP de classement est RECALCULÉ CÔTÉ SERVEUR depuis les données réelles de
// l'utilisateur (anti-triche) — miroir de app_logic.actionXp/xpForDay.
import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
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
  await db.collection("leaderboard_entries").doc(uid).set(
    { pseudo, optedIn: true, ...xp, updatedAt: FieldValue.serverTimestamp() },
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
