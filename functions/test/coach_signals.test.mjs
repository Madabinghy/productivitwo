import { test } from "node:test";
import assert from "node:assert/strict";
import { signalsForCoach, signalReportLines, talkingPoints, watchFlag, clockOf } from "../lib/coach_signals.js";

const raw = {
  days: ["2026-10-25", "2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31"],
  watch: { days: [true, true, false, true, false, true, false], blockers: [
    { name: "Courses", domainId: "maison", lostDays: 3, goalMin: 20 },
    { name: "Projet secret", domainId: "prive", lostDays: 1, goalMin: 30 },
  ] },
  metronome: { days: [true, true, true, true, true, false, true] },
  parole: { days: [true, true, false, null, true, false, null] },
  cap: { days: ["held", null, "held", "posed", null, "held", null] },
  sleep: {
    nights: [380, 460, 370, 360, 455, 350, 470], nightsBefore: [400, 380, 360, 360, 455, 350, 470],
    targetMin: 450, avgMin: 406, debtMin: 300, avgBed: 10, spreadMin: 45, plannedBed: -60,
    impact: { longLowPct: 18, shortLowPct: 41, longDays: 6, shortDays: 7 },
  },
};

test("consentement : rien sans opt-in, sommeil à part, domaines non partagés jamais nommés", () => {
  assert.equal(signalsForCoach(raw, {}, new Set(["maison"])), null);
  const games = signalsForCoach(raw, { games: true }, new Set(["maison"]));
  assert.equal(games.sleep, undefined);
  assert.deepEqual(games.watch.blockers.map((b) => b.name), ["Courses"]);
  const sleep = signalsForCoach(raw, { sleep: true }, new Set());
  assert.equal(sleep.watch, undefined);
  assert.equal(sleep.sleep.avgMin, 406);
});

test("rapport et points à aborder, tirés des faits", () => {
  const s = signalsForCoach(raw, { games: true, sleep: true }, new Set(["maison"]));
  const lines = signalReportLines(s);
  assert.ok(lines[0].startsWith("Sommeil : 6 h 46"));
  assert.ok(lines.some((l) => l === "Parole tenue : 3 jours sur 5 donnés"));
  assert.ok(lines.some((l) => l === "Montre suisse : 4 / 7 · bloque : Courses"));
  const pts = talkingPoints(s);
  assert.ok(pts[0].startsWith("Nuits courtes 4 sur 7, couché·e en moyenne à 00:10, 1 h 10 après son bloc"));
  assert.ok(pts[1].includes("Les jours manqués suivent une nuit courte."));
  assert.ok(pts.some((p) => p.includes("« Courses »")));
  assert.ok(pts.some((p) => p.startsWith("Bon point")));
  assert.equal(clockOf(-60), "23:00");
});

test("pastille À SURVEILLER", () => {
  const s = signalsForCoach({ ...raw, sleep: { ...raw.sleep, nights: [300, 310, 320, 330, 340, 460, 350] } }, { games: true, sleep: true }, new Set());
  assert.equal(watchFlag(s), "nuits courtes");
  assert.equal(watchFlag(null), null);
});
