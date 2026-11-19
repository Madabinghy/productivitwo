import test from "node:test";
import assert from "node:assert/strict";
import {
  rollingDayTarget, shiftYmd, livedYmdOfTs, routineCover, coverNote, isRollingRoutine, normalizeMinPerHit, rhythmPatch,
} from "../lib/routine_cover.js";

// Jeudi 19 nov. 2026 ; [perDay] = coches d'il y a n jours … jusqu'au jour visé.
const DAY = "2026-11-19";
const counts = (perDay) => Object.fromEntries(perDay.map((n, i) => [shiftYmd(DAY, i - (perDay.length - 1)), n]));

test("rollingDayTarget : l'avance réduit jusqu'à zéro, le retard ne s'accumule pas", () => {
  assert.equal(rollingDayTarget(10, 60), 10);
  assert.equal(rollingDayTarget(10, 65), 5);
  assert.equal(rollingDayTarget(10, 80), 0);
  assert.equal(rollingDayTarget(10, 0), 10);
});

test("livedYmdOfTs : avant 5 h, la coche appartient à la veille", () => {
  assert.equal(livedYmdOfTs("2026-11-19T09:00:00.000"), "2026-11-19");
  assert.equal(livedYmdOfTs("2026-11-19T02:30:00.000"), "2026-11-18");
  assert.equal(livedYmdOfTs("2026-11-01T00:10:00.000"), "2026-10-31");
  assert.equal(livedYmdOfTs("n'importe quoi"), "");
});

test("routineCover : mêmes cas que l'app", () => {
  let c = routineCover(10, counts([10, 10, 10, 10, 10, 10, 0]), DAY);
  assert.deepEqual([c.dayTarget, c.held, c.aheadDays], [10, false, 0]);
  c = routineCover(10, counts([10, 10, 10, 10, 10, 10, 10]), DAY);
  assert.deepEqual([c.held, c.aheadDays, c.tomorrowTarget], [true, 0, 10]);
  c = routineCover(10, counts([10, 10, 10, 10, 10, 10, 30]), DAY);
  assert.deepEqual([c.held, c.aheadDays, c.tomorrowTarget], [true, 2, 0]);
  c = routineCover(10, counts([10, 10, 10, 10, 10, 30, 0]), DAY);
  assert.deepEqual([c.dayTarget, c.held, c.aheadDays], [0, true, 1]);
  c = routineCover(10, counts([10, 10, 10, 10, 10, 15, 0]), DAY);
  assert.equal(c.dayTarget, 5);
  c = routineCover(10, counts([10, 10, 10, 10, 10, 0, 0]), DAY);
  assert.equal(c.dayTarget, 10);
});

test("coverNote : ce que Claude lit", () => {
  assert.match(coverNote(routineCover(10, counts([10, 10, 10, 10, 10, 30, 0]), DAY)), /COUVERTE ce jour-là.*ne pas la programmer/);
  assert.match(coverNote(routineCover(10, counts([10, 10, 10, 10, 10, 15, 0]), DAY)), /réduit la part du jour à 5 au lieu de 10/);
  assert.match(coverNote(routineCover(10, counts([10, 10, 10, 10, 10, 10, 0]), DAY)), /part du jour 10 \(60 \/ 70 sur 7 j\)/);
});

test("isRollingRoutine : routine quotidienne réglée", () => {
  assert.equal(isRollingRoutine({ type: "habit", habitFreq: 0, rolling: true }), true);
  assert.equal(isRollingRoutine({ type: "habit", habitFreq: 1, rolling: true }), false);
  assert.equal(isRollingRoutine({ type: "habit", habitFreq: 0 }), false);
  assert.equal(isRollingRoutine({ type: "time", rolling: true }), false);
});

test("normalizeMinPerHit : entier de 1 à 240, sinon rien", () => {
  assert.equal(normalizeMinPerHit(5), 5);
  assert.equal(normalizeMinPerHit("10"), 10);
  assert.equal(normalizeMinPerHit(0), null);
  assert.equal(normalizeMinPerHit(""), null);
  assert.equal(normalizeMinPerHit(999), 240);
});

test("rhythmPatch : sur 7 jours seulement pour une quotidienne", () => {
  let r = rhythmPatch({ rolling: true }, { type: "habit", habitFreq: 0 });
  assert.deepEqual(r.patch, { rolling: true });
  r = rhythmPatch({ rolling: false }, { type: "habit", habitFreq: 0 });
  assert.deepEqual(r.patch, { rolling: false });
  r = rhythmPatch({ rolling: true }, { type: "habit", habitFreq: 1 });
  assert.deepEqual(r.patch, {});
  assert.match(r.notes[0], /routines quotidiennes/);
  r = rhythmPatch({ rolling: true }, { type: "time" });
  assert.deepEqual(r.patch, {});
});

test("rhythmPatch : le chrono coche, avec ou sans activité liée", () => {
  let r = rhythmPatch({ minPerHit: 5 }, { type: "habit", habitFreq: 0, linkedActivityId: "act" });
  assert.deepEqual(r.patch, { minPerHit: 5 });
  assert.equal(r.notes.length, 1);
  r = rhythmPatch({ minPerHit: 5 }, { type: "habit", habitFreq: 1 });
  assert.deepEqual(r.patch, { minPerHit: 5 });
  assert.match(r.notes[1], /Aucune activité liée/);
  r = rhythmPatch({ minPerHit: 0 }, { type: "habit", habitFreq: 0, linkedActivityId: "act" });
  assert.deepEqual(r.patch, { minPerHit: null });
  r = rhythmPatch({}, { type: "habit", habitFreq: 0 });
  assert.deepEqual(r, { patch: {}, notes: [] });
});
