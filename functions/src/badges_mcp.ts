/**
 * Badges côté MCP (lot B chasse, 2026-10) — logique pure. Le deck est calculé par
 * l'APP (lib/utils/badges_logic.dart) qui en dépose un instantané dans
 * `users/{uid}/data/badges` à chaque recalcul ; le serveur ne recalcule rien :
 * il lit l'instantané, le résume, et gère les chasses (`data/meta.badgeHunts`).
 */

export const MAX_BADGE_HUNTS = 3;

export interface BadgeSnapshotItem {
  id: string;
  family: string;
  name: string;
  level: number; // paliers atteints
  tiers: number[];
  value: number;
  unit?: string;
  nextTarget?: number | null;
  obtained?: string | null; // YYYY-MM-DD du dernier palier
  measured?: boolean;
}

export interface BadgeSnapshot {
  updatedAt?: string;
  acquired: number;
  total: number;
  badges: BadgeSnapshotItem[];
}

export interface BadgeHuntDoc {
  badgeId: string;
  tier: number;
  since: string;
  targetDate?: string;
}

export const FAMILY_LABELS: Record<string, string> = {
  routines: "Séries de routine",
  objectives: "Objectifs",
  days: "Journées",
  discipline: "Discipline",
  chain: "Enchaîner",
  actions: "Actions accomplies",
  time: "Temps investi",
};

export function parseSnapshot(raw: unknown): BadgeSnapshot | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const badges = Array.isArray(r.badges) ? (r.badges as unknown[]).map(parseItem).filter((b): b is BadgeSnapshotItem => b !== null) : [];
  return {
    updatedAt: typeof r.updatedAt === "string" ? r.updatedAt : undefined,
    acquired: Number(r.acquired) || 0,
    total: Number(r.total) || 0,
    badges,
  };
}

function parseItem(raw: unknown): BadgeSnapshotItem | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.id !== "string" || !r.id) return null;
  const tiers = Array.isArray(r.tiers) ? (r.tiers as unknown[]).map(Number).filter((n) => isFinite(n)) : [];
  return {
    id: r.id,
    family: String(r.family ?? ""),
    name: String(r.name ?? r.id),
    level: Number(r.level) || 0,
    tiers,
    value: Number(r.value) || 0,
    unit: typeof r.unit === "string" ? r.unit : undefined,
    nextTarget: typeof r.nextTarget === "number" ? r.nextTarget : null,
    obtained: typeof r.obtained === "string" ? r.obtained : null,
    measured: r.measured !== false,
  };
}

export function parseHunts(raw: unknown): BadgeHuntDoc[] {
  if (!Array.isArray(raw)) return [];
  const out: BadgeHuntDoc[] = [];
  for (const h of raw) {
    if (!h || typeof h !== "object") continue;
    const r = h as Record<string, unknown>;
    if (typeof r.badgeId !== "string" || !r.badgeId) continue;
    out.push({
      badgeId: r.badgeId,
      tier: Number(r.tier) || 1,
      since: String(r.since ?? ""),
      ...(typeof r.targetDate === "string" ? { targetDate: r.targetDate } : {}),
    });
  }
  return out;
}

/** Vérifie une chasse contre l'instantané : badge connu, mesuré, palier restant, trois au plus. */
export function validateHunt(
  snap: BadgeSnapshot | null,
  hunts: BadgeHuntDoc[],
  badgeId: string,
  tier: number | undefined,
  targetDate: string | undefined
): { ok: true; hunt: BadgeHuntDoc; badge: BadgeSnapshotItem } | { ok: false; error: string } {
  if (!snap) return { ok: false, error: "Aucun instantané de badges : ouvre l'app une fois (onglet Objectifs) pour que le deck soit calculé." };
  const badge = snap.badges.find((b) => b.id === badgeId);
  if (!badge) return { ok: false, error: `Badge « ${badgeId} » inconnu — list_badges donne les ids.` };
  if (badge.measured === false) return { ok: false, error: `« ${badge.name} » n'est pas encore mesuré.` };
  const levels = Math.max(1, badge.tiers.length);
  const t = tier ?? badge.level + 1;
  if (!Number.isInteger(t) || t < 1 || t > levels) return { ok: false, error: `Palier ${t} invalide pour « ${badge.name} » (1 à ${levels}).` };
  if (t <= badge.level) return { ok: false, error: `Le palier ${t} de « ${badge.name} » est déjà atteint.` };
  if (targetDate !== undefined && !/^\d{4}-\d{2}-\d{2}$/.test(targetDate)) return { ok: false, error: "targetDate : YYYY-MM-DD." };
  const others = hunts.filter((h) => h.badgeId !== badgeId);
  if (others.length >= MAX_BADGE_HUNTS) return { ok: false, error: `Trois chasses au plus : retire-en une d'abord (${others.map((h) => h.badgeId).join(", ")}).` };
  return { ok: true, hunt: { badgeId, tier: t, since: new Date().toISOString().slice(0, 10), ...(targetDate ? { targetDate } : {}) }, badge };
}

