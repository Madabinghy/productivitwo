import { test } from "node:test";
import assert from "node:assert/strict";
import { pushTitleFor, shouldPushNow, pushAllowed } from "../lib/push_rules.js";

test("pushTitleFor : coach signe, ORION par défaut", () => {
  assert.equal(pushTitleFor("coach", "Marie"), "🎓 Marie");
  assert.equal(pushTitleFor("coach", ""), "🎓 Ton coach");
  assert.equal(pushTitleFor(undefined, undefined), "◉ ORION");
  assert.equal(pushTitleFor("orion", "ORION"), "◉ ORION");
});

test("shouldPushNow : jamais avant le jour visé", () => {
  assert.equal(shouldPushNow("2026-10-30", "2026-10-30"), true);
  assert.equal(shouldPushNow("2026-10-29", "2026-10-30"), true);
  assert.equal(shouldPushNow("2026-11-02", "2026-10-30"), false);
});

test("pushAllowed : absent = oui, false = non", () => {
  assert.equal(pushAllowed(undefined), true);
  assert.equal(pushAllowed({}), true);
  assert.equal(pushAllowed({ pushEnabled: false }), false);
});
