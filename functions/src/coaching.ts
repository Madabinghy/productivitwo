import { onRequest } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import * as admin from "firebase-admin";
import { randomUUID } from "crypto";
import { db } from "./db";
import { executePushAssistantMessage } from "./execute";

// ─── BRIQUE COACHING v1 (mini-CRM + lecture + messages) ──────────────────────
//
// Un coach humain accompagne des coachés dans l'app : Productivi-TWO — ORION
// + le coach. v1 : fiches coachés (pipeline), invitation (allowlist), lien
// coach↔coaché avec CONSENTEMENT (lien partageable, révocable), tableau de
// bord en LECTURE, messages coach dans l'app du coaché (assistant_messages).
// La configuration ÉCRITE de l'app du coaché viendra en phase 2 (console web).
//
// Collections RACINE (sans règle Firestore → admin SDK uniquement) :
// - coaches/{uid}               : {active} — qui a le droit d'être coach
//                                 (posé via adminProductivitwo action setCoach)
// - coaching/{id}               : la fiche coaché — {coachUid, email,
//                                 coacheeUid?, name?, status, notes,
//                                 nextSession?, consent, consentAt?, ...}
// - coaching_consents/{token}   : jetons de consentement éphémères (14 j)
//
// Invariants : chaque lecture/écriture des DONNÉES du coaché exige
// consent == "granted" ; le consentement est révocable par le même lien ;
// tout est scopé coachUid (multi-coach prêt, même si un seul coach aujourd'hui).

type Json = Record<string, any>;

const COACHING_STATUSES = ["prospect", "explo", "actif", "autonome", "termine"];
const CONSENT_URL = "https://coachconsent-dzos75b65q-uc.a.run.app";

const coachingRef = (id: string) => db.doc(`coaching/${id}`);

/** L'appelant (ID token Firebase) est-il un coach actif ? → uid ou null. */
async function coachUidFrom(authHeader: string): Promise<string | null> {
  if (!authHeader.startsWith("Bearer ")) return null;
  try {
    const uid = (await admin.auth().verifyIdToken(authHeader.slice(7).trim())).uid;
    const snap = await db.doc(`coaches/${uid}`).get();
    return snap.exists && snap.data()?.active === true ? uid : null;
  } catch {
    return null;
  }
}

/** Résout (et mémorise) l'uid Firebase du coaché à partir de son email. */
async function resolveCoacheeUid(docId: string, data: Json): Promise<string | null> {
  if (typeof data.coacheeUid === "string" && data.coacheeUid !== "") {
    return data.coacheeUid as string;
  }
  try {
    const user = await admin.auth().getUserByEmail(data.email as string);
    await coachingRef(docId).set({ coacheeUid: user.uid }, { merge: true });
    return user.uid;
  } catch {
    return null; // pas encore de compte — la fiche vit quand même (phase explo)
  }
}

/** Tableau de bord LECTURE d'un coaché : composé côté serveur, jamais de
 *  passe-plat des règles Firestore d'un user vers un autre. */
async function buildDashboard(coacheeUid: string): Promise<Json> {
  const now = new Date();
  const today = new Date(now.getTime());
  const ymd = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
  const weekAgo = new Date(now.getTime() - 7 * 86400000);

  const [domSnap, actSnap, schedSnap, sessSnap, capSnap] = await Promise.all([
    db.collection(`users/${coacheeUid}/domains`).get(),
    db.collection(`users/${coacheeUid}/activities`).get(),
    db.doc(`users/${coacheeUid}/daily_schedules/${ymd}`).get(),
    db.collection(`users/${coacheeUid}/sessions`)
      .where("startAt", ">=", weekAgo.toISOString()).get()
      .catch(() => null),
    db.collection(`users/${coacheeUid}/captures`)
      .where("status", "==", "pending").get()
      .catch(() => null),
  ]);

  const domains = domSnap.docs
    .map((d) => d.data())
    .filter((v) => v.deleted !== true)
    .map((v) => ({
      id: v.id, name: v.name,
      intention: v.intention ?? null,
      definitionStatus: v.definitionStatus ?? null,
    }));

  const activities = actSnap.docs
    .map((d) => d.data())
    .filter((v) => v.deleted !== true)
    .map((v) => ({
      id: v.id, name: v.name, type: v.type ?? "time",
      domainId: v.domainId ?? null,
      goalMin: v.goalMin ?? null,
      habitTarget: v.habitTarget ?? null,
    }));

  // Minutes loggées sur 7 jours, par activité (sessions terminées).
  const minutesByActivity: Record<string, number> = {};
  for (const d of sessSnap?.docs ?? []) {
    const v = d.data();
    const start = Date.parse(String(v.startAt ?? ""));
    const end = Date.parse(String(v.endAt ?? ""));
    if (!isFinite(start) || !isFinite(end) || end <= start) continue;
    const id = String(v.activityId ?? "");
    minutesByActivity[id] =
      (minutesByActivity[id] ?? 0) + Math.round((end - start) / 60000);
  }

  const blocks = ((schedSnap.data()?.blocks as Json[]) ?? [])
    .filter((b) => b.status !== "deleted")
    .map((b) => ({
      startTime: b.startTime, durationMin: b.durationMin,
      title: b.title, status: b.status, challenge: b.challenge === true,
    }));

  return {
    date: ymd,
    domains,
    activities,
    todayBlocks: blocks,
    weekMinutesByActivity: minutesByActivity,
    pendingIdeas: capSnap?.size ?? 0,
  };
}

