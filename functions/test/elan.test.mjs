import test from "node:test";
import assert from "node:assert/strict";
import {
  dedupeMoodMarks,
  elanBucket, livedParts, livedDayEndMs, elanWindows, winsIn, elanSummary, formatElanSummary, validMoodValue,
} from "../lib/elan.js";

const OFF = 120; // Paris en octobre (UTC+2), posé explicitement pour des tests stables
const mark = (at, value, over = {}) => ({ id: at, at, ymd: livedParts(at, OFF).ymd, kind: "elan", value, moment: elanBucket(livedParts(at, OFF).min), ...over });

test("valeurs admises : élan 1–5, effort et humeur 0–2", () => {
  assert.equal(validMoodValue("elan", 3), true);
  assert.equal(validMoodValue("elan", 0), false);
  assert.equal(validMoodValue("effort", 2), true);
  assert.equal(validMoodValue("mood", 3), false);
  assert.equal(validMoodValue("elan", 2.5), false);
});

test("jour vécu : 02:30 locales appartiennent à la veille, minute vécue 26 h 30", () => {
  const p = livedParts("2026-10-25T00:30:00.000Z", OFF); // 02:30 à Paris
  assert.equal(p.ymd, "2026-10-24");
  assert.equal(p.min, 26 * 60 + 30);
  assert.equal(elanBucket(p.min), "soir");
  assert.equal(elanBucket(8 * 60), "matin");
  assert.equal(elanBucket(13 * 60), "aprem");
});

test("fenêtres : du pointage au suivant, puis jusqu'à la bascule (5 h locales le lendemain)", () => {
  const marks = [mark("2026-10-25T06:00:00.000Z", 2), mark("2026-10-25T12:00:00.000Z", 4)];
  const ws = elanWindows(marks, "2026-10-25", OFF);
  assert.equal(ws.length, 2);
  assert.equal(ws[0].endMs, Date.parse("2026-10-25T12:00:00.000Z"));
  assert.equal(ws[1].endMs, livedDayEndMs("2026-10-25", OFF));
  assert.equal(new Date(ws[1].endMs).toISOString(), "2026-10-26T03:00:00.000Z"); // 05:00 à Paris
});

test("victoire sur la flemme : bloc terminé ou routine atteinte dans la fenêtre", () => {
  const w = elanWindows([mark("2026-10-25T06:00:00.000Z", 1)], "2026-10-25", OFF)[0];
  const n = winsIn(
    w,
    [{ status: "done", doneAt: "2026-10-25T07:30:00.000Z" }, { status: "pending" }, { status: "done", doneAt: "2026-10-24T07:30:00.000Z" }],
    [{ habitId: "med", ts: "2026-10-25T08:00:00.000Z" }, { habitId: "med", ts: "2026-10-25T00:30:00.000Z" }],
    [{ id: "med", type: "habit", habitFreq: 0, habitTarget: 1 }],
    OFF
  );
  assert.equal(n, 2); // le bloc de 7 h 30 et le hit de 8 h ; celui de 00:30 UTC est sur la veille vécue
});

test("résumé 7 jours : moyenne, fenêtres de flemme, discipline, efforts, ligne de prompt", () => {
  const marks = [
    mark("2026-10-24T06:00:00.000Z", 1),
    mark("2026-10-24T13:00:00.000Z", 2),
    mark("2026-10-25T06:00:00.000Z", 4),
    { id: "e1", at: "2026-10-24T10:00:00.000Z", ymd: "2026-10-24", kind: "effort", value: 1 },
    { id: "m1", at: "2026-10-25T19:00:00.000Z", ymd: "2026-10-25", kind: "mood", value: 2 },
  ];
  const s = elanSummary({
    marks,
    schedulesByYmd: new Map([["2026-10-24", [{ status: "done", doneAt: "2026-10-24T07:00:00.000Z" }]]]),
    hits: [],
    activities: [],
    todayYmd: "2026-10-26",
    offsetMin: OFF,
  });
  assert.equal(s.days.length, 7);
  assert.equal(s.days[6].ymd, "2026-10-26");
  assert.equal(s.count, 3);
  assert.equal(s.mean, 2.3);
  assert.equal(s.lowCount, 2);
  assert.equal(s.lowWon, 1);
  assert.equal(s.discipline, 0.5);
  assert.deepEqual(s.effort, { facile: 0, juste: 1, dur: 0 });
  assert.equal(s.days.find((d) => d.ymd === "2026-10-25").mood, 2);
  assert.equal(formatElanSummary(s), "Élan 7 j : moyen 2,3 sur 5 (3 pointages) · face à la flemme 1 / 2 (50 %) · effort : 0 facile, 1 juste, 0 dur");
  assert.equal(formatElanSummary(elanSummary({ marks: [], schedulesByYmd: new Map(), hits: [], activities: [], todayYmd: "2026-10-26", offsetMin: OFF })), null);
});

test("dedupeMoodMarks : un pointage par (jour, créneau), le plus récent gagne", () => {
  const mk = (id, at, value, moment) => ({ id, at, ymd: "2026-10-26", kind: "elan", value, moment });
  const kept = dedupeMoodMarks([
    mk("b", "2026-10-26T08:30:00.000Z", 4, "matin"),
    mk("a", "2026-10-26T08:00:00.000Z", 2, "matin"),
    mk("c", "2026-10-26T14:00:00.000Z", 3, "aprem"),
  ]);
  assert.deepEqual(kept.map((m) => m.id), ["b", "c"]);
});