function fmtN(n: number): string {
  return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
}

/** Une ligne par chasse : « Méditation · palier 66 j · 34 / 66 · d'ici le 2026-11-27 ». */
export function huntLines(snap: BadgeSnapshot | null, hunts: BadgeHuntDoc[]): string[] {
  return hunts.map((h) => {
    const b = snap?.badges.find((x) => x.id === h.badgeId);
    if (!b) return `${h.badgeId} · palier ${h.tier}`;
    const target = b.tiers[h.tier - 1] ?? h.tier;
    const unit = b.unit ? ` ${b.unit}` : "";
    const caught = b.level >= h.tier;
    return `${b.name} · palier ${fmtN(target)}${unit} · ${caught ? "ATTEINT" : `${fmtN(b.value)} / ${fmtN(target)}${unit}`}${h.targetDate ? ` · d'ici le ${h.targetDate}` : ""}`;
  });
}

/** Résumé compact pour get_user_context. */
export function badgesSummary(snap: BadgeSnapshot | null, hunts: BadgeHuntDoc[]): Record<string, unknown> | null {
  if (!snap) return null;
  const last = snap.badges.filter((b) => b.obtained).sort((a, b) => String(b.obtained).localeCompare(String(a.obtained)))[0];
  // Un palier « proche » : il reste ≤ 20 % du prochain palier, ou ≤ 3 jours pour une série.
  const close = snap.badges
    .filter((b) => b.measured !== false && b.nextTarget && b.value > 0)
    .map((b) => ({ b, left: (b.nextTarget as number) - b.value }))
    .filter(({ b, left }) => left > 0 && (left <= Math.max(1, (b.nextTarget as number) * 0.2) || (b.family === "routines" && left <= 3)))
    .sort((x, y) => x.left / (x.b.nextTarget as number) - y.left / (y.b.nextTarget as number))
    .slice(0, 3)
    .map(({ b, left }) => `${b.name} : encore ${fmtN(left)}${b.unit ? " " + b.unit : ""} avant le palier ${fmtN(b.nextTarget as number)}`);
  return {
    acquired: snap.acquired,
    total: snap.total,
    ...(last ? { lastObtained: `${last.name} (${last.obtained})` } : {}),
    hunts: huntLines(snap, hunts),
    closeToTier: close,
    _hint: "Une chasse se PROPOSE (hunt_badge) quand un palier est proche et que l'utilisateur en parle ou le demande ; jamais imposée, trois au plus. Un badge est un fait : cite-le, ne le commente pas.",
  };
}

/** Liste lisible du deck pour list_badges. */
export function formatBadgeList(snap: BadgeSnapshot | null, hunts: BadgeHuntDoc[]): string {
  if (!snap) return "Aucun instantané de badges : ouvre l'app une fois (onglet Objectifs) pour que le deck soit calculé.";
  const lines: string[] = [`BADGES — ${snap.acquired} / ${snap.total} paliers (hors séries de routine)${snap.updatedAt ? ` · instantané du ${snap.updatedAt.slice(0, 16).replace("T", " ")}` : ""}`];
  if (hunts.length) {
    lines.push("", `EN CHASSE (${hunts.length} / ${MAX_BADGE_HUNTS}) :`);
    for (const l of huntLines(snap, hunts)) lines.push(`  🎯 ${l}`);
  }
  const families = ["routines", "objectives", "days", "discipline", "chain", "actions", "time"];
  for (const f of families) {
    const items = snap.badges.filter((b) => b.family === f);
    if (!items.length) continue;
    lines.push("", `${FAMILY_LABELS[f] ?? f} :`);
    for (const b of items) {
      const levels = b.tiers.length;
      const unit = b.unit ? ` ${b.unit}` : "";
      const state = b.measured === false
        ? "pas encore mesuré"
        : b.level >= levels
          ? `complet (${fmtN(b.tiers[levels - 1] ?? 1)}${unit})`
          : b.nextTarget
            ? `${fmtN(b.value)} / ${fmtN(b.nextTarget)}${unit}`
            : "pas encore";
      const tiers = levels > 1 ? ` · paliers ${b.tiers.map(fmtN).join(" / ")} · ${b.level} atteint${b.level > 1 ? "s" : ""}` : "";
      lines.push(`  ${b.level > 0 ? "✓" : "▢"} ${b.name} [${b.id}] — ${state}${tiers}${b.obtained ? ` · obtenu le ${b.obtained}` : ""}`);
    }
  }
  return lines.join("\n");
}