// ── coachApi : POST + Authorization: Bearer <ID token Firebase du coach> ──────

export const coachApi = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

    const coachUid = await coachUidFrom(req.headers.authorization ?? "");
    if (!coachUid) { res.status(403).json({ error: "Accès coach requis" }); return; }

    const { action, id, email, name, status, notes, nextSession, text, targetDate } =
      req.body as {
        action?: string; id?: string; email?: string; name?: string;
        status?: string; notes?: string; nextSession?: string;
        text?: string; targetDate?: string;
      };

    /** Fiche appartenant à CE coach — null sinon (jamais celle d'un autre). */
    const ownDoc = async (docId?: string): Promise<Json | null> => {
      if (!docId) return null;
      const snap = await coachingRef(docId).get();
      const d = snap.data();
      return snap.exists && d?.coachUid === coachUid ? { ...d, id: docId } : null;
    };

    try {
      if (action === "listClients") {
        const snap = await db.collection("coaching")
          .where("coachUid", "==", coachUid).get();
        const clients = snap.docs.map((d) => {
          const v = d.data();
          return {
            id: d.id, email: v.email, name: v.name ?? null,
            coacheeUid: v.coacheeUid ?? null,
            status: v.status, notes: v.notes ?? "",
            nextSession: v.nextSession ?? null,
            consent: v.consent ?? "pending",
          };
        });
        res.status(200).json({ clients });
        return;
      }

      if (action === "createClient") {
        const em = (email ?? "").trim().toLowerCase();
        if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(em)) {
          res.status(400).json({ error: "Email invalide" }); return;
        }
        // Une fiche par email et par coach — la phase explo crée la fiche
        // AVANT que le compte du coaché existe.
        const dup = await db.collection("coaching")
          .where("coachUid", "==", coachUid).where("email", "==", em).get();
        if (!dup.empty) {
          res.status(409).json({ error: "Fiche déjà existante", id: dup.docs[0].id });
          return;
        }
        const docId = randomUUID();
        await coachingRef(docId).set({
          id: docId,
          coachUid,
          email: em,
          name: (name ?? "").trim() || null,
          coacheeUid: null,
          status: COACHING_STATUSES.includes(status ?? "") ? status : "prospect",
          notes: notes ?? "",
          nextSession: null,
          consent: "pending",
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        res.status(200).json({ ok: true, id: docId });
        return;
      }

      if (action === "updateClient") {
        const doc = await ownDoc(id);
        if (!doc) { res.status(404).json({ error: "Fiche introuvable" }); return; }
        const patch: Json = { updatedAt: FieldValue.serverTimestamp() };
        if (status != null && COACHING_STATUSES.includes(status)) patch.status = status;
        if (notes != null) patch.notes = notes;
        if (name != null) patch.name = name.trim() || null;
        if (nextSession != null) patch.nextSession = nextSession.trim() || null;
        await coachingRef(doc.id).set(patch, { merge: true });
        res.status(200).json({ ok: true });
        return;
      }

      if (action === "invite") {
        // Ouvre l'accès app au coaché : allowlist → sendMagicLink passera.
        const doc = await ownDoc(id);
        if (!doc) { res.status(404).json({ error: "Fiche introuvable" }); return; }
        await db.collection("allowlist").doc(doc.email as string).set(
          { addedAt: FieldValue.serverTimestamp(), addedBy: `coach:${coachUid}` },
          { merge: true });
        res.status(200).json({ ok: true, email: doc.email });
        return;
      }

      if (action === "consentLink") {
        // Lien de consentement PARTAGEABLE (WhatsApp, mail…) — le coaché
        // accepte ou refuse sur une page web, révocable par le même lien.
        const doc = await ownDoc(id);
        if (!doc) { res.status(404).json({ error: "Fiche introuvable" }); return; }
        const token = randomUUID();
        await db.doc(`coaching_consents/${token}`).set({
          coachingId: doc.id,
          email: doc.email,
          createdAt: FieldValue.serverTimestamp(),
          expiresAt: Date.now() + 14 * 86400000,
        });
        res.status(200).json({ ok: true, url: `${CONSENT_URL}?token=${token}` });
        return;
      }

      if (action === "dashboard") {
        const doc = await ownDoc(id);
        if (!doc) { res.status(404).json({ error: "Fiche introuvable" }); return; }
        if (doc.consent !== "granted") {
          res.status(200).json({ ok: false, reason: "consent_required" }); return;
        }
        const coacheeUid = await resolveCoacheeUid(doc.id as string, doc);
        if (!coacheeUid) {
          res.status(200).json({ ok: false, reason: "no_account" }); return;
        }
        const dash = await buildDashboard(coacheeUid);
        res.status(200).json({ ok: true, dashboard: dash });
        return;
      }

      if (action === "message") {
        // Message du coach dans l'app du coaché — même canal qu'ORION
        // (assistant_messages), signé du nom du coach.
        const doc = await ownDoc(id);
        if (!doc) { res.status(404).json({ error: "Fiche introuvable" }); return; }
        if (doc.consent !== "granted") {
          res.status(200).json({ ok: false, reason: "consent_required" }); return;
        }
        const coacheeUid = await resolveCoacheeUid(doc.id as string, doc);
        if (!coacheeUid) {
          res.status(200).json({ ok: false, reason: "no_account" }); return;
        }
        const body = (text ?? "").trim();
        if (!body) { res.status(400).json({ error: "text requis" }); return; }
        const coachName =
          (await admin.auth().getUser(coachUid)).displayName ?? "Ton coach";
        const date = targetDate && /^\d{4}-\d{2}-\d{2}$/.test(targetDate)
          ? targetDate
          : new Date().toISOString().slice(0, 10);
        await executePushAssistantMessage(coacheeUid, {
          targetDate: date,
          text: body,
          condition: { type: "always" },
          characterName: coachName,
          expiresAfterDays: 5,
        });
        res.status(200).json({ ok: true });
        return;
      }

      res.status(400).json({ error: `action inconnue : ${action}` });
    } catch (e) {
      console.error("coachApi error:", e);
      res.status(500).json({ error: "Erreur serveur coaching" });
    }
  }
);

