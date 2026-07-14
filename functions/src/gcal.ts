import { onRequest } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { randomUUID } from "crypto";
import { db } from "./db";
import { validateToken, userDayParts } from "./execute";

// ─── GOOGLE AGENDA NATIF (Direction D) ───────────────────────────────────────
//
// OAuth CÔTÉ SERVEUR (authorization code + refresh token) : ORION, le MCP
// (add_event/schedule_day) et l'app écrivent dans l'agenda sans que l'app
// soit ouverte et sans passer par le connecteur Claude.
//
// - Tokens dans `gcal_tokens/{uid}` (collection racine SANS règle Firestore →
//   accès client refusé par défaut, admin SDK uniquement).
// - Sync par TRIGGER Firestore sur users/{uid}/daily_schedules/{date} : un
//   seul chemin de sync qui couvre TOUS les écrivains (app, schedule_day,
//   add_event, défis ORION). Diff idempotent par extendedProperties privées
//   (pwoBlockId / pwoDate) — jamais de doublon, suppression comprise.
// - Événements taggés `pwo=1` : la sync ne touche JAMAIS les événements
//   personnels de l'utilisateur.
//
// Prérequis (une fois, console Google Cloud du projet Firebase) :
//   1. Activer l'API « Google Calendar API ».
//   2. Créer un identifiant OAuth 2.0 « Application Web » avec l'URI de
//      redirection EXACTE : https://gcaloauthcallback-dzos75b65q-uc.a.run.app
//   3. firebase functions:secrets:set GCAL_CLIENT_ID
//      firebase functions:secrets:set GCAL_CLIENT_SECRET
// Détails : docs/gcal_setup.md

// Node 20 fournit fetch nativement ; la lib TS (es2017) ne le déclare pas.
// Typage minimal, suffisant pour les appels REST Google.
declare function fetch(
  url: string,
  init?: { method?: string; headers?: Record<string, string>; body?: string }
): Promise<{
  ok: boolean;
  status: number;
  json(): Promise<unknown>;
  text(): Promise<string>;
}>;

const CALLBACK_URL = "https://gcaloauthcallback-dzos75b65q-uc.a.run.app";
const SCOPES = "openid email https://www.googleapis.com/auth/calendar.events";
const CAL_BASE = "https://www.googleapis.com/calendar/v3/calendars/primary";
const GCAL_SECRETS = ["GCAL_CLIENT_ID", "GCAL_CLIENT_SECRET"];

type Json = Record<string, any>;

const tokensRef = (uid: string) => db.doc(`gcal_tokens/${uid}`);

/** Fuseau VÉCU de l'utilisateur : fait `data/meta.tzOffsetMin` (minutes à
 *  ajouter à l'UTC, ex -240 en Guadeloupe) posé par l'app à l'ouverture.
 *  Null = fait absent → fallback Europe/Paris via userDayParts. */
async function userTzOffset(uid: string): Promise<number | null> {
  const snap = await db.doc(`users/${uid}/data/meta`).get();
  const v = snap.data()?.tzOffsetMin;
  return typeof v === "number" && isFinite(v) ? v : null;
}

/** Offset RFC3339 (« -04:00 ») depuis des minutes. */
function offsetStr(offsetMin: number): string {
  const sign = offsetMin < 0 ? "-" : "+";
  const abs = Math.abs(offsetMin);
  return `${sign}${String(Math.floor(abs / 60)).padStart(2, "0")}:${String(abs % 60).padStart(2, "0")}`;
}

/** Offset Europe/Paris (minutes) pour un jour donné — fallback quand le fait
 *  tzOffsetMin n'existe pas encore (gère l'heure d'été/hiver). */
function parisOffsetMin(ymd: string): number {
  const utcNoon = new Date(`${ymd}T12:00:00Z`);
  // sv-SE → « YYYY-MM-DD HH:mm » ; l'écart avec midi UTC = l'offset.
  const wall = utcNoon.toLocaleString("sv-SE", { timeZone: "Europe/Paris" });
  const h = parseInt(wall.slice(11, 13), 10);
  const m = parseInt(wall.slice(14, 16), 10);
  return (h - 12) * 60 + m;
}

