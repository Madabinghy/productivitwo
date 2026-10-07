import test from "node:test";
import assert from "node:assert/strict";
import {
  DEFAULT_TEMPLATE, buildIntervention, buildInterventionTasks, shiftTasks, retitleTasks,
  applyCarryOver, detectTriplets, applyTriplet, parseTimeRange, phaseForDate, validateInput, addDays,
  parseTimeRanges, slotFromRanges, netSlotMin, titleHints, attachTask, detachAll, mergeInterventions,
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

test("detectTriplets + applyTriplet : migration des triplets existants (appariement temporel)", () => {
  const tasks = [
    { id: "p", title: "📝 Préparer — Séance du 12 oct", groupLabel: "Séance — 12 oct", startDate: "2026-10-06", endDate: "2026-10-11", status: "pending", actions: [] },
    { id: "m", title: "🎯 Lun 12 oct — Contrôle", groupLabel: "Séance — 12 oct", startDate: "2026-10-12", endDate: "2026-10-12", status: "pending",
      actions: [{ title: "Dérouler la séance (13h15–15h00)", done: false }] },
    { id: "c", title: "✅ Clôturer — Séance du 12 oct", groupLabel: "Séance — 12 oct", startDate: "2026-10-12", status: "pending", actions: [] },
    { id: "w", title: "✍️ Corriger", groupLabel: "Séance — 12 oct", startDate: "2026-10-12", status: "pending", actions: [] },
    { id: "m2", title: "🎯 Lun 9 nov — Soustractions", groupLabel: "Séance — 9 nov", startDate: "2026-11-09", status: "pending", actions: [] },
    { id: "done", title: "🎯 Lun 5 oct", groupLabel: "Séance — 5 oct", startDate: "2026-10-05", status: "done", actions: [] },
    { id: "skip", title: "🎯 annulé", groupLabel: "x", startDate: "2026-10-08", status: "skipped", actions: [] },
  ];
  const { triplets: found, warnings } = detectTriplets(tasks, { description: "Lundi 13h15–15h00, CM1-CM2." });
  // m2 et done sont des orphelins (ni 📝 ni ✅) : ignorés par défaut.
  assert.deepEqual(found.map((t) => t.session.id), ["m"]);
  assert.equal(found[0].prep.id, "p");
  assert.equal(found[0].closure.id, "c");
  assert.equal(found[0].timeSource, "task");
  assert.equal(warnings.length, 0);
  const all = detectTriplets(tasks, { description: "Lundi 13h15–15h00, CM1-CM2.", includeOrphans: true }).triplets;
  assert.deepEqual(all.map((t) => t.session.id), ["done", "m", "m2"]);
  assert.equal(all[2].timeSource, "description");
  assert.equal(all[2].startTime, "13:15");
  assert.equal(all[2].orphan, true);
  const applied = applyTriplet(tasks, found[0]);
  assert.equal(applied.intervention.title, "Séance — 12 oct");
  assert.equal(applied.tasks.find((t) => t.id === "m").interventionRole, "session");
  assert.equal(applied.tasks.find((t) => t.id === "p").interventionId, applied.intervention.id);
  assert.equal(applied.tasks.find((t) => t.id === "w").interventionId, undefined);
  assert.equal(applyTriplet(tasks, all[0]).intervention.status, "done");
  // Déjà taguées : plus détectées.
  assert.equal(detectTriplets(applied.tasks).triplets.length, 0);
});

test("appariement PLIE : un seul groupLabel, 7 jalons → chaque 📝 / ✅ va au jalon qu'elle encadre ; 🏁 final ignoré", () => {
  const tasks = [];
  const days = ["2026-10-02", "2026-10-09", "2026-10-16", "2026-10-23", "2026-11-06", "2026-11-20", "2026-12-04"];
  days.forEach((d, i) => {
    tasks.push({ id: `p${i}`, title: `📝 Préparer J${i + 1}`, groupLabel: "Module 4", startDate: addDays(d, -5), endDate: addDays(d, -1), status: "pending", actions: [] });
    tasks.push({ id: `s${i}`, title: `🎯 J${i + 1} — 8h30–12h30 + 13h30–16h30`, groupLabel: "Module 4", startDate: d, endDate: d, status: "pending", actions: [] });
    tasks.push({ id: `c${i}`, title: `✅ Clôturer J${i + 1}`, groupLabel: "Module 4", startDate: d, endDate: addDays(d, 2), status: "pending", actions: [] });
  });
  tasks.push({ id: "end", title: "🏁 Module terminé", groupLabel: "Module 4", startDate: "2026-12-04", endDate: "2026-12-04", status: "pending", actions: [] });
  tasks.push({ id: "cal", title: "🎯 Remplacement calé", groupLabel: "Admin", startDate: "2026-11-06", status: "pending", actions: [] });
  const { triplets, warnings } = detectTriplets(tasks);
  assert.equal(triplets.length, 7);
  triplets.forEach((t, i) => {
    assert.equal(t.session.id, `s${i}`);
    assert.equal(t.prep.id, `p${i}`);
    assert.equal(t.closure.id, `c${i}`);
    assert.equal(t.startTime, "08:30");
    assert.equal(t.endTime, "16:30");
    assert.deepEqual(t.breaks, [{ start: "12:30", end: "13:30" }]);
  });
  // Le 🏁 du 4 déc tombe le jour du J7 → tâche extra de cette séance ; « Remplacement calé » = orphelin ignoré.
  assert.deepEqual(triplets[6].extras.map((e) => e.id), ["end"]);
  assert.equal(warnings.length, 0);
  const applied = applyTriplet(tasks, triplets[6]);
  assert.equal(applied.tasks.find((t) => t.id === "end").interventionRole, "extra");
  assert.deepEqual(applied.intervention.breaks, [{ start: "12:30", end: "13:30" }]);
});

test("repère de titre > proximité ; 📝 / ✅ sans partenaire et jours doubles signalés", () => {
  const tasks = [
    { id: "pA", title: "📝 Préparer séance du 15 oct", groupLabel: "G", startDate: "2026-09-25", endDate: "2026-09-30", status: "pending", actions: [] },
    { id: "pB", title: "📝 Préparer séance du 1er oct", groupLabel: "G", startDate: "2026-10-10", endDate: "2026-10-14", status: "pending", actions: [] },
    { id: "pC", title: "📝 Préparer un truc", groupLabel: "G", startDate: "2026-10-20", endDate: "2026-10-21", status: "pending", actions: [] },
    { id: "s1", title: "🎯 Séance", groupLabel: "G", startDate: "2026-10-01", status: "pending", actions: [] },
    { id: "s2", title: "🎯 Séance", groupLabel: "G", startDate: "2026-10-15", status: "pending", actions: [] },
    { id: "s3", title: "🎯 Autre groupe", groupLabel: "H", startDate: "2026-10-15", status: "pending", actions: [] },
    { id: "cH", title: "✅ Clôturer", groupLabel: "H", startDate: "2026-10-15", status: "pending", actions: [] },
  ];
  const { triplets, warnings } = detectTriplets(tasks);
  const byId = Object.fromEntries(triplets.map((t) => [t.session.id, t]));
  assert.equal(byId.s1.prep.id, "pB"); // repère « 1er oct » malgré des dates incohérentes
  assert.equal(byId.s2.prep.id, "pA"); // repère « 15 oct »
  assert.equal(byId.s3.closure.id, "cH");
  assert.ok(warnings.some((w) => w.kind === "unpaired_prep" && w.text.includes("un truc")));
  assert.ok(warnings.some((w) => w.kind === "same_day" && w.text.includes("2026-10-15")));
  assert.deepEqual([...titleHints("✅ Clôturer J3 — 23/11")], ["j3", "23-11"]);
});

test("plages multiples, créneau net, parseTimeRanges", () => {
  const ranges = parseTimeRanges("8h30–12h30 + 13h30–16h30");
  assert.equal(ranges.length, 2);
  const slot = slotFromRanges(ranges);
  assert.equal(slot.startTime, "08:30");
  assert.equal(slot.endTime, "16:30");
  assert.equal(netSlotMin(slot), 420);
  assert.equal(slotFromRanges([]), null);
  assert.deepEqual(parseTimeRange("13h15–15h00"), { startTime: "13:15", endTime: "15:00" });
});

test("attachTask : rattache, refuse un rôle principal déjà tenu, détache sans toucher au reste", () => {
  const i = buildIntervention({ title: "S", date: "2026-10-12", startTime: "13:15", endTime: "15:00" });
  const b = buildInterventionTasks(i, DEFAULT_TEMPLATE);
  const loose = { id: "x", title: "✅ Autre clôture", startDate: "2026-10-12", status: "done", actions: [{ title: "a" }] };
  const tasks = [b.prep, b.session, b.closure, loose];
  assert.throws(() => attachTask(tasks, [i], "x", i.id, "closure"), /déjà tenu par/);
  assert.throws(() => attachTask(tasks, [i], "x", "nope", "closure"), /introuvable/);
  assert.throws(() => attachTask(tasks, [i], "x", i.id), /interventionRole requis/);
  const extra = attachTask(tasks, [i], "x", i.id, "extra");
  assert.equal(extra.tasks[3].interventionRole, "extra");
  assert.equal(extra.tasks[3].status, "done");
  const det = attachTask(extra.tasks, [i], b.closure.id, "");
  assert.equal(det.tasks[2].interventionId, undefined);
  assert.equal(det.tasks[2].startDate, b.closure.startDate);
  const re = attachTask(det.tasks, [i], "x", i.id, "closure");
  assert.equal(re.tasks[3].interventionRole, "closure");
  const all = detachAll(re.tasks, i.id);
  assert.equal(all.touched.length, 3); // prep, session, x (la clôture d'origine a été détachée)
  assert.ok(all.tasks.every((t) => t.interventionId === undefined));
});

test("mergeInterventions : tâches reprises, conflit de rôle → extra, bilans concaténés, source retirée", () => {
  const a = { ...buildIntervention({ title: "Séance 15 oct", date: "2026-10-15", startTime: "08:00", endTime: "12:00" }), debriefText: "A" };
  const b = { ...buildIntervention({ title: "Éval 15 oct", date: "2026-10-15", startTime: "08:00", endTime: "12:00" }), debriefText: "B", carryOver: [{ id: "c1", title: "x", done: false }] };
  const ta = buildInterventionTasks(a, DEFAULT_TEMPLATE);
  const tb = buildInterventionTasks(b, DEFAULT_TEMPLATE);
  const tasks = [ta.session, tb.prep, tb.session, tb.closure];
  const r = mergeInterventions(tasks, [a, b], a.id, b.id);
  assert.equal(r.interventions.length, 1);
  assert.equal(r.interventions[0].debriefText, "A\n\nB");
  assert.equal(r.interventions[0].carryOver.length, 1);
  const roles = Object.fromEntries(r.tasks.map((t) => [t.id, t.interventionRole]));
  assert.equal(roles[tb.prep.id], "prep");
  assert.equal(roles[tb.closure.id], "closure");
  assert.equal(roles[tb.session.id], "extra");
  assert.ok(r.tasks.every((t) => t.interventionId === a.id));
  assert.equal(r.moved.filter((m) => m.demoted).length, 1);
  assert.throws(() => mergeInterventions(tasks, [a, b], a.id, a.id), /autre intervention/);
});
