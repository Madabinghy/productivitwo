import test from "node:test";
import assert from "node:assert/strict";
import { planPrep, isPrintAction, addDays } from "../lib/prep_planner.js";

const win = { startMin: 8 * 60, endMin: 22 * 60 };
const session = { date: "2026-10-12", startTime: "13:15", title: "Séance — 12 oct" };
const actions = [
  { id: "a1", title: "Contrôle CM1 / CM2 + corrigé", estimatedMin: 45, contexts: ["@ordinateur"] },
  { id: "a2", title: "Importer les images dans le Kahoot", estimatedMin: 10, contexts: ["@ordinateur"] },
  { id: "p1", title: "Imprimer à l'école : contrôle + fiche de séquence", estimatedMin: 10, contexts: ["@impression"] },
];

test("veille au soir d'abord, impression collée au début de la séance", () => {
  const r = planPrep({ intervention: session, actions, existing: {}, window: win, today: "2026-10-07", nowMin: 9 * 60 });
  assert.equal(r.unplaced.length, 0);
  const byId = Object.fromEntries(r.placements.map((p) => [p.actionId, p]));
  assert.equal(byId.a1.date, "2026-10-11");
  assert.equal(byId.a1.startTime, "18:00");
  assert.equal(byId.a1.why, "veille au soir");
  assert.equal(byId.a2.date, "2026-10-11");
  assert.equal(byId.a2.startTime, "18:45");
  assert.equal(byId.p1.date, "2026-10-12");
  assert.equal(byId.p1.startTime, "13:00"); // 15 min de marge avant 13h15
  assert.equal(byId.p1.durationMin, 15);
  assert.equal(byId.p1.why, "impression sur place");
});

test("soir occupé → soir précédent ; rendez-vous agenda respectés ; rien dans le passé", () => {
  const existing = {
    "2026-10-11": [
      { startTime: "18:00", durationMin: 240, status: "pending", gcalEventId: "x", title: "Dîner" },
    ],
    "2026-10-12": [
      { startTime: "12:30", durationMin: 60, status: "pending", title: "Déjeuner" },
    ],
  };
  const r = planPrep({ intervention: session, actions, existing, window: win, today: "2026-10-10", nowMin: 20 * 60 });
  const byId = Object.fromEntries(r.placements.map((p) => [p.actionId, p]));
  // 11/10 : soir pris jusqu'à 22 h → on descend au soir du 10/10, mais il est 20 h → à partir de 20 h.
  assert.equal(byId.a1.date, "2026-10-10");
  assert.equal(byId.a1.startTime, "20:00");
  assert.equal(byId.a1.why, "soir J-2");
  // Impression : 13h00–13h15 chevauche le déjeuner (12h30–13h30) → recule avant 12h30.
  assert.equal(byId.p1.startTime, "12:15");
});

test("sans trou le soir → journée (le plus tard possible) ; sans trou du tout → alternatives", () => {
  const full = (from, to) => [{ startTime: from, durationMin: (toMin(to) - toMin(from)), status: "pending", title: "occupé" }];
  function toMin(hm) { const [h, m] = hm.split(":").map(Number); return h * 60 + m; }
  const existing = {};
  for (let d = "2026-10-05"; d <= "2026-10-11"; d = addDays(d, 1)) existing[d] = full("17:00", "22:00");
  const r = planPrep({ intervention: session, actions: [actions[0]], existing, window: win, today: "2026-10-05", nowMin: 8 * 60 });
  assert.equal(r.placements[0].date, "2026-10-11");
  assert.equal(r.placements[0].startTime, "16:15"); // juste avant 17 h, fin au plus tard dans la journée
  assert.equal(r.placements[0].why, "journée J-1");
  // Tout plein (journée active entière) → rien de posé, alternatives vides mais listées.
  const jammed = {};
  for (let d = "2026-10-05"; d <= "2026-10-12"; d = addDays(d, 1)) jammed[d] = full("08:00", "22:00");
  const r2 = planPrep({ intervention: session, actions: [actions[0]], existing: jammed, window: win, today: "2026-10-05", nowMin: 8 * 60 });
  assert.equal(r2.placements.length, 0);
  assert.equal(r2.unplaced[0].actionId, "a1");
  assert.deepEqual(r2.unplaced[0].alternatives, []);
  // Un seul trou le 8 à 10 h → alternative proposée quand le soir est plein partout.
  const one = { ...jammed, "2026-10-08": full("08:00", "10:00").concat(full("11:00", "22:00")) };
  const r3 = planPrep({ intervention: session, actions: [actions[0]], existing: one, window: win, today: "2026-10-05", nowMin: 8 * 60 });
  assert.equal(r3.placements[0].date, "2026-10-08");
  assert.equal(r3.placements[0].startTime, "10:15"); // le plus tard possible dans le trou 10 h–11 h
});

test("earliest (début de la tâche 📝) borne la fenêtre ; isPrintAction", () => {
  const r = planPrep({ intervention: session, actions: [actions[0]], existing: {}, window: win, today: "2026-10-01", nowMin: 0, earliest: "2026-10-10" });
  assert.equal(r.placements[0].date, "2026-10-11");
  assert.equal(isPrintAction({ id: "x", title: "Imprimer" }), true);
  assert.equal(isPrintAction({ id: "x", title: "Fiche", contexts: ["@impression"] }), true);
  assert.equal(isPrintAction({ id: "x", title: "Fiche", contexts: ["@ordinateur"] }), false);
});