// ── Access token : lit le cache, sinon refresh. Null = pas connecté. ────────
async function accessTokenFor(uid: string): Promise<string | null> {
  const snap = await tokensRef(uid).get();
  if (!snap.exists) return null;
  const d = snap.data() as Json;
  if (!d.refreshToken) return null;
  if (d.accessToken && typeof d.accessTokenExp === "number" &&
      d.accessTokenExp > Date.now() + 60_000) {
    return d.accessToken as string;
  }
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: process.env.GCAL_CLIENT_ID ?? "",
      client_secret: process.env.GCAL_CLIENT_SECRET ?? "",
      refresh_token: d.refreshToken as string,
      grant_type: "refresh_token",
    }).toString(),
  });
  const body = (await res.json()) as Json;
  if (!res.ok || !body.access_token) {
    // Accès révoqué côté Google : on le note, le statut app le montrera.
    console.error("gcal refresh failed:", res.status, JSON.stringify(body));
    if (body.error === "invalid_grant") {
      await tokensRef(uid).set({ revoked: true }, { merge: true });
    }
    return null;
  }
  await tokensRef(uid).set(
    {
      accessToken: body.access_token,
      accessTokenExp: Date.now() + (Number(body.expires_in ?? 3600) - 60) * 1000,
      revoked: FieldValue.delete(),
    },
    { merge: true }
  );
  return body.access_token as string;
}

// ── Sync d'un jour : diff programme ↔ agenda (idempotent) ────────────────────

const hmToMin = (hm: string) =>
  parseInt(hm.slice(0, 2), 10) * 60 + parseInt(hm.slice(3, 5), 10);

/** date + minutes depuis minuit → {ymd, HH:mm} (gère le passage de minuit). */
function dateTimeOf(date: string, minutes: number): { ymd: string; hm: string } {
  const dayShift = Math.floor(minutes / 1440);
  const m = ((minutes % 1440) + 1440) % 1440;
  let ymd = date;
  if (dayShift !== 0) {
    const d = new Date(`${date}T12:00:00Z`);
    d.setUTCDate(d.getUTCDate() + dayShift);
    ymd = d.toISOString().slice(0, 10);
  }
  return {
    ymd,
    hm: `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`,
  };
}

// ── Import agenda → programme (blocs MIROIRS) ────────────────────────────────
//
// Les événements de l'agenda qui ne viennent PAS de nous deviennent des blocs
// « miroirs » (gcalEventId) dans le programme : le coach les voit (trous,
// horizon, proposition AUTOUR). L'AGENDA est leur source de vérité — déplacé
// dans GCal → le bloc suit ; supprimé dans GCal → le bloc part ; swipé dans
// l'app → masqué SANS toucher au vrai rendez-vous (jamais recréé). La sync
// sortante les ignore : chaque objet ne se supprime que chez son propriétaire.

