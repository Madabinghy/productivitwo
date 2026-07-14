// ─── MÉTA-CONTEXTES HORAIRES DES ROUTINES — MIROIR SERVEUR ───────────────────
//
// Miroir de lib/utils/routine_context.dart (source de vérité côté app —
// garder les deux en phase). Consommé par proposeDayPlan : la ligne
// « contexte : soir » du prompt + le placement déterministe du programme
// idéal (une routine sans heure mesurée se pose dans SA fenêtre, jamais en
// cascade aveugle après le lever).

export type TimeContextDef = {
  key: string;
  label: string;
  windows: Array<[number, number]>; // minutes depuis minuit — vide = libre
  anchorMin: number; // heure de pose par défaut
};

export const TIME_CONTEXTS: Record<string, TimeContextDef> = {
  morning: { key: "morning", label: "matin", windows: [[330, 660]], anchorMin: 450 },
  midday: { key: "midday", label: "midi", windows: [[690, 840]], anchorMin: 750 },
  afternoon: { key: "afternoon", label: "après-midi", windows: [[840, 1140]], anchorMin: 930 },
  evening: { key: "evening", label: "soir", windows: [[1140, 1410]], anchorMin: 1260 },
  meal: { key: "meal", label: "repas", windows: [[690, 810], [1110, 1230]], anchorMin: 720 },
  day: { key: "day", label: "journée", windows: [[420, 1200]], anchorMin: 600 },
  allday: { key: "allday", label: "toute la journée", windows: [[360, 1380]], anchorMin: 540 },
  any: { key: "any", label: "libre", windows: [], anchorMin: 600 },
};

const ARCHETYPES: Array<{ keywords: string[]; contextKey: string }> = [
  { keywords: ["hygiene du soir", "routine du soir", "routine soir", "coucher", "skincare", "demaquill"], contextKey: "evening" },
  { keywords: ["hygiene du matin", "routine du matin", "routine matin", "miracle morning", "vitamine"], contextKey: "morning" },
  { keywords: ["boire", "eau", "hydrat"], contextKey: "allday" },
  { keywords: ["cuisin", "repas", "gamelle", "meal prep", "batch cooking"], contextKey: "meal" },
  { keywords: ["sport", "muscu", "pompes", "traction", "course", "running", "footing", "velo", "natation", "etirement", "yoga", "gym", "entrainement"], contextKey: "day" },
  { keywords: ["menage", "vaisselle", "rangement", "lessive"], contextKey: "day" },
  { keywords: ["sommeil", "dormir"], contextKey: "evening" },
];

/** Repli casse + accents — même logique que foldName côté app. */
function fold(s: string): string {
  return s
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "");
}

/** Contexte effectif d'une routine : override utilisateur (`timeContext`)
 *  d'abord, archétype du nom sinon, null si aucune évidence. */
export function routineTimeContext(
  name: string,
  overrideKey?: string | null
): TimeContextDef | null {
  if (overrideKey && TIME_CONTEXTS[overrideKey]) return TIME_CONTEXTS[overrideKey];
  const n = fold(String(name ?? "").trim());
  if (n.length < 3) return null;
  for (const a of ARCHETYPES) {
    if (a.keywords.some((k) => n.includes(k))) return TIME_CONTEXTS[a.contextKey];
  }
  return null;
}
