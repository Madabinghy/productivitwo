import test from "node:test";
import assert from "node:assert/strict";
import { sameSlot, splitAgainstMirrors, dropPlainDuplicates } from "../lib/schedule_dedupe.js";

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
