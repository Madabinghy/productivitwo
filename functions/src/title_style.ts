// ── Règles d'écriture des titres (A, 2026-10) ────────────────────────────────
// Diagnostic : Claude écrit des titres « cahier des charges » (codes, coefs,
// consignes d'impression, parenthèses) pensés pour un Claude futur, et l'app les
// affiche tels quels dans Aujourd'hui. Un titre doit se lire au moment de
// FAIRE : verbe + objet, dans les mots de l'utilisateur. Le détail va dans
// `note` (action) ou `description` (tâche). Ce module ne réécrit jamais un
// titre : il signale, l'appelant décide.

export const TITLE_MAX = 80;

/** Texte partagé par les descriptions d'outils (push_gantt, add_task,
 *  update_task, update_action, add_activity_action, schedule_day). */
export const WRITING_RULES =
  "RÈGLES D'ÉCRITURE (l'utilisateur lit ces titres dans l'app, pas toi) : " +
  "un titre = verbe + objet, dans ses mots, ≤ 8 mots, sans parenthèse ni code (pas de « 1.B.1 », " +
  "« coef. 2 », « recto verso ×19 », « CM1.2 : »). Tout le détail utile (consignes, quantités, fichiers, " +
  "contraintes, rappels à toi-même) va dans `note` pour une action, `description` pour une tâche — " +
  "jamais dans le titre. Tâche de séance : garde la forme courte « 📝 Préparer — Séance du 12 oct » / " +
  "« 🎯 Lun 12 oct — <thème en 3 mots> » / « ✅ Clôturer — Séance du 12 oct », le contenu détaillé dans " +
  "description. Une chose n'a qu'UNE maison : pas de tâche « Corriger… » si une action « Corriger… » " +
  "existe déjà dans la prépa. " +
  "DATES : `focusDate` = le jour visé (quand l'utilisateur veut l'action sous la main — la date par défaut, une " +
  "intention, jamais en retard) ; `dueDate` = une VRAIE échéance seulement (séance, rendu, démarche).";

const ROLE_EMOJI = /^(📝|🎯|✅|🏁|✍️)\s*/u;
const SPEC_TOKENS = /(\bcoef\.?\s*\d|\brecto\s*verso\b|×\s*\d+|\bx\s*\d+\b|\b\d+\.[A-Z]\.?\d*\b|\bp\.\s*\d+|\bex\.?\s*\d|\bCM[12]\b\s*[:.]|\(\s*\d+\s*(pages?|min)\b)/iu;

export interface TitleCheck {
  warnings: string[];
  /** Titre tel qu'il devrait être lu (sans emoji de rôle quand la structure le porte). */
  suggested?: string;
}

export function checkTitle(
  title: string,
  opts: { kind: "task" | "action" | "block"; interventionRole?: string | null } = { kind: "action" }
): TitleCheck {
  const t = (title ?? "").trim();
  const warnings: string[] = [];
  let suggested: string | undefined;
  if (!t) return { warnings };

  if (t.length > TITLE_MAX) {
    warnings.push(`titre long (${t.length} car.) : garde verbe + objet, mets le détail dans ${opts.kind === "task" ? "description" : "note"}`);
  }
  const parens = (t.match(/\(/g) ?? []).length;
  if (parens >= 1 && t.length > 50) {
    warnings.push("parenthèses dans le titre : les précisions vont dans le détail");
  }
  if (SPEC_TOKENS.test(t)) {
    warnings.push("codes / consignes dans le titre (coef., p., ×n, 1.B.1…) : à déplacer dans le détail");
  }
  // Tâche de séance : l'émoji de rôle reste le repère visuel de l'app (pas encore
  // rendu depuis la structure) ; on vérifie seulement la longueur du titre nu.
  if (opts.interventionRole && ROLE_EMOJI.test(t)) suggested = t.replace(ROLE_EMOJI, "");
  const words = t.split(/\s+/).length;
  if (words > 14) warnings.push(`${words} mots : un titre se dit en une respiration`);
  return { warnings, suggested };
}

/** Une ligne d'avertissement pour la réponse d'un outil, ou "" si rien. */
export function titleAdvice(items: Array<{ title: string; kind: "task" | "action"; interventionRole?: string | null }>): string {
  const rows: string[] = [];
  for (const it of items) {
    const c = checkTitle(it.title, { kind: it.kind, interventionRole: it.interventionRole });
    if (c.warnings.length) rows.push(`• « ${it.title.length > 60 ? `${it.title.slice(0, 57)}…` : it.title} » — ${c.warnings[0]}`);
    if (rows.length >= 4) break;
  }
  if (!rows.length) return "";
  return `\n✍️ Titres à alléger (règle : verbe + objet, détail dans note / description) :\n${rows.join("\n")}`;
}
