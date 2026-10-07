// Estimation par défaut d'une action à sa création (brief 2026-10, § 2.4) :
// quand ni l'utilisateur ni l'IA n'ont posé `estimatedMin`, on déduit une
// durée plausible du verbe / de l'objet de l'action (imprimer 10, fiche de
// séquence 15, corriger 45…). Le filtre « J'ai 20 min » et le planificateur
// de prépa s'en servent ; `estimate_accuracy` corrige ensuite avec le réel.
// Logique pure ; null = aucune règle ne s'applique (l'app compte 45 min).

const norm = (s: unknown) =>
  String(s ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "");

interface Rule { test: RegExp; min: number; label: string }

/** Ordre = priorité : la première règle qui matche gagne. */
export const DEFAULT_ESTIMATE_RULES: Rule[] = [
  { test: /\bderouler\b/, min: 0, label: "déroulé (durée = créneau)" },
  { test: /\b(imprimer|impression|photocopi)/, min: 10, label: "impression" },
  { test: /adapter au bilan|reprendre le non[- ]fait|reprendre le bilan/, min: 15, label: "adapter au bilan" },
  { test: /remplir la fiche de sequence|fiche de sequence \(realise/, min: 15, label: "fiche de séquence (bilan)" },
  { test: /fiche de sequence/, min: 15, label: "fiche de séquence" },
  { test: /\b(corriger|correction)\b.*\b(copies|controle|evaluation|dm|devoirs?)\b|\bcorriger les copies\b|\bcorriger\b/, min: 45, label: "correction" },
  { test: /\b(saisir|reporter|noter)\b.*\b(notes?|ligues?|resultats?)\b|\bsaisir les notes\b/, min: 10, label: "saisie des notes" },
  { test: /\bnoter (le report|ce qui)/, min: 5, label: "report" },
  { test: /\b(deposer|envoyer|poster|publier|transmettre)\b/, min: 5, label: "dépôt / envoi" },
  { test: /\b(relire|verifier|checker)\b/, min: 10, label: "relecture" },
  { test: /\bkahoot\b/, min: 20, label: "Kahoot" },
  { test: /\b(appeler|telephoner|rappeler|mail|courriel|message|ecrire a)\b/, min: 10, label: "contact" },
  { test: /\b(rediger|creer|produire|concevoir|preparer|construire|elaborer|definir)\b/, min: 45, label: "production" },
  { test: /\b(ranger|classer|archiver|nettoyer)\b/, min: 15, label: "rangement" },
];

/** Minutes par défaut pour un titre d'action, ou null si aucune règle. 0 = « durée du créneau » (dérouler) → null aussi. */
export function defaultEstimateFor(title: unknown, contexts: unknown[] = []): number | null {
  const t = norm(title);
  if (!t.trim()) return null;
  const ctx = contexts.map(norm);
  if (ctx.some((c) => c === "@impression")) return 10;
  for (const r of DEFAULT_ESTIMATE_RULES) {
    if (r.test.test(t)) return r.min > 0 ? r.min : null;
  }
  return null;
}

/** Règle qui a joué (pour expliquer la valeur dans une réponse MCP). */
export function defaultEstimateLabel(title: unknown, contexts: unknown[] = []): string | null {
  const t = norm(title);
  if (contexts.map(norm).some((c) => c === "@impression")) return "impression";
  for (const r of DEFAULT_ESTIMATE_RULES) if (r.test.test(t)) return r.min > 0 ? r.label : null;
  return null;
}
