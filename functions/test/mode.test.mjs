import test from "node:test";
import assert from "node:assert/strict";
import { modeOf, modeFromElan, modeElanValue, lastElanMark, parseRestDomains, isResting, activeRests, parseBudgetWindowDays, isTactical, modeRules } from "../lib/mode.js";

const mark = (at, value, ymd = "2026-10-27") => ({ id: at, at, ymd, kind: "elan", value, moment: "matin" });

test("modeOf : dernier élan de la journée vécue, sinon normal ; seuils", () => {
  assert.deepEqual(modeOf([], "2026-10-27"), { mode: "normal", since: null });
  assert.equal(modeOf([mark("2026-10-27T06:00:00.000Z", 1)], "2026-10-27").mode, "low");
  assert.equal(modeOf([mark("2026-10-27T06:00:00.000Z", 1), mark("2026-10-27T12:00:00.000Z", 5)], "2026-10-27").mode, "high");
  assert.equal(modeOf([mark("2026-10-26T20:00:00.000Z", 1, "2026-10-26")], "2026-10-27").mode, "normal");
  assert.equal(lastElanMark([mark("2026-10-27T06:00:00.000Z", 1), mark("2026-10-27T12:00:00.000Z", 5)], "2026-10-27", "2026-10-27T10:00:00.000Z").value, 1);
  assert.equal(modeFromElan(modeElanValue("low")), "low");
  assert.equal(modeFromElan(modeElanValue("high")), "high");
});

test("restDomains, budget, tactique, règles", () => {
  const rest = parseRestDomains({ sante: "2026-10-31", maison: "x", y: 3 });
  assert.deepEqual(rest, { sante: "2026-10-31" });
  assert.equal(isResting("sante", rest, "2026-10-31"), true);
  assert.equal(isResting("sante", rest, "2026-11-01"), false);
  assert.equal(isResting(null, rest, "2026-10-27"), false);
  assert.deepEqual(activeRests(rest, "2026-11-02"), {});
  assert.equal(parseBudgetWindowDays(14), 14);
  assert.equal(parseBudgetWindowDays("7"), 7);
  assert.equal(isTactical({ horizon: "tactical" }), true);
  assert.equal(isTactical({}), false);
  assert.ok(modeRules("low")[0].includes("FLEMME"));
  assert.ok(modeRules("high")[0].includes("deep work"));
});
