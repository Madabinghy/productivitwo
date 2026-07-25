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

// ── Périmètre de partage (US-1) ──────────────────────────────────────────────
// Le consentement OUVRE le lien mais ne partage RIEN : le coaché opte ensuite
// domaine par domaine depuis son app (coacheeApi), et choisit la granularité.
// "status" = engagements tenus/en retard seulement ; "detail" = + temps par
// activité et blocs de journée. Défaut : aucun domaine, "status".

type Granularity = "status" | "detail";
type Sharing = { domainIds: string[]; granularity: Granularity };

function sharingOf(data: Json): Sharing {
  const s = (data.sharing ?? {}) as Json;
  return {
    domainIds: Array.isArray(s.domainIds) ? s.domainIds.map(String) : [],
    granularity: s.granularity === "detail" ? "detail" : "status",
  };
}

/** Journal RGPD : chaque transition de consentement/périmètre est horodatée,
 *  avec un snapshot du périmètre alors en vigueur. Jamais purgé. */
async function logConsentEvent(
  coachingId: string,
  event: "granted" | "refused" | "revoked" | "sharing_updated",
  scope?: Sharing,
): Promise<void> {
  await db.collection(`coaching/${coachingId}/consent_log`).doc(randomUUID()).set({
    event,
    actor: "coachee",
    at: FieldValue.serverTimestamp(),
    ...(scope ? { scope } : {}),
  });
}

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
 *  passe-plat des règles Firestore d'un user vers un autre. Minimisation :
 *  seuls les domaines du périmètre apparaissent — nulle part ailleurs, même
 *  pas agrégés ; le mode "status" omet temps, blocs et boîte à idées. */
