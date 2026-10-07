// Revue hebdo des orphelins (brief 2026-10, § 2.5 + B5 + B7) : logique pure.
// Un passage sur tous les projets produit une liste de constats à valider,
// chacun avec l'appel MCP qui le corrige. Rien n'est modifié ici.

type AnyRec = Record<string, unknown>;

export interface AuditProject {
  id: string;
  title: string;
  status: string;
  paused?: boolean;
  startDate?: string;
  endDate?: string;
  parentProjectId?: string | null;
  phases: AnyRec[];
  tasks: AnyRec[];
  interventions: AnyRec[];
}

export type FindingKind =
  | "task_without_phase"
  | "task_outside_phase"
  | "milestone_overdue"
  | "closure_overdue"
  | "inactive_with_upcoming"
  | "no_milestone_14d"
  | "duplicate_projects"
  | "unmigrated_triplet";

export interface Finding {
  kind: FindingKind;
  projectId: string;
  projectTitle: string;
  text: string;
  /** Appel MCP suggéré, prêt à copier. */
  fix?: string;
}

const ymd = (v: unknown) => String(v ?? "").slice(0, 10);
const lead = (t: AnyRec, re: RegExp) => re.test(String(t.title ?? "").trimStart());
const isSession = (t: AnyRec) => t.isMilestone === true || lead(t, /^(🎯|🏁)/);
const isClosure = (t: AnyRec) => t.interventionRole === "closure" || lead(t, /^✅/);
const isPrep = (t: AnyRec) => t.interventionRole === "prep" || lead(t, /^📝/);
const live = (t: AnyRec) => t.status !== "skipped" && t.status !== "done";

