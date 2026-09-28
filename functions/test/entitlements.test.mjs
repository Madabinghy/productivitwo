import { test } from "node:test";
import assert from "node:assert/strict";
import ent from "../lib/entitlements.js";

const { effectivePro, FREE_FOR_ALL } = ent;
const ts = (ms) => ({ toMillis: () => ms });
const future = ts(Date.now() + 86_400_000);
const past = ts(Date.now() - 86_400_000);

test("ouverture : FREE_FOR_ALL est actif et rend tout le monde Pro", () => {
  assert.equal(FREE_FOR_ALL, true);
  assert.equal(effectivePro({}), true);
  assert.equal(effectivePro(undefined), true);
  assert.equal(effectivePro({ proUntil: past }), true);
});

test("abonnement fermé : les trois sources restent évaluées", () => {
  assert.equal(effectivePro({}, false), false);
  assert.equal(effectivePro(undefined, false), false);
  assert.equal(effectivePro({ subscriptionUntil: future }, false), true);
  assert.equal(effectivePro({ subscriptionUntil: past }, false), false);
  assert.equal(effectivePro({ proUntil: future }, false), true);
  assert.equal(effectivePro({ proUntil: past }, false), false);
  assert.equal(effectivePro({ isPro: true }, false), true);
  assert.equal(effectivePro({ isPro: "true" }, false), false);
});
