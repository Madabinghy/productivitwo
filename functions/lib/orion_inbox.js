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
/// Contextes GTD par défaut — miroir de kDefaultGtdContexts (lib/models/projects.dart).
const DEFAULT_GTD_CONTEXTS = [
    "@maison", "@bureau", "@ordinateur", "@courses", "@extérieur", "@téléphone",
];
const ROUTING_PROMPT = `Tu es ORION, l'assistant de Productivitwo. Tu traites la boîte à idées de l'utilisateur selon la méthode GTD : chaque idée est classée PROJET, ACTION ponctuelle, ÉVÉNEMENT, ou laissée.

## CLASSIFICATION GTD (la règle la plus importante)
- **PROJET** ("newProjects") : un VRAI travail multi-étapes, stratégique, méritant un suivi sur plusieurs jours/semaines. Jamais pour une simple corvée.
- **ACTION ponctuelle** ("schedule") : réalisable en un coup (corvée, course, appel, petite réparation, message) → DÉFI daté dans les 14 prochains jours — jour et heure PLAUSIBLES (jamais avant {{WAKE}} ni après 21h, corvée extérieure en journée), durée réaliste (5-60 min), charge étalée (max 2 défis/jour). Si une routine/activité existante correspond au sujet, mets son activityId (chrono ciblé).
- **ÉVÉNEMENT** ("events") : l'idée mentionne un rendez-vous à date/heure FIXE (rdv médecin mardi 15h, réunion, anniversaire) → bloc d'agenda simple à cette date/heure, SANS le traiter comme un défi.
- **Laisser** ("skip") : note vague, non actionnable, ou qui demande une décision de l'utilisateur.
Dans le doute : skip. Mieux vaut laisser une idée que créer un projet bidon ou un défi absurde.

## Règles
1. Préfère TOUJOURS enrichir un projet ACTIF existant (appendTo) plutôt que créer, si l'idée s'y rattache sémantiquement.
2. AGRÈGE : si plusieurs idées concernent le même sujet, regroupe-les — soit dans UN seul newProject (plusieurs ideaIds), soit en plusieurs tâches d'un même projet.
3. Chaque idée apparaît EXACTEMENT une fois (dans newProjects, appendTo, schedule, events, OU skip).
4. Pour un nouveau projet :
   - titre court et clair, domainId le plus cohérent parmi les domaines (ou null) ;
   - si un OBJECTIF stratégique existant (voir liste) correspond au projet, mets son id dans \`objectiveId\` (sinon null) ;
   - 2-4 tâches de niveau PHASE (un verbe d'action, \`durationDays\` 1-15, enchaînées dans le temps) — SANS sous-actions : c'est l'utilisateur qui définira ses actions, pas toi ;
   - \`firstAction\` = LA PROCHAINE ACTION GTD : la première chose physique et concrète à faire pour démarrer (ex: "Appeler la mairie pour les horaires"), avec son \`context\` choisi dans la liste des contextes ci-dessous (où/avec quoi c'est réalisable).
5. PLANIFICATION RÉALISTE (important) : l'utilisateur a DÉJÀ des projets en cours avec des tâches planifiées (voir leurs dates). Ne surcharge PAS les prochains jours. Donne à chaque nouveau projet un \`startOffsetDays\` pour ÉTALER la charge. Un projet peu urgent peut démarrer dans 1-3 semaines.

## Message léger (nudge) — optionnel
Les propositions apparaissent EN SILENCE. MAIS si une idée est laissée (skip), tu peux proposer "nudge": { "text": "..." } = UN message court à la 1ère personne d'ORION qui évoque cette idée — SANS JAMAIS dire que tu as traité l'inbox. Un seul nudge max.
PRIORISE l'idée laissée qui traîne depuis le PLUS LONGTEMPS (\`ageDays\` le plus élevé), et adapte le ton à l'âge :
- récente (≤ 3j) : pas forcément de nudge (laisse infuser), ou rappel très léger ;
- une à deux semaines : rappel amical (ex: "Pense à boucler ta facture SOF 😉") ;
- ancienne (> 2-3 semaines) : invite à trancher (ex: "Ça fait {ageDays} jours que tu as noté « X » — tu veux t'y mettre ou je la classe sans suite ?").
Omets le nudge si rien ne le mérite.

## Idées en attente
{{IDEAS}}

## Projets actifs (pour rattacher)
{{PROJECTS}}

## Objectifs stratégiques actifs (pour objectiveId)
{{OBJECTIVES}}

## Contextes GTD disponibles (pour firstAction.context)
{{CONTEXTS}}

## Domaines
{{DOMAINS}}

## Routines & activités existantes (pour l'activityId des défis)
{{ACTIVITIES}}

Date du jour : {{TODAY}} — heure de lever de l'utilisateur : {{WAKE}}

Réponds UNIQUEMENT avec ce JSON (rien d'autre) :
{
  "newProjects": [ { "title": "...", "description": "...", "domainId": "<id|null>", "objectiveId": "<id|null>", "ideaIds": ["..."], "startOffsetDays": 0, "tasks": [ {"title":"...", "durationDays": 2} ], "firstAction": { "title": "...", "context": "@maison" } } ],
  "appendTo": [ { "projectId": "...", "ideaIds": ["..."], "tasks": [ {"title":"..."} ] } ],
  "schedule": [ { "ideaId": "...", "title": "...", "dayOffset": 1, "startTime": "10:00", "durationMin": 25, "activityId": null } ],
  "events": [ { "ideaId": "...", "title": "...", "dayOffset": 3, "startTime": "15:00", "durationMin": 60 } ],
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
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x, _y, _z, _0, _1, _2, _3, _4, _5, _6, _7, _8;
    // Jour + heure VÉCUS (fait data/meta.tzOffsetMin posé par l'app) —
    // fallback Paris tant que le fait n'existe pas.
    const tzSnap = await db_1.db.doc(`users/${uid}/data/meta`).get();
    const tzOffsetMin = (_a = tzSnap.data()) === null || _a === void 0 ? void 0 : _a.tzOffsetMin;
    const userParts = (d = new Date()) => {
        if (typeof tzOffsetMin === "number" && isFinite(tzOffsetMin)) {
            const iso = new Date(d.getTime() + tzOffsetMin * 60000).toISOString();
            return { ymd: iso.slice(0, 10), hm: iso.slice(11, 16) };
        }
        return {
            ymd: todayParis(d),
            hm: new Intl.DateTimeFormat("en-GB", {
                timeZone: "Europe/Paris", hour: "2-digit", minute: "2-digit", hour12: false,
            }).format(d),
        };
    };
    const today = userParts().ymd;
    const gateRef = db_1.db.doc(`users/${uid}/data/inbox_sweep`);
    const gate = await gateRef.get();
    if (!(opts === null || opts === void 0 ? void 0 : opts.force) && gate.exists && ((_b = gate.data()) === null || _b === void 0 ? void 0 : _b.lastSweepYmd) === today) {
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
        return { found: 0, created: 0, appended: 0, scheduled: 0, events: 0, skipped: 0 };
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
    const [projSnap, domSnap, actsSnap, metaSnap, objSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
        db_1.db.collection(`users/${uid}/domains`).get(),
        db_1.db.collection(`users/${uid}/activities`).get(),
        db_1.db.doc(`users/${uid}/data/meta`).get(),
        db_1.db.collection(`users/${uid}/strategic_objectives`).get(),
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
    const activities = actsSnap.docs
        .map((d) => d.data())
        .filter((v) => v.deleted !== true)
        .map((v) => { var _a; return ({ id: v.id, name: v.name, type: (_a = v.type) !== null && _a !== void 0 ? _a : "time" }); });
    const metaWake = (_c = metaSnap.data()) === null || _c === void 0 ? void 0 : _c.wakeTime;
    const wake = typeof metaWake === "string" && /^\d{2}:\d{2}$/.test(metaWake) ? metaWake : "07:00";
    // Objectifs stratégiques actifs (rattachement des nouveaux projets).
    const objectives = objSnap.docs
        .map((d) => { var _a; return (Object.assign(Object.assign({}, d.data()), { id: (_a = d.data().id) !== null && _a !== void 0 ? _a : d.id })); })
        .filter((v) => { var _a; return String((_a = v.status) !== null && _a !== void 0 ? _a : "active") === "active"; })
        .map((v) => {
        var _a;
        const o = v;
        return { id: o.id, title: o.title, kpiTarget: (_a = o.kpiTarget) !== null && _a !== void 0 ? _a : null };
    });
    // Contextes GTD = défauts + personnalisés (data/meta.customContexts).
    const customContexts = ((_e = (_d = metaSnap.data()) === null || _d === void 0 ? void 0 : _d.customContexts) !== null && _e !== void 0 ? _e : [])
        .filter((c) => typeof c === "string" && c.trim().length > 0);
    const gtdContexts = [
        ...DEFAULT_GTD_CONTEXTS,
        ...customContexts.filter((c) => !DEFAULT_GTD_CONTEXTS.includes(c)),
    ];
    const prompt = ROUTING_PROMPT.replace("{{IDEAS}}", JSON.stringify(ideas, null, 2))
        .replace("{{PROJECTS}}", JSON.stringify(projects, null, 2))
        .replace("{{OBJECTIVES}}", JSON.stringify(objectives, null, 2))
        .replace("{{CONTEXTS}}", JSON.stringify(gtdContexts))
        .replace("{{DOMAINS}}", JSON.stringify(domains, null, 2))
        .replace("{{ACTIVITIES}}", JSON.stringify(activities, null, 2))
        .replace(/\{\{WAKE\}\}/g, wake)
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
        // NE PAS avancer lastSweepYmd en cas d'échec : le sweep doit pouvoir réessayer
        // le jour même. Sinon un seul plantage (ex: secret LLM indisponible) gèle le tri
        // de l'inbox pendant 24h. On consigne juste l'erreur pour diagnostic.
        await gateRef.set({ lastError: String(e), lastErrorAt: db_1.FieldValue.serverTimestamp() }, { merge: true });
        return null;
    }
    const ideaById = new Map(ideas.map((i) => [i.id, i]));
    let created = 0;
    let appended = 0;
    for (const np of (_f = decision.newProjects) !== null && _f !== void 0 ? _f : []) {
        const origin = ((_g = np.ideaIds) !== null && _g !== void 0 ? _g : [])
            .map((id) => ideaById.get(id))
            .filter((i) => !!i)
            .map((i) => ({ text: i.text, date: i.date }));
        if (origin.length === 0)
            continue;
        // Tâches ENCHAÎNÉES dans le temps (staircase Gantt) + sous-actions.
        // Démarrage décalé (startOffsetDays) pour étaler la charge vs les en-cours.
        const offset = Math.min(120, Math.max(0, Math.round((_h = np.startOffsetDays) !== null && _h !== void 0 ? _h : 0)));
        const projectStart = addDays(today, offset);
        const rawTasks = ((_j = np.tasks) === null || _j === void 0 ? void 0 : _j.length) ? np.tasks : [{ title: np.title }];
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
        const lastEnd = tasks.length ? (_k = tasks[tasks.length - 1].endDate) !== null && _k !== void 0 ? _k : projectStart : projectStart;
        const phases = [
            { id: "phase-1", label: "Réalisation", startDate: projectStart, endDate: lastEnd },
        ];
        const ids = ((_l = np.ideaIds) !== null && _l !== void 0 ? _l : []).filter((id) => ideaById.has(id));
        // Prochaine action GTD proposée : contexte validé contre la liste connue,
        // objectif validé contre les objectifs actifs.
        const firstActionTitle = (_o = (_m = np.firstAction) === null || _m === void 0 ? void 0 : _m.title) === null || _o === void 0 ? void 0 : _o.trim();
        const firstActionContext = ((_p = np.firstAction) === null || _p === void 0 ? void 0 : _p.context) && gtdContexts.includes(np.firstAction.context)
            ? np.firstAction.context
            : null;
        const objectiveId = np.objectiveId && objectives.some((o) => o.id === np.objectiveId)
            ? np.objectiveId
            : undefined;
        // Au lieu de créer le projet en silence → on PROPOSE (file « À valider »).
        await (0, execute_1.executeProposeChange)(uid, {
            kind: "new_project",
            title: `Créer le projet « ${np.title} »`,
            rationale: (_q = np.description) !== null && _q !== void 0 ? _q : origin.map((o) => o.text).join(" · "),
            sourceCaptureId: ids[0],
            payload: Object.assign({ projectTitle: np.title, domainId: (_r = np.domainId) !== null && _r !== void 0 ? _r : undefined, objectiveId, description: np.description, startDate: projectStart, endDate: lastEnd, phases,
                tasks }, (firstActionTitle
                ? { firstAction: { title: firstActionTitle, context: firstActionContext } }
                : {})),
        });
        await Promise.all(ids.map((id) => db_1.db.doc(`users/${uid}/captures/${id}`).set({ status: "proposed" }, { merge: true })));
        created++;
    }
    for (const ap of (_s = decision.appendTo) !== null && _s !== void 0 ? _s : []) {
        const proj = projects.find((p) => p.id === ap.projectId);
        if (!proj)
            continue;
        const ids = ((_t = ap.ideaIds) !== null && _t !== void 0 ? _t : []).filter((id) => ideaById.has(id));
        for (const t of (_u = ap.tasks) !== null && _u !== void 0 ? _u : []) {
            await (0, execute_1.executeProposeChange)(uid, {
                kind: "attach_idea_as_task",
                title: `Ajouter « ${t.title} » à « ${proj.title} »`,
                rationale: ids.map((id) => { var _a; return (_a = ideaById.get(id)) === null || _a === void 0 ? void 0 : _a.text; }).filter(Boolean).join(" · "),
                sourceCaptureId: ids[0],
                payload: {
                    projectId: ap.projectId,
                    taskTitle: t.title,
                    description: ((_v = t.actions) !== null && _v !== void 0 ? _v : []).slice(0, 6).join(" · "),
                },
            });
            appended++;
        }
        await Promise.all(ids.map((id) => db_1.db.doc(`users/${uid}/captures/${id}`).set({ status: "proposed" }, { merge: true })));
    }
    // Défis datés : posés DIRECTEMENT (un bloc se refuse d'un swipe, sans
    // pénalité) — l'idée est marquée traitée avec sa provenance. Garde-fous
    // déterministes : jamais avant le lever, heure passée → lendemain.
    const validActivityIds = new Set(activities.map((a) => a.id));
    let scheduled = 0;
    const nowHm = userParts().hm; // heure VÉCUE — « déjà passé » se juge là
    const toMin = (hm) => parseInt(hm.slice(0, 2), 10) * 60 + parseInt(hm.slice(3, 5), 10);
    for (const sc of (_w = decision.schedule) !== null && _w !== void 0 ? _w : []) {
        const idea = ideaById.get(sc.ideaId);
        if (!idea || !((_x = sc.title) === null || _x === void 0 ? void 0 : _x.trim()))
            continue;
        let offset = Math.min(14, Math.max(0, Math.round((_y = sc.dayOffset) !== null && _y !== void 0 ? _y : 1)));
        let startTime = typeof sc.startTime === "string" && /^\d{2}:\d{2}$/.test(sc.startTime)
            ? sc.startTime
            : "09:00";
        if (toMin(startTime) < toMin(wake))
            startTime = wake;
        // Aujourd'hui mais l'heure est déjà passée → demain.
        if (offset === 0 && toMin(startTime) <= toMin(nowHm) + 15)
            offset = 1;
        const ymd = addDays(today, offset);
        const block = {
            id: (0, uuid_1.v4)(),
            startTime,
            durationMin: Math.min(60, Math.max(5, Math.round((_z = sc.durationMin) !== null && _z !== void 0 ? _z : 25))),
            title: `🔥 Défi : ${sc.title.trim()}`,
            category: "personal",
            projectId: null,
            taskId: null,
            activityId: sc.activityId && validActivityIds.has(sc.activityId) ? sc.activityId : null,
            actionId: null,
            status: "pending",
            doneAt: null,
            challenge: true,
        };
        const ref = db_1.db.doc(`users/${uid}/daily_schedules/${ymd}`);
        const snap = await ref.get();
        if (!snap.exists) {
            await ref.set({
                date: ymd,
                generatedBy: "orion",
                generatedAt: db_1.FieldValue.serverTimestamp(),
                blocks: [block],
            });
        }
        else {
            const blocks = (_0 = snap.data().blocks) !== null && _0 !== void 0 ? _0 : [];
            blocks.push(block);
            await ref.update({ blocks });
        }
        await db_1.db.doc(`users/${uid}/captures/${sc.ideaId}`).set({
            status: "processed",
            orionNote: `Défi posé le ${ymd} à ${startTime} — « ${sc.title.trim()} »`,
            processedAt: new Date().toISOString(),
        }, { merge: true });
        scheduled++;
    }
    // Événements (rendez-vous à date/heure fixe) : bloc d'agenda simple, sans 🔥
    // ni challenge — miroir d'executeAddEvent (category personal, subtitle).
    let events = 0;
    for (const ev of (_1 = decision.events) !== null && _1 !== void 0 ? _1 : []) {
        const idea = ideaById.get(ev.ideaId);
        if (!idea || !((_2 = ev.title) === null || _2 === void 0 ? void 0 : _2.trim()))
            continue;
        const offset = Math.min(60, Math.max(0, Math.round((_3 = ev.dayOffset) !== null && _3 !== void 0 ? _3 : 1)));
        const startTime = typeof ev.startTime === "string" && /^\d{2}:\d{2}$/.test(ev.startTime)
            ? ev.startTime
            : "09:00";
        const ymd = addDays(today, offset);
        const block = {
            id: (0, uuid_1.v4)(),
            startTime,
            durationMin: Math.min(480, Math.max(15, Math.round((_4 = ev.durationMin) !== null && _4 !== void 0 ? _4 : 60))),
            title: ev.title.trim(),
            subtitle: "événement",
            category: "personal",
            projectId: null,
            taskId: null,
            activityId: null,
            actionId: null,
            status: "pending",
            doneAt: null,
        };
        const ref = db_1.db.doc(`users/${uid}/daily_schedules/${ymd}`);
        const snap = await ref.get();
        if (!snap.exists) {
            await ref.set({
                date: ymd,
                generatedBy: "orion",
                generatedAt: db_1.FieldValue.serverTimestamp(),
                blocks: [block],
            });
        }
        else {
            const blocks = (_5 = snap.data().blocks) !== null && _5 !== void 0 ? _5 : [];
            blocks.push(block);
            await ref.update({ blocks });
        }
        await db_1.db.doc(`users/${uid}/captures/${ev.ideaId}`).set({
            status: "processed",
            orionNote: `Événement posé le ${ymd} à ${startTime} — « ${ev.title.trim()} »`,
            processedAt: new Date().toISOString(),
        }, { merge: true });
        events++;
    }
    const skipped = ((_6 = decision.skip) !== null && _6 !== void 0 ? _6 : []).filter((id) => ideaById.has(id)).length;
    // Silence sur les projets créés (effet « wow »). Seul message éventuel : un
    // nudge léger sur une idée laissée, sans révéler le traitement de l'inbox.
    const nudgeText = (_8 = (_7 = decision.nudge) === null || _7 === void 0 ? void 0 : _7.text) === null || _8 === void 0 ? void 0 : _8.trim();
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
        lastResult: { found: ideas.length, created, appended, scheduled, events, skipped },
        at: db_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { found: ideas.length, created, appended, scheduled, events, skipped };
}
//# sourceMappingURL=orion_inbox.js.map