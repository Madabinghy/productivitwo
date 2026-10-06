import test from "node:test";
import assert from "node:assert/strict";
import { auditSessions, formatAudit } from "../lib/sessions_audit.js";

const names = { a: "GDS", b: "Interventions", z: "Sommeil" };
const NOW = Date.parse("2026-08-10T12:00:00Z");

test("doublons, chevauchement, somme > temps réel", () => {
  const sessions = [
    { id: "1", activityId: "a", startAt: "2026-07-28T09:00:00.000", endAt: "2026-07-28T11:00:00.000" },
    { id: "2", activityId: "a", startAt: "2026-07-28T09:00:20.000", endAt: "2026-07-28T11:00:10.000" },
    { id: "3", activityId: "b", startAt: "2026-07-28T10:00:00.000", endAt: "2026-07-28T12:00:00.000" },
  ];
  const r = auditSessions(sessions, names, "2026-07-28", "2026-07-28", NOW);
  assert.deepEqual(r.duplicates, [["1", "2"]]);
  assert.equal(r.overlaps.length, 2); // 3 chevauche 1 et 2
  assert.equal(r.days[0].summedMin, 360);
  assert.equal(r.days[0].wallClockMin, 180);
});

test("session ouverte = comptée jusqu'à maintenant, longue et ouverte signalées", () => {
  const sessions = [{ id: "o", activityId: "b", startAt: "2026-08-08T09:00:00.000", endAt: null }];
  const r = auditSessions(sessions, names, "2026-08-08", "2026-08-09", NOW);
  assert.deepEqual(r.open, ["o"]);
  assert.deepEqual(r.long, ["o"]);
  assert.equal(r.days[0].summedMin, 15 * 60);
  assert.equal(r.days[1].summedMin, 24 * 60);
});

test("sommeil : seuil 13 h, supprimées ignorées, découpe par jour", () => {
  const sessions = [
    { id: "s", activityId: "z", startAt: "2026-07-27T23:00:00.000", endAt: "2026-07-28T08:00:00.000" },
    { id: "d", activityId: "a", startAt: "2026-07-28T09:00:00.000", endAt: "2026-07-28T10:00:00.000", deleted: true },
  ];
  const r = auditSessions(sessions, names, "2026-07-28", "2026-07-28", NOW);
  assert.deepEqual(r.long, []);
  assert.equal(r.rows.length, 1);
  assert.equal(r.days[0].summedMin, 8 * 60);
  const txt = formatAudit(r, "2026-07-28", "2026-07-28", false);
  assert.match(txt, /Sommeil/);
});
