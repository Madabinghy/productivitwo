// Audit des sessions de temps (outils MCP list_sessions / delete_sessions / update_session).
// Logique pure, testée dans test/sessions_audit.test.mjs.
//
// Les stats de l'app (`totalForRange`) découpent chaque session par jour : une session seule
// ne dépasse jamais 24 h/jour. Un total > 24 h/jour (ou > 168 h/semaine) vient donc forcément
// de sessions qui se CHEVAUCHENT (doublons, deux chronos en parallèle).
//
// Heures : l'app écrit `startAt`/`endAt` en ISO local SANS fuseau (`2026-07-28T09:00:00.000`).
// On les lit comme heure murale (suffixe Z ajouté si absent) pour découper les jours comme l'app.

export interface RawSession {
  id: string;
  activityId: string;
  startAt: string;
  endAt?: string | null;
  taskId?: string | null;
  actionId?: string | null;
  deleted?: boolean;
}

export interface SessionRow {
  id: string;
  activityId: string;
  activityName: string;
  startAt: string;
  endAt: string | null;
  durationMin: number;
  open: boolean;
}

export interface DayStat {
  day: string;
  summedMin: number;
  wallClockMin: number;
  overlapMin: number;
}

export interface AuditResult {
  rows: SessionRow[];
  days: DayStat[];
  duplicates: string[][];
  overlaps: { a: string; b: string; overlapMin: number }[];
  long: string[];
  open: string[];
}

const DAY_MS = 86400000;

export function wallMs(iso: string): number {
  const hasZone = /([zZ]|[+-]\d{2}:?\d{2})$/.test(iso);
  return Date.parse(hasZone ? iso : `${iso}Z`);
}