export async function importGcalDay(
  uid: string,
  date: string
): Promise<{ ok: boolean; imported: number; updated: number; removed: number; reason?: string }> {
  const none = { imported: 0, updated: 0, removed: 0 };
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return { ok: false, ...none, reason: "bad_date" };
  const token = await accessTokenFor(uid);
  if (!token) return { ok: false, ...none, reason: "not_connected" };
  const tzOff = (await userTzOffset(uid)) ?? parisOffsetMin(date);
  const off = offsetStr(tzOff);

  const listRes = await fetch(
    `${CAL_BASE}/events?` +
      new URLSearchParams({
        timeMin: `${date}T00:00:00${off}`,
        timeMax: `${date}T23:59:59${off}`,
        singleEvents: "true",
        orderBy: "startTime",
        maxResults: "100",
      }).toString(),
    { headers: { Authorization: `Bearer ${token}` } }
  );
  if (!listRes.ok) {
    console.error("gcal import list failed:", listRes.status, await listRes.text());
    return { ok: false, ...none, reason: `list_http_${listRes.status}` };
  }
  const items = (((await listRes.json()) as Json).items as Json[]) ?? [];

  // Événements retenus : PAS les nôtres (pwo), avec une heure (pas de
  // « journée entière » en v1), non annulés, non refusés par l'utilisateur.
  const events = new Map<string, { title: string; startMin: number; durationMin: number }>();
  for (const ev of items) {
    if (ev.status === "cancelled") continue;
    if (ev.extendedProperties?.private?.pwo === "1") continue;
    const startIso = ev.start?.dateTime as string | undefined;
    const endIso = ev.end?.dateTime as string | undefined;
    if (!startIso || !endIso) continue; // journée entière
    const self = ((ev.attendees as Json[]) ?? []).find((a) => a.self === true);
    if (self?.responseStatus === "declined") continue;
    const startMs = Date.parse(startIso);
    const endMs = Date.parse(endIso);
    if (!isFinite(startMs) || !isFinite(endMs)) continue;
    const local = new Date(startMs + tzOff * 60_000).toISOString();
    if (local.slice(0, 10) !== date) continue; // instance d'un autre jour vécu
    events.set(String(ev.id), {
      title: String(ev.summary ?? "(Sans titre)").trim() || "(Sans titre)",
      startMin: parseInt(local.slice(11, 13), 10) * 60 + parseInt(local.slice(14, 16), 10),
      durationMin: Math.max(5, Math.round((endMs - startMs) / 60_000)),
    });
  }

  // Merge dans le doc du jour — écrit UNIQUEMENT si quelque chose change.
  const ref = db.doc(`users/${uid}/daily_schedules/${date}`);
  const snap = await ref.get();
  const blocks = ((snap.data()?.blocks as Json[]) ?? []).slice();
  let imported = 0, updated = 0, removed = 0;

  for (let i = blocks.length - 1; i >= 0; i--) {
    const b = blocks[i];
    if (!b.gcalEventId) continue;
    const ev = events.get(String(b.gcalEventId));
    if (ev == null) {
      blocks.splice(i, 1); // l'événement a disparu de l'agenda → le miroir part
      removed++;
      continue;
    }
    events.delete(String(b.gcalEventId)); // déjà représenté
    if (b.status === "deleted") continue; // swipé : masqué, on respecte
    const hm = `${String(Math.floor(ev.startMin / 60)).padStart(2, "0")}:${String(ev.startMin % 60).padStart(2, "0")}`;
    if (b.startTime !== hm || b.durationMin !== ev.durationMin || b.title !== ev.title) {
      b.startTime = hm;
      b.durationMin = ev.durationMin;
      b.title = ev.title;
      updated++;
    }
  }
  for (const [eventId, ev] of events) {
    blocks.push({
      id: `gcal-${eventId}`,
      startTime: `${String(Math.floor(ev.startMin / 60)).padStart(2, "0")}:${String(ev.startMin % 60).padStart(2, "0")}`,
      durationMin: ev.durationMin,
      title: ev.title,
      category: "personal",
      projectId: null,
      taskId: null,
      activityId: null,
      actionId: null,
      status: "pending",
      doneAt: null,
      subtitle: "Agenda Google",
      gcalEventId: eventId,
    });
    imported++;
  }

  if (imported + updated + removed > 0) {
    if (snap.exists) {
      await ref.update({ blocks });
    } else {
      await ref.set({
        date,
        generatedBy: "gcal",
        generatedAt: FieldValue.serverTimestamp(),
        blocks,
      });
    }
  }
  return { ok: true, imported, updated, removed };
}