// ── coachConsent : page web du coaché (GET, sans compte requis) ───────────────

const consentPage = (title: string, body: string) => `<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>body{font-family:-apple-system,sans-serif;background:#101418;color:#e8eef2;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
main{text-align:center;padding:32px;max-width:440px}h1{font-size:20px}p{color:#9fb0bb;line-height:1.5}
.btn{display:inline-block;margin:8px;padding:12px 22px;border-radius:12px;text-decoration:none;font-weight:700}
.ok{background:#1a9e6e;color:#fff}.no{background:#2a3440;color:#e8eef2}</style>
</head><body><main><h1>${title}</h1>${body}</main></body></html>`;

export const coachConsent = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    const token = String(req.query.token ?? "");
    const decision = String(req.query.decision ?? "");
    const fail = (msg: string) =>
      res.status(400).send(consentPage("Lien invalide", `<p>${msg}</p>`));
    if (!token) { fail("Ce lien est incomplet — redemande-le à ton coach."); return; }

    try {
      const tokSnap = await db.doc(`coaching_consents/${token}`).get();
      const tok = tokSnap.data();
      if (!tokSnap.exists || Number(tok?.expiresAt ?? 0) < Date.now()) {
        fail("Ce lien a expiré — redemande-le à ton coach."); return;
      }
      const docSnap = await coachingRef(tok!.coachingId as string).get();
      if (!docSnap.exists) { fail("Fiche introuvable."); return; }
      const d = docSnap.data() as Json;
      const coachName =
        (await admin.auth().getUser(d.coachUid as string)).displayName ?? "Ton coach";

      // Pas de décision → page de choix (jamais d'action sur simple ouverture :
      // les scanners d'emails ouvrent les liens).
      if (decision !== "accept" && decision !== "refuse") {
        res.status(200).send(consentPage(
          "Accompagnement Productivitwo",
          `<p><b>${coachName}</b> souhaite t'accompagner dans Productivitwo :
           il pourra <b>voir</b> tes domaines, routines, programme et temps
           passés, et t'envoyer des messages dans l'app. Rien n'est modifié
           sans toi, et tu peux révoquer cet accès à tout moment avec ce même
           lien.</p>
           <a class="btn ok" href="?token=${token}&decision=accept">J'accepte</a>
           <a class="btn no" href="?token=${token}&decision=refuse">Je refuse</a>`));
        return;
      }

      const granted = decision === "accept";
      await coachingRef(tok!.coachingId as string).set({
        consent: granted ? "granted" : "revoked",
        consentAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      // Lier l'uid si le compte existe déjà (sinon il se liera plus tard).
      try {
        const user = await admin.auth().getUserByEmail(d.email as string);
        await coachingRef(tok!.coachingId as string)
          .set({ coacheeUid: user.uid }, { merge: true });
      } catch { /* pas encore de compte */ }

      res.status(200).send(consentPage(
        granted ? "C'est noté ✓" : "Accès refusé",
        granted
          ? `<p>${coachName} peut maintenant suivre ton avancée et t'écrire
             dans l'app. Tu peux révoquer cet accès à tout moment en rouvrant
             ce lien.</p>
             <a class="btn no" href="?token=${token}&decision=refuse">Révoquer l'accès</a>`
          : `<p>Aucun accès n'est ouvert. Tu peux changer d'avis avec ce même
             lien.</p>
             <a class="btn ok" href="?token=${token}&decision=accept">Finalement, j'accepte</a>`));
    } catch (e) {
      console.error("coachConsent error:", e);
      fail("Erreur serveur — réessaie dans un instant.");
    }
  }
);
