import test from "node:test";
import assert from "node:assert/strict";
import {
  summarizeTrajectory, isReadingDue, latestReading, upsertReading, parseReadings, parseMetric,
  expectedMetricAt, objectiveStartYmd, formatReadingsDue,
} from "../lib/objective_trajectory.js";

const base = (over = {}) => ({
  id: "o1", title: "100 clients", status: "active", startDate: "2026-10-01", endDate: "2026-12-10",
  timeCommitments: [{ activityId: "a1", weeklyMin: 300 }], ...over,
});

test("moyens : attendu linéaire sur les semaines écoulées, fait = minutes des activités engagées", () => {
  const t = summarizeTrajectory(base(), "2026-10-01", new Map([["a1", 300], ["autre", 999]]), "2026-10-15");
  assert.equal(t.means.doneMin, 300);
  assert.equal(t.means.expectedMin, 600); // 300 × 14 j / 7
  assert.equal(t.means.totalMin, 3000);
  assert.equal(t.means.status, "behind");
  assert.equal(t.timePct, 20);
  assert.equal(t.result, null);
  assert.equal(t.readingDue, false);
});

test("résultat : droite start → target, statut, écart signé (croissant et décroissant)", () => {
  const m = { label: "Clients", unit: "clients", startValue: 20, targetValue: 100 };
  const behind = summarizeTrajectory(base({ metric: m, readings: [{ date: "2026-11-04", value: 40 }] }), "2026-10-01", new Map(), "2026-11-05");
  assert.equal(behind.result.expectedValue, 60);
  assert.equal(behind.result.delta, -20);
  assert.equal(behind.result.status, "behind");
  assert.equal(behind.daysSinceReading, 1);

  const ahead = summarizeTrajectory(base({ metric: m, readings: [{ date: "2026-11-05", value: 75 }] }), "2026-10-01", new Map(), "2026-11-05");
  assert.equal(ahead.result.status, "ahead");

  const none = summarizeTrajectory(base({ metric: m }), "2026-10-01", new Map(), "2026-11-05");
  assert.equal(none.result.status, "unknown");
  assert.equal(none.result.latestValue, null);

  const kg = summarizeTrajectory(base({ metric: { label: "Poids", unit: "kg", startValue: 90, targetValue: 80 }, readings: [{ date: "2026-11-05", value: 83 }] }), "2026-10-01", new Map(), "2026-11-05");
  assert.equal(kg.result.expectedValue, 85);
  assert.equal(kg.result.delta, 2);
  assert.equal(kg.result.status, "ahead");
});

test("relevé dû : depuis le dernier relevé sinon depuis le début ; checkInEvery ; jamais sans métrique", () => {
  const m = { label: "x", targetValue: 10 };
  assert.equal(isReadingDue(base({ metric: m }), "2026-10-01", "2026-10-07"), false);
  assert.equal(isReadingDue(base({ metric: m }), "2026-10-01", "2026-10-08"), true);
  assert.equal(isReadingDue(base({ metric: m, readings: [{ date: "2026-10-20", value: 3 }] }), "2026-10-01", "2026-10-24"), false);
  assert.equal(isReadingDue(base({ metric: m, readings: [{ date: "2026-10-20", value: 3 }] }), "2026-10-01", "2026-10-27"), true);
  assert.equal(isReadingDue(base({ metric: m, checkInEvery: 3 }), "2026-10-01", "2026-10-04"), true);
  assert.equal(isReadingDue(base(), "2026-10-01", "2026-12-01"), false);
  assert.equal(isReadingDue(base({ metric: m, status: "done" }), "2026-10-01", "2026-12-01"), false);
});

test("relevés : parse tolérant, dernier du jour gagne, upsert remplace le jour", () => {
  const rs = parseReadings([
    { date: "2026-10-20", value: 3, createdAt: "2026-10-20T09:00:00Z" },
    { date: "2026-10-20", value: 5, createdAt: "2026-10-20T18:00:00Z" },
    { date: "bad", value: 1 }, { date: "2026-10-01", value: "nan" },
  ]);
  assert.equal(rs.length, 2);
  assert.equal(latestReading(rs).value, 5);
  const up = upsertReading(rs, { date: "2026-10-20", value: 7 });
  assert.equal(up.length, 1);
  assert.equal(up[0].value, 7);
  assert.equal(parseMetric({ label: "x" }), null);
  assert.equal(parseMetric({ targetValue: 10 }).startValue, 0);
});

test("début : startDate, sinon createdAt ; attendu sans échéance = startValue", () => {
  assert.equal(objectiveStartYmd({ startDate: "2026-09-01" }, "2026-10-19", () => null), "2026-09-01");
  assert.equal(objectiveStartYmd({ createdAt: "x" }, "2026-10-19", () => "2026-09-15"), "2026-09-15");
  assert.equal(objectiveStartYmd({}, "2026-10-19", () => null), "2026-10-19");
  assert.equal(expectedMetricAt({ label: "", startValue: 5, targetValue: 50 }, "2026-10-01", null, "2026-11-01"), 5);
  const txt = formatReadingsDue([{ title: "T", id: "o1", label: "MRR", unit: "€", daysSince: null, every: 7 }]);
  assert.ok(txt.includes("aucun relevé") && txt.includes('log_objective_reading(objectiveId:"o1"'));
});
