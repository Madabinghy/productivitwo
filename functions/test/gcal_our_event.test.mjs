import { test } from "node:test";
import assert from "node:assert/strict";
import gcal from "../lib/gcal.js";

const { isOurEvent } = gcal;

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
