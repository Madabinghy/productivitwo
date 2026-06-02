"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getFocus = getFocus;
exports.setFocus = setFocus;
exports.getOrCreateBrief = getOrCreateBrief;
exports.setBriefFeedback = setBriefFeedback;
exports.listBriefs = listBriefs;
const sdk_1 = require("@anthropic-ai/sdk");
const db_1 = require("./db");
const models_1 = require("./models");
function todayInParis(d = new Date()) {
    return d.toLocaleDateString("sv-SE", { timeZone: "Europe/Paris" });
}
// ── Focus ────────────────────────────────────────────────────────────────────
async function getFocus(uid) {
    var _a, _b;
    const snap = await db_1.db.collection(`users/${uid}/orion_config`).doc("main").get();
    return (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.focus) !== null && _b !== void 0 ? _b : "";
}
async function setFocus(uid, focus) {
    await db_1.db.collection(`users/${uid}/orion_config`).doc("main").set({
        focus: focus.trim(),
        focusUpdatedAt: db_1.FieldValue.serverTimestamp(),
    }, { merge: true });
}
// ── Brief ────────────────────────────────────────────────────────────────────
const BRIEF_PROMPT = `Tu es ORION, le stratège quotidien de l'utilisateur de Productivitwo.

Le FOCUS ACTUEL de l'utilisateur :
{{FOCUS}}

État de ses projets et activités (concis) :
{{CONTEXT}}

Aujourd'hui : {{TODAY}}

Tu produis un brief structuré pour aujourd'hui. Réponds UNIQUEMENT en JSON valide, sans markdown ni texte autour :
{
  "priorityAction": "1 phrase concrète et SPÉCIFIQUE à son contexte — l'action la plus stratégique aujourd'hui pour avancer son focus",
  "risk": "1 phrase ou null — UNIQUEMENT s'il existe un élément à traiter AUJOURD'HUI sous peine de le rater (deadline du jour, échéance imminente, créneau qui se ferme). Sinon null. Pas de risque général ni de vigilance vague",
  "question": "1 phrase ou null — une question stratégique qui pousse à la réflexion. null si pas nécessaire aujourd'hui"
}

RÈGLES STRICTES :
- Tout doit converger vers son FOCUS
- Concret et spécifique — JAMAIS de motivation creuse ou de conseil générique (genre "fais du sport")
- Si rien de pertinent pour risk ou question, mets null. Ne remplis pas pour remplir
- Ton ferme et direct — tu es un stratège, pas un coach mou
- Maximum 25 mots par champ`;
async function buildBriefContext(uid) {
    var _a, _b, _c;
    // Projets actifs avec leur progression
    const projectsSnap = await db_1.db.collection(`users/${uid}/projects`)
        .where("status", "==", "active")
        .get();
    const projects = projectsSnap.docs.slice(0, 8).map((d) => {
        var _a, _b;
        const data = d.data();
        const tasks = (_a = data.tasks) !== null && _a !== void 0 ? _a : [];
        const done = tasks.filter((t) => t.status === "done").length;
        const total = tasks.length;
        const overdue = tasks.filter((t) => {
            var _a, _b;
            const td = d.data();
            const taskEnd = (_b = (_a = td.tasks) === null || _a === void 0 ? void 0 : _a.find((x) => x === t)) === null || _b === void 0 ? void 0 : _b.endDate;
            return taskEnd && taskEnd < todayInParis() && t.status !== "done" && t.status !== "skipped";
        }).length;
        return `• ${data.title} : ${done}/${total} tâches, ${overdue} en retard, fin ${(_b = data.endDate) !== null && _b !== void 0 ? _b : "non définie"}`;
    });
    // Domaines actifs (juste pour le contexte de QUI il est)
    const domainsSnap = await db_1.db.collection(`users/${uid}/domains`).get();
    const domains = domainsSnap.docs
        .filter((d) => !d.data().deleted)
        .map((d) => d.data().name)
        .join(", ");
    // Sessions des 3 derniers jours (où a-t-il mis son temps)
    const threeDaysAgo = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    const sessionsSnap = await db_1.db.collection(`users/${uid}/sessions`)
        .where("date", ">=", threeDaysAgo)
        .get();
    const minByActivity = {};
    for (const doc of sessionsSnap.docs) {
        const v = doc.data();
        const name = (_a = v.activityName) !== null && _a !== void 0 ? _a : "?";
        minByActivity[name] = ((_b = minByActivity[name]) !== null && _b !== void 0 ? _b : 0) + ((_c = v.durationMin) !== null && _c !== void 0 ? _c : 0);
    }
    const topActivities = Object.entries(minByActivity)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 5)
        .map(([name, min]) => `${name}: ${min}min`)
        .join(", ");
    return [
        `Domaines : ${domains || "aucun"}`,
        `Projets actifs (max 8) :`,
        projects.length ? projects.join("\n") : "  (aucun projet actif)",
        `Temps loggué 3 derniers jours : ${topActivities || "rien"}`,
    ].join("\n");
}
async function getOrCreateBrief(uid) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q;
    const date = todayInParis();
    const ref = db_1.db.collection(`users/${uid}/orion_briefs`).doc(date);
    const existing = await ref.get();
    if (existing.exists) {
        const d = existing.data();
        return {
            date,
            focus: (_a = d.focus) !== null && _a !== void 0 ? _a : null,
            priorityAction: d.priorityAction,
            risk: (_b = d.risk) !== null && _b !== void 0 ? _b : null,
            question: (_c = d.question) !== null && _c !== void 0 ? _c : null,
            feedback: (_d = d.feedback) !== null && _d !== void 0 ? _d : null,
            feedbackAt: (_h = (_g = (_f = (_e = d.feedbackAt) === null || _e === void 0 ? void 0 : _e.toDate) === null || _f === void 0 ? void 0 : _f.call(_e)) === null || _g === void 0 ? void 0 : _g.toISOString()) !== null && _h !== void 0 ? _h : null,
            createdAt: (_m = (_l = (_k = (_j = d.createdAt) === null || _j === void 0 ? void 0 : _j.toDate) === null || _k === void 0 ? void 0 : _k.call(_j)) === null || _l === void 0 ? void 0 : _l.toISOString()) !== null && _m !== void 0 ? _m : new Date().toISOString(),
        };
    }
    // Génère le brief
    const focus = await getFocus(uid);
    if (!focus) {
        throw new Error("FOCUS_NOT_SET");
    }
    const context = await buildBriefContext(uid);
    const prompt = BRIEF_PROMPT
        .replace("{{FOCUS}}", focus)
        .replace("{{CONTEXT}}", context)
        .replace("{{TODAY}}", date);
    const client = new sdk_1.default({ apiKey: process.env.ANTHROPIC_API_KEY });
    const message = await client.messages.create({
        model: models_1.MODELS.HAIKU,
        max_tokens: 512,
        messages: [{ role: "user", content: prompt }],
    });
    (0, models_1.logTokenUsage)("orion_brief", models_1.MODELS.HAIKU, message.usage);
    const rawText = message.content[0].text.trim();
    const jsonMatch = rawText.match(/\{[\s\S]*\}/);
    if (!jsonMatch)
        throw new Error("ORION_INVALID_RESPONSE");
    const parsed = JSON.parse(jsonMatch[0]);
    const briefData = {
        date,
        focus,
        priorityAction: (_o = parsed.priorityAction) !== null && _o !== void 0 ? _o : "",
        risk: (_p = parsed.risk) !== null && _p !== void 0 ? _p : null,
        question: (_q = parsed.question) !== null && _q !== void 0 ? _q : null,
        feedback: null,
        feedbackAt: null,
        createdAt: db_1.FieldValue.serverTimestamp(),
    };
    await ref.set(briefData);
    return {
        date,
        focus,
        priorityAction: briefData.priorityAction,
        risk: briefData.risk,
        question: briefData.question,
        feedback: null,
        feedbackAt: null,
        createdAt: new Date().toISOString(),
    };
}
async function setBriefFeedback(uid, date, feedback) {
    await db_1.db.collection(`users/${uid}/orion_briefs`).doc(date).update({
        feedback,
        feedbackAt: db_1.FieldValue.serverTimestamp(),
    });
}
async function listBriefs(uid, limit = 30) {
    const snap = await db_1.db.collection(`users/${uid}/orion_briefs`)
        .orderBy("createdAt", "desc")
        .limit(limit)
        .get();
    return snap.docs.map((doc) => {
        var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m;
        const d = doc.data();
        return {
            date: doc.id,
            focus: (_a = d.focus) !== null && _a !== void 0 ? _a : null,
            priorityAction: d.priorityAction,
            risk: (_b = d.risk) !== null && _b !== void 0 ? _b : null,
            question: (_c = d.question) !== null && _c !== void 0 ? _c : null,
            feedback: (_d = d.feedback) !== null && _d !== void 0 ? _d : null,
            feedbackAt: (_h = (_g = (_f = (_e = d.feedbackAt) === null || _e === void 0 ? void 0 : _e.toDate) === null || _f === void 0 ? void 0 : _f.call(_e)) === null || _g === void 0 ? void 0 : _g.toISOString()) !== null && _h !== void 0 ? _h : null,
            createdAt: (_m = (_l = (_k = (_j = d.createdAt) === null || _j === void 0 ? void 0 : _j.toDate) === null || _k === void 0 ? void 0 : _k.call(_j)) === null || _l === void 0 ? void 0 : _l.toISOString()) !== null && _m !== void 0 ? _m : "",
        };
    });
}
//# sourceMappingURL=orion_brief.js.map