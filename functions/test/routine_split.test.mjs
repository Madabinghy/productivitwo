import test from "node:test";
import assert from "node:assert/strict";
import { normalizeSplitMoments, splitShares, splitLabel } from "../lib/routine_split.js";

test("normalizeSplitMoments : clés ou libellés, ordre de la journée, deux minimum", () => {
  assert.deepEqual(normalizeSplitMoments(["soir", "midi"]), { moments: ["midday", "evening"], unknown: [] });
  assert.deepEqual(normalizeSplitMoments("matin et soir").moments, ["morning", "evening"]);
  assert.deepEqual(normalizeSplitMoments(["evening", "Matin", "nuit"]), { moments: ["morning", "evening"], unknown: ["nuit"] });
  assert.deepEqual(normalizeSplitMoments(["soir"]).moments, []);
  assert.deepEqual(normalizeSplitMoments([]).moments, []);
});

test("splitShares / splitLabel : cible ÷ moments, surplus aux premiers, part nulle ignorée", () => {
  assert.deepEqual(splitShares(20, ["morning", "evening"]), [{ moment: "morning", share: 10 }, { moment: "evening", share: 10 }]);
  assert.equal(splitLabel(3, ["morning", "evening"]), "2 le matin · 1 le soir");
  assert.equal(splitLabel(1, ["morning", "evening"]), "1 le matin");
  assert.equal(splitLabel(2, ["midday", "evening"]), "1 le midi · 1 le soir");
  assert.equal(splitLabel(5, ["morning"]), "");
});
