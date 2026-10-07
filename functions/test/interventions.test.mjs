import test from "node:test";
import assert from "node:assert/strict";
import {
  DEFAULT_TEMPLATE, buildIntervention, buildInterventionTasks, shiftTasks, retitleTasks,
  applyCarryOver, detectTriplets, applyTriplet, parseTimeRange, phaseForDate, validateInput, addDays,
} from "../lib/interventions.js";

const phases = [
  { id: "p1", label: "Période 1", startDate: "2026-09-01", endDate: "2026-10-20" },
  { id: "p2", label: "Période 2", startDate: "2026-11-02", endDate: "2026-12-18" },
];

test("validateInput / addDays / parseTimeRange", () => {
  assert.equal(validateInput({ title: "x", date: "2026-10-12", startTime: "13:15", endTime: "15:00" }), null);
  assert.match(validateInput({ title: "x", date: "12/10", startTime: "13:15", endTime: "15:00" }), /date/);
  assert.match(validateInput({ title: "x", date: "2026-10-12", startTime: "15:00", endTime: "13:15" }), /après/);
  assert.equal(addDays("2026-10-12", -7), "2026-10-05");
  assert.deepEqual(parseTimeRange("Dérouler la séance (13h15–15h00)"), { startTime: "13:15", endTime: "15:00" });
  assert.deepEqual(parseTimeRange("Lundi 8h-12h, CM1"), { startTime: "08:00", endTime: "12:00" });
  assert.equal(parseTimeRange("rien"), null);
});

test("buildInterventionTasks : trois tâches taguées, fenêtres J-7→J-1 et J→J+2, phase par date", () => {
  const i = buildIntervention({ title: "Séance — 12 oct", date: "2026-10-12", startTime: "13:15", endTime: "15:00" });
  const { prep, session, closure } = buildInterventionTasks(i, { ...DEFAULT_TEMPLATE, sessionContext: "@Chérubins" },
    { phases, steps: ["13h15 Ramasser le DM", "13h20 Contrôle"] });
  assert.equal(prep.title, "📝 Préparer — Séance — 12 oct");
  assert.equal(prep.startDate, "2026-10-05");
  assert.equal(prep.endDate, "2026-10-11");
  assert.equal(prep.interventionRole, "prep");
  assert.equal(prep.interventionId, i.id);
  assert.equal(prep.phaseId, "p1");
  assert.equal(prep.actions.length, 4);
  assert.deepEqual(prep.actions[3].contexts, ["@impression"]);
  assert.equal(prep.estimatedMin, 85);
  assert.equal(session.title, "🎯 Lun 12 oct. — Séance — 12 oct");
  assert.equal(session.isMilestone, true);
  assert.equal(session.actions[0].title, "Dérouler la séance (13h15–15h00)");
  assert.equal(session.actions[0].estimatedMin, 105);
  assert.equal(session.actions[0].context, "@Chérubins");
  assert.equal(session.actions[0].checklist.length, 2);
  assert.equal(closure.startDate, "2026-10-12");
  assert.equal(closure.endDate, "2026-10-14");
  assert.equal(closure.groupLabel, "Séance — 12 oct");
  assert.equal(phaseForDate(phases, "2026-10-25"), undefined);
});

test("shiftTasks + retitleTasks : la date bouge, les trois tâches suivent", () => {
  const i = buildIntervention({ title: "S", date: "2026-10-12", startTime: "13:15", endTime: "15:00" });
  const b = buildInterventionTasks(i, DEFAULT_TEMPLATE);
  const tasks = [b.prep, b.session, b.closure, { id: "other", title: "x", startDate: "2026-10-12" }];
  const shifted = shiftTasks(tasks, i.id, "2026-10-12", "2026-10-19");
  assert.equal(shifted[0].startDate, "2026-10-12");
  assert.equal(shifted[1].startDate, "2026-10-19");
  assert.equal(shifted[2].endDate, "2026-10-21");
  assert.equal(shifted[3].startDate, "2026-10-12");
  const retitled = retitleTasks(shifted, { ...i, date: "2026-10-19", title: "S2" });
  assert.equal(retitled[1].title, "🎯 Lun 19 oct. — S2");
  assert.equal(retitled[0].groupLabel, "S2");
});

