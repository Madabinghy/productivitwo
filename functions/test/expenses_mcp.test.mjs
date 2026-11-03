import { test } from "node:test";
import assert from "node:assert/strict";
import { expensesIn, expenseLine, planDelete } from "../lib/expenses_mcp.js";

const expenses = {
  a: { ymd: "2026-11-03", amount: 1267, envelopeId: "courses", note: "Courses", domainId: "s", items: ["Pomme de terre 1,35 kg", "Lardons"], at: 1 },
  b: { ymd: "2026-11-03", amount: 167, envelopeId: "courses", note: "Courses", domainId: "i", at: 2 },
  "t-0": { ymd: "2026-11-03", amount: 1267, envelopeId: "courses", note: "Courses", domainId: "s", receiptId: "t", at: 3 },
  "t-1": { ymd: "2026-11-03", amount: 167, envelopeId: "courses", note: "Courses", domainId: "i", receiptId: "t", at: 3 },
  old: { ymd: "2026-10-20", amount: 500, envelopeId: "sorties" },
};
const receipts = { t: { ymd: "2026-11-03", total: 1434 } };

test("lister une période, la plus récente d'abord, avec les ids", () => {
  const l = expensesIn(expenses, "2026-11-01", "2026-11-30");
  assert.deepEqual(l.map(([id]) => id), ["t-0", "t-1", "b", "a"]);
  const line = expenseLine("a", expenses.a, { domain: (d) => ({ s: "Santé" })[d], envelope: () => "Courses" });
  assert.equal(line, "• [a] 2026-11-03 · 12,67 € · Courses (Courses · Santé) — Pomme de terre 1,35 kg, Lardons");
});

test("retirer des dépenses, un ticket entier, signaler les inconnues", () => {
  const p = planDelete(expenses, receipts, ["a", "b", "zz"], []);
  assert.deepEqual(p.expenseIds.sort(), ["a", "b"]);
  assert.deepEqual(p.receiptIds, []);
  assert.deepEqual(p.missing, ["zz"]);
  assert.equal(p.total, 1434);
  const r = planDelete(expenses, receipts, [], ["t"]);
  assert.deepEqual(r.expenseIds.sort(), ["t-0", "t-1"]);
  assert.deepEqual(r.receiptIds, ["t"]);
  const part = planDelete(expenses, receipts, ["t-1"], []);
  assert.deepEqual(part.receiptIds, []);
  const whole = planDelete(expenses, receipts, ["t-1"], [], true);
  assert.deepEqual(whole.expenseIds.sort(), ["t-0", "t-1"]);
});
