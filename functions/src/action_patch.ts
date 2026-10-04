/** Modification d'une action existante (projet ou activité) — logique pure.
 *  Champs : titre, contextes (remplacer / ajouter / retirer), estimation,
 *  activité liée, état fait. Renvoie l'action patchée et la liste des
 *  changements en clair (pour le retour outil). */
import { contextsOf, normalizeContext } from "./contexts";

export type ActionPatch = {
  title?: string;
  contexts?: string[];        // remplace tout ([] = aucun contexte)
  addContexts?: string[];
  removeContexts?: string[];
  estimatedMin?: number | null; // null = effacer
  linkedActivityId?: string | null; // null = délier (actions de projet)
  done?: boolean;
};

type ActionLike = Record<string, unknown>;

function cleanList(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  const out: string[] = [];
  for (const r of raw) {
    const c = normalizeContext(r);
    if (c && !out.includes(c)) out.push(c);
  }
  return out;
}

export function applyActionPatch(
  action: ActionLike, patch: ActionPatch, nowIso: string = new Date().toISOString(),
): { action: ActionLike; changes: string[] } {
  const changes: string[] = [];
  let a: ActionLike = { ...action };

  if (patch.title !== undefined) {
    const t = patch.title.trim().replace(/\s+/g, " ");
    if (t && t !== a.title) {
      changes.push(`titre « ${a.title ?? ""} » → « ${t} »`);
      a = { ...a, title: t };
    }
  }

  if (patch.contexts !== undefined || patch.addContexts !== undefined || patch.removeContexts !== undefined) {
    const before = contextsOf(a);
    let next = patch.contexts !== undefined ? cleanList(patch.contexts) : [...before];
    for (const c of cleanList(patch.addContexts)) if (!next.includes(c)) next.push(c);
    const rm = cleanList(patch.removeContexts);
    if (rm.length) next = next.filter((c) => !rm.includes(c));
    if (next.join("\u0000") !== before.join("\u0000")) {
      changes.push(`contextes ${before.length ? before.join(" ") : "(aucun)"} → ${next.length ? next.join(" ") : "(aucun)"}`);
      a = { ...a, contexts: next, context: next.length ? next[0] : null };
    }
  }

  if (patch.estimatedMin !== undefined) {
    const v = patch.estimatedMin;
    if (v !== null && (!Number.isFinite(v) || v < 0)) {
      changes.push("estimation ignorée (minutes ≥ 0 attendues)");
    } else {
      const n = v === null ? null : Math.round(v);
      const cur = typeof a.estimatedMin === "number" ? a.estimatedMin : null;
      if (n !== cur) {
        changes.push(`estimation ${cur === null ? "—" : `${cur} min`} → ${n === null ? "—" : `${n} min`}`);
        a = { ...a, estimatedMin: n };
      }
    }
  }

  if (patch.linkedActivityId !== undefined) {
    const v = patch.linkedActivityId && patch.linkedActivityId.trim() ? patch.linkedActivityId.trim() : null;
    const cur = typeof a.linkedActivityId === "string" && a.linkedActivityId ? a.linkedActivityId : null;
    if (v !== cur) {
      changes.push(v ? `activité liée → ${v}` : "activité déliée");
      a = { ...a, linkedActivityId: v };
    }
  }

  if (patch.done !== undefined && patch.done !== (a.done === true)) {
    changes.push(patch.done ? "marquée faite" : "rouverte");
    a = { ...a, done: patch.done, doneAt: patch.done ? nowIso : null };
    if (patch.done && Array.isArray(a.checklist)) {
      a = {
        ...a,
        checklist: (a.checklist as ActionLike[]).map((c) =>
          c.done === true ? c : { ...c, done: true, doneAt: nowIso }),
      };
    }
  }

  return { action: a, changes };
}