export function dayKey(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/** Heure murale ISO sans fuseau, format écrit par l'app. */
export function toWallIso(ms: number): string {
  return new Date(ms).toISOString().replace("Z", "");
}

function endMsOf(s: RawSession, nowMs: number): number {
  return s.endAt ? wallMs(s.endAt) : nowMs;
}

/** Durée max « normale » d'une session avant d'être signalée comme trop longue. */
export function longThresholdMin(activityName: string): number {
  return /sommeil|sleep/i.test(activityName) ? 13 * 60 : 6 * 60;
}

function unionMin(intervals: [number, number][]): number {
  const sorted = [...intervals].sort((x, y) => x[0] - y[0]);
  let total = 0;
  let curS = -1;
  let curE = -1;
  for (const [s, e] of sorted) {
    if (s > curE) {
      if (curE > curS) total += curE - curS;
      curS = s;
      curE = e;
    } else if (e > curE) {
      curE = e;
    }
  }
  if (curE > curS) total += curE - curS;
  return Math.round(total / 60000);
}

/**
 * Audite les sessions qui touchent [fromDay, toDay] (YYYY-MM-DD inclus, heure murale).
 * `nowMs` = maintenant en heure murale de l'utilisateur (sessions ouvertes).
 */
export function auditSessions(
  sessions: RawSession[],
  names: Record<string, string>,
  fromDay: string,
  toDay: string,
  nowMs: number,
): AuditResult {
  const fromMs = wallMs(`${fromDay}T00:00:00`);
  const toMs = wallMs(`${toDay}T00:00:00`) + DAY_MS;

  const live = sessions.filter((s) => {
    if (s.deleted || !s.startAt) return false;
    const st = wallMs(s.startAt);
    const en = endMsOf(s, nowMs);
    return !Number.isNaN(st) && st < toMs && en > fromMs;
  });

  const nameOf = (id: string) => names[id] ?? "(activité supprimée)";

  const rows: SessionRow[] = live
    .map((s) => {
      const st = wallMs(s.startAt);
      const en = endMsOf(s, nowMs);
      return {
        id: s.id,
        activityId: s.activityId,
        activityName: nameOf(s.activityId),
        startAt: s.startAt,
        endAt: s.endAt ?? null,
        durationMin: Math.max(0, Math.round((en - st) / 60000)),
        open: !s.endAt,
      };
    })
    .sort((a, b) => wallMs(a.startAt) - wallMs(b.startAt));

  // Par jour : somme découpée (= ce que l'app affiche) vs temps mural réel (union).
  const days: DayStat[] = [];
  for (let d = fromMs; d < toMs; d += DAY_MS) {
    const dEnd = d + DAY_MS;
    const clipped: [number, number][] = [];
    for (const s of live) {
      const st = Math.max(wallMs(s.startAt), d);
      const en = Math.min(endMsOf(s, nowMs), dEnd);
      if (en > st) clipped.push([st, en]);
    }
    const summedMin = Math.round(clipped.reduce((acc, [s, e]) => acc + (e - s), 0) / 60000);
    const wallClockMin = unionMin(clipped);
    days.push({ day: dayKey(d), summedMin, wallClockMin, overlapMin: summedMin - wallClockMin });
  }

  // Doublons : même activité, début et fin à moins d'une minute près.
  const dupGroups = new Map<string, string[]>();
  const seen = new Set<string>();
  for (let i = 0; i < live.length; i++) {
    const a = live[i];
    if (seen.has(a.id)) continue;
    const group = [a.id];
    for (let j = i + 1; j < live.length; j++) {
      const b = live[j];
      if (seen.has(b.id) || b.activityId !== a.activityId) continue;
      const sameStart = Math.abs(wallMs(a.startAt) - wallMs(b.startAt)) < 60000;
      const sameEnd = Math.abs(endMsOf(a, nowMs) - endMsOf(b, nowMs)) < 60000;
      if (sameStart && sameEnd) {
        group.push(b.id);
        seen.add(b.id);
      }
    }
    if (group.length > 1) dupGroups.set(a.id, group);
  }
  const duplicates = Array.from(dupGroups.values());
  const dupIds = new Set(duplicates.flat());

  // Chevauchements (hors doublons déjà signalés) : au moins 5 min en commun.
  const overlaps: { a: string; b: string; overlapMin: number }[] = [];
  const byStart = [...live].sort((x, y) => wallMs(x.startAt) - wallMs(y.startAt));
  for (let i = 0; i < byStart.length; i++) {
    const a = byStart[i];
    const aEnd = endMsOf(a, nowMs);
    for (let j = i + 1; j < byStart.length; j++) {
      const b = byStart[j];
      const bStart = wallMs(b.startAt);
      if (bStart >= aEnd) break;
      if (dupIds.has(a.id) && dupIds.has(b.id)) continue;
      const ov = Math.round((Math.min(aEnd, endMsOf(b, nowMs)) - bStart) / 60000);
      if (ov >= 5) overlaps.push({ a: a.id, b: b.id, overlapMin: ov });
    }
  }

  const long = rows
    .filter((r) => r.durationMin > longThresholdMin(r.activityName))
    .map((r) => r.id);
  const open = rows.filter((r) => r.open).map((r) => r.id);

  return { rows, days, duplicates, overlaps, long, open };
}

function hhmm(iso: string | null): string {
  if (!iso) return "en cours";
  const t = toWallIso(wallMs(iso));
  return `${t.slice(5, 10)} ${t.slice(11, 16)}`;
}

function fmtMin(m: number): string {
  const h = Math.floor(m / 60);
  const r = m % 60;
  return h > 0 ? `${h} h ${String(r).padStart(2, "0")}` : `${r} min`;
}

/** Rendu texte pour le MCP. `anomaliesOnly` = ne lister que les sessions suspectes. */
export function formatAudit(res: AuditResult, fromDay: string, toDay: string, anomaliesOnly: boolean): string {
  const byId = new Map(res.rows.map((r) => [r.id, r]));
  const line = (id: string) => {
    const r = byId.get(id);
    if (!r) return `  · ${id}`;
    return `  · ${r.id} — ${r.activityName} · ${hhmm(r.startAt)} → ${hhmm(r.endAt)} (${fmtMin(r.durationMin)})`;
  };
  const out: string[] = [];
  out.push(`Sessions du ${fromDay} au ${toDay} : ${res.rows.length}`);

  const totalSummed = res.days.reduce((a, d) => a + d.summedMin, 0);
  const totalWall = res.days.reduce((a, d) => a + d.wallClockMin, 0);
  out.push(`Total compté par les stats : ${fmtMin(totalSummed)} · temps réel (sans chevauchements) : ${fmtMin(totalWall)}`);

  out.push("", "Par jour (compté / réel) :");
  for (const d of res.days) {
    const flag = d.summedMin > 1440 ? " ⚠️ > 24 h" : d.overlapMin >= 5 ? ` ⚠️ ${fmtMin(d.overlapMin)} de chevauchement` : "";
    out.push(`  ${d.day} : ${fmtMin(d.summedMin)} / ${fmtMin(d.wallClockMin)}${flag}`);
  }

  out.push("", `Doublons (même activité, mêmes heures) : ${res.duplicates.length}`);
  for (const g of res.duplicates) {
    out.push(`  Groupe de ${g.length} — garder le premier, supprimer : ${g.slice(1).join(", ")}`);
    g.forEach((id) => out.push(line(id)));
  }

  out.push("", `Chevauchements (≥ 5 min) : ${res.overlaps.length}`);
  for (const o of res.overlaps) {
    out.push(`  ${fmtMin(o.overlapMin)} en commun :`);
    out.push(line(o.a));
    out.push(line(o.b));
  }

  out.push("", `Sessions anormalement longues (> 6 h, > 13 h pour le sommeil) : ${res.long.length}`);
  res.long.forEach((id) => out.push(line(id)));

  out.push("", `Sessions encore ouvertes : ${res.open.length}`);
  res.open.forEach((id) => out.push(line(id)));

  if (!anomaliesOnly) {
    out.push("", "Toutes les sessions :");
    res.rows.forEach((r) => out.push(line(r.id)));
  }

  out.push(
    "",
    "Corriger : delete_sessions(sessionIds) pour les doublons, update_session(sessionId, startAt?, endAt?) pour une durée fausse. " +
      "Toujours montrer la liste à l'utilisateur et attendre son accord avant de supprimer.",
  );
  return out.join("\n");
}

/** Docs de sessions hors suppression douce (`deleted:true`) — à utiliser pour toute lecture de stats. */
export function liveSessionDocs<T extends { data(): { [k: string]: unknown } | undefined }>(snap: { docs: T[] }): T[] {
  return snap.docs.filter((d) => d.data()?.deleted !== true);
}
