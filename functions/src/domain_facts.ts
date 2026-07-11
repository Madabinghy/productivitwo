import { db } from "./db";

// ─── DOSSIER DE FAITS D'UN DOMAINE (sessions de définition 19/20) ─────────────
//
// Agrégats DÉTERMINISTES injectés dans le prompt define_domain : le coach ne
// part pas de zéro sur un domaine vivant (heures réelles par activité, blocs
// sautés + motifs, artefacts existants à ADOPTER), et sur un domaine sans
// données, le vide lui-même est le point de départ (ce qu'on voit en creux :
// dimanches travaillés, soirées vides). Aucun chiffre inventé : une donnée
// absente = ligne omise.

export interface DomainDossier {
  mode: "vivant" | "vide";
  text: string; // lignes de faits prêtes pour le prompt ("" si aucune)
}

const DAY_MS = 86400000;

export async function buildDomainDossier(
  uid: string,
  domainName: string
): Promise<DomainDossier> {
  const now = new Date();
  const sinceIso = new Date(now.getTime() - 42 * DAY_MS).toISOString(); // 6 sem
  const last14: string[] = [];
  for (let i = 1; i <= 14; i++) {
    last14.push(new Date(now.getTime() - i * DAY_MS).toISOString().slice(0, 10));
  }

  const [domainsSnap, actsSnap, sessionsSnap, artsSnap, projectsSnap, schedSnaps] =
    await Promise.all([
      db.collection(`users/${uid}/domains`).get(),
      db.collection(`users/${uid}/activities`).get(),
      db.collection(`users/${uid}/sessions`).where("startAt", ">=", sinceIso).get(),
      db.collection(`users/${uid}/artifacts`).get(),
      db.collection(`users/${uid}/projects`).get(),
      Promise.all(last14.map((d) => db.doc(`users/${uid}/daily_schedules/${d}`).get())),
    ]);

  const domain = domainsSnap.docs
    .map((d) => d.data() as Record<string, unknown>)
    .find(
      (v) =>
        v.deleted !== true &&
        String(v.name ?? "").trim().toLowerCase() ===
          domainName.trim().toLowerCase()
    );
  const domainId = domain ? String(domain.id ?? "") : null;

  // Activités du domaine (les 0 h comptent : c'est la matière de la
  // confrontation déclaré vs réel).
  const domainActs = new Map<string, string>(); // activityId → nom
  for (const a of actsSnap.docs) {
    const data = a.data() as Record<string, unknown>;
    if (data.deleted === true) continue;
    if (domainId && data.domainId === domainId) {
      domainActs.set(a.id, String(data.name ?? a.id));
    }
  }

  const minutesByAct = new Map<string, number>();
  for (const s of sessionsSnap.docs) {
    const actId = String(s.get("activityId") ?? "");
    if (!domainActs.has(actId)) continue;
    const start = new Date(String(s.get("startAt"))).getTime();
    const endRaw = s.get("endAt");
    const end = endRaw ? new Date(String(endRaw)).getTime() : start;
    minutesByAct.set(
      actId,
      (minutesByAct.get(actId) ?? 0) + Math.max(0, (end - start) / 60000)
    );
  }

  // Blocs du domaine sur 14 jours : sautés + motifs, par engagement.
  const skipStats = new Map<string, { skips: number; causes: Map<string, number> }>();
  let domainBlocksSeen = 0;
  for (const snap of schedSnaps) {
    if (!snap.exists) continue;
    const blocks =
      ((snap.data() as Record<string, unknown>).blocks as Array<
        Record<string, unknown>
      >) ?? [];
    for (const b of blocks) {
      if (b.status === "deleted" || b.kind === "prep" || b.category === "break") continue;
      if (!domainActs.has(String(b.activityId ?? ""))) continue;
      domainBlocksSeen++;
      if (b.status === "done") continue;
      const title = String(b.title ?? "");
      const entry = skipStats.get(title) ?? { skips: 0, causes: new Map() };
      entry.skips++;
      const cause = String(b.skipReason ?? "").trim();
      if (cause) entry.causes.set(cause, (entry.causes.get(cause) ?? 0) + 1);
      skipStats.set(title, entry);
    }
  }

  const lines: string[] = [];
  let totalMinutes = 0;
  for (const [actId, name] of domainActs) {
    const min = Math.round(minutesByAct.get(actId) ?? 0);
    totalMinutes += min;
    const perWeek = Math.round((min / 60 / 6) * 10) / 10;
    lines.push(
      min > 0
        ? `  · ${name} : ${Math.round(min / 60)} h en 6 semaines (≈ ${perWeek} h/sem)`
        : `  · ${name} : 0 h en 6 semaines`
    );
  }
  for (const [title, s] of skipStats) {
    if (s.skips < 2) continue; // en dessous, pas un motif — du bruit
    let topCause = "";
    let topN = 0;
    s.causes.forEach((n, c) => {
      if (n > topN) { topCause = c; topN = n; }
    });
    lines.push(
      `  · « ${title} » : sauté ${s.skips} fois en 14 jours` +
        (topCause ? ` — ${topN} fois « ${topCause} »` : "")
    );
  }
  // Tâches Gantt du domaine (Project.domainId) : deadlines réelles, retard
  // chiffré — la matière du « tes heures disent l'inverse de ta phrase ».
  let ganttSeen = 0;
  if (domainId) {
    const today = new Date(now.toISOString().slice(0, 10) + "T00:00:00Z");
    for (const p of projectsSnap.docs) {
      const data = p.data() as Record<string, unknown>;
      if (data.domainId !== domainId) continue;
      const status = String(data.status ?? "active");
      if (status === "archived" || status === "done") continue;
      const tasks = ((data.tasks as Array<Record<string, unknown>>) ?? [])
        .filter((t) => t.status !== "done" && t.status !== "skipped");
      if (tasks.length === 0) continue;
      ganttSeen++;
      // La deadline la plus proche parmi les tâches ouvertes datées.
      let nearest: Date | null = null;
      for (const t of tasks) {
        if (!t.endDate) continue;
        const d = new Date(String(t.endDate));
        if (!isNaN(d.getTime()) && (nearest === null || d < nearest)) nearest = d;
      }
      let deadline = "";
      if (nearest) {
        const iso = nearest.toISOString().slice(0, 10);
        const lateDays = Math.floor((today.getTime() - nearest.getTime()) / DAY_MS);
        deadline = lateDays > 0
          ? ` — deadline ${iso}, en retard de ${lateDays >= 7 ? `${Math.floor(lateDays / 7)} semaine(s)` : `${lateDays} jour(s)`}`
          : ` — deadline ${iso}`;
      }
      lines.push(
        `  · Gantt « ${String(data.title ?? p.id)} » : ${tasks.length} tâche(s) ouverte(s)${deadline}`
      );
    }
    for (const a of artsSnap.docs) {
      const data = a.data() as Record<string, unknown>;
      if (data.deleted === true || data.domainId !== domainId) continue;
      lines.push(
        `  · Artefact existant : « ${String(data.title ?? data.kind)} » — À ADOPTER tel quel (le référencer), ne JAMAIS proposer de le régénérer.`
      );
    }
  }

  const vivant = totalMinutes > 0 || domainBlocksSeen > 0 || ganttSeen > 0;
  if (vivant) return { mode: "vivant", text: lines.join("\n") };

  // ── Sans données : ce qu'on voit EN CREUX (tous domaines confondus) ─────────
  const creux: string[] = [];
  const sundays = new Set<string>();
  const workedSundays = new Set<string>();
  const since28 = new Date(now.getTime() - 28 * DAY_MS).toISOString();
  for (const s of sessionsSnap.docs) {
    const startAt = String(s.get("startAt") ?? "");
    if (startAt < since28) continue;
    const d = new Date(startAt);
    if (d.getDay() === 0) workedSundays.add(startAt.slice(0, 10));
  }
  for (let i = 1; i <= 28; i++) {
    const d = new Date(now.getTime() - i * DAY_MS);
    if (d.getDay() === 0) sundays.add(d.toISOString().slice(0, 10));
  }
  if (workedSundays.size > 0) {
    creux.push(
      `  · ${workedSundays.size} dimanche(s) sur ${sundays.size} travaillé(s) (sessions logguées) — c'est le créneau qui déborde en premier.`
    );
  }
  let emptyEvenings = 0;
  let daysWithSchedule = 0;
  for (const snap of schedSnaps) {
    if (!snap.exists) continue;
    daysWithSchedule++;
    const blocks =
      ((snap.data() as Record<string, unknown>).blocks as Array<
        Record<string, unknown>
      >) ?? [];
    const evening = blocks.some(
      (b) => b.status !== "deleted" && String(b.startTime ?? "") >= "19:00"
    );
    if (!evening) emptyEvenings++;
  }
  if (daysWithSchedule >= 5 && emptyEvenings > 0) {
    creux.push(
      `  · Soirées vides dans l'app ${emptyEvenings} jours sur ${daysWithSchedule} — remplies de quoi, en vrai ?`
    );
  }
  return { mode: "vide", text: creux.join("\n") };
}