export async function syncDayToGcal(
  uid: string,
  date: string
): Promise<{ ok: boolean; created: number; updated: number; deleted: number; reason?: string }> {
  const none = { created: 0, updated: 0, deleted: 0 };
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return { ok: false, ...none, reason: "bad_date" };
  const token = await accessTokenFor(uid);
  if (!token) return { ok: false, ...none, reason: "not_connected" };
  const auth = { Authorization: `Bearer ${token}` };
  // Les heures du programme sont des heures de MUR du téléphone : l'événement
  // porte l'offset du fuseau vécu (fait) — sinon fallback Europe/Paris.
  const tzOff = await userTzOffset(uid);

  // Blocs vivants du programme (doc absent = tout supprimer côté agenda).
  // Les MIROIRS (gcalEventId) sont ignorés : l'événement existe déjà dans
  // l'agenda et lui appartient — jamais re-poussé, jamais dupliqué.
  const snap = await db.doc(`users/${uid}/daily_schedules/${date}`).get();
  const blocks = ((snap.data()?.blocks as Json[]) ?? []).filter(
    (b) =>
      !b.gcalEventId &&
      (b.status === "pending" || b.status === "done") &&
      /^\d{2}:\d{2}$/.test(String(b.startTime ?? "")) &&
      String(b.title ?? "").trim() !== "" &&
      b.id
  );

  // Événements Productivitwo existants pour CE jour (jamais les personnels).
  const listRes = await fetch(
    `${CAL_BASE}/events?privateExtendedProperty=${encodeURIComponent(`pwoDate=${date}`)}&maxResults=250&showDeleted=false`,
    { headers: auth }
  );
  if (!listRes.ok) {
    console.error("gcal list failed:", listRes.status, await listRes.text());
    return { ok: false, ...none, reason: `list_http_${listRes.status}` };
  }
  const listBody = (await listRes.json()) as Json;
  const existing = new Map<string, Json>();
  for (const ev of (listBody.items as Json[]) ?? []) {
    const bid = ev.extendedProperties?.private?.pwoBlockId;
    if (bid) existing.set(String(bid), ev);
  }

  let created = 0, updated = 0, deleted = 0;
  const seen = new Set<string>();
  for (const b of blocks) {
    const id = String(b.id);
    seen.add(id);
    const startMin = hmToMin(String(b.startTime));
    const dur = Math.max(5, Number(b.durationMin ?? 30));
    const start = dateTimeOf(date, startMin);
    const end = dateTimeOf(date, startMin + dur);
    const desired = {
      summary: String(b.title),
      description: [
        b.subtitle ? String(b.subtitle) : null,
        "source: productivitwo",
      ].filter(Boolean).join("\n"),
      start: tzOff != null
        ? { dateTime: `${start.ymd}T${start.hm}:00${offsetStr(tzOff)}` }
        : { dateTime: `${start.ymd}T${start.hm}:00`, timeZone: "Europe/Paris" },
      end: tzOff != null
        ? { dateTime: `${end.ymd}T${end.hm}:00${offsetStr(tzOff)}` }
        : { dateTime: `${end.ymd}T${end.hm}:00`, timeZone: "Europe/Paris" },
      extendedProperties: { private: { pwo: "1", pwoBlockId: id, pwoDate: date } },
    };
    const ev = existing.get(id);
    if (ev == null) {
      const r = await fetch(`${CAL_BASE}/events`, {
        method: "POST",
        headers: { ...auth, "Content-Type": "application/json" },
        body: JSON.stringify(desired),
      });
      if (r.ok) created++;
      else console.error("gcal insert failed:", r.status, await r.text());
    } else {
      // Avec offset connu : comparaison d'INSTANTS (Google peut renvoyer la
      // même heure sous une autre représentation). Sinon, heure de mur.
      const sameStart = tzOff != null
        ? Date.parse(String(ev.start?.dateTime ?? "")) ===
            Date.parse(`${start.ymd}T${start.hm}:00${offsetStr(tzOff)}`)
        : String(ev.start?.dateTime ?? "").startsWith(`${start.ymd}T${start.hm}`);
      const sameEnd = tzOff != null
        ? Date.parse(String(ev.end?.dateTime ?? "")) ===
            Date.parse(`${end.ymd}T${end.hm}:00${offsetStr(tzOff)}`)
        : String(ev.end?.dateTime ?? "").startsWith(`${end.ymd}T${end.hm}`);
      if (ev.summary !== desired.summary || !sameStart || !sameEnd) {
        const r = await fetch(`${CAL_BASE}/events/${ev.id}`, {
          method: "PATCH",
          headers: { ...auth, "Content-Type": "application/json" },
          body: JSON.stringify(desired),
        });
        if (r.ok) updated++;
        else console.error("gcal patch failed:", r.status, await r.text());
      }
    }
  }
  // Blocs supprimés/sautés du programme → leurs événements partent aussi.
  for (const [bid, ev] of existing) {
    if (seen.has(bid)) continue;
    const r = await fetch(`${CAL_BASE}/events/${ev.id}`, { method: "DELETE", headers: auth });
    if (r.ok || r.status === 404 || r.status === 410) deleted++;
    else console.error("gcal delete failed:", r.status, await r.text());
  }
  return { ok: true, created, updated, deleted };
}

