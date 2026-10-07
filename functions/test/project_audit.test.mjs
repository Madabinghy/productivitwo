import test from "node:test";
import assert from "node:assert/strict";
import { auditProjects, similarProjects, upcomingSessions, formatFindings, titleKey } from "../lib/project_audit.js";

const today = "2026-10-07";
const base = (over) => ({
  id: "p", title: "P", status: "active", paused: false, startDate: "2026-09-01", endDate: "2027-06-30",
  parentProjectId: null, phases: [], tasks: [], interventions: [], ...over,
});
const kinds = (f) => f.map((x) => x.kind);

test("tâches sans phase / hors phase ; jalon passé ; clôture non faite", () => {
  const p = base({
    phases: [{ id: "ph", label: "P1", startDate: "2026-09-01", endDate: "2026-10-20" }],
    tasks: [
      { id: "t1", title: "Sans phase", startDate: "2026-10-01", status: "pending", actions: [] },
      { id: "t2", title: "Hors phase", startDate: "2026-11-01", endDate: "2026-11-05", phaseId: "ph", status: "pending", actions: [] },
      { id: "t3", title: "🎯 Vieux jalon", startDate: "2026-10-01", phaseId: "ph", status: "pending", actions: [], isMilestone: true },
      { id: "t4", title: "✅ Clôturer", startDate: "2026-10-01", endDate: "2026-10-03", phaseId: "ph", status: "pending", actions: [{ done: false }] },
      { id: "t5", title: "🎯 Fait", startDate: "2026-10-01", phaseId: "ph", status: "done", actions: [], isMilestone: true },
      { id: "t6", title: "🎯 À venir", startDate: "2026-10-12", phaseId: "ph", status: "pending", actions: [], isMilestone: true },
    ],
  });
  const f = auditProjects([p], today);
  assert.deepEqual(kinds(f).sort(), ["closure_overdue", "milestone_overdue", "task_outside_phase", "task_without_phase", "unmigrated_triplet"]);
  assert.ok(f.find((x) => x.kind === "task_without_phase").fix.includes('taskId:"t1"'));
  assert.ok(f.find((x) => x.kind === "milestone_overdue").text.includes("Vieux jalon"));
});

test("B5 : projet en pause / archivé avec séances à venir (natives ou jalons)", () => {
  const paused = base({ id: "a", title: "PLIE", paused: true,
    interventions: [{ id: "i", title: "J1", date: "2026-11-16", status: "planned" }, { id: "c", title: "x", date: "2026-11-20", status: "cancelled" }] });
  const archived = base({ id: "b", title: "Vieux", status: "archived",
    tasks: [{ id: "m", title: "🎯 Séance", startDate: "2026-10-20", status: "pending", actions: [], isMilestone: true }] });
  const past = base({ id: "c", title: "Fini", status: "archived",
    tasks: [{ id: "m", title: "🎯 Séance", startDate: "2026-09-20", status: "pending", actions: [], isMilestone: true }] });
  const f = auditProjects([paused, archived, past], today);
  assert.deepEqual(kinds(f), ["inactive_with_upcoming", "inactive_with_upcoming"]);
  assert.equal(upcomingSessions(paused, today).length, 1);
  assert.ok(f[0].fix.includes("paused:false"));
  assert.ok(f[1].fix.includes("restore:true"));
});

test("sans séance à 14 jours → mise en veille proposée ; dossier ignoré ; projet sans jalon ignoré", () => {
  const far = base({ id: "f", title: "Loin", tasks: [{ id: "m", title: "🎯 Séance", startDate: "2026-11-09", status: "pending", actions: [], isMilestone: true }] });
  const near = base({ id: "n", title: "Proche", tasks: [{ id: "m", title: "🎯 Séance", startDate: "2026-10-12", status: "pending", actions: [], isMilestone: true }] });
  const folder = base({ id: "d", title: "Dossier", tasks: [] });
  const child = base({ id: "ch", title: "Enfant", parentProjectId: "d", tasks: [{ id: "t", title: "Tâche", startDate: "2026-10-01", status: "pending", actions: [] }] });
  const f = auditProjects([far, near, folder, child], today);
  assert.deepEqual(kinds(f), ["no_milestone_14d"]);
  assert.equal(f[0].projectId, "f");
  assert.ok(f[0].text.includes("2026-11-09"));
});

test("B7 : doublons de projets (titre proche + période), une fois par paire", () => {
  const a = base({ id: "a", title: "6e — Mathématiques", startDate: "2026-09-07", endDate: "2027-06-30" });
  const b = base({ id: "b", title: "6e/5e — Mathématiques", startDate: "2026-09-07", endDate: "2027-06-30" });
  const c = base({ id: "c", title: "5e — Mathématiques", startDate: "2026-09-07", endDate: "2027-06-30" });
  const d = base({ id: "d", title: "SOF — Encaissement, fiches de séquence & QualiAura", startDate: "2026-09-29", endDate: "2026-10-16" });
  const e = base({ id: "e", title: "SOF Conseil", startDate: "2026-09-28", endDate: "2027-06-30" });
  const f = auditProjects([a, b, c, d, e], today);
  const dup = f.filter((x) => x.kind === "duplicate_projects");
  assert.equal(dup.length, 2); // a~b et b~c (mots « 6e » / « 5e » + rien d'autre → 1 mot commun ne suffit pas sans 2e)…
  assert.equal(similarProjects(d, [e]).length, 0); // « sof » seul = 1 mot commun → pas un doublon
  assert.deepEqual([...titleKey("6e — Mathématiques")], ["6e"]);
});

test("formatFindings : rien → ✅ ; sinon groupé par type avec le correctif", () => {
  assert.match(formatFindings([], today), /rien d'orphelin/);
  const txt = formatFindings([{ kind: "milestone_overdue", projectId: "p", projectTitle: "P", text: "x", fix: "y" }], today);
  assert.match(txt, /Jalons passés non cochés \(1\)/);
  assert.match(txt, /→ y/);
});
