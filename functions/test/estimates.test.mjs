import test from "node:test";
import assert from "node:assert/strict";
import {
  sessionMinutes, spentMaps, timeEntries, measured, calibrate, overBudget, workedUnestimated,
  median, roundFactor, fmtFactor, adviceLine, fmtMin,
} from "../lib/estimates.js";

const S = (start, min, extra = {}) => ({
  startAt: new Date(Date.parse(start)).toISOString(),
  endAt: min === null ? null : new Date(Date.parse(start) + min * 60000).toISOString(),
  ...extra,
});

test("sessionMinutes : fermée, ouverte, invalide, chrono oublié (> 12 h)", () => {
  assert.equal(sessionMinutes(S("2026-10-01T09:00:00Z", 45)), 45);
  assert.equal(sessionMinutes(S("2026-10-01T09:00:00Z", null)), 0);
  assert.equal(sessionMinutes({ startAt: "x", endAt: "y" }), 0);
  assert.equal(sessionMinutes(S("2026-10-01T09:00:00Z", 13 * 60)), 0);
  const ts = { toDate: () => new Date("2026-10-01T09:00:00Z") };
  const te = { toDate: () => new Date("2026-10-01T09:30:00Z") };
  assert.equal(sessionMinutes({ startAt: ts, endAt: te }), 30);
});

test("spentMaps : cumul par action et par tâche", () => {
  const m = spentMaps([
    S("2026-10-01T09:00:00Z", 30, { actionId: "a1", taskId: "t1" }),
    S("2026-10-02T09:00:00Z", 20, { actionId: "a1", taskId: "t1" }),
    S("2026-10-02T10:00:00Z", 15, { taskId: "t1" }),
    S("2026-10-02T11:00:00Z", 10, {}),
  ]);
  assert.equal(m.byAction.get("a1"), 50);
  assert.equal(m.byTask.get("t1"), 65);
});

const projects = [{
  id: "p", title: "Site", status: "active",
  tasks: [{
    id: "t", title: "Maquette", status: "pending", estimatedMin: 120,
    actions: [
      { id: "a1", title: "Wireframe", done: true, doneAt: "2026-10-02T12:00:00Z", estimatedMin: 30, contexts: ["@ordinateur"] },
      { id: "a2", title: "Couleurs", done: true, doneAt: "2026-10-03T12:00:00Z", estimatedMin: 60, context: "@ordinateur" },
      { id: "a3", title: "Logo", done: false, estimatedMin: 20, contexts: ["@ordinateur"] },
      { id: "a4", title: "Typo", done: false, contexts: [] },
      { id: "a5", title: "Sans chrono", done: true, estimatedMin: 15 },
    ],
  }],
}];
const activities = [{ id: "act", name: "Admin", ownActions: [
  { id: "o1", title: "Factures", done: true, doneAt: "2026-10-03T08:00:00Z", estimatedMin: 20, contexts: ["@ordinateur"] },
] }];
const sessions = [
  S("2026-10-02T09:00:00Z", 60, { actionId: "a1", taskId: "t" }),  // ×2
  S("2026-10-03T09:00:00Z", 60, { actionId: "a2", taskId: "t" }),  // ×1
  S("2026-10-03T10:00:00Z", 35, { actionId: "a3", taskId: "t" }),  // dépassement en cours
  S("2026-10-03T11:00:00Z", 25, { actionId: "a4", taskId: "t" }),  // sans estimation
  S("2026-10-03T07:00:00Z", 30, { actionId: "o1" }),               // ×1,5
];

test("timeEntries + measured : seules les actions terminées, estimées ET chronométrées", () => {
  const e = timeEntries(projects, activities, sessions);
  const m = measured(e);
  assert.deepEqual(m.map((x) => x.title).sort(), ["Couleurs", "Factures", "Wireframe"]);
  const task = e.find((x) => x.ref.kind === "task");
  assert.equal(task.spentMin, 180);
  assert.equal(task.estimatedMin, 120);
});

test("calibrate : médiane, comptes, groupes par contexte (≥ 3)", () => {
  const c = calibrate(measured(timeEntries(projects, activities, sessions)));
  assert.equal(c.n, 3);
  assert.equal(c.factor, 1.5); // ratios 2, 1, 1.5
  assert.equal(c.accurate, 1);
  assert.equal(c.under, 2);
  assert.equal(c.over, 0);
  assert.deepEqual(c.byContext, [{ context: "@ordinateur", n: 3, factor: 1.5 }]);
  assert.deepEqual(c.byHolder, []); // aucun porteur avec 3 mesures
});

test("overBudget et workedUnestimated", () => {
  const e = timeEntries(projects, activities, sessions);
  assert.deepEqual(overBudget(e).map((x) => x.title), ["Logo"]);
  assert.deepEqual(workedUnestimated(e).map((x) => x.title), ["Typo"]);
});

test("measured : filtre de période sur doneAt", () => {
  const e = timeEntries(projects, activities, sessions);
  assert.deepEqual(measured(e, Date.parse("2026-10-03T00:00:00Z")).map((x) => x.title).sort(), ["Couleurs", "Factures"]);
});

test("utilitaires : median, roundFactor, fmtFactor, fmtMin, adviceLine", () => {
  assert.equal(median([3, 1, 2]), 2);
  assert.equal(median([1, 2, 3, 4]), 2.5);
  assert.equal(median([]), null);
  assert.equal(roundFactor(1.43), 1.45);
  assert.equal(roundFactor(9), 4);
  assert.equal(fmtFactor(1.5), "×1,5");
  assert.equal(fmtFactor(1.45), "×1,45");
  assert.equal(fmtFactor(1), "×1,0");
  assert.equal(fmtMin(75), "1 h 15");
  assert.equal(fmtMin(120), "2 h");
  assert.match(adviceLine({ n: 5, factor: 1.4 }), /sous-estimes/);
  assert.match(adviceLine({ n: 5, factor: 0.7 }), /surestimes/);
  assert.match(adviceLine({ n: 5, factor: 1.05 }), /justes/);
  assert.match(adviceLine({ n: 2, factor: 1.4 }), /indicatif/);
  assert.match(adviceLine({ n: 0, factor: null }), /Pas encore/);
});
