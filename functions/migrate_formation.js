// Migration des données formation vers le bon compte
// Source : QETPpTmSOTcvN18fFrDnTKVcWuh2 (compte Google)
// Cible  : 8kcC1O8o2QSt4vJi1vNo1nBZaOG2 (compte iOS réel)

const admin = require("firebase-admin");

const SOURCE_UID = "QETPpTmSOTcvN18fFrDnTKVcWuh2";
const TARGET_UID = "8kcC1O8o2QSt4vJi1vNo1nBZaOG2";
const COLLECTIONS = ["domains", "activities", "projects"];

admin.initializeApp();
const db = admin.firestore();

async function migrate() {
  let total = 0;

  for (const col of COLLECTIONS) {
    const snap = await db.collection(`users/${SOURCE_UID}/${col}`).get();
    if (snap.empty) { console.log(`  ${col} : vide`); continue; }

    const batch = db.batch();
    for (const doc of snap.docs) {
      const ref = db.collection(`users/${TARGET_UID}/${col}`).doc(doc.id);
      batch.set(ref, doc.data(), { merge: true });
    }
    await batch.commit();
    console.log(`  ✓ ${col} : ${snap.size} doc(s) migrés`);
    total += snap.size;
  }

  // formation_access aussi
  const faSnap = await db.collection("formation_access").doc(SOURCE_UID).get();
  if (faSnap.exists) {
    await db.collection("formation_access").doc(TARGET_UID).set(
      { ...faSnap.data(), uid: TARGET_UID },
      { merge: true }
    );
    console.log("  ✓ formation_access migré");
  }

  console.log(`\n✅ Migration terminée — ${total} documents copiés vers ${TARGET_UID}`);
  console.log("⚠️  Les données sources ne sont pas supprimées (à faire manuellement si besoin).");
  process.exit(0);
}

migrate().catch(e => { console.error("❌", e.message); process.exit(1); });
