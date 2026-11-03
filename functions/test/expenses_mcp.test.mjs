import { test } from "node:test";
import assert from "node:assert/strict";
import { expensesIn, expenseLine, planDelete, planReceiptUpdate, planExpenseUpdate, noteForStore } from "../lib/expenses_mcp.js";

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

test("corriger un ticket : magasin, heure, date ; les dépenses suivent", () => {
  const exp = {
    "t-0": { ymd: "2026-11-03", amount: 1000, note: "Courses", receiptId: "t" },
    "t-1": { ymd: "2026-11-03", amount: 434, note: "pour Julie", receiptId: "t" },
    x: { ymd: "2026-11-03", amount: 167, note: "Courses" },
  };
  const p = planReceiptUpdate("t", { ymd: "2026-11-03", total: 1434 }, exp, { store: " K-Market ", time: "9:05", date: "2026-11-02", ref: "" });
  assert.deepEqual(p.errors, []);
  assert.deepEqual(p.receipt, { store: "K-Market", ref: null, time: "09:05", ymd: "2026-11-02" });
  assert.deepEqual(p.expenses, { "t-0": { note: "Courses · K-Market", ymd: "2026-11-02" }, "t-1": { ymd: "2026-11-02" } });
  assert.match(planReceiptUpdate("zz", undefined, exp, { store: "A" }).errors[0], /introuvable/);
  assert.match(planReceiptUpdate("t", {}, exp, { time: "9h" }).errors[0], /HH:MM/);
  assert.equal(noteForStore("Courses · Lidl", null), "Courses");
});

test("corriger une dépense seule ; une part de ticket garde son montant", () => {
  const p = planExpenseUpdate({ ymd: "2026-11-03", amount: 167, note: "Courses" }, { note: "Courses · K-Market", amount: 199, domainId: "", date: "2026-11-02" });
  assert.deepEqual(p.errors, []);
  assert.deepEqual(p.set, { note: "Courses · K-Market", amount: 199, ymd: "2026-11-02" });
  assert.deepEqual(p.remove, ["domainId"]);
  const r = planExpenseUpdate({ ymd: "2026-11-03", amount: 100, receiptId: "t" }, { amount: 50 });
  assert.match(r.errors[0], /part de ticket/);
  assert.match(planExpenseUpdate(undefined, {}).errors[0], /introuvable/);
});