async function buildDashboard(coacheeUid: string, sharing: Sharing): Promise<Json> {
  const detail = sharing.granularity === "detail";
  const sharedDomains = new Set(sharing.domainIds);
  const now = new Date();
  const today = new Date(now.getTime());
  const ymd = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
  const weekAgo = new Date(now.getTime() - 7 * 86400000);
  // Lundi de la semaine courante (les engagements sont hebdo) puis S-3 :
  // fenêtre des 4 semaines de la tendance (console coach 8a / US-2).
  const monday = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7));
  const fourWeeksAgo = new Date(monday.getTime() - 3 * 7 * 86400000);

  const [domSnap, actSnap, schedSnap, sessSnap, capSnap, hitsSnap] = await Promise.all([
    db.collection(`users/${coacheeUid}/domains`).get(),
    db.collection(`users/${coacheeUid}/activities`).get(),
    db.doc(`users/${coacheeUid}/daily_schedules/${ymd}`).get(),
    db.collection(`users/${coacheeUid}/sessions`)
      .where("startAt", ">=", fourWeeksAgo.toISOString()).get()
      .catch(() => null),
    db.collection(`users/${coacheeUid}/captures`)
      .where("status", "==", "pending").get()
      .catch(() => null),
    db.collection(`users/${coacheeUid}/habitHits`)
      .where("ts", ">=", fourWeeksAgo.toISOString()).get()
      .catch(() => null),
  ]);

  const domains = domSnap.docs
    .map((d) => d.data())
    .filter((v) => v.deleted !== true && sharedDomains.has(String(v.id)))
    .map((v) => ({
      id: v.id, name: v.name,
      intention: v.intention ?? null,
      definitionStatus: v.definitionStatus ?? null,
    }));

  // Domaine de CHAQUE activité (partagée ou non) — sert à écarter les blocs
  // rattachés à un domaine hors périmètre.
  const domainOfActivity: Record<string, string> = {};
  for (const d of actSnap.docs) {
    const v = d.data();
    domainOfActivity[String(v.id)] = String(v.domainId ?? "");
  }

  const activities = actSnap.docs
    .map((d) => d.data())
    .filter((v) => v.deleted !== true && sharedDomains.has(String(v.domainId ?? "")))
    .map((v) => ({
      id: v.id, name: v.name, type: v.type ?? "time",
      domainId: v.domainId ?? null,
      goalMin: v.goalMin ?? null,
      habitTarget: v.habitTarget ?? null,
    }));
  const sharedActivityIds = new Set(activities.map((a) => String(a.id)));

  // Minutes loggées sur 7 jours, par activité partagée (mode détail seulement).
  const minutesByActivity: Record<string, number> = {};
  for (const d of sessSnap?.docs ?? []) {
    const v = d.data();
    const start = Date.parse(String(v.startAt ?? ""));
    const end = Date.parse(String(v.endAt ?? ""));
    if (!isFinite(start) || !isFinite(end) || end <= start) continue;
    if (start < weekAgo.getTime()) continue;
    const id = String(v.activityId ?? "");
    if (!sharedActivityIds.has(id)) continue;
    minutesByActivity[id] =
      (minutesByActivity[id] ?? 0) + Math.round((end - start) / 60000);
  }

  // ── Les 3 chiffres de l'US-2 (console 8a) — disponibles dès "status" ────────
  // Engagements hebdo = routines des domaines partagés (habitFreq 0=daily,
  // 1=weekly ; monthly hors tendance). Cible daily ramenée à la semaine (×7).
  const habits = actSnap.docs
    .map((d) => d.data())
    .filter((v) =>
      v.deleted !== true &&
      v.type === "habit" &&
      (v.habitFreq === 0 || v.habitFreq === 1) &&
      sharedDomains.has(String(v.domainId ?? "")));
  const hitsByHabit: Record<string, number[]> = {}; // habitId → timestamps
  for (const d of hitsSnap?.docs ?? []) {
    const v = d.data();
    const t = Date.parse(String(v.ts ?? ""));
    if (!isFinite(t)) continue;
    (hitsByHabit[String(v.habitId ?? "")] ??= []).push(t);
  }
  const weekTarget = (h: Json): number => {
    const base = Number(h.habitTarget ?? 1) || 1;
    return Math.max(1, h.habitFreq === 0 ? base * 7 : base);
  };
  const doneInRange = (habitId: string, from: number, to: number): number =>
    (hitsByHabit[habitId] ?? []).filter((t) => t >= from && t < to).length;
  const doneInWeek = (habitId: string, weekStart: Date): number =>
    doneInRange(habitId, weekStart.getTime(), weekStart.getTime() + 7 * 86400000);

  // Suivi AU FIL DE L'EAU : fenêtre GLISSANTE de 7 jours — un lundi matin,
  // la semaine calendaire serait quasi vide (chiffres anxiogènes sans info).
  const rollingFrom = now.getTime() - 7 * 86400000;
  const engagements = habits.map((h) => {
    const target = weekTarget(h);
    const done = doneInRange(String(h.id), rollingFrom, now.getTime() + 1);
    return {
      id: h.id, domainId: h.domainId ?? null, label: h.name,
      target, done, kept: done >= target,
    };
  });

  // Tendance : 3 semaines calendaires RÉVOLUES (S-3 → S-1), puis les
  // 7 jours glissants comme dernier bloc — cohérent avec les engagements.
  const weeks = [3, 2, 1].map((back) => {
    const ws = new Date(monday.getTime() - back * 7 * 86400000);
    const kept = habits.filter(
      (h) => doneInWeek(String(h.id), ws) >= weekTarget(h)).length;
    return {
      startYmd: ws.toISOString().slice(0, 10),
      label: `S-${back}`,
      pct: habits.length === 0 ? 0 : Math.round((kept / habits.length) * 100),
    };
  });
  weeks.push({
    startYmd: new Date(rollingFrom).toISOString().slice(0, 10),
    label: "7 j",
    pct: habits.length === 0
      ? 0
      : Math.round(
          (habits.filter((h) =>
            doneInRange(String(h.id), rollingFrom, now.getTime() + 1) >=
            weekTarget(h)).length / habits.length) * 100),
  });

  // Dernière activité — périmètre partagé uniquement (minimisation).
  let lastActivityAt: number | null = null;
  for (const d of sessSnap?.docs ?? []) {
    const v = d.data();
    if (!sharedActivityIds.has(String(v.activityId ?? ""))) continue;
    const t = Date.parse(String(v.startAt ?? ""));
    if (isFinite(t) && (lastActivityAt == null || t > lastActivityAt)) {
      lastActivityAt = t;
    }
  }
  const sharedHabitIds = new Set(habits.map((h) => String(h.id)));
  for (const [habitId, ts] of Object.entries(hitsByHabit)) {
    if (!sharedHabitIds.has(habitId)) continue;
    for (const t of ts) {
      if (lastActivityAt == null || t > lastActivityAt) lastActivityAt = t;
    }
  }

  // Blocs du jour (mode détail) — un bloc rattaché à une activité d'un domaine
  // NON partagé est écarté ; les blocs sans rattachement domaine passent.
  const blocks = ((schedSnap.data()?.blocks as Json[]) ?? [])
    .filter((b) => b.status !== "deleted")
    .filter((b) => {
      const actId = String(b.activityId ?? "");
      return actId === "" || sharedDomains.has(domainOfActivity[actId] ?? "");
    })
    .map((b) => ({
      startTime: b.startTime, durationMin: b.durationMin,
      title: b.title, status: b.status, challenge: b.challenge === true,
    }));

  return {
    date: ymd,
    granularity: sharing.granularity,
    domains,
    activities,
    engagements,
    weeks,
    lastActivityAt: lastActivityAt == null
      ? null
      : new Date(lastActivityAt).toISOString(),
    todayBlocks: detail ? blocks : null,
    weekMinutesByActivity: detail ? minutesByActivity : null,
    pendingIdeas: detail ? (capSnap?.size ?? 0) : null,
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
          const sharing = sharingOf(v);
          return {
            id: d.id, email: v.email, name: v.name ?? null,
            coacheeUid: v.coacheeUid ?? null,
            status: v.status, notes: v.notes ?? "",
            nextSession: v.nextSession ?? null,
            consent: v.consent ?? "pending",
            sharing: {
              domainCount: sharing.domainIds.length,
              granularity: sharing.granularity,
            },
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

      if (action === "deleteClient") {
        // Suppression DURE assumée (cas explicite : fiche mal créée — mauvais
        // email). Collection racine server-only : aucun merge client ne peut
        // la ressusciter. Nettoie aussi l'allowlist si C'EST CE COACH qui
        // avait invité cet email, et les jetons de consentement du doc.
        const doc = await ownDoc(id);
        if (!doc) { res.status(404).json({ error: "Fiche introuvable" }); return; }
        const allowRef = db.collection("allowlist").doc(doc.email as string);
        const allowSnap = await allowRef.get();
        if (allowSnap.exists && allowSnap.data()?.addedBy === `coach:${coachUid}`) {
          await allowRef.delete();
        }
        const toks = await db.collection("coaching_consents")
          .where("coachingId", "==", doc.id).get();
        await Promise.all(toks.docs.map((t) => t.ref.delete()));
        await coachingRef(doc.id as string).delete();
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
        // Générer le lien VAUT invitation : l'email du coaché passe en
        // allowlist, sinon sendMagicLink lui répond « réservé à la
        // formation » au moment de créer son compte. Même marquage que
        // l'action invite → nettoyé si la fiche est supprimée.
        await db.collection("allowlist").doc(doc.email as string).set(
          { addedAt: FieldValue.serverTimestamp(), addedBy: `coach:${coachUid}` },
          { merge: true });
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
        const sharing = sharingOf(doc);
        if (sharing.domainIds.length === 0) {
          res.status(200).json({ ok: false, reason: "no_scope" }); return;
        }
        const dash = await buildDashboard(coacheeUid, sharing);
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
          `<p><b>${coachName}</b> souhaite t'accompagner dans Productivitwo.
           Accepter ouvre le lien, mais <b>ne partage rien</b> : c'est toi qui
           choisiras ensuite, dans l'app (Paramètres → Mon coach), quels
           domaines de vie il peut voir et à quel niveau de détail. Rien n'est
           modifié sans toi, et tu peux tout révoquer à n'importe quel moment.</p>
           <a class="btn ok" href="?token=${token}&decision=accept">J'accepte</a>
           <a class="btn no" href="?token=${token}&decision=refuse">Je refuse</a>`));
        return;
      }

      const granted = decision === "accept";

      // Un seul coach par coaché (V1.1) : refuse l'acceptation si un AUTRE
      // lien est déjà actif pour cet email.
      if (granted) {
        const others = await db.collection("coaching")
          .where("email", "==", d.email).where("consent", "==", "granted").get();
        if (others.docs.some((o) => o.id !== tok!.coachingId)) {
          res.status(200).send(consentPage(
            "Un coach à la fois",
            `<p>Tu as déjà un accompagnement actif avec un autre coach.
             Révoque d'abord cet accès (depuis ton app : Paramètres → Mon
             coach) avant d'en accepter un nouveau.</p>`));
          return;
        }
      }

      const prevConsent = String(d.consent ?? "pending");
      await coachingRef(tok!.coachingId as string).set({
        consent: granted ? "granted" : "revoked",
        consentAt: FieldValue.serverTimestamp(),
        // L'acceptation (re)part toujours d'un périmètre VIDE : le partage
        // est un opt-in du coaché dans son app, jamais un état hérité.
        ...(granted ? { sharing: { domainIds: [], granularity: "status" } } : {}),
      }, { merge: true });
      await logConsentEvent(
        tok!.coachingId as string,
        granted ? "granted" : prevConsent === "granted" ? "revoked" : "refused",
        granted ? { domainIds: [], granularity: "status" } : sharingOf(d),
      );
      // Lier l'uid si le compte existe déjà (sinon il se liera plus tard).
      try {
        const user = await admin.auth().getUserByEmail(d.email as string);
        await coachingRef(tok!.coachingId as string)
          .set({ coacheeUid: user.uid }, { merge: true });
      } catch { /* pas encore de compte */ }

      res.status(200).send(consentPage(
        granted ? "C'est noté ✓" : "Accès refusé",
        granted
          ? `<p>Le lien avec ${coachName} est actif — mais il ne voit encore
             <b>rien</b> : ouvre ton app (Paramètres → Mon coach) pour choisir
             les domaines à partager et le niveau de détail. Tu peux révoquer
             cet accès à tout moment, depuis l'app ou en rouvrant ce lien.</p>
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

// ── coacheeApi : le CÔTÉ COACHÉ du lien (US-1) ────────────────────────────────
//
// POST + Authorization: Bearer <ID token Firebase du coaché>.
// Le coaché gère seul son partage depuis son app : voir le lien (getLink),
// choisir domaines + granularité (updateSharing), tout couper (revoke).
// La fiche racine reste server-only — jamais d'accès Firestore direct.

/** Fiche coaching du coaché appelant : par coacheeUid, sinon par email
 *  (compte créé après la fiche — on mémorise alors l'uid). Lien actif
 *  d'abord, sinon la plus pertinente. */
async function coacheeFiche(
  uid: string, email: string,
): Promise<{ id: string; data: Json } | null> {
  let snap = await db.collection("coaching").where("coacheeUid", "==", uid).get();
  if (snap.empty && email) {
    snap = await db.collection("coaching")
      .where("email", "==", email.toLowerCase()).get();
  }
  if (snap.empty) return null;
  const rank = (v: Json) =>
    v.consent === "granted" ? 0 : v.consent === "pending" ? 1 : 2;
  const doc = [...snap.docs].sort((a, b) => rank(a.data()) - rank(b.data()))[0];
  if (doc.data().coacheeUid !== uid) {
    await doc.ref.set({ coacheeUid: uid }, { merge: true });
  }
  return { id: doc.id, data: doc.data() };
}

export const coacheeApi = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

    const authHeader = req.headers.authorization ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Authorization requis" }); return;
    }
    let uid: string; let email: string;
    try {
      const decoded = await admin.auth().verifyIdToken(authHeader.slice(7).trim());
      uid = decoded.uid;
      email = decoded.email ?? "";
    } catch {
      res.status(401).json({ error: "Token invalide ou expiré" }); return;
    }

    const { action, domainIds, granularity } = req.body as {
      action?: string; domainIds?: string[]; granularity?: string;
    };

    try {
      const fiche = await coacheeFiche(uid, email);

      if (action === "getLink") {
        if (!fiche) { res.status(200).json({ linked: false }); return; }
        const coachName =
          (await admin.auth().getUser(fiche.data.coachUid as string))
            .displayName ?? "Ton coach";
        res.status(200).json({
          linked: true,
          coachName,
          consent: fiche.data.consent ?? "pending",
          sharing: sharingOf(fiche.data),
        });
        return;
      }

      if (action === "updateSharing") {
        if (!fiche || fiche.data.consent !== "granted") {
          res.status(400).json({ error: "Aucun lien coach actif" }); return;
        }
        const gran: Granularity = granularity === "detail" ? "detail" : "status";
        const wanted = Array.isArray(domainIds) ? domainIds.map(String) : [];
        // Uniquement des domaines existants (non supprimés) du coaché.
        const domSnap = await db.collection(`users/${uid}/domains`).get();
        const valid = new Set(domSnap.docs
          .map((d) => d.data())
          .filter((v) => v.deleted !== true)
          .map((v) => String(v.id)));
        const sharing: Sharing = {
          domainIds: [...new Set(wanted.filter((id) => valid.has(id)))],
          granularity: gran,
        };
        await coachingRef(fiche.id).set(
          { sharing, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
        await logConsentEvent(fiche.id, "sharing_updated", sharing);
        res.status(200).json({ ok: true, sharing });
        return;
      }

      if (action === "revoke") {
        if (!fiche) { res.status(400).json({ error: "Aucun lien coach" }); return; }
        await coachingRef(fiche.id).set({
          consent: "revoked",
          consentAt: FieldValue.serverTimestamp(),
        }, { merge: true });
        await logConsentEvent(fiche.id, "revoked", sharingOf(fiche.data));
        res.status(200).json({ ok: true });
        return;
      }

      res.status(400).json({ error: `action inconnue : ${action}` });
    } catch (e) {
      console.error("coacheeApi error:", e);
      res.status(500).json({ error: "Erreur serveur coaching" });
    }
  }
);
