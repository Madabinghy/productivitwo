#!/usr/bin/env node
/**
 * inbox.js — lit / ajoute / supprime des captures (liste d'idées) d'un utilisateur.
 * Auth : Application Default Credentials (gcloud auth application-default login).
 *
 * Usage :
 *   node scripts/inbox.js list <uid>
 *   node scripts/inbox.js add  <uid> "texte de la capture"
 *   node scripts/inbox.js del  <uid> <captureId>
 */
const path = require("path");
const admin = require(path.join(__dirname, "..", "functions", "node_modules", "firebase-admin"));
const { randomUUID } = require("crypto");

admin.initializeApp({ projectId: "productivitwo-app" });
const db = admin.firestore();

const [, , cmd, uid, arg] = process.argv;

async function main() {
  if (!cmd || !uid) {
    console.error("usage: inbox.js <list|add|del> <uid> [text|id]");
    process.exit(1);
  }
  const col = db.collection("users").doc(uid).collection("captures");

  if (cmd === "list") {
    const snap = await col.get();
    const items = snap.docs
      .map((d) => d.data())
      .filter((x) => (x.status ?? "pending") === "pending")
      .sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)));
    console.log(JSON.stringify(items, null, 2));
    console.log(`\n${items.length} capture(s) pending`);
  } else if (cmd === "add") {
    const id = randomUUID();
    await col.doc(id).set({
      id,
      text: arg ?? "",
      createdAt: new Date().toISOString(),
      status: "pending",
      orionNote: null,
      processedAt: null,
      createdBy: "claude",
    });
    console.log("added", id);
  } else if (cmd === "del") {
    await col.doc(arg).delete();
    console.log("deleted", arg);
  } else {
    console.error("unknown command", cmd);
    process.exit(1);
  }
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
