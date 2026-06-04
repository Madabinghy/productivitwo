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
/** Ajoute n jours à un YYYY-MM-DD et renvoie un YYYY-MM-DD. */
function addDays(ymd, n) {
    const d = new Date(`${ymd}T00:00:00Z`);
    d.setUTCDate(d.getUTCDate() + n);
    return d.toISOString().slice(0, 10);
}
/** Nombre de jours entre deux YYYY-MM-DD (b - a). */
function daysBetween(a, b) {
    const da = new Date(`${a}T00:00:00Z`).getTime();
    const db = new Date(`${b}T00:00:00Z`).getTime();
    return Math.max(0, Math.round((db - da) / 86400000));
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
4. Pour un nouveau projet : titre court et clair, domainId le plus cohérent parmi les domaines (ou null), et 2-4 tâches qui forment un VRAI Gantt :
   - chaque tâche = un verbe d'action + 2-4 **sous-actions** concrètes (\`actions\`) qui détaillent comment la faire,
   - chaque tâche a une **durée réaliste** en jours (\`durationDays\`, 1 à 15) — les tâches seront ENCHAÎNÉES dans le temps (l'une après l'autre), donne donc un ordre logique d'exécution.
5. PLANIFICATION RÉALISTE (important) : l'utilisateur a DÉJÀ des projets en cours avec des tâches planifiées (voir leurs dates). Ne surcharge PAS les prochains jours. Donne à chaque nouveau projet un \`startOffsetDays\` (dans combien de jours il démarre) pour ÉTALER la charge : tiens compte des tâches existantes ET des autres nouveaux projets (ne les fais pas tous démarrer en même temps). Un projet peu urgent peut démarrer dans 1-3 semaines.

## Message léger (nudge) — optionnel
Les projets créés apparaissent EN SILENCE (effet de surprise). MAIS si une idée est laissée (skip), tu peux proposer "nudge": { "text": "..." } = UN message court à la 1ère personne d'ORION qui évoque cette idée — SANS JAMAIS dire que tu as traité l'inbox ni mentionner les projets créés. Un seul nudge max.
PRIORISE l'idée laissée qui traîne depuis le PLUS LONGTEMPS (\`ageDays\` le plus élevé), et adapte le ton à l'âge :
- récente (≤ 3j) : pas forcément de nudge (laisse infuser), ou rappel très léger ;
- une à deux semaines : rappel amical (ex: "Pense à boucler ta facture SOF 😉") ;
- ancienne (> 2-3 semaines) : invite à trancher (ex: "Ça fait {ageDays} jours que tu as noté « X » — tu veux t'y mettre ou je la classe sans suite ?").
Omets le nudge si rien ne le mérite.

## Idées en attente
{{IDEAS}}

## Projets actifs (pour rattacher)
{{PROJECTS}}

## Domaines
{{DOMAINS}}

Date du jour : {{TODAY}}

Réponds UNIQUEMENT avec ce JSON (rien d'autre) :
{
  "newProjects": [ { "title": "...", "description": "...", "domainId": "<id|null>", "ideaIds": ["..."], "startOffsetDays": 0, "tasks": [ {"title":"...", "actions":["...","..."], "durationDays": 2} ] } ],
  "appendTo": [ { "projectId": "...", "ideaIds": ["..."], "tasks": [ {"title":"...", "actions":["..."]} ] } ],
  "skip": ["ideaId", ...],
  "nudge": { "text": "..." }
}`;
/**
 * Sweep autonome de l'inbox → projets. Gaté 1×/jour (déclenché en lazy à
 * l'ouverture de l'app via getOrCreateBrief). Routage/agrégation par un appel
 * Sonnet, application déterministe. Les projets créés portent source:"orion" +
 * la provenance des idées (originIdeas) pour le style distinct + l'effet « wow ».
 */
async function processInboxToProjects(uid, opts) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r;
    const today = todayParis();
    const gateRef = db_1.db.doc(`users/${uid}/data/inbox_sweep`);
    const gate = await gateRef.get();
    if (!(opts === null || opts === void 0 ? void 0 : opts.force) && gate.exists && ((_a = gate.data()) === null || _a === void 0 ? void 0 : _a.lastSweepYmd) === today) {
        return null; // déjà passé aujourd'hui
    }
    // Pas d'orderBy ici → évite un index composite (status+createdAt). On trie en
    // mémoire (l'inbox est petite).
    const inboxSnap = await db_1.db
        .collection(`users/${uid}/captures`)
        .where("status", "==", "pending")
        .get();
    if (inboxSnap.empty) {
        await gateRef.set({ lastSweepYmd: today }, { merge: true });
        return { found: 0, created: 0, appended: 0, skipped: 0 };
    }
    const sortedDocs = inboxSnap.docs.slice().sort((a, b) => {
        var _a, _b, _c, _d, _e, _f;
        const ta = (_c = (_b = (_a = a.data().createdAt) === null || _a === void 0 ? void 0 : _a.toMillis) === null || _b === void 0 ? void 0 : _b.call(_a)) !== null && _c !== void 0 ? _c : 0;
        const tb = (_f = (_e = (_d = b.data().createdAt) === null || _d === void 0 ? void 0 : _d.toMillis) === null || _e === void 0 ? void 0 : _e.call(_d)) !== null && _f !== void 0 ? _f : 0;
        return ta - tb;
    });
    const ideas = sortedDocs.map((d) => {
        var _a, _b, _c, _d, _e, _f, _g, _h;
        const v = d.data();
        const date = (_f = (_e = (_d = (_c = (_b = (_a = v.createdAt) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a)) === null || _c === void 0 ? void 0 : _c.toISOString) === null || _d === void 0 ? void 0 : _d.call(_c)) === null || _e === void 0 ? void 0 : _e.slice(0, 10)) !== null && _f !== void 0 ? _f : today;
        return {
            id: (_g = v.id) !== null && _g !== void 0 ? _g : d.id,
            text: (_h = v.text) !== null && _h !== void 0 ? _h : "",
            date,
            ageDays: daysBetween(date, today),
        };
    });
    const [projSnap, domSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
        db_1.db.collection(`users/${uid}/domains`).get(),
    ]);
    const projects = projSnap.docs.map((d) => {
        var _a, _b, _c;
        const v = d.data();
        // Tâches déjà planifiées (non terminées) avec dates → permet à Sonnet de
        // placer les nouveaux projets SANS surcharger les jours déjà occupés.
        const activeTasks = ((_a = v.tasks) !== null && _a !== void 0 ? _a : [])
            .filter((t) => t.status !== "done" && t.status !== "skipped")
            .map((t) => {
            var _a, _b;
            return ({
                title: t.title,
                startDate: (_a = t.startDate) !== null && _a !== void 0 ? _a : null,
                endDate: (_b = t.endDate) !== null && _b !== void 0 ? _b : null,
            });
        });
        return {
            id: v.id,
            title: v.title,
            description: (_b = v.description) !== null && _b !== void 0 ? _b : "",
            domainId: (_c = v.domainId) !== null && _c !== void 0 ? _c : null,
            activeTasks,
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
            max_tokens: 3000,
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
        // Tâches ENCHAÎNÉES dans le temps (staircase Gantt) + sous-actions.
        // Démarrage décalé (startOffsetDays) pour étaler la charge vs les en-cours.
        const offset = Math.min(120, Math.max(0, Math.round((_d = np.startOffsetDays) !== null && _d !== void 0 ? _d : 0)));
        const projectStart = addDays(today, offset);
        const rawTasks = ((_e = np.tasks) === null || _e === void 0 ? void 0 : _e.length) ? np.tasks : [{ title: np.title }];
        let cursor = projectStart;
        const tasks = rawTasks.map((t, i) => {
            var _a, _b;
            const dur = Math.min(15, Math.max(1, Math.round((_a = t.durationDays) !== null && _a !== void 0 ? _a : 2)));
            const startDate = cursor;
            const endDate = addDays(startDate, dur);
            cursor = addDays(endDate, 1); // la tâche suivante démarre après celle-ci
            return {
                id: `task-${i + 1}`,
                title: t.title,
                phaseId: "phase-1",
                startDate,
                endDate,
                actions: ((_b = t.actions) !== null && _b !== void 0 ? _b : []).slice(0, 6),
            };
        });
        const lastEnd = tasks.length ? (_f = tasks[tasks.length - 1].endDate) !== null && _f !== void 0 ? _f : projectStart : projectStart;
        const phases = [
            { id: "phase-1", label: "Réalisation", startDate: projectStart, endDate: lastEnd },
        ];
        await (0, execute_1.executePushGantt)(uid, {
            uid,
            project: {
                title: np.title,
                description: np.description,
                domainId: (_g = np.domainId) !== null && _g !== void 0 ? _g : undefined,
                startDate: projectStart,
                endDate: lastEnd,
                phases,
                tasks,
            },
        }, { source: "orion", originIdeas: origin });
        for (const id of (_h = np.ideaIds) !== null && _h !== void 0 ? _h : []) {
            if (ideaById.has(id)) {
                await (0, execute_1.executeProcessInboxItem)(uid, id, `→ projet ORION « ${np.title} »`);
            }
        }
        created++;
    }
    for (const ap of (_j = decision.appendTo) !== null && _j !== void 0 ? _j : []) {
        const proj = projects.find((p) => p.id === ap.projectId);
        if (!proj)
            continue;
        for (const t of (_k = ap.tasks) !== null && _k !== void 0 ? _k : []) {
            await (0, execute_1.executeAddTask)(uid, ap.projectId, {
                id: (0, uuid_1.v4)(),
                title: t.title,
                startDate: today,
                actions: ((_l = t.actions) !== null && _l !== void 0 ? _l : []).slice(0, 6),
            });
            appended++;
        }
        const origin = ((_m = ap.ideaIds) !== null && _m !== void 0 ? _m : [])
            .map((id) => ideaById.get(id))
            .filter((i) => !!i)
            .map((i) => ({ text: i.text, date: i.date }));
        if (origin.length) {
            await db_1.db
                .doc(`users/${uid}/projects/${ap.projectId}`)
                .set({ originIdeas: db_1.FieldValue.arrayUnion(...origin) }, { merge: true });
        }
        for (const id of (_o = ap.ideaIds) !== null && _o !== void 0 ? _o : []) {
            if (ideaById.has(id)) {
                await (0, execute_1.executeProcessInboxItem)(uid, id, `→ ajoutée au projet « ${proj.title} »`);
            }
        }
    }
    const skipped = ((_p = decision.skip) !== null && _p !== void 0 ? _p : []).filter((id) => ideaById.has(id)).length;
    // Silence sur les projets créés (effet « wow »). Seul message éventuel : un
    // nudge léger sur une idée laissée, sans révéler le traitement de l'inbox.
    const nudgeText = (_r = (_q = decision.nudge) === null || _q === void 0 ? void 0 : _q.text) === null || _r === void 0 ? void 0 : _r.trim();
    if (nudgeText) {
        try {
            await (0, execute_1.executePushAssistantMessage)(uid, {
                targetDate: today,
                text: nudgeText,
                condition: { type: "always" },
                characterName: "ORION",
                expiresAfterDays: 3,
            });
        }
        catch (e) {
            console.error("nudge push failed (non bloquant)", e);
        }
    }
    await gateRef.set({
        lastSweepYmd: today,
        lastResult: { found: ideas.length, created, appended, skipped },
        at: db_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { found: ideas.length, created, appended, skipped };
}
//# sourceMappingURL=orion_inbox.js.map