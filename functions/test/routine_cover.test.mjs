import test from "node:test";
import assert from "node:assert/strict";
import {
  rollingDayTarget, shiftYmd, livedYmdOfTs, routineCover, coverNote, isRollingRoutine, normalizeMinPerHit, rhythmPatch,
  isCatchUpRoutine, catchUpOf, catchUpNote,
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
  assert.deepEqual(r.patch, { rolling: true, catchUp: false });
  r = rhythmPatch({ rolling: false }, { type: "habit", habitFreq: 0 });
  assert.deepEqual(r.patch, { rolling: false });
  r = rhythmPatch({ rolling: true }, { type: "habit", habitFreq: 1 });
  assert.deepEqual(r.patch, {});
  assert.match(r.notes[0], /routines quotidiennes/);
  r = rhythmPatch({ rolling: true }, { type: "time" });
  assert.deepEqual(r.patch, {});
});

test("rhythmPatch : la cible automatique, pour une quotidienne sans cap", () => {
  let r = rhythmPatch({ autoTarget: true }, { type: "habit", habitFreq: 0 });
  assert.deepEqual(r.patch, { autoTarget: true });
  assert.match(r.notes[0], /120 %/);
  r = rhythmPatch({ autoTarget: false }, { type: "habit", habitFreq: 0, finalTarget: 50 });
  assert.deepEqual(r.patch, { autoTarget: false });
  // Hebdomadaire, à cap, ou activité de temps : refusé, rien n'est écrit.
  r = rhythmPatch({ autoTarget: true }, { type: "habit", habitFreq: 1 });
  assert.deepEqual(r.patch, {});
  assert.match(r.notes[0], /quotidiennes/);
  r = rhythmPatch({ autoTarget: true }, { type: "habit", habitFreq: 0, finalTarget: 50 });
  assert.deepEqual(r.patch, {});
  assert.match(r.notes[0], /cap/);
  r = rhythmPatch({ autoTarget: true }, { type: "time" });
  assert.deepEqual(r.patch, {});
  // Avec un autre réglage du rythme dans le même appel.
  r = rhythmPatch({ rolling: true, autoTarget: true }, { type: "habit", habitFreq: 0 });
  assert.deepEqual(r.patch, { rolling: true, catchUp: false, autoTarget: true });
});

test("rhythmPatch : le chrono coche, avec ou sans activité liée", () => {
  // Une seule durée par routine : celle du chrono qui coche est aussi celle du minuteur.
  let r = rhythmPatch({ minPerHit: 5 }, { type: "habit", habitFreq: 0, linkedActivityId: "act" });
  assert.deepEqual(r.patch, { minPerHit: 5, chronoOff: false, timerMin: 5 });
  assert.equal(r.notes.length, 1);
  r = rhythmPatch({ minPerHit: 5 }, { type: "habit", habitFreq: 1 });
  assert.deepEqual(r.patch, { minPerHit: 5, chronoOff: false, timerMin: 5 });
  assert.match(r.notes[1], /Aucune activité liée/);
  r = rhythmPatch({ minPerHit: 0 }, { type: "habit", habitFreq: 0, linkedActivityId: "act" });
  // Éteint par choix : l'app ne cochera plus d'office, même si la routine est seule sur son activité.
  assert.deepEqual(r.patch, { minPerHit: null, chronoOff: true });
  r = rhythmPatch({}, { type: "habit", habitFreq: 0 });
  assert.deepEqual(r, { patch: {}, notes: [] });
});

test("rhythmPatch : rattrapable, exclusif de « sur 7 jours »", () => {
  let r = rhythmPatch({ catchUp: true }, { type: "habit", habitFreq: 0 });
  assert.deepEqual(r.patch, { catchUp: true, rolling: false });
  assert.match(r.notes[0], /rattrapable/);
  r = rhythmPatch({ catchUp: false }, { type: "habit", habitFreq: 0 });
  assert.deepEqual(r.patch, { catchUp: false });
  // Les deux demandés : « sur 7 jours » rattrape déjà.
  r = rhythmPatch({ rolling: true, catchUp: true }, { type: "habit", habitFreq: 0 });
  assert.deepEqual(r.patch, { rolling: true, catchUp: false });
  r = rhythmPatch({ catchUp: true }, { type: "habit", habitFreq: 1 });
  assert.deepEqual(r.patch, {});
  r = rhythmPatch({ catchUp: true }, { type: "time" });
  assert.deepEqual(r.patch, {});
});

test("isCatchUpRoutine : rattrapable ou sur 7 jours, quotidienne seulement", () => {
  assert.equal(isCatchUpRoutine({ type: "habit", habitFreq: 0, catchUp: true }), true);
  assert.equal(isCatchUpRoutine({ type: "habit", habitFreq: 0, rolling: true }), true);
  assert.equal(isCatchUpRoutine({ type: "habit", habitFreq: 0 }), false);
  assert.equal(isCatchUpRoutine({ type: "habit", habitFreq: 1, catchUp: true }), false);
});

test("catchUpOf : ce qui est fait en plus comble le jour raté le plus récent d'abord", () => {
  // Cible 1 ; mardi 17 et mercredi 18 ratés.
  let c = catchUpOf(1, counts([1, 1, 1, 1, 0, 0, 1]), DAY, false);
  assert.deepEqual(c.repaired, []);
  assert.deepEqual(c.open.map((h) => h.ymd), ["2026-11-18", "2026-11-17"]);
  c = catchUpOf(1, counts([1, 1, 1, 1, 0, 0, 2]), DAY, false);
  assert.deepEqual(c.repaired, ["2026-11-18"]);
  c = catchUpOf(1, counts([1, 1, 1, 1, 0, 0, 3]), DAY, false);
  assert.deepEqual(c.repaired.sort(), ["2026-11-17", "2026-11-18"]);
  // Passé 7 jours, le trou ne se rattrape plus.
  assert.deepEqual(catchUpOf(1, counts([1, 0, 1, 1, 1, 1, 1, 1, 3]), DAY, false).repaired, []);
  assert.deepEqual(catchUpOf(1, counts([1, 0, 1, 1, 1, 1, 1, 2]), DAY, false).repaired, ["2026-11-13"]);
  // Rattrapé un autre jour : comblé la veille, plus rien d'ouvert le jour visé.
  c = catchUpOf(10, counts([10, 4, 13, 13, 0]), DAY, false);
  assert.deepEqual([c.repaired, c.open], [["2026-11-16"], []]);
  assert.deepEqual(catchUpOf(1, {}, DAY, false), { repaired: [], open: [] });
});

test("catchUpNote : ce qu'il faut faire en plus, en coches ou en minutes", () => {
  const c = catchUpOf(1, counts([1, 1, 1, 1, 0, 0, 0]), DAY, false);
  assert.match(catchUpNote(c), /2 jours ratés encore rattrapables \(11-18, 11-17\) : 2 coches en plus/);
  assert.match(catchUpNote(c, 10), /20 min en plus/);
  assert.equal(catchUpNote({ repaired: [], open: [] }), "");
});