test("applyCarryOver : les points à reprendre deviennent la checklist « Adapter au bilan » de la prépa suivante", () => {
  const a = buildIntervention({ title: "A", date: "2026-10-12", startTime: "13:15", endTime: "15:00" });
  const b = buildIntervention({ title: "B", date: "2026-10-19", startTime: "13:15", endTime: "15:00" });
  const tb = buildInterventionTasks(b, DEFAULT_TEMPLATE);
  const tasks = [tb.prep, tb.session, tb.closure];
  const r = applyCarryOver(tasks, [a, b], a.id, ["Reprendre les problèmes du tout", " "]);
  assert.equal(r.nextId, b.id);
  const adapt = r.tasks[0].actions[0];
  assert.match(adapt.title, /Adapter au bilan/);
  assert.equal(adapt.checklist.length, 1);
  const again = applyCarryOver(r.tasks, [a, b], a.id, ["reprendre les problèmes du tout", "Revoir les retenues"]);
  assert.equal(again.tasks[0].actions[0].checklist.length, 2);
  assert.equal(applyCarryOver(tasks, [a, b], b.id, ["x"]).nextId, null);
});

test("detectTriplets + applyTriplet : migration des triplets existants", () => {
  const tasks = [
    { id: "p", title: "📝 Préparer — Séance du 12 oct", groupLabel: "Séance — 12 oct", startDate: "2026-10-06", status: "pending", actions: [] },
    { id: "m", title: "🏁 Lun 12 oct — Contrôle", groupLabel: "Séance — 12 oct", startDate: "2026-10-12", endDate: "2026-10-12", status: "pending",
      actions: [{ title: "Dérouler la séance (13h15–15h00)", done: false }] },
    { id: "c", title: "✅ Clôturer — Séance du 12 oct", groupLabel: "Séance — 12 oct", startDate: "2026-10-12", status: "pending", actions: [] },
    { id: "w", title: "✍️ Corriger", groupLabel: "Séance — 12 oct", startDate: "2026-10-12", status: "pending", actions: [] },
    { id: "m2", title: "🎯 Lun 9 nov — Soustractions", groupLabel: "Séance — 9 nov", startDate: "2026-11-09", status: "pending", actions: [] },
    { id: "done", title: "🎯 Lun 5 oct", groupLabel: "Séance — 5 oct", startDate: "2026-10-05", status: "done", actions: [] },
    { id: "skip", title: "🎯 annulé", groupLabel: "x", startDate: "2026-10-08", status: "skipped", actions: [] },
  ];
  const found = detectTriplets(tasks, { description: "Lundi 13h15–15h00, CM1-CM2." });
  assert.deepEqual(found.map((t) => t.session.id), ["done", "m", "m2"]);
  assert.equal(found[1].prep.id, "p");
  assert.equal(found[1].closure.id, "c");
  assert.equal(found[1].timeSource, "task");
  assert.equal(found[2].timeSource, "description");
  assert.equal(found[2].startTime, "13:15");
  const applied = applyTriplet(tasks, found[1]);
  assert.equal(applied.intervention.title, "Séance — 12 oct");
  assert.equal(applied.tasks.find((t) => t.id === "m").interventionRole, "session");
  assert.equal(applied.tasks.find((t) => t.id === "p").interventionId, applied.intervention.id);
  assert.equal(applied.tasks.find((t) => t.id === "w").interventionId, undefined);
  assert.equal(applyTriplet(tasks, found[0]).intervention.status, "done");
  // Déjà taguées : plus détectées.
  assert.equal(detectTriplets(applied.tasks).length, 2);
});
