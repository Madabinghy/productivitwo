/**
 * Routines réparties sur plusieurs moments (2026-10-30) — miroir serveur de
 * `splitMomentsOf` / `momentShareOf` (lib/utils/routine_moments.dart, **garder
 * alignés**). `Activity.splitMoments` = moments horaires (morning · midday ·
 * afternoon · evening), deux ou plus ; la cible du jour se partage entre eux
 * (cible ÷ moments, le surplus aux premiers, un moment sans part ignoré).
 *
 * 2026-11-21 : un cinquième moment, `miracle` (Miracle Morning, avant le
 * matin), et des parts RÉGLÉES (`Activity.momentShares` : moment → part),
 * lues au prorata (`momentParts`) pour que la somme suive la cible du jour.
 */

export const SPLIT_MOMENTS = ["miracle", "morning", "midday", "afternoon", "evening"] as const;

const LABEL: Record<string, string> = {
  miracle: "au Miracle Morning",
  morning: "le matin",
  midday: "le midi",
  afternoon: "l'après-midi",
  evening: "le soir",
};

const ALIASES: Record<string, string> = {
  miracle: "miracle", "miracle morning": "miracle", "miracle-morning": "miracle", miraclemorning: "miracle", reveil: "miracle", "réveil": "miracle",
  morning: "morning", matin: "morning",
  midday: "midday", midi: "midday", dejeuner: "midday", "déjeuner": "midday",
  afternoon: "afternoon", "apres-midi": "afternoon", "après-midi": "afternoon", apresmidi: "afternoon", aprem: "afternoon",
  evening: "evening", soir: "evening", diner: "evening", "dîner": "evening",
};

/**
 * Normalise une liste de moments (clés ou libellés français) dans l'ordre de
 * la journée. Moins de deux moments valides = [] (routine non répartie) ;
 * `unknown` liste ce qui n'a pas été reconnu.
 */
export function normalizeSplitMoments(input: unknown): { moments: string[]; unknown: string[] } {
  const list = Array.isArray(input) ? input : typeof input === "string" ? input.split(/[,+&]|\bet\b/) : [];
  const set = new Set<string>();
  const unknown: string[] = [];
  for (const raw of list) {
    const k = String(raw ?? "").replace(/[\[\]"']/g, "").trim().toLowerCase();
    if (!k) continue;
    const key = ALIASES[k];
    if (key) set.add(key);
    else unknown.push(String(raw).trim());
  }
  const ordered = SPLIT_MOMENTS.filter((m) => set.has(m));
  return { moments: ordered.length >= 2 ? [...ordered] : [], unknown };
}

/**
 * Parts réglées, ramenées aux moments [moments] : entiers ≥ 0, clés ou
 * libellés français. {} quand rien d'utilisable (parts égales).
 */
export function normalizeMomentShares(input: unknown, moments: string[]): Record<string, number> {
  if (!input || typeof input !== "object" || Array.isArray(input)) return {};
  const out: Record<string, number> = {};
  for (const [raw, v] of Object.entries(input as Record<string, unknown>)) {
    const key = ALIASES[String(raw).trim().toLowerCase()];
    const n = Math.floor(Number(v));
    if (!key || !moments.includes(key) || !Number.isFinite(n) || n < 0) continue;
    out[key] = n;
  }
  if (!Object.values(out).some((n) => n > 0)) return {};
  for (const m of moments) if (out[m] === undefined) out[m] = 0;
  return out;
}

/**
 * Les parts de [n] entre [moments] : égales sans réglage (le surplus aux
 * premiers), sinon au prorata des parts réglées, au plus fort reste (le
 * premier moment à égalité). Miroir de `momentParts` (routine_moments.dart).
 */
export function momentParts(n: number, moments: string[], shares: Record<string, number> = {}): number[] {
  if (!moments.length || n <= 0) return moments.map(() => 0);
  let w = moments.map((m) => Math.max(0, Math.floor(Number(shares[m] ?? 0))));
  let total = w.reduce((s, x) => s + x, 0);
  if (!Object.keys(shares).length || total === 0) {
    w = moments.map(() => 1);
    total = w.length;
  }
  const parts = w.map((x) => Math.floor((n * x) / total));
  let rest = n - parts.reduce((s, x) => s + x, 0);
  const order = w.map((_, i) => i).sort((a, b) => ((n * w[b]) % total) - ((n * w[a]) % total) || a - b);
  for (const i of order) {
    if (rest <= 0) break;
    if (w[i] === 0) continue;
    parts[i]++;
    rest--;
  }
  return parts;
}

/** Parts de la cible du jour par moment : [{moment, share}], sans part nulle. */
export function splitShares(target: number, moments: string[], shares: Record<string, number> = {}): Array<{ moment: string; share: number }> {
  const n = Math.max(0, Math.floor(target));
  if (moments.length < 2 || n <= 0) return [];
  const parts = momentParts(n, moments, shares);
  return moments
    .map((m, i) => ({ moment: m, share: parts[i] }))
    .filter((p) => p.share > 0);
}

/** « 10 le matin · 10 le soir » (vide si non répartie). */
export function splitLabel(target: number, moments: string[], shares: Record<string, number> = {}): string {
  return splitShares(target, moments, shares).map((p) => `${p.share} ${LABEL[p.moment] ?? p.moment}`).join(" · ");
}