// ── API app : status / authUrl / setAutoSync / syncDay / disconnect ──────────

export const gcalApi = onRequest(
  { cors: true, invoker: "public", secrets: GCAL_SECRETS },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }
    const authHeader = req.headers.authorization ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing Authorization header" }); return;
    }
    const { uid, action, date, value } = req.body as {
      uid?: string; action?: string; date?: string; value?: boolean;
    };
    if (!uid || !action) { res.status(400).json({ error: "uid et action requis" }); return; }
    const valid = await validateToken(uid, authHeader.slice(7).trim());
    if (!valid) { res.status(401).json({ error: "Token invalide ou révoqué" }); return; }

    try {
      if (action === "status") {
        const snap = await tokensRef(uid).get();
        const d = snap.data() as Json | undefined;
        res.status(200).json({
          connected: snap.exists && !!d?.refreshToken,
          email: d?.email ?? null,
          autoSync: d?.autoSync !== false,
          revoked: d?.revoked === true,
        });
        return;
      }
      if (action === "authUrl") {
        const state = randomUUID();
        await db.doc(`gcal_oauth_states/${state}`).set({
          uid,
          createdAt: FieldValue.serverTimestamp(),
          expiresAt: Date.now() + 15 * 60_000,
        });
        const url =
          "https://accounts.google.com/o/oauth2/v2/auth?" +
          new URLSearchParams({
            client_id: process.env.GCAL_CLIENT_ID ?? "",
            redirect_uri: CALLBACK_URL,
            response_type: "code",
            scope: SCOPES,
            access_type: "offline",
            prompt: "consent",
            state,
          }).toString();
        res.status(200).json({ url });
        return;
      }
      if (action === "setAutoSync") {
        await tokensRef(uid).set({ autoSync: value === true }, { merge: true });
        res.status(200).json({ ok: true, autoSync: value === true });
        return;
      }
      if (action === "syncDay") {
        // Bidirectionnel : import (agenda → miroirs) PUIS push (programme →
        // agenda) — l'import écrit le doc, le trigger re-poussera de toute
        // façon, mais on répond avec l'état complet tout de suite.
        const d = date && /^\d{4}-\d{2}-\d{2}$/.test(date)
          ? date
          : userDayParts(await userTzOffset(uid)).ymd;
        const imp = await importGcalDay(uid, d);
        const push = await syncDayToGcal(uid, d);
        res.status(200).json({
          ...push,
          imported: imp.imported,
          updatedFromCal: imp.updated,
          removedFromCal: imp.removed,
        });
        return;
      }
      if (action === "disconnect") {
        const snap = await tokensRef(uid).get();
        const refresh = (snap.data() as Json | undefined)?.refreshToken;
        if (refresh) {
          // Révocation best-effort — la suppression du doc fait foi.
          await fetch("https://oauth2.googleapis.com/revoke", {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: new URLSearchParams({ token: refresh as string }).toString(),
          }).catch(() => null);
        }
        await tokensRef(uid).delete();
        res.status(200).json({ ok: true });
        return;
      }
      res.status(400).json({ error: `action inconnue : ${action}` });
    } catch (e) {
      console.error("gcalApi error:", e);
      res.status(500).json({ error: "Erreur Google Agenda" });
    }
  }
);

// ── Callback OAuth (navigateur) ───────────────────────────────────────────────

const htmlPage = (title: string, body: string) => `<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>body{font-family:-apple-system,sans-serif;background:#101418;color:#e8eef2;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
main{text-align:center;padding:32px;max-width:420px}h1{font-size:20px}p{color:#9fb0bb;line-height:1.5}</style>
</head><body><main><h1>${title}</h1><p>${body}</p></main></body></html>`;

