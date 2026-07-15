import { mondayOf } from "./weekly_report";

// ── Objectifs stratégiques : résumé compact + progression hebdo ───────────────
// Définition partagée avec lib/utils/objective_progress.dart (même sémantique) :
// fenêtre = semaine courante (lundi → maintenant), seuil onTrack = 70 % du
// cumul attendu au prorata des jours écoulés (même seuil que
// activity_behind_target côté app).

export interface ObjectiveCommitmentSummary {
  type: "time" | "routine";
  activityId: string;
  name: string;
  weeklyMin?: number; // engagement temps (minutes/semaine)
  weeklyTarget?: number; // cible hebdo équivalente d'une routine
  weekDone: number; // minutes ou hits depuis lundi
  onTrack: boolean;
}

export interface ObjectiveSummary {
  id: string;
  title: string;
  kpiTarget: string | null;
  horizonLabel: string | null;
  endDate: string | null;
  daysLeft: number | null;
  weekPercent: number | null; // % moyen des engagements sur la semaine (null si aucun)
  commitments: ObjectiveCommitmentSummary[];
}

function parisDayOf(v: unknown): string | null {
  try {
    let d: Date | null = null;
    if (v instanceof Date) d = v;
    else if (typeof v === "string") d = new Date(v);
    else if (v && typeof (v as { toDate?: () => Date }).toDate === "function") {
      d = (v as { toDate: () => Date }).toDate();
    }
    if (!d || isNaN(d.getTime())) return null;
    return d.toLocaleDateString("sv-SE", { timeZone: "Europe/Paris" });
  } catch {
    return null;
  }
}

/** Cible hebdo équivalente d'une routine (habitFreq stocké en index Dart :
 *  0 = daily, 1 = weekly, 2 = monthly ; tolère aussi les libellés). */
function weeklyRoutineTarget(habitFreq: unknown, habitTarget: unknown): number {
  const target = Math.max(1, Math.round(Number(habitTarget) || 1));
  const freq = typeof habitFreq === "string" ? habitFreq
    : habitFreq === 0 ? "daily" : habitFreq === 1 ? "weekly" : "monthly";
  if (freq === "daily") return target * 7;
  if (freq === "weekly") return target;
  return Math.max(1, Math.round((target * 7) / 30)); // monthly
}

/**
 * Résume les objectifs actifs avec leur progression hebdo, à partir de
 * snapshots déjà fetchés (sessions/habitHits des 7 derniers jours suffisent :
 * lundi ⊂ fenêtre 7 jours — zéro lecture Firestore supplémentaire).
 */
export function summarizeObjectives(
  objectives: Array<Record<string, unknown>>,
  activities: Array<Record<string, unknown>>,
  sessions: Array<Record<string, unknown>>,
  habitHits: Array<Record<string, unknown>>,
  todayStr: string
): ObjectiveSummary[] {
  const monday = mondayOf(todayStr);
  const weekday = ((new Date(`${todayStr}T12:00:00Z`).getUTCDay() + 6) % 7) + 1; // 1 = lundi … 7 = dimanche
  const prorate = (weekday / 7) * 0.7;

  const activityById = new Map<string, Record<string, unknown>>();
  for (const a of activities) activityById.set(String(a.id), a);

  // Minutes loggées depuis lundi, par activité
  const minSinceMonday = new Map<string, number>();
  for (const s of sessions) {
    if (!s.endAt) continue;
    const day = parisDayOf(s.startAt);
    if (!day || day < monday) continue;
    const start = new Date(String(s.startAt));
    const end = new Date(String(s.endAt));
    const mins = Math.round((end.getTime() - start.getTime()) / 60000);
    if (mins > 0) {
      const id = String(s.activityId);
      minSinceMonday.set(id, (minSinceMonday.get(id) || 0) + mins);
    }
  }

  // Hits de routine depuis lundi, par routine
  const hitsSinceMonday = new Map<string, number>();
  for (const h of habitHits) {
    const day = parisDayOf(h.ts);
    if (!day || day < monday) continue;
    const id = String(h.habitId);
    hitsSinceMonday.set(id, (hitsSinceMonday.get(id) || 0) + 1);
  }

  return objectives.map((o) => {
    const commitments: ObjectiveCommitmentSummary[] = [];
    const pcts: number[] = [];

    const timeCommitments = Array.isArray(o.timeCommitments) ? o.timeCommitments : [];
    for (const c of timeCommitments as Array<Record<string, unknown>>) {
      const activityId = String(c.activityId ?? "");
      const weeklyMin = Math.max(1, Math.round(Number(c.weeklyMin) || 1));
      const a = activityById.get(activityId);
      const done = minSinceMonday.get(activityId) || 0;
      pcts.push(Math.min(done / weeklyMin, 1));
      commitments.push({
        type: "time",
        activityId,
        name: String(a?.name ?? activityId),
        weeklyMin,
        weekDone: done,
        onTrack: done >= weeklyMin * prorate,
      });
    }

    const routineCommitments = Array.isArray(o.routineCommitments) ? o.routineCommitments : [];
    for (const c of routineCommitments as Array<Record<string, unknown>>) {
      const activityId = String(c.activityId ?? "");
      const a = activityById.get(activityId);
      const weeklyTarget = weeklyRoutineTarget(a?.habitFreq, a?.habitTarget);
      const done = hitsSinceMonday.get(activityId) || 0;
      pcts.push(Math.min(done / weeklyTarget, 1));
      commitments.push({
        type: "routine",
        activityId,
        name: String(a?.name ?? activityId),
        weeklyTarget,
        weekDone: done,
        onTrack: done >= weeklyTarget * prorate,
      });
    }

    const endDate = typeof o.endDate === "string" ? o.endDate : null;
    let daysLeft: number | null = null;
    if (endDate) {
      daysLeft = Math.round(
        (new Date(`${endDate}T12:00:00Z`).getTime() -
          new Date(`${todayStr}T12:00:00Z`).getTime()) / 86400000
      );
    }

    return {
      id: String(o.id ?? ""),
      title: String(o.title ?? ""),
      kpiTarget: typeof o.kpiTarget === "string" ? o.kpiTarget : null,
      horizonLabel: typeof o.horizonLabel === "string" ? o.horizonLabel : null,
      endDate,
      daysLeft,
      weekPercent: pcts.length > 0
        ? Math.round((pcts.reduce((s, p) => s + p, 0) / pcts.length) * 100)
        : null,
      commitments,
    };
  });
}
