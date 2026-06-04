"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.processInboxToProjects = processInboxToProjects;
const sdk_1 = require("@anthropic-ai/sdk");
const uuid_1 = require("uuid");
const db_1 = require("./db");
const models_1 = require("./models");
const execute_1 = require("./execute");
function todayParis(d = new Date()) {
    return new Intl.DateTimeFormat("en-CA", {
        timeZone: "Europe/Paris",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
    }).format(d);
}
const ROUTING_PROMPT = `Tu es ORION, l'assistant de Productivitwo. Tu traites la boîte à idées de l'utilisateur : transformer des idées en projets Gantt, les rattacher à des projets existants, ou les laisser.

## RÈGLE D'OR (granularité — la plus importante)
Ne crée un projet QUE pour une idée (ou un groupe d'idées) qui décrit un VRAI travail multi-étapes, stratégique, méritant un suivi sur plusieurs jours/semaines.
Une simple tâche isolée, une course, un achat, une note vague, un rappel ponctuel → NE PAS créer de projet → mets-la dans "skip".
Dans le doute : skip. Mieux vaut laisser une idée que créer un projet bidon.

## Règles
1. Préfère TOUJOURS enrichir un projet ACTIF existant (appendTo) plutôt que créer, si l'idée s'y rattache sémantiquement.
2. AGRÈGE : si plusieurs idées concernent le même sujet, regroupe-les — soit dans UN seul newProject (plusieurs ideaIds), soit en plusieurs tâches d'un même projet.
3. Chaque idée apparaît EXACTEMENT une fois (dans newProjects, appendTo, OU skip).
4. Pour un nouveau projet : titre court et clair, 2-4 tâches concrètes (verbe d'action), domainId le plus cohérent parmi les domaines (ou null).

## Idées en attente
{{IDEAS}}

## Projets actifs (pour rattacher)
{{PROJECTS}}

## Domaines
{{DOMAINS}}

Date du jour : {{TODAY}}

Réponds UNIQUEMENT avec ce JSON (rien d'autre) :
{
  "newProjects": [ { "title": "...", "description": "...", "domainId": "<id|null>", "ideaIds": ["..."], "tasks": [ {"title":"..."} ] } ],
  "appendTo": [ { "projectId": "...", "ideaIds": ["..."], "tasks": [ {"title":"..."} ] } ],
  "skip": ["ideaId", ...]
}`;
/**
 * Sweep autonome de l'inbox → projets. Gaté 1×/jour (déclenché en lazy à
 * l'ouverture de l'app via getOrCreateBrief). Routage/agrégation par un appel
 * Sonnet, application déterministe. Les projets créés portent source:"orion" +
 * la provenance des idées (originIdeas) pour le style distinct + l'effet « wow ».
 */