export const gcalOauthCallback = onRequest(
  { cors: true, invoker: "public", secrets: GCAL_SECRETS },
  async (req, res) => {
    const code = String(req.query.code ?? "");
    const state = String(req.query.state ?? "");
    const fail = (msg: string) =>
      res.status(400).send(htmlPage("Connexion impossible", msg));
    if (!code || !state) { fail("Paramètres manquants — relance la connexion depuis l'app."); return; }

    try {
      const stateRef = db.doc(`gcal_oauth_states/${state}`);
      const stateSnap = await stateRef.get();
      const st = stateSnap.data() as Json | undefined;
      await stateRef.delete().catch(() => null);
      if (!stateSnap.exists || !st?.uid || Number(st.expiresAt ?? 0) < Date.now()) {
        fail("Lien expiré — relance la connexion depuis l'app."); return;
      }
      const uid = String(st.uid);

      const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          code,
          client_id: process.env.GCAL_CLIENT_ID ?? "",
          client_secret: process.env.GCAL_CLIENT_SECRET ?? "",
          redirect_uri: CALLBACK_URL,
          grant_type: "authorization_code",
        }).toString(),
      });
      const body = (await tokenRes.json()) as Json;
      if (!tokenRes.ok || !body.refresh_token) {
        console.error("gcal token exchange failed:", tokenRes.status, JSON.stringify(body));
        fail("Google n'a pas accordé l'accès. Réessaie depuis l'app."); return;
      }

      // Email depuis l'id_token (scope openid email) — zéro appel API en plus.
      let email: string | null = null;
      try {
        const payload = String(body.id_token ?? "").split(".")[1];
        if (payload) {
          email =
            (JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as Json)
              .email ?? null;
        }
      } catch (_) { /* l'email est un confort, pas un prérequis */ }

      await tokensRef(uid).set({
        refreshToken: body.refresh_token,
        accessToken: body.access_token ?? null,
        accessTokenExp: Date.now() + (Number(body.expires_in ?? 3600) - 60) * 1000,
        email,
        autoSync: true,
        connectedAt: FieldValue.serverTimestamp(),
        revoked: FieldValue.delete(),
      }, { merge: true });

      // Première sync immédiate (best-effort), dans les deux sens : le
      // programme du jour apparaît dans l'agenda ET les rendez-vous du jour
      // apparaissent dans le programme.
      const ymd0 = userDayParts(await userTzOffset(uid)).ymd;
      await importGcalDay(uid, ymd0).catch(() => null);
      await syncDayToGcal(uid, ymd0).catch(() => null);

      res.status(200).send(htmlPage(
        "✅ Google Agenda connecté",
        `Ton programme du jour est synchronisé${email ? ` sur <b>${email}</b>` : ""}. Tu peux fermer cette page et revenir dans Productivitwo.`
      ));
    } catch (e) {
      console.error("gcalOauthCallback error:", e);
      fail("Erreur inattendue — réessaie depuis l'app.");
    }
  }
);

// ── Trigger : TOUTE écriture d'un programme synchronise l'agenda ─────────────
//
// Un seul chemin de sync pour tous les écrivains (app, schedule_day,
// add_event, défis ORION, check-in). Jours passés ignorés (l'agenda n'est pas
// un journal). La sync n'écrit jamais dans Firestore → aucune boucle.

export const gcalOnScheduleWrite = onDocumentWritten(
  { document: "users/{uid}/daily_schedules/{date}", secrets: GCAL_SECRETS },
  async (event) => {
    const uid = event.params.uid;
    const date = event.params.date;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return; // brouillons & docs annexes
    if (date < userDayParts(await userTzOffset(uid)).ymd) return; // jour vécu
    const snap = await tokensRef(uid).get();
    const d = snap.data() as Json | undefined;
    if (!snap.exists || !d?.refreshToken || d.autoSync === false) return;
    const r = await syncDayToGcal(uid, date);
    if (!r.ok) console.error(`gcal auto-sync ${uid}/${date}:`, r.reason);
  }
);
