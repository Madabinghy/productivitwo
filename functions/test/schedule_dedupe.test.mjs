import test from "node:test";
import assert from "node:assert/strict";
import { sameSlot, splitAgainstMirrors, dropPlainDuplicates, fillAgainstExisting, toMin, nearestFreeSlot, nearestFreeSlotAnywhere, nextFreeSlot, isSettledBlock, blockHasSession } from "../lib/schedule_dedupe.js";

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

test("nearestFreeSlot : créneau libre le plus proche, dans la fenêtre, sans chevauchement", () => {
  const busy = [
    { startTime: "09:00", durationMin: 60, status: "pending" },
    { startTime: "10:00", durationMin: 30, status: "pending" },
    { startTime: "11:00", durationMin: 60, status: "deleted" },
  ];
  const win = { startMin: 8 * 60, endMin: 20 * 60 };
  // Demandé 09:30 (occupé) → 10:30 est libre (le bloc supprimé de 11 h ne compte pas).
  assert.equal(nearestFreeSlot({ startTime: "09:30", durationMin: 45 }, busy, win), "10:30");
  // Demandé 09:00 avec 60 min : 08:00 est à −60, 10:30 à +90 → 08:00.
  assert.equal(nearestFreeSlot({ startTime: "09:00", durationMin: 60 }, busy, win), "08:00");
  // Trop long pour la fenêtre → null.
  assert.equal(nearestFreeSlot({ startTime: "09:00", durationMin: 13 * 60 }, busy, win), null);
  // Jamais avant le début de la journée active.
  assert.equal(nearestFreeSlot({ startTime: "07:00", durationMin: 30 }, [], win), "08:00");
});

test("isSettledBlock (B10) : fait, chrono rattaché, ou tombstone — un bloc passé non fait n'est PAS protégé", () => {
  const b = (startTime, status = "pending", extra = {}) => ({ startTime, durationMin: 50, status, ...extra });
  assert.equal(isSettledBlock(b("22:40")), false, "BPF passé non fait : il a sauté, remplaçable");
  assert.equal(isSettledBlock(b("22:40", "done")), true, "fait = un fait");
  assert.equal(isSettledBlock(b("22:40", "skipped")), true, "sauté : tombstone gardé (check-in)");
  assert.equal(isSettledBlock(b("22:40", "deleted")), true, "retiré : tombstone gardé (ne pas recréer)");
  const corr = b("11:30", "pending", { taskId: "t-corr", durationMin: 420 });
  const sessions = [{ startMin: toMin("11:30"), endMin: toMin("18:40"), taskId: "t-corr", activityId: "prepa" }];
  assert.equal(isSettledBlock(corr, { sessions }), true, "chrono réel sur la tâche du bloc : protégé");
  assert.equal(isSettledBlock(b("21:00", "pending", { taskId: "autre" }), { sessions }), false);
  // Bloc d'activité (sans tâche) : même activité + chevauchement.
  const act = b("12:00", "pending", { activityId: "prepa", durationMin: 60 });
  assert.equal(blockHasSession(act, sessions), true);
  assert.equal(blockHasSession(b("19:00", "pending", { activityId: "prepa" }), sessions), false, "hors créneau");
});

test("remplacement (B10) : le BPF passé non relisté disparaît, le bloc fait reste, un entrant sur un bloc fait est écarté", () => {
  const prev = [
    { id: "corr", startTime: "11:30", durationMin: 420, status: "done", title: "Correction" },
    { id: "bpf", startTime: "22:40", durationMin: 50, status: "pending", title: "BPF" },
  ];
  const settled = prev.filter((b) => isSettledBlock(b));
  assert.deepEqual(settled.map((b) => b.id), ["corr"]);
  const incoming = [
    { startTime: "12:00", durationMin: 60, title: "Doublon passé" },
    { startTime: "23:15", durationMin: 15, title: "Petit bloc du soir" },
  ];
  const { kept, dropped, conflicts } = fillAgainstExisting(incoming, settled);
  assert.deepEqual(kept.map((b) => b.title), ["Petit bloc du soir"]);
  assert.deepEqual(dropped.map((b) => b.title), ["Doublon passé"]);
  assert.equal(conflicts[0].by.id, "corr", "le message nomme le bloc occupant");
});

test("mode compléter : un bloc écarté nomme son occupant ; sauté ou retiré, il libère le créneau", () => {
  const bpf = { id: "bpf", startTime: "22:40", durationMin: 50, status: "pending", title: "BPF" };
  const want = [{ startTime: "23:15", durationMin: 15, title: "Soir" }];
  const r1 = fillAgainstExisting(want, [bpf]);
  assert.equal(r1.kept.length, 0);
  assert.equal(r1.conflicts[0].by.id, "bpf");
  const r2 = fillAgainstExisting(want, [{ ...bpf, status: "skipped" }]);
  assert.equal(r2.kept.length, 1, "update_block(status:skipped) libère le créneau");
  const r3 = fillAgainstExisting(want, [{ ...bpf, status: "deleted" }]);
  assert.equal(r3.kept.length, 1, "update_block(delete:true) aussi");
});

test("nearestFreeSlotAnywhere : la journée active d'abord, sinon le vrai libre hors fenêtre (23:30 après le dernier bloc)", () => {
  const busy = [
    { startTime: "07:00", durationMin: 15 * 60, status: "done", title: "Journée" },
    { startTime: "22:00", durationMin: 90, status: "pending", title: "Soirée" },
  ];
  const win = { startMin: 7 * 60, endMin: 22 * 60 };
  const r = nearestFreeSlotAnywhere({ startTime: "22:40", durationMin: 30 }, busy, win);
  assert.deepEqual(r, { slot: "23:30", inWindow: false });
  const r2 = nearestFreeSlotAnywhere({ startTime: "09:00", durationMin: 30 }, [], win);
  assert.deepEqual(r2, { slot: "09:00", inWindow: true });
});

test("nextFreeSlot (B11) : vers l'avant depuis max(maintenant, demandé), jamais depuis 00:00 ; sinon dit jusqu'où", () => {
  const bpf = { id: "bpf", startTime: "22:40", durationMin: 50, status: "pending", title: "BPF" };
  const sommeil = { id: "s", startTime: "23:30", durationMin: 30, status: "pending", title: "Sommeil" };
  const want = { startTime: "23:15", durationMin: 15 };
  // 23:05, BPF jusqu'à 23:30 puis Sommeil : rien de 15 min avant Sommeil 23:30.
  assert.deepEqual(nextFreeSlot(want, [bpf, sommeil], Math.max(toMin("23:05"), toMin("23:15"))),
    { slot: null, until: { title: "Sommeil", startTime: "23:30" } });
  // Sans Sommeil : 23:30 est libre (après le BPF), pas 20:45.
  assert.deepEqual(nextFreeSlot(want, [bpf], toMin("23:15")), { slot: "23:30", until: null });
  // Autre date : à partir de l'heure demandée, trou de 09:00 ignoré.
  const busy = [{ startTime: "10:00", durationMin: 60, status: "pending", title: "A" }];
  assert.deepEqual(nextFreeSlot({ startTime: "10:30", durationMin: 30 }, busy, toMin("10:30")), { slot: "11:00", until: null });
  // Dépasse minuit : rien.
  assert.deepEqual(nextFreeSlot({ startTime: "23:50", durationMin: 30 }, [], toMin("23:50")), { slot: null, until: null });
});
