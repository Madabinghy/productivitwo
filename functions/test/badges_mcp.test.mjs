import test from "node:test";
import assert from "node:assert/strict";
import { parseSnapshot, parseHunts, validateHunt, huntLines, badgesSummary, formatBadgeList } from "../lib/badges_mcp.js";

const snap = parseSnapshot({
  updatedAt: "2026-10-26T10:00:00.000Z",
  acquired: 8,
  total: 37,
  badges: [
    { id: "serie-med", family: "routines", name: "Méditation", level: 3, tiers: [3, 7, 21, 66, 100], value: 64, unit: "j", nextTarget: 66, obtained: "2026-10-14" },
    { id: "actions", family: "actions", name: "Actions accomplies", level: 3, tiers: [10, 50, 100, 250, 500, 1000, 5000, 10000], value: 142, unit: "actions", nextTarget: 250, obtained: "2026-10-11" },
    { id: "journee-parfaite", family: "days", name: "Journée parfaite", level: 1, tiers: [1], value: 3, nextTarget: null, obtained: "2026-09-18" },
    { id: "enchaineur", family: "chain", name: "Enchaîneur", level: 0, tiers: [10], value: 0, nextTarget: 10, measured: false },
    "poubelle",
  ],
});

test("instantané et chasses : lecture tolérante", () => {
  assert.equal(snap.badges.length, 4);
  assert.equal(snap.badges[0].nextTarget, 66);
  assert.deepEqual(parseHunts([{ badgeId: "serie-med", tier: 4, since: "2026-10-20", targetDate: "2026-11-27" }, { tier: 2 }, null]), [
    { badgeId: "serie-med", tier: 4, since: "2026-10-20", targetDate: "2026-11-27" },
  ]);
  assert.equal(parseSnapshot(null), null);
});

test("hunt_badge : validation (badge, palier, mesure, trois au plus)", () => {
  const ok = validateHunt(snap, [], "serie-med", undefined, "2026-11-27");
  assert.equal(ok.ok, true);
  assert.equal(ok.hunt.tier, 4);
  assert.equal(ok.hunt.targetDate, "2026-11-27");
  assert.match(validateHunt(snap, [], "x", 1, undefined).error, /inconnu/);
  assert.match(validateHunt(snap, [], "serie-med", 2, undefined).error, /déjà atteint/);
  assert.match(validateHunt(snap, [], "serie-med", 9, undefined).error, /invalide/);
  assert.match(validateHunt(snap, [], "enchaineur", 1, undefined).error, /pas encore mesuré/);
  assert.match(validateHunt(snap, [], "actions", 4, "27/11").error, /YYYY-MM-DD/);
  const full = [{ badgeId: "a", tier: 1, since: "" }, { badgeId: "b", tier: 1, since: "" }, { badgeId: "c", tier: 1, since: "" }];
  assert.match(validateHunt(snap, full, "serie-med", 4, undefined).error, /Trois chasses/);
  // remplacer une chasse existante sur le même badge ne compte pas en plus
  assert.equal(validateHunt(snap, [...full.slice(0, 2), { badgeId: "serie-med", tier: 4, since: "" }], "serie-med", 5, undefined).ok, true);
  assert.match(validateHunt(null, [], "serie-med", 4, undefined).error, /instantané/);
});

test("résumé et liste", () => {
  const hunts = [{ badgeId: "serie-med", tier: 4, since: "2026-10-20", targetDate: "2026-11-27" }];
  assert.deepEqual(huntLines(snap, hunts), ["Méditation · palier 66 j · 64 / 66 j · d'ici le 2026-11-27"]);
  const s = badgesSummary(snap, hunts);
  assert.equal(s.acquired, 8);
  assert.equal(s.lastObtained, "Méditation (2026-10-14)");
  assert.deepEqual(s.closeToTier, ["Méditation : encore 2 j avant le palier 66"]);
  const txt = formatBadgeList(snap, hunts);
  assert.match(txt, /BADGES — 8 \/ 37 paliers/);
  assert.match(txt, /🎯 Méditation · palier 66 j/);
  assert.match(txt, /✓ Actions accomplies \[actions\] — 142 \/ 250 actions · paliers 10 \/ 50 \/ 100 \/ 250 \/ 500 \/ 1 000 \/ 5 000 \/ 10 000 · 3 atteints/);
  assert.match(txt, /▢ Enchaîneur \[enchaineur\] — pas encore mesuré/);
  assert.equal(badgesSummary(null, []), null);
});
