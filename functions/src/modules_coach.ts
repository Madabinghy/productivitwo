// Modules (lot 5, 2026-11-16) : le coach voit les modules allumés de son coaché (jamais Liberté) et peut en
// proposer un. Aligné sur lib/utils/modules.dart (clés) et lib/utils/module_journey.dart (pending).

export const MODULE_NAMES: Record<string, string> = {
  modes: "Modes d'action",
  planning: "Planification",
  game: "Jeu et badges",
  seasons: "Saisons",
  sleep: "Sommeil",
  sport: "Sport",
  kitchen: "Cuisine",
  finances: "Finances",
  freedom: "Liberté",
  analysis: "Analyse",
  trainer: "Formateur",
  assistant: "Assistant",
};

/** Privé : le coach ne le voit jamais et ne peut pas le proposer. */
export const PRIVATE_MODULES = new Set(["freedom"]);

type Json = Record<string, unknown>;

/** Les modules allumés, vus par le coach. Absent = compte d'avant les modules, tout allumé. */
export function coachModuleView(raw: unknown): { on: string[]; offered: string[]; pending: string | null } {
  const keys = Object.keys(MODULE_NAMES).filter((k) => !PRIVATE_MODULES.has(k));
  const m = (raw && typeof raw === "object" ? raw : {}) as Json;
  const list = Array.isArray(m.on) ? (m.on as unknown[]).map(String) : null;
  const on = list === null ? keys : keys.filter((k) => list.includes(k));
  const pending = typeof m.pending === "string" && !PRIVATE_MODULES.has(m.pending) ? m.pending : null;
  return { on, offered: keys.filter((k) => !on.includes(k)), pending };
}

/** Le correctif à écrire dans `data/meta.modules` pour une proposition du coach, ou une erreur. */
export function planCoachProposal(
  raw: unknown,
  key: string,
  coachName: string,
  today: string,
): { patch: Json } | { error: string } {
  if (!(key in MODULE_NAMES)) return { error: `module inconnu : ${key}` };
  if (PRIVATE_MODULES.has(key)) return { error: "ce module est privé" };
  const view = coachModuleView(raw);
  if (view.on.includes(key)) return { error: "déjà allumé" };
  return { patch: { pending: key, pendingBy: "coach", pendingCoach: coachName, lastProposed: today } };
}
