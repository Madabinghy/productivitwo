import test from "node:test";
import assert from "node:assert/strict";
import { sameSlot, splitAgainstMirrors, dropPlainDuplicates, fillAgainstExisting, toMin } from "../lib/schedule_dedupe.js";

const mirror = { id: "gcal-1", startTime: "08:30", durationMin: 240, title: "Cléa Numérique - LAM4", gcalEventId: "1", status: "pending" };

test("sameSlot : même début + même titre (accents/casse ignorés) ou même durée", () => {
  assert.equal(sameSlot({ startTime: "08:30", durationMin: 60, title: "clea numerique - lam4" }, mirror), true);
  assert.equal(sameSlot({ startTime: "08:30", durationMin: 240, title: "Autre chose" }, mirror), true);
  assert.equal(sameSlot({ startTime: "08:30", durationMin: 60, title: "Autre chose" }, mirror), false);
  assert.equal(sameSlot({ startTime: "09:00", durationMin: 240, title: "Cléa Numérique - LAM4" }, mirror), false);
});

test("splitAgainstMirrors : le doublon est écarté, le reste gardé ; miroir swipé = pas un miroir", () => {
  const incoming = [
    { startTime: "08:30", durationMin: 240, title: "Cléa Numérique - LAM4" },
    { startTime: "12:30", durationMin: 60, title: "Pause déjeuner" },
  ];
  const r = splitAgainstMirrors(incoming, [mirror]);
  assert.equal(r.kept.length, 1);
  assert.equal(r.dropped.length, 1);
  assert.equal(r.kept[0].title, "Pause déjeuner");
  const swiped = { ...mirror, status: "deleted" };
  assert.equal(splitAgainstMirrors(incoming, [swiped]).dropped.length, 0);
});

test("dropPlainDuplicates : retire les copies ordinaires des miroirs, garde les faits", () => {
  const blocks = [
    mirror,
    { id: "a", startTime: "08:30", durationMin: 240, title: "Cléa Numérique - LAM4", status: "pending" },
    { id: "b", startTime: "13:30", durationMin: 180, title: "Autre", status: "pending" },
    { id: "c", startTime: "08:30", durationMin: 240, title: "Cléa Numérique - LAM4", status: "done" },
  ];
  const r = dropPlainDuplicates(blocks);
  assert.equal(r.removed, 1);
  assert.deepEqual(r.blocks.map((b) => b.id), ["gcal-1", "b", "c"]);
  assert.equal(dropPlainDuplicates([blocks[2]]).removed, 0);
});

test("fillAgainstExisting : garde les trous, écarte les chevauchements, ignore supprimés/sautés", () => {
  const existing = [
    { startTime: "09:00", durationMin: 60, title: "Fait", status: "done" },
    { startTime: "14:00", durationMin: 120, title: "Cours", status: "pending" },
    { startTime: "11:00", durationMin: 60, title: "Swipé", status: "deleted" },
    { startTime: "16:30", durationMin: 30, title: "Sauté", status: "skipped" },
  ];
  const incoming = [
    { startTime: "09:30", durationMin: 30, title: "Chevauche le fait" },
    { startTime: "10:00", durationMin: 60, title: "Libre" },
    { startTime: "11:00", durationMin: 60, title: "Sur un supprimé" },
    { startTime: "13:30", durationMin: 60, title: "Mord sur le cours" },
    { startTime: "16:30", durationMin: 30, title: "Sur un sauté" },
    { startTime: "10:30", durationMin: 30, title: "Chevauche un entrant déjà posé" },
  ];
  const r = fillAgainstExisting(incoming, existing);
  assert.deepEqual(r.kept.map((b) => b.title), ["Libre", "Sur un supprimé", "Sur un sauté"]);
  assert.deepEqual(r.dropped.map((b) => b.title), ["Chevauche le fait", "Mord sur le cours", "Chevauche un entrant déjà posé"]);
  assert.equal(toMin("09:30"), 570);
  assert.equal(toMin("x"), 0);
});
