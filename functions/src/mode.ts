// ── Modes et coups tactiques (lot 0, 2026-10) ───────────────────────────────
// Miroir de `lib/utils/mode.dart` (garder alignés). Le MODE du jour n'est pas
// stocké : dernier pointage d'élan de la journée vécue — ≤ 2 Flemme · 3 Normal
// · ≥ 4 En forme ; aucun = Normal.
import type { MoodMarkDoc } from "./elan";

export type DayMode = "low" | "normal" | "high";
export const MODE_LABELS: Record<DayMode, string> = { low: "Flemme", normal: "Normal", high: "En forme" };
export const MODE_KINDS: DayMode[] = ["low", "normal", "high"];

export function modeElanValue(m: DayMode): number {
  return m === "low" ? 2 : m === "high" ? 4 : 3;
}

export function modeFromElan(value: number): DayMode {
  return value <= 2 ? "low" : value >= 4 ? "high" : "normal";
}

/** Dernier pointage d'élan de la journée vécue [ymd], à [atIso] au plus tard. */
export function lastElanMark(marks: MoodMarkDoc[], ymd: string, atIso?: string): MoodMarkDoc | null {
  let best: MoodMarkDoc | null = null;
  for (const m of marks) {
    if (m.kind !== "elan" || m.ymd !== ymd) continue;
    if (atIso && m.at > atIso) continue;
    if (!best || m.at > best.at) best = m;
  }
  return best;
}

export function modeOf(marks: MoodMarkDoc[], ymd: string): { mode: DayMode; since: string | null } {
  const m = lastElanMark(marks, ymd);
  return m ? { mode: modeFromElan(m.value), since: m.at } : { mode: "normal", since: null };
}

/** `data/meta.restDomains {domainId: "YYYY-MM-DD"}` — veille jusqu'à la date incluse. */
export function parseRestDomains(raw: unknown): Record<string, string> {
  if (!raw || typeof raw !== "object") return {};
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    if (typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v)) out[k] = v;
  }
  return out;
}

export function isResting(domainId: string | null | undefined, rest: Record<string, string>, todayYmd: string): boolean {
  if (!domainId) return false;
  const until = rest[domainId];
  return !!until && until >= todayYmd;
}

export function activeRests(rest: Record<string, string>, todayYmd: string): Record<string, string> {
  return Object.fromEntries(Object.entries(rest).filter(([, until]) => until >= todayYmd));
}

export function parseBudgetWindowDays(raw: unknown): number {
  const v = typeof raw === "number" ? raw : Number(raw);
  return v === 14 ? 14 : 7;
}

/** Un objectif tactique (« coup ») : horizon "tactical", 3 à 10 jours. */
export function isTactical(o: Record<string, unknown>): boolean {
  return o.horizon === "tactical";
}

/** Règles de `plan_day` selon le mode (texte prêt pour le workflow). */
export function modeRules(mode: DayMode): string[] {
  switch (mode) {
    case "low":
      return [
        `   → MODE FLEMME déclaré : blocs COURTS (≤ 30 min), routines et étapes simples d'abord, rien de nouveau ;`,
        `     une seule chose à la fois, pas de deep work, pas de relance sur ce qui n'est pas fait.`,
      ];
    case "high":
      return [
        `   → MODE EN FORME déclaré : UN bloc de deep work ≥ 90 min sur le coup en cours (sinon le projet le plus`,
        `     en retard), pas de dispersion ; les domaines en veille ne sont jamais programmés.`,
      ];
    default:
      return [`   → MODE NORMAL : rythme habituel ; les domaines en veille ne sont jamais programmés.`];
  }
}
