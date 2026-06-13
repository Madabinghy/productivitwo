#!/usr/bin/env node
/**
 * reset_deck.cjs — pose deckResetYmd (deck d'invasion propre à partir de cette
 * date, sans toucher l'historique réel). Optionnel : --wipe-pestkills, --wipe-sessions.
 *
 *   node scripts/reset_deck.cjs <uid> [YYYY-MM-DD] [--wipe-pestkills] [--wipe-sessions]
 */
const path = require("path");
const admin = require(path.join(__dirname, "..", "functions", "node_modules", "firebase-admin"));

admin.initializeApp({ projectId: "productivitwo-app" });
const db = admin.firestore();

const args = process.argv.slice(2);
const uid = args[0];
const ymd = args.find((a) => /^\d{4}-\d{2}-\d{2}$/.test(a)) ||
  new Date().toISOString().slice(0, 10);
const wipePest = args.includes("--wipe-pestkills");
const wipeSessions = args.includes("--wipe-sessions");

async function main() {
  if (!uid) {
    console.error("usage: reset_deck.cjs <uid> [YYYY-MM-DD] [--wipe-pestkills] [--wipe-sessions]");
    process.exit(1);
  }
  const meta = db.doc(`users/${uid}/data/meta`);
  const patch = { deckResetYmd: ymd };
  if (wipePest) patch.pestKills = {};
  await meta.set(patch, { merge: true });
  console.log(`deckResetYmd=${ymd} posé sur ${uid}${wipePest ? " (+pestKills vidé)" : ""}`);

  if (wipeSessions) {
    const col = db.collection(`users/${uid}/sessions`);
    let n = 0;
    while (true) {
      const snap = await col.limit(400).get();
      if (snap.empty) break;
      const batch = db.batch();
      snap.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      n += snap.size;
      if (snap.size < 400) break;
    }
    console.log(`${n} session(s) de temps supprimée(s)`);
  }
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
