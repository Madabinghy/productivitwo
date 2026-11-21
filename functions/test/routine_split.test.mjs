import test from "node:test";
import assert from "node:assert/strict";
import { momentParts, normalizeMomentShares, normalizeSplitMoments, splitShares, splitLabel } from "../lib/routine_split.js";

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

test("normalizeSplitMoments : liste JSON passée en texte", () => {
  assert.deepEqual(normalizeSplitMoments('["morning", "evening"]').moments, ["morning", "evening"]);
});

test("Miracle Morning : un cinquième moment, avant le matin", () => {
  assert.deepEqual(normalizeSplitMoments(["matin", "Miracle Morning"]).moments, ["miracle", "morning"]);
  assert.equal(splitLabel(3, ["miracle", "morning"]), "2 au Miracle Morning · 1 le matin");
});

test("parts réglées : au prorata, la somme fait toujours la cible", () => {
  const all = ["miracle", "morning", "midday", "afternoon", "evening"];
  const shares = normalizeMomentShares({ miracle: 1, matin: 2, midi: 2, "après-midi": 2, soir: 1 }, all);
  assert.deepEqual(shares, { miracle: 1, morning: 2, midday: 2, afternoon: 2, evening: 1 });
  assert.deepEqual(momentParts(8, all, shares), [1, 2, 2, 2, 1]);
  assert.equal(splitLabel(8, all, shares), "1 au Miracle Morning · 2 le matin · 2 le midi · 2 l'après-midi · 1 le soir");
  // La cible du jour baisse (routine sur 7 jours) : mêmes proportions, somme = 4.
  assert.deepEqual(momentParts(4, all, shares), [1, 1, 1, 1, 0]);
  assert.equal(momentParts(11, all, shares).reduce((a, b) => a + b, 0), 11);
  // Sans réglage : parts égales, comme avant.
  assert.deepEqual(momentParts(3, ["morning", "evening"]), [2, 1]);
  // Parts inutilisables = parts égales.
  assert.deepEqual(normalizeMomentShares({ nuit: 3 }, all), {});
  assert.deepEqual(normalizeMomentShares("x", all), {});
  // Un moment sans part réglée ne reçoit rien.
  assert.deepEqual(normalizeMomentShares({ matin: 3 }, ["morning", "evening"]), { morning: 3, evening: 0 });
  assert.equal(splitLabel(3, ["morning", "evening"], { morning: 3, evening: 0 }), "3 le matin");
});