async function processInboxToProjects(uid, opts) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l;
    const today = todayParis();
    const gateRef = db_1.db.doc(`users/${uid}/data/inbox_sweep`);
    const gate = await gateRef.get();
    if (!(opts === null || opts === void 0 ? void 0 : opts.force) && gate.exists && ((_a = gate.data()) === null || _a === void 0 ? void 0 : _a.lastSweepYmd) === today) {
        return null; // déjà passé aujourd'hui
    }
    const inboxSnap = await db_1.db
        .collection(`users/${uid}/captures`)
        .where("status", "==", "pending")
        .orderBy("createdAt", "asc")
        .get();
    if (inboxSnap.empty) {
        await gateRef.set({ lastSweepYmd: today }, { merge: true });
        return { created: 0, appended: 0, skipped: 0 };
    }
    const ideas = inboxSnap.docs.map((d) => {
        var _a, _b, _c, _d, _e, _f, _g, _h;
        const v = d.data();
        return {
            id: (_a = v.id) !== null && _a !== void 0 ? _a : d.id,
            text: (_b = v.text) !== null && _b !== void 0 ? _b : "",
            date: (_h = (_g = (_f = (_e = (_d = (_c = v.createdAt) === null || _c === void 0 ? void 0 : _c.toDate) === null || _d === void 0 ? void 0 : _d.call(_c)) === null || _e === void 0 ? void 0 : _e.toISOString) === null || _f === void 0 ? void 0 : _f.call(_e)) === null || _g === void 0 ? void 0 : _g.slice(0, 10)) !== null && _h !== void 0 ? _h : today,
        };
    });
    const [projSnap, domSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
        db_1.db.collection(`users/${uid}/domains`).get(),
    ]);
    const projects = projSnap.docs.map((d) => {
        var _a, _b;
        const v = d.data();
        return {
            id: v.id,
            title: v.title,
            description: (_a = v.description) !== null && _a !== void 0 ? _a : "",
            domainId: (_b = v.domainId) !== null && _b !== void 0 ? _b : null,
        };
    });
    const domains = domSnap.docs
        .map((d) => d.data())
        .filter((v) => !v.deleted)
        .map((v) => ({ id: v.id, name: v.name }));
    const prompt = ROUTING_PROMPT.replace("{{IDEAS}}", JSON.stringify(ideas, null, 2))
        .replace("{{PROJECTS}}", JSON.stringify(projects, null, 2))
        .replace("{{DOMAINS}}", JSON.stringify(domains, null, 2))
        .replace("{{TODAY}}", today);
    let decision;
    try {
        const client = new sdk_1.default({ apiKey: process.env.ANTHROPIC_API_KEY });
        const msg = await client.messages.create({
            model: (0, models_1.getModel)("inbox_routing"),
            max_tokens: 1500,
            messages: [{ role: "user", content: prompt }],
        });
        (0, models_1.logTokenUsage)("inbox_routing", (0, models_1.getModel)("inbox_routing"), msg.usage);
        const raw = msg.content[0].text.trim();
        const m = raw.match(/\{[\s\S]*\}/);
        if (!m)
            throw new Error("no json");
        decision = JSON.parse(m[0]);
    }
    catch (e) {
        console.error("inbox routing failed", e);
        await gateRef.set({ lastSweepYmd: today, error: String(e) }, { merge: true });
        return null;
    }
    const ideaById = new Map(ideas.map((i) => [i.id, i]));
    let created = 0;
    let appended = 0;
    for (const np of (_b = decision.newProjects) !== null && _b !== void 0 ? _b : []) {
        const origin = ((_c = np.ideaIds) !== null && _c !== void 0 ? _c : [])
            .map((id) => ideaById.get(id))
            .filter((i) => !!i)
            .map((i) => ({ text: i.text, date: i.date }));
        if (origin.length === 0)
            continue;
        const tasks = (((_d = np.tasks) === null || _d === void 0 ? void 0 : _d.length) ? np.tasks : [{ title: np.title }]).map((t, i) => ({ id: `task-${i + 1}`, title: t.title, startDate: today }));
        await (0, execute_1.executePushGantt)(uid, {
            uid,
            project: {
                title: np.title,
                description: np.description,
                domainId: (_e = np.domainId) !== null && _e !== void 0 ? _e : undefined,
                startDate: today,
                tasks,
            },
        }, { source: "orion", originIdeas: origin });
        for (const id of (_f = np.ideaIds) !== null && _f !== void 0 ? _f : []) {
            if (ideaById.has(id)) {
                await (0, execute_1.executeProcessInboxItem)(uid, id, `→ projet ORION « ${np.title} »`);
            }
        }
        created++;
    }
    for (const ap of (_g = decision.appendTo) !== null && _g !== void 0 ? _g : []) {
        const proj = projects.find((p) => p.id === ap.projectId);
        if (!proj)
            continue;
        for (const t of (_h = ap.tasks) !== null && _h !== void 0 ? _h : []) {
            await (0, execute_1.executeAddTask)(uid, ap.projectId, {
                id: (0, uuid_1.v4)(),
                title: t.title,
                startDate: today,
            });
            appended++;
        }
        const origin = ((_j = ap.ideaIds) !== null && _j !== void 0 ? _j : [])
            .map((id) => ideaById.get(id))
            .filter((i) => !!i)
            .map((i) => ({ text: i.text, date: i.date }));
        if (origin.length) {
            await db_1.db
                .doc(`users/${uid}/projects/${ap.projectId}`)
                .set({ originIdeas: db_1.FieldValue.arrayUnion(...origin) }, { merge: true });
        }
        for (const id of (_k = ap.ideaIds) !== null && _k !== void 0 ? _k : []) {
            if (ideaById.has(id)) {
                await (0, execute_1.executeProcessInboxItem)(uid, id, `→ ajoutée au projet « ${proj.title} »`);
            }
        }
    }
    const skipped = ((_l = decision.skip) !== null && _l !== void 0 ? _l : []).filter((id) => ideaById.has(id)).length;
    await gateRef.set({
        lastSweepYmd: today,
        lastResult: { created, appended, skipped },
        at: db_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { created, appended, skipped };
}
//# sourceMappingURL=orion_inbox.js.map