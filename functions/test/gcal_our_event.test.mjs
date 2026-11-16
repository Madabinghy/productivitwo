import { test } from "node:test";
import assert from "node:assert/strict";
import gcal from "../lib/gcal.js";

const { isOurEvent, isNativeEvent, isCopyOfBlock } = gcal;

test("sync natif : propriété privée pwo", () => {
  assert.equal(isOurEvent({ extendedProperties: { private: { pwo: "1" } } }), true);
});

test("Claude via connecteur : description source: productivitwo", () => {
  assert.equal(isOurEvent({ summary: "Finir les factures SOF", description: "source: productivitwo | category: project" }), true);
  assert.equal(isOurEvent({ summary: "Pause", description: "Source: Productivitwo" }), true);
});

test("Claude via connecteur : suffixe de titre", () => {
  assert.equal(isOurEvent({ summary: "Séance musculation - Productivitwo" }), true);
});

test("rendez-vous de l'utilisateur : importé", () => {
  assert.equal(isOurEvent({ summary: "Cléa Numérique - LAM4", description: "Salle 12" }), false);
  assert.equal(isOurEvent({ summary: "Productivitwo point coach" }), false);
});

test("marqué par Claude : ignoré seulement s'il recopie un bloc du programme", () => {
  assert.equal(isNativeEvent({ extendedProperties: { private: { pwo: "1" } } }), true);
  assert.equal(isNativeEvent({ description: "source: productivitwo" }), false);
  // Copie dupliquée à la main : garde pwoDate du jour d'origine.
  const copy = { extendedProperties: { private: { pwo: "1", pwoBlockId: "b", pwoDate: "2026-11-13" } } };
  assert.equal(isNativeEvent(copy, "2026-11-13"), true);
  assert.equal(isNativeEvent(copy, "2026-11-17"), false);
  const blocks = [
    { startTime: "09:00", durationMin: 60, title: "Deep work", status: "pending" },
    { startTime: "14:00", durationMin: 30, title: "Pause", status: "deleted" },
    { startTime: "16:00", durationMin: 60, title: "Rdv", status: "pending", gcalEventId: "x" },
  ];
  assert.equal(isCopyOfBlock({ startTime: "09:00", durationMin: 60, title: "Deep work" }, blocks), true);
  assert.equal(isCopyOfBlock({ startTime: "08:30", durationMin: 240, title: "Cléa Num- SPJ2" }, blocks), false);
  assert.equal(isCopyOfBlock({ startTime: "14:00", durationMin: 30, title: "Pause" }, blocks), true); // bloc retiré : sa copie ne revient pas
  assert.equal(isCopyOfBlock({ startTime: "16:00", durationMin: 60, title: "Rdv" }, blocks), false);
});