export function addDays(ymdStr: string, n: number): string {
  const d = new Date(`${ymdStr}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** Jalons / séances à venir d'un projet (date ≥ today), tâches ou interventions natives. */
export function upcomingSessions(p: AuditProject, today: string): Array<{ date: string; title: string }> {
  const out = new Map<string, { date: string; title: string }>();
  for (const i of p.interventions) {
    if (i.status === "cancelled" || i.status === "done") continue;
    const d = ymd(i.date);
    if (d >= today) out.set(`i:${i.id}`, { date: d, title: String(i.title) });
  }
  for (const t of p.tasks) {
    if (!live(t) || !isSession(t) || t.interventionId) continue;
    const d = ymd(t.endDate ?? t.startDate);
    if (d >= today) out.set(`t:${t.id}`, { date: d, title: String(t.title) });
  }
  return [...out.values()].sort((a, b) => a.date.localeCompare(b.date));
}

/** Clé de similarité de titre : minuscules sans accents, mots ≥ 3 lettres hors parasites. */
export function titleKey(title: string): Set<string> {
  const stop = new Set(["les", "des", "une", "pour", "avec", "dans", "sur", "mathematiques", "maths", "projet"]);
  return new Set(
    String(title ?? "")
      .toLowerCase()
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .replace(/[^a-z0-9]+/g, " ")
      .split(" ")
      // « 6e », « 5e », « cm1 » comptent : ce sont souvent les seuls mots discriminants.
      .filter((w) => (w.length >= 3 || /\d/.test(w)) && !stop.has(w))
  );
}

const overlapPeriod = (a: AuditProject, b: AuditProject) => {
  const aS = ymd(a.startDate) || "0000", aE = ymd(a.endDate) || "9999";
  const bS = ymd(b.startDate) || "0000", bE = ymd(b.endDate) || "9999";
  return aS <= bE && bS <= aE;
};

/** Doublons potentiels : ≥ 60 % de mots communs (Jaccard sur le plus petit) + périodes qui se chevauchent. */
export function similarProjects(p: AuditProject, others: AuditProject[]): AuditProject[] {
  const k = titleKey(p.title);
  if (k.size === 0) return [];
  return others.filter((o) => {
    if (o.id === p.id || !overlapPeriod(p, o)) return false;
    const ok = titleKey(o.title);
    if (ok.size === 0) return false;
    const common = [...k].filter((w) => ok.has(w)).length;
    const minSize = Math.min(k.size, ok.size);
    // « 6e — Mathématiques » vs « 6e/5e — Mathématiques » : un seul mot utile, commun.
    return common / minSize >= 0.6 && (common >= 2 || minSize === 1);
  });
}

export function auditProjects(projects: AuditProject[], today: string, opts: { horizonDays?: number } = {}): Finding[] {
  const horizon = addDays(today, opts.horizonDays ?? 14);
  const out: Finding[] = [];
  const hasChildren = new Set(projects.map((p) => p.parentProjectId).filter(Boolean) as string[]);
  const activeLive = projects.filter((p) => p.status === "active" && !p.paused);

  for (const p of projects) {
    const f = (kind: FindingKind, text: string, fix?: string) =>
      out.push({ kind, projectId: p.id, projectTitle: p.title, text, fix });
    const phaseIds = new Set(p.phases.map((ph) => String(ph.id)));
    const isFolder = p.tasks.length === 0 && hasChildren.has(p.id);
    const inactive = p.status === "archived" || p.paused === true;

    if (inactive) {
      // B5 : projet en veille / archivé qui porte encore des séances à venir.
      const up = upcomingSessions(p, today);
      if (up.length) {
        f("inactive_with_upcoming",
          `${p.status === "archived" ? "archivé" : "en pause"} mais ${up.length} séance(s) à venir : ${up.slice(0, 3).map((u) => `${u.date} « ${u.title} »`).join(" · ")}${up.length > 3 ? "…" : ""}`,
          p.status === "archived"
            ? `archive_project(projectId:"${p.id}", restore:true) — ou update_intervention(status:"cancelled") / update_task_status(skipped) sur chaque séance`
            : `update_project(projectId:"${p.id}", paused:false) — ou annule les séances`);
      }
      continue;
    }
    if (p.status !== "active") continue;

    // Tâches sans phase / hors des dates de leur phase.
    if (phaseIds.size > 0) {
      for (const t of p.tasks) {
        if (!live(t)) continue;
        const pid = typeof t.phaseId === "string" ? t.phaseId : "";
        if (!pid || !phaseIds.has(pid)) {
          f("task_without_phase", `« ${t.title} » (${ymd(t.startDate)}) sans phase`,
            `update_task(projectId:"${p.id}", taskId:"${t.id}", phaseId:"<libellé ou id de phase>")`);
          continue;
        }
        const ph = p.phases.find((x) => String(x.id) === pid)!;
        const s = ymd(t.startDate), e = ymd(t.endDate ?? t.startDate);
        const ps = ymd(ph.startDate), pe = ymd(ph.endDate);
        if (s < ps || e > pe) {
          f("task_outside_phase",
            `« ${t.title} » (${s} → ${e}) hors de sa phase « ${ph.label} » (${ps} → ${pe})`,
            `update_task(projectId:"${p.id}", taskId:"${t.id}", startDate|endDate|phaseId…)`);
        }
      }
    }

    // Jalons passés non cochés, clôtures non faites.
    for (const t of p.tasks) {
      if (!live(t)) continue;
      const d = ymd(t.endDate ?? t.startDate);
      if (isSession(t) && d < today) {
        f("milestone_overdue", `jalon « ${t.title} » du ${d} non coché`,
          `update_task_status(projectId:"${p.id}", taskId:"${t.id}", status:"done") (ou skipped si la séance n'a pas eu lieu)`);
      } else if (isClosure(t) && d < today) {
        const open = ((t.actions as AnyRec[]) ?? []).filter((a) => a.done !== true).length;
        f("closure_overdue", `clôture « ${t.title} » (échéance ${d}) : ${open || "des"} action(s) encore ouverte(s)`,
          `mark_action_done / update_task_status(projectId:"${p.id}", taskId:"${t.id}", status:"done")`);
      }
    }

    // Triplets non migrés (📝 / ✅ sans interventionId).
    const unmigrated = p.tasks.filter((t) => live(t) && !t.interventionId && (isPrep(t) || isClosure(t) || isSession(t)));
    if (unmigrated.length >= 2) {
      f("unmigrated_triplet", `${unmigrated.length} tâche(s) 📝 / 🎯 / ✅ sans intervention native`,
        `migrate_interventions(projectId:"${p.id}") (dryRun) puis dryRun:false`);
    }

    // Projet actif sans jalon à 14 jours → mise en veille (règle d'usage § 5).
    if (!isFolder) {
      const up = upcomingSessions(p, today).filter((u) => u.date <= horizon);
      const hasLiveMilestones = p.tasks.some((t) => isSession(t));
      if (hasLiveMilestones && up.length === 0) {
        const next = upcomingSessions(p, today)[0];
        f("no_milestone_14d",
          next ? `aucune séance avant le ${next.date} (« ${next.title} »)` : "aucune séance à venir",
          `update_project(projectId:"${p.id}", paused:true) — le Gantt redevient un radar des séances à venir`);
      }
    }
  }

  // B7 : doublons de projets actifs (titre proche + période qui se chevauche), une fois par paire.
  const seen = new Set<string>();
  for (const p of activeLive) {
    for (const o of similarProjects(p, activeLive)) {
      const key = [p.id, o.id].sort().join("|");
      if (seen.has(key)) continue;
      seen.add(key);
      out.push({
        kind: "duplicate_projects", projectId: p.id, projectTitle: p.title,
        text: `« ${p.title} » et « ${o.title} » se ressemblent sur la même période`,
        fix: `fusionner : update_task(... déplacer les tâches) puis archive_project(projectId:"${o.id}") — ou update_project(parentProjectId) si l'un est le dossier de l'autre`,
      });
    }
  }
  return out;
}

export const KIND_LABEL: Record<FindingKind, string> = {
  task_without_phase: "Tâches sans phase",
  task_outside_phase: "Tâches hors des dates de leur phase",
  milestone_overdue: "Jalons passés non cochés",
  closure_overdue: "Clôtures non faites",
  inactive_with_upcoming: "Projets en veille / archivés avec des séances à venir",
  no_milestone_14d: "Projets actifs sans séance à 14 jours (à mettre en veille ?)",
  duplicate_projects: "Doublons de projets probables",
  unmigrated_triplet: "Triplets 📝 / 🎯 / ✅ non migrés",
};

export const KIND_ORDER: FindingKind[] = [
  "inactive_with_upcoming", "milestone_overdue", "closure_overdue", "task_without_phase",
  "task_outside_phase", "duplicate_projects", "no_milestone_14d", "unmigrated_triplet",
];

export function formatFindings(findings: Finding[], today: string): string {
  if (!findings.length) return `✅ Revue du ${today} : rien d'orphelin — tout est rangé.`;
  const out = [`🧹 REVUE HEBDO (${today}) — ${findings.length} point(s) à valider. Rien n'a été modifié : propose, l'utilisateur dispose.`];
  for (const kind of KIND_ORDER) {
    const rows = findings.filter((f) => f.kind === kind);
    if (!rows.length) continue;
    out.push(``, `── ${KIND_LABEL[kind]} (${rows.length}) ──`);
    for (const r of rows) {
      out.push(`• [${r.projectTitle}] ${r.text}`);
      if (r.fix) out.push(`    → ${r.fix}`);
    }
  }
  return out.join("\n");
}
