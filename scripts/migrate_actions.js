#!/usr/bin/env node
// Migration one-shot : convertit les actions string[] → TaskAction[] dans les projets Firestore
// Usage : node scripts/migrate_actions.js
const admin = require('firebase-admin');
const { v4: uuidv4 } = require('uuid');

admin.initializeApp({ projectId: 'productivitwo-app' });
const db = admin.firestore();

const UID = '8kcC1O8o2QSt4vJi1vNo1nBZaOG2';

async function migrate() {
  const snap = await db.collection(`users/${UID}/projects`).get();
  let fixed = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const tasks = data.tasks || [];
    let needsFix = false;

    const fixedTasks = tasks.map((t) => {
      const actions = (t.actions || []).map((a) => {
        if (typeof a === 'string') {
          needsFix = true;
          return { id: uuidv4(), title: a, done: false, doneAt: null, createdAt: new Date().toISOString() };
        }
        return a;
      });
      return { ...t, actions };
    });

    if (needsFix) {
      await doc.ref.update({ tasks: fixedTasks });
      console.log(`✅ Corrigé : "${data.title}" (${doc.id})`);
      fixed++;
    } else {
      console.log(`⏭  OK déjà : "${data.title}" (${doc.id})`);
    }
  }

  console.log(`\nMigration terminée — ${fixed} projet(s) corrigé(s) sur ${snap.size}`);
  process.exit(0);
}

migrate().catch((e) => { console.error(e); process.exit(1); });
