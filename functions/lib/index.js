"use strict";
var __rest = (this && this.__rest) || function (s, e) {
    var t = {};
    for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p) && e.indexOf(p) < 0)
        t[p] = s[p];
    if (s != null && typeof Object.getOwnPropertySymbols === "function")
        for (var i = 0, p = Object.getOwnPropertySymbols(s); i < p.length; i++) {
            if (e.indexOf(p[i]) < 0 && Object.prototype.propertyIsEnumerable.call(s, p[i]))
                t[p[i]] = s[p[i]];
        }
    return t;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.resetDemoData = exports.getDemoToken = exports.applyFormationProfile = exports.getVisionAccess = exports.generateFormationAccess = exports.adminProductivitwo = exports.revenueCatWebhook = exports.onboardingChat = exports.structureProject = exports.orionCron = exports.orionBrief = exports.orionRunCount = exports.orionSaveConfig = exports.githubWebhook = exports.orionWebhook = exports.mcpHandler = exports.sendMagicLink = exports.getCustomToken = exports.pushAssistantMessage = exports.defineDomainChat = exports.proposeDayPlan = exports.nowAssist = exports.pushGantt = void 0;
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const crypto_1 = require("crypto");
const orion_1 = require("./orion");
const orion_inbox_1 = require("./orion_inbox");
const orion_brief_1 = require("./orion_brief");
const models_1 = require("./models");
const sdk_1 = require("@anthropic-ai/sdk");
const sgMail = require("@sendgrid/mail");
const orion_tasks_1 = require("./orion_tasks");
const uuid_1 = require("uuid");
const db_1 = require("./db");
const prompts_1 = require("./prompts");
const tools_1 = require("./tools");
const execute_1 = require("./execute");
// ── pushGantt ─────────────────────────────────────────────────────────────────
//
// POST https://us-central1-productivitwo-app.cloudfunctions.net/pushGantt
// Headers: Authorization: Bearer <token>
// Body: { uid, project, strategicObjective? }
exports.pushGantt = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const authHeader = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
    }
    const rawToken = authHeader.slice(7).trim();
    const body = req.body;
    if (!body.uid || !((_b = body.project) === null || _b === void 0 ? void 0 : _b.title) || !((_c = body.project) === null || _c === void 0 ? void 0 : _c.startDate)) {
        res.status(400).json({ error: "Missing required fields: uid, project.title, project.startDate" });
        return;
    }
    const { uid, project, strategicObjective } = body;
    const valid = await (0, execute_1.validateToken)(uid, rawToken);
    if (!valid) {
        res.status(401).json({ error: "Invalid or revoked token" });
        return;
    }
    const rl = await (0, execute_1.checkRateLimit)(uid, "pushGantt", 30);
    if (rl.limited) {
        res.status(429).json({ error: `Rate limit dépassé — réessaie dans ${rl.retryAfterSecs}s` });
        return;
    }
    let pickedProject;
    let pickedSO;
    try {
        pickedProject = (0, execute_1.pickProject)(project);
        if (strategicObjective)
            pickedSO = (0, execute_1.pickStrategicObjective)(strategicObjective);
    }
    catch (e) {
        res.status(400).json({ error: e instanceof Error ? e.message : String(e) });
        return;
    }
    let strategicObjectiveId;
    if (strategicObjective && pickedSO) {
        const objId = strategicObjective.id || (0, uuid_1.v4)();
        strategicObjectiveId = objId;
        await db_1.db.collection(`users/${uid}/strategic_objectives`).doc(objId).set(Object.assign(Object.assign({}, pickedSO), { id: objId, status: "active", updatedAt: db_1.FieldValue.serverTimestamp(), createdAt: db_1.FieldValue.serverTimestamp() }), { merge: true });
    }
    const projectId = project.id || (0, uuid_1.v4)();
    await db_1.db.collection(`users/${uid}/projects`).doc(projectId).set(Object.assign(Object.assign(Object.assign(Object.assign({}, pickedProject), { id: projectId, createdBy: uid, sourceType: "claude_api", status: "active" }), (strategicObjectiveId ? { strategicObjectiveId } : {})), { updatedAt: db_1.FieldValue.serverTimestamp(), createdAt: db_1.FieldValue.serverTimestamp() }), { merge: true });
    if (strategicObjectiveId) {
        await db_1.db.collection(`users/${uid}/strategic_objectives`).doc(strategicObjectiveId)
            .update({ projectIds: db_1.FieldValue.arrayUnion(projectId) });
    }
    res.status(200).json({ success: true, projectId, strategicObjectiveId: strategicObjectiveId !== null && strategicObjectiveId !== void 0 ? strategicObjectiveId : null });
});
// ── markPlanItemDone : SUPPRIMÉ ──────────────────────────────────────────────
// Écrivait users/{uid}/dayPlan, collection morte depuis la suppression de
// DayPlanItem (le widget iOS ne l'appelle plus — vérifié dans ios/). Le
// scheduling passe par daily_schedules + mark_block_done.
// ── nowAssist ─────────────────────────────────────────────────────────────────
//
// POST { uid, message } + Authorization: Bearer <api_token>
// Champ libre de l'onglet « Maintenant » : « Que souhaites-tu faire ? »
// Boucle Sonnet plafonnée, outils restreints. Règle d'or : ne JAMAIS créer une
// routine/activité qui existe déjà (liste injectée) — la mission par défaut est
// de PROGRAMMER les prochaines heures (add_blocks_today), pas de créer.
// Limite : 10 appels / jour / user (garde de coût).
const NOW_ASSIST_MAX_PER_DAY = 10;
const NOW_ASSIST_MAX_TURNS = 5;
const ADD_BLOCKS_TODAY_TOOL = {
    name: "add_blocks_today",
    description: "Ajoute des blocs au programme d'AUJOURD'HUI (sans toucher aux blocs existants). " +
        "Uniquement des heures À VENIR — jamais le passé. Un bloc peut porter " +
        "activityId (chrono ciblé au lancement).",
    input_schema: {
        type: "object",
        required: ["blocks"],
        properties: {
            blocks: {
                type: "array",
                items: {
                    type: "object",
                    required: ["startTime", "durationMin", "title", "category"],
                    properties: {
                        startTime: { type: "string", description: "HH:mm — obligatoirement ≥ heure actuelle" },
                        durationMin: { type: "integer" },
                        title: { type: "string" },
                        category: { type: "string", enum: ["project", "routine", "personal", "break"] },
                        activityId: { type: "string" },
                        projectId: { type: "string" },
                        taskId: { type: "string" },
                    },
                },
            },
        },
    },
};
exports.nowAssist = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["ANTHROPIC_API_KEY"] }, async (req, res) => {
    var _a, _b, _c;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const authHeader = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
    }
    const { uid, message } = req.body;
    if (!uid || !(message === null || message === void 0 ? void 0 : message.trim())) {
        res.status(400).json({ error: "uid et message requis" });
        return;
    }
    const valid = await (0, execute_1.validateToken)(uid, authHeader.slice(7).trim());
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    // Limite quotidienne (garde de coût) — compteur simple par jour.
    const today = (0, execute_1.todayInParis)();
    const limitRef = db_1.db.doc(`users/${uid}/rate_limits/now_assist`);
    const limitSnap = await limitRef.get();
    const limitData = limitSnap.data();
    const count = (limitData === null || limitData === void 0 ? void 0 : limitData.ymd) === today ? ((_b = limitData.count) !== null && _b !== void 0 ? _b : 0) : 0;
    if (count >= NOW_ASSIST_MAX_PER_DAY) {
        res.status(429).json({ error: `Limite atteinte (${NOW_ASSIST_MAX_PER_DAY}/jour) — réessaie demain.` });
        return;
    }
    await limitRef.set({ ymd: today, count: count + 1 }, { merge: true });
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
        res.status(500).json({ error: "ANTHROPIC_API_KEY manquante" });
        return;
    }
    const client = new sdk_1.default({ apiKey });
    const nowHm = new Date().toLocaleTimeString("fr-FR", {
        timeZone: "Europe/Paris", hour: "2-digit", minute: "2-digit", hour12: false,
    });
    // Contexte : programme restant + routines/activités existantes (anti-doublon).
    const [schedule, actsSnap] = await Promise.all([
        (0, execute_1.executeGetDaySchedule)(uid, today),
        db_1.db.collection(`users/${uid}/activities`).get(),
    ]);
    const acts = actsSnap.docs
        .map((d) => d.data())
        .filter((a) => a.deleted !== true);
    const routineList = acts.filter((a) => a.type === "habit")
        .map((a) => `  · "${a.name}" (activityId: ${a.id})`).join("\n") || "  Aucune.";
    const activityList = acts.filter((a) => a.type !== "habit")
        .map((a) => `  · "${a.name}" (activityId: ${a.id})`).join("\n") || "  Aucune.";
    const systemPrompt = [
        `Tu es l'assistant « Maintenant » de Productivitwo. L'utilisateur te dit ce qu'il veut faire là, tout de suite. Il est ${nowHm} (${today}, Europe/Paris).`,
        ``,
        `RÈGLES STRICTES :`,
        `1. Ta mission PAR DÉFAUT est de PROGRAMMER les prochaines heures avec add_blocks_today — blocs UNIQUEMENT ≥ ${nowHm}, jamais le passé, jamais toute la journée (2-3 blocs max).`,
        `2. Ne crée JAMAIS une routine ou activité qui existe déjà ci-dessous — référence son activityId dans le bloc. create_routine/create_activity SEULEMENT si rien d'existant ne correspond.`,
        `3. Réponse finale : 1-2 phrases en français, concrètes (ce que tu as posé et quand).`,
        ``,
        `ROUTINES EXISTANTES :`,
        routineList,
        ``,
        `ACTIVITÉS-TEMPS EXISTANTES :`,
        activityList,
        ``,
        `PROGRAMME DU JOUR (ne pas dupliquer, ne pas toucher aux blocs existants) :`,
        schedule,
    ].join("\n");
    // Ajout de blocs au programme du jour SANS remplacer l'existant.
    const addBlocksToday = async (blocks) => {
        var _a, _b, _c, _d, _e, _f, _g, _h, _j;
        const ref = db_1.db.doc(`users/${uid}/daily_schedules/${today}`);
        const snap = await ref.get();
        const existing = snap.exists
            ? ((_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.blocks) !== null && _b !== void 0 ? _b : [])
            : [];
        const kept = [];
        const skipped = [];
        for (const b of blocks) {
            const startTime = String((_c = b.startTime) !== null && _c !== void 0 ? _c : "");
            if (!/^\d{2}:\d{2}$/.test(startTime) || startTime < nowHm) {
                skipped.push(`"${b.title}" (${startTime || "?"} — heure passée/invalide)`);
                continue;
            }
            kept.push({
                id: (0, uuid_1.v4)(),
                startTime,
                durationMin: Number((_d = b.durationMin) !== null && _d !== void 0 ? _d : 30),
                title: String((_e = b.title) !== null && _e !== void 0 ? _e : ""),
                category: String((_f = b.category) !== null && _f !== void 0 ? _f : "personal"),
                projectId: (_g = b.projectId) !== null && _g !== void 0 ? _g : null,
                taskId: (_h = b.taskId) !== null && _h !== void 0 ? _h : null,
                activityId: (_j = b.activityId) !== null && _j !== void 0 ? _j : null,
                actionId: null,
                status: "pending",
                doneAt: null,
            });
        }
        if (kept.length > 0) {
            await ref.set({
                date: today,
                generatedBy: "claude",
                generatedAt: db_1.FieldValue.serverTimestamp(),
                blocks: [...existing, ...kept],
            }, { merge: true });
        }
        return `${kept.length} bloc(s) ajouté(s).${skipped.length ? ` Ignorés (passé/invalide) : ${skipped.join(", ")}` : ""}`;
    };
    try {
        const messages = [{ role: "user", content: message.trim() }];
        const tools = [tools_1.CREATE_ROUTINE_TOOL, tools_1.CREATE_ACTIVITY_TOOL, ADD_BLOCKS_TODAY_TOOL];
        let blocksAdded = 0;
        let finalText = "";
        for (let turn = 0; turn < NOW_ASSIST_MAX_TURNS; turn++) {
            const response = await client.messages.create({
                model: (0, models_1.getModel)("chat"),
                max_tokens: 1024,
                system: systemPrompt,
                tools: tools,
                messages: messages,
            });
            (0, models_1.logTokenUsage)("now_assist", (0, models_1.getModel)("chat"), response.usage);
            finalText += response.content
                .filter((b) => b.type === "text")
                .map((b) => b.text)
                .join("");
            if (response.stop_reason !== "tool_use")
                break;
            messages.push({ role: "assistant", content: response.content });
            const toolResults = [];
            for (const block of response.content) {
                if (block.type !== "tool_use")
                    continue;
                const args = block.input;
                let result = "";
                try {
                    if (block.name === "add_blocks_today") {
                        const blocks = (_c = args.blocks) !== null && _c !== void 0 ? _c : [];
                        result = await addBlocksToday(blocks);
                        blocksAdded += blocks.length;
                    }
                    else if (block.name === "create_routine") {
                        result = await (0, execute_1.executeCreateRoutine)(uid, args);
                    }
                    else if (block.name === "create_activity") {
                        result = await (0, execute_1.executeCreateActivity)(uid, args);
                    }
                    else {
                        result = `Outil inconnu : ${block.name}`;
                    }
                }
                catch (e) {
                    result = `Erreur : ${e instanceof Error ? e.message : String(e)}`;
                }
                toolResults.push({ type: "tool_result", tool_use_id: block.id, content: result });
            }
            messages.push({ role: "user", content: toolResults });
        }
        res.status(200).json({
            message: finalText.trim() || "C'est noté — regarde ton programme.",
            blocksAdded,
        });
    }
    catch (e) {
        console.error("nowAssist error:", e);
        res.status(500).json({ error: "Assistant indisponible — réessaie." });
    }
});
// ── proposeDayPlan ────────────────────────────────────────────────────────────
//
// POST { uid, date? } + Authorization: Bearer <api_token>
// Écran de planification (check-in « Poser demain » / rattrapage du matin) :
// retourne une PROPOSITION de programme en JSON structuré — n'écrit RIEN.
// La validation côté app passe par les écritures existantes (schedule_day /
// saveDailySchedule + add_prep_block). 1 appel Haiku par ouverture d'écran.
const PROPOSE_PLAN_MAX_PER_DAY = 20;
exports.proposeDayPlan = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["ANTHROPIC_API_KEY"] }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _l;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const authHeader = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
    }
    const { uid, date } = req.body;
    if (!uid) {
        res.status(400).json({ error: "uid requis" });
        return;
    }
    const valid = await (0, execute_1.validateToken)(uid, authHeader.slice(7).trim());
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    const today = (0, execute_1.todayInParis)();
    const target = date && /^\d{4}-\d{2}-\d{2}$/.test(date) ? date : today;
    // Jour de référence = la veille de la cible (son programme + ses causes).
    const refDate = (0, execute_1.todayInParis)(new Date(new Date(target).getTime() - 24 * 60 * 60 * 1000));
    // Garde de coût quotidienne.
    const limitRef = db_1.db.doc(`users/${uid}/rate_limits/plan_proposal`);
    const limitSnap = await limitRef.get();
    const limitData = limitSnap.data();
    const count = (limitData === null || limitData === void 0 ? void 0 : limitData.ymd) === today ? ((_b = limitData.count) !== null && _b !== void 0 ? _b : 0) : 0;
    if (count >= PROPOSE_PLAN_MAX_PER_DAY) {
        res.status(429).json({ error: `Limite atteinte (${PROPOSE_PLAN_MAX_PER_DAY}/jour).` });
        return;
    }
    // Plafond par DATE CIBLE (protection : le client cache le brouillon, une
    // ouverture répétée de l'écran ne doit plus regénérer).
    const dateLimitRef = db_1.db.doc(`users/${uid}/rate_limits/plan_proposal_${target}`);
    const dateLimitSnap = await dateLimitRef.get();
    const dateLimitData = dateLimitSnap.data();
    const dateCount = (dateLimitData === null || dateLimitData === void 0 ? void 0 : dateLimitData.ymd) === today ? ((_c = dateLimitData.count) !== null && _c !== void 0 ? _c : 0) : 0;
    if (dateCount >= 5) {
        res.status(429).json({ error: "Limite atteinte pour cette date (5 générations/jour) — le brouillon existant reste utilisable." });
        return;
    }
    await Promise.all([
        limitRef.set({ ymd: today, count: count + 1 }, { merge: true }),
        dateLimitRef.set({ ymd: today, count: dateCount + 1 }, { merge: true }),
    ]);
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
        res.status(500).json({ error: "ANTHROPIC_API_KEY manquante" });
        return;
    }
    const nowHm = new Date().toLocaleTimeString("fr-FR", {
        timeZone: "Europe/Paris", hour: "2-digit", minute: "2-digit", hour12: false,
    });
    const sameDay = target === today;
    try {
        // ── Contexte ────────────────────────────────────────────────────────────
        const [refSnap, targetSnap, actsSnap, projSnap, docsSnap, domainsSnap] = await Promise.all([
            db_1.db.doc(`users/${uid}/daily_schedules/${refDate}`).get(),
            db_1.db.doc(`users/${uid}/daily_schedules/${target}`).get(),
            db_1.db.collection(`users/${uid}/activities`).get(),
            db_1.db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
            db_1.db.collection(`users/${uid}/documents`).orderBy("updatedAt", "desc").limit(10).get()
                .catch(() => db_1.db.collection(`users/${uid}/documents`).limit(10).get()),
            db_1.db.collection(`users/${uid}/domains`).get(),
        ]);
        // Domaines définis (session de définition) : intention + vital + modalités
        // — la colonne vertébrale de la proposition, cités en provenance.
        const domainLines = domainsSnap.docs
            .map((d) => d.data())
            .filter((v) => v.deleted !== true && v.definitionStatus === "active" && v.intention)
            .map((v) => {
            var _a, _b;
            const vital = ((_a = v.vitalMinimum) !== null && _a !== void 0 ? _a : [])
                .map((m) => m.label).join(" · ");
            const mods = ((_b = v.modalities) !== null && _b !== void 0 ? _b : [])
                .map((m) => { var _a; return (_a = m.label) !== null && _a !== void 0 ? _a : m; }).join(" · ");
            return `  · ${v.name} — intention : « ${v.intention} »` +
                (vital ? `\n    minimum vital : ${vital}` : "") +
                (mods ? `\n    modalités : ${mods}` : "");
        });
        const refData = refSnap.exists ? refSnap.data() : {};
        const refBlocks = ((_d = refData.blocks) !== null && _d !== void 0 ? _d : [])
            .filter((b) => b.status !== "deleted" && b.kind !== "prep");
        const refLines = refBlocks.map((b) => {
            var _a;
            const st = b.status === "done" ? "✅" : "❌ SAUTÉ";
            const reason = b.skipReason ? ` (cause : ${b.skipReason})` : "";
            return `  ${b.startTime} "${b.title}" [${b.category}] ${st}${reason}` +
                (b.activityId ? ` activityId=${b.activityId}` : "") +
                (b.projectId ? ` projectId=${b.projectId} taskId=${(_a = b.taskId) !== null && _a !== void 0 ? _a : ""}` : "");
        });
        const dayReason = (_e = refData.dayReason) !== null && _e !== void 0 ? _e : null;
        const targetBlocks = targetSnap.exists
            ? (((_g = (_f = targetSnap.data()) === null || _f === void 0 ? void 0 : _f.blocks) !== null && _g !== void 0 ? _g : [])
                .filter((b) => b.status !== "deleted"))
            : [];
        const acts = actsSnap.docs
            .map((d) => d.data())
            .filter((a) => a.deleted !== true);
        const routineList = acts.filter((a) => a.type === "habit")
            .map((a) => `  · "${a.name}" (activityId: ${a.id})`).join("\n") || "  Aucune.";
        const activityList = acts.filter((a) => a.type !== "habit")
            .map((a) => `  · "${a.name}" (activityId: ${a.id})`).join("\n") || "  Aucune.";
        const projLines = [];
        for (const doc of projSnap.docs) {
            const p = doc.data();
            const pending = (p.tasks || [])
                .filter((t) => t.status !== "done" && t.status !== "skipped")
                .slice(0, 3)
                .map((t) => `    - "${t.title}" (taskId: ${t.id}${t.endDate ? `, deadline ${t.endDate}` : ""})`);
            if (pending.length > 0) {
                projLines.push(`  · "${p.title}" (projectId: ${p.id})\n${pending.join("\n")}`);
            }
        }
        const docLines = docsSnap.docs.map((d) => {
            var _a;
            const doc = d.data();
            return `  · "${(_a = doc.title) !== null && _a !== void 0 ? _a : d.id}" (documentId: ${d.id})`;
        });
        const systemPrompt = [
            `Tu prépares la PROPOSITION de programme du ${target} pour l'écran de planification de Productivitwo. Il est ${nowHm} (${today}, Europe/Paris).`,
            sameDay
                ? `⚠️ La cible est AUJOURD'HUI (rattrapage express) : ne propose AUCUN bloc avant ${nowHm}. Horizon = ce qui reste de la journée.`
                : `La cible est un jour complet (7h-21h environ).`,
            ``,
            `Tu réponds UNIQUEMENT avec un objet JSON valide, sans markdown ni texte autour :`,
            `{`,
            `  "message": "pourquoi cette proposition, 1-2 phrases avec la provenance (plans, deadlines, causes d'hier)",`,
            `  "sources": [{"title": "nom court de l'artefact/plan utilisé", "documentId": "id ou null"}],`,
            `  "blocks": [{"startTime": "HH:mm", "durationMin": 30, "title": "…", "category": "project|routine|personal|break",`,
            `              "activityId": null, "projectId": null, "taskId": null,`,
            `              "subtitle": "provenance courte (ex: plan de reprise S2, deadline 30 sept)", "reproposed": false}]`,
            `}`,
            ``,
            `RÈGLES :`,
            `1. 3 à 6 blocs, jamais une page vide. Heures plausibles, pas de chevauchement.`,
            `2. REPROPOSER les blocs SAUTÉS de la VEILLE uniquement (reproposed: true, même source liée) — un engagement rompu n'est pas perdu : il revient LE LENDEMAIN, marqué reproposé, refusable en un tap.`,
            ...(sameDay
                ? [`2bis. JAMAIS de rattrapage le jour même : les blocs/routines d'AUJOURD'HUI déjà passés ou sautés sont MORTS pour aujourd'hui — ne les repropose pas ce soir (une routine ratée est morte, sans pénalité). Ils reviendront demain s'ils le méritent.`]
                : []),
            dayReason === "irrealiste"
                ? `3. ⚠️ La veille était « programme irréaliste » : propose MOINS de blocs que la veille (${Math.max(2, refBlocks.length - 2)} max) et dis-le dans message (« Hier était trop chargé — demain est plus court, volontairement. »).`
                : `3. Charge réaliste : ne pas dépasser la veille.`,
            `4. Réutilise les activityId/projectId/taskId existants ci-dessous (chrono ciblé) — jamais d'id inventé.`,
            `5. Chiffres et provenances réels uniquement (deadlines, plans listés). Si aucune provenance : sources: [].`,
            ``,
            ...(domainLines.length > 0
                ? [
                    `── DOMAINES DÉFINIS (respecte les modalités, défends le minimum vital) ──`,
                    domainLines.join("\n"),
                    ``,
                ]
                : []),
            `── PROGRAMME DE LA VEILLE (${refDate})${dayReason ? ` — cause globale : ${dayReason}` : ""} ──`,
            refLines.length > 0 ? refLines.join("\n") : "  Aucun programme.",
            ``,
            `── PROGRAMME DÉJÀ EN PLACE POUR ${target} (à intégrer, ne pas dupliquer) ──`,
            targetBlocks.length > 0
                ? targetBlocks.map((b) => `  ${b.startTime} "${b.title}" [${b.status}]`).join("\n")
                : "  Aucun.",
            ``,
            `── ROUTINES ──`, routineList,
            `── ACTIVITÉS-TEMPS ──`, activityList,
            `── PROJETS ACTIFS (tâches ouvertes) ──`,
            projLines.length > 0 ? projLines.join("\n") : "  Aucun.",
            `── DOCUMENTS/PLANS DISPONIBLES (provenance) ──`,
            docLines.length > 0 ? docLines.join("\n") : "  Aucun.",
        ].join("\n");
        const client = new sdk_1.default({ apiKey });
        const model = (0, models_1.getModel)("plan_proposal");
        const response = await client.messages.create({
            model,
            max_tokens: 1500,
            system: systemPrompt,
            messages: [{ role: "user", content: `Propose le programme du ${target}.` }],
        });
        (0, models_1.logTokenUsage)("plan_proposal", model, response.usage);
        const raw = response.content
            .filter((b) => b.type === "text")
            .map((b) => b.text)
            .join("");
        // Extraction tolérante : premier { … dernier } (Haiku peut entourer de texte).
        const start = raw.indexOf("{");
        const end = raw.lastIndexOf("}");
        if (start < 0 || end <= start)
            throw new Error("Réponse sans JSON");
        const proposal = JSON.parse(raw.slice(start, end + 1));
        res.status(200).json({
            message: (_h = proposal.message) !== null && _h !== void 0 ? _h : "",
            sources: (_j = proposal.sources) !== null && _j !== void 0 ? _j : [],
            blocks: ((_l = proposal.blocks) !== null && _l !== void 0 ? _l : []).filter((b) => { var _a; return /^\d{2}:\d{2}$/.test(String((_a = b.startTime) !== null && _a !== void 0 ? _a : "")) && b.title; }),
            refDate,
            dayReason,
        });
    }
    catch (e) {
        console.error("proposeDayPlan error:", e);
        // Le client a un fallback déterministe — 502 le déclenche proprement.
        res.status(502).json({ error: "Proposition indisponible — fallback local." });
    }
});
// ── defineDomainChat ──────────────────────────────────────────────────────────
//
// POST { uid, domainName, messages: [{role, content}] } + Bearer <api_token>
// Session de définition d'un domaine (13a-13c) : conversation guidée en 3
// phases (intention → minimum vital → modalités & artefacts). Chaque élément
// validé est ÉCRIT via save_domain_definition — fait structuré, jamais un
// souvenir de chat. Moment fondateur → classe premium (pattern
// structure_project : faible volume, plafonné).
const DEFINE_DOMAIN_MAX_PER_DAY = 80; // messages/jour (une session ≈ 15-25 tours)
const DEFINE_DOMAIN_MAX_TURNS = 4;
exports.defineDomainChat = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["ANTHROPIC_API_KEY"] }, async (req, res) => {
    var _a, _b;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const authHeader = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
    }
    const { uid, domainName, messages } = req.body;
    if (!uid || !(domainName === null || domainName === void 0 ? void 0 : domainName.trim()) || !(messages === null || messages === void 0 ? void 0 : messages.length)) {
        res.status(400).json({ error: "uid, domainName et messages requis" });
        return;
    }
    const valid = await (0, execute_1.validateToken)(uid, authHeader.slice(7).trim());
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    // Garde de coût (classe premium).
    const today = (0, execute_1.todayInParis)();
    const limitRef = db_1.db.doc(`users/${uid}/rate_limits/define_domain`);
    const limitSnap = await limitRef.get();
    const limitData = limitSnap.data();
    const count = (limitData === null || limitData === void 0 ? void 0 : limitData.ymd) === today ? ((_b = limitData.count) !== null && _b !== void 0 ? _b : 0) : 0;
    if (count >= DEFINE_DOMAIN_MAX_PER_DAY) {
        res.status(429).json({ error: "Limite de session atteinte pour aujourd'hui." });
        return;
    }
    await limitRef.set({ ymd: today, count: count + 1 }, { merge: true });
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
        res.status(500).json({ error: "ANTHROPIC_API_KEY manquante" });
        return;
    }
    const client = new sdk_1.default({ apiKey });
    const model = (0, models_1.getModel)("define_domain");
    try {
        const convo = messages
            .filter((m) => { var _a; return (_a = m.content) === null || _a === void 0 ? void 0 : _a.trim(); })
            .map((m) => ({ role: m.role, content: m.content }));
        let finalText = "";
        let domainId = null;
        let finalized = false;
        // Format API Anthropic (input_schema) depuis la définition MCP (inputSchema).
        const anthropicTools = [{
                name: tools_1.SAVE_DOMAIN_DEFINITION_TOOL.name,
                description: tools_1.SAVE_DOMAIN_DEFINITION_TOOL.description,
                input_schema: tools_1.SAVE_DOMAIN_DEFINITION_TOOL.inputSchema,
            }];
        for (let turn = 0; turn < DEFINE_DOMAIN_MAX_TURNS; turn++) {
            const response = await client.messages.create({
                model,
                max_tokens: 1024,
                system: (0, prompts_1.defineDomainSystemPrompt)(domainName.trim()),
                tools: anthropicTools,
                messages: convo,
            });
            (0, models_1.logTokenUsage)("define_domain", model, response.usage);
            finalText += response.content
                .filter((b) => b.type === "text")
                .map((b) => b.text)
                .join("");
            if (response.stop_reason !== "tool_use")
                break;
            convo.push({ role: "assistant", content: response.content });
            const toolResults = [];
            for (const block of response.content) {
                if (block.type !== "tool_use")
                    continue;
                let result = "";
                try {
                    if (block.name === "save_domain_definition") {
                        const args = block.input;
                        result = await (0, execute_1.executeSaveDomainDefinition)(uid, args);
                        const idMatch = result.match(/\(id: ([^)]+)\)/);
                        if (idMatch)
                            domainId = idMatch[1];
                        if (args.finalize === true)
                            finalized = true;
                    }
                    else {
                        result = `Outil inconnu : ${block.name}`;
                    }
                }
                catch (e) {
                    result = `Erreur : ${e instanceof Error ? e.message : String(e)}`;
                }
                toolResults.push({ type: "tool_result", tool_use_id: block.id, content: result });
            }
            convo.push({ role: "user", content: toolResults });
        }
        res.status(200).json({
            message: finalText.trim() || "…",
            domainId,
            finalized,
        });
    }
    catch (e) {
        console.error("defineDomainChat error:", e);
        res.status(500).json({ error: "Session indisponible — réessaie." });
    }
});
// ── pushAssistantMessage ──────────────────────────────────────────────────────
//
// POST https://us-central1-productivitwo-app.cloudfunctions.net/pushAssistantMessage
exports.pushAssistantMessage = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const authHeader = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
    }
    const rawToken = authHeader.slice(7).trim();
    const body = req.body;
    if (!body.uid || !body.targetDate || !body.text || !body.condition) {
        res.status(400).json({ error: "Missing required fields: uid, targetDate, text, condition" });
        return;
    }
    const valid = await (0, execute_1.validateToken)(body.uid, rawToken);
    if (!valid) {
        res.status(401).json({ error: "Invalid or revoked token" });
        return;
    }
    const result = await (0, execute_1.executePushAssistantMessage)(body.uid, body);
    const messageId = (_b = result.match(/messageId : (.+)$/m)) === null || _b === void 0 ? void 0 : _b[1];
    res.status(200).json({ success: true, messageId });
});
// ── getCustomToken ────────────────────────────────────────────────────────────
//
// POST { uid, token } — retourne un Firebase custom token pour cet UID.
exports.getCustomToken = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const { uid, token } = req.body;
    if (!uid || !token) {
        res.status(400).json({ error: "uid et token requis" });
        return;
    }
    const valid = await (0, execute_1.validateToken)(uid, token);
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    const customToken = await admin.auth().createCustomToken(uid);
    res.status(200).json({ customToken });
});
// ── sendMagicLink ───────────────────────────────────────────────────────────
//
// POST https://sendmagiclink-dzos75b65q-uc.a.run.app
// Body: { email, continueUrl? }
//
// Génère un lien de connexion passwordless (Admin SDK) et l'envoie via SendGrid
// avec un mail HTML brandé Productivitwo — remplace le mail générique Firebase.
// La complétion côté client reste signInWithEmailLink (inchangée).
// ⚠️ MAGIC_FROM_EMAIL doit être un expéditeur VÉRIFIÉ dans SendGrid
// (Single Sender ou domaine authentifié). Sinon SendGrid rejette l'envoi.
const MAGIC_FROM_EMAIL = "noreply@productivitwo.com";
const MAGIC_FROM_NAME = "Productivitwo";
const MAGIC_DEFAULT_CONTINUE_URL = "https://app.productivitwo.com/";
function magicLinkEmailHtml(link) {
    return `<!DOCTYPE html>
<html lang="fr">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#0D2A1E;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0D2A1E;padding:40px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:440px;background:#0F1F19;border:1px solid rgba(255,255,255,0.08);border-radius:20px;overflow:hidden;">
        <tr><td style="padding:36px 32px 8px;text-align:center;">
          <div style="font-size:26px;font-weight:800;color:#E6F7F2;letter-spacing:-0.5px;">Productivitwo</div>
          <div style="font-size:13px;color:#9FE1CB;margin-top:6px;">Gérez vos projets, pilotés par l'IA</div>
        </td></tr>
        <tr><td style="padding:24px 32px 8px;text-align:center;">
          <div style="font-size:15px;color:#D6EFE6;line-height:1.5;">Voici ton lien de connexion.<br>Pas de mot de passe à retenir.</div>
        </td></tr>
        <tr><td style="padding:24px 32px;text-align:center;">
          <a href="${link}" style="display:inline-block;background:#10B981;color:#06231A;text-decoration:none;font-weight:700;font-size:15px;padding:14px 28px;border-radius:999px;">Me connecter</a>
        </td></tr>
        <tr><td style="padding:0 32px 28px;text-align:center;">
          <div style="font-size:11px;color:#6E8C82;line-height:1.5;">Si le bouton ne fonctionne pas, copie ce lien dans ton navigateur :<br>
          <a href="${link}" style="color:#6BBFA3;word-break:break-all;">${link}</a></div>
          <div style="font-size:11px;color:#52685F;margin-top:20px;">Tu n'as pas demandé cette connexion ? Ignore cet email.</div>
        </td></tr>
      </table>
      <div style="font-size:11px;color:#3F5249;margin-top:20px;">© ${new Date().getFullYear()} Productivitwo</div>
    </td></tr>
  </table>
</body>
</html>`;
}
// Throttle anti-abus : max 5 envois / heure / adresse email (endpoint public).
async function checkMagicLinkThrottle(email) {
    var _a, _b, _c, _d;
    const id = (0, crypto_1.createHmac)("sha256", "magic-link-throttle").update(email).digest("hex").slice(0, 40);
    const ref = db_1.db.doc(`magic_link_throttle/${id}`);
    const now = Date.now();
    const HOUR_MS = 60 * 60 * 1000;
    const snap = await ref.get();
    const data = ((_a = snap.data()) !== null && _a !== void 0 ? _a : {});
    const expired = now - ((_b = data.windowStart) !== null && _b !== void 0 ? _b : now) >= HOUR_MS;
    const count = expired ? 0 : ((_c = data.count) !== null && _c !== void 0 ? _c : 0);
    if (count >= 5)
        return true;
    await ref.set({ count: count + 1, windowStart: expired ? now : ((_d = data.windowStart) !== null && _d !== void 0 ? _d : now) }, { merge: true });
    return false;
}
exports.sendMagicLink = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["SENDGRID_API_KEY"] }, async (req, res) => {
    var _a, _b, _c;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const { email, continueUrl } = req.body;
    const cleanEmail = (email !== null && email !== void 0 ? email : "").trim().toLowerCase();
    if (!cleanEmail || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(cleanEmail)) {
        res.status(400).json({ error: "Adresse email invalide" });
        return;
    }
    // Accès réservé (beta) : compte déjà provisionné (acheteur formation ou
    // connexion antérieure) OU email pré-autorisé dans la collection `allowlist`
    // (ajoute un doc `allowlist/{email}` pour inviter un beta-testeur).
    // Les inconnus sont bloqués → funnel contrôlé, pas de compte fantôme.
    let authorized = false;
    try {
        await admin.auth().getUserByEmail(cleanEmail);
        authorized = true;
    }
    catch (_d) {
        const allow = await db_1.db.collection("allowlist").doc(cleanEmail).get();
        authorized = allow.exists;
    }
    if (!authorized) {
        res.status(403).json({
            code: "NO_ACCESS",
            error: "Cet email n'a pas encore accès — il est réservé à la formation pour le moment.",
        });
        return;
    }
    const apiKey = process.env.SENDGRID_API_KEY;
    if (!apiKey) {
        res.status(500).json({ error: "SENDGRID_API_KEY non configurée" });
        return;
    }
    if (await checkMagicLinkThrottle(cleanEmail)) {
        res.status(429).json({ error: "Trop de demandes. Réessaie dans une heure." });
        return;
    }
    try {
        const url = continueUrl && continueUrl.startsWith("https://")
            ? continueUrl
            : MAGIC_DEFAULT_CONTINUE_URL;
        const link = await admin.auth().generateSignInWithEmailLink(cleanEmail, {
            url,
            handleCodeInApp: true,
        });
        sgMail.setApiKey(apiKey);
        await sgMail.send({
            to: cleanEmail,
            from: { email: MAGIC_FROM_EMAIL, name: MAGIC_FROM_NAME },
            subject: "Ton lien de connexion Productivitwo",
            text: `Connecte-toi à Productivitwo en ouvrant ce lien :\n\n${link}\n\n` +
                `Tu n'as pas demandé cette connexion ? Ignore cet email.`,
            html: magicLinkEmailHtml(link),
        });
        res.status(200).json({ ok: true });
    }
    catch (e) {
        console.error("sendMagicLink error:", (_c = (_b = (_a = e === null || e === void 0 ? void 0 : e.response) === null || _a === void 0 ? void 0 : _a.body) !== null && _b !== void 0 ? _b : e === null || e === void 0 ? void 0 : e.message) !== null && _c !== void 0 ? _c : e);
        res.status(500).json({ error: "Envoi impossible" });
    }
});
// ── mcpHandler ────────────────────────────────────────────────────────────────
//
// URL : /mcp/{uid} + header `Authorization: Bearer <token>` (recommandé — un
// token dans l'URL finit dans les logs proxy/CDN), OU /mcp/{uid}/{token}
// (legacy, conservé pour les connecteurs déjà configurés).
// Protocole MCP JSON-RPC 2.0 (Streamable HTTP, stateless).
exports.mcpHandler = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["ANTHROPIC_API_KEY"] }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _l, _m, _o, _p, _q, _r;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    const parts = (req.path || "").replace(/^\/+mcp\/*/, "").split("/");
    const uid = parts[0] || "";
    const authHeader = (_a = req.headers["authorization"]) === null || _a === void 0 ? void 0 : _a.trim();
    const headerToken = (authHeader === null || authHeader === void 0 ? void 0 : authHeader.startsWith("Bearer ")) ? authHeader.slice(7).trim() : "";
    const token = headerToken || parts[1] || "";
    if (!uid || !token) {
        res.status(401).json({ error: "Auth requise — /mcp/{uid} + header Authorization: Bearer <token> (ou /mcp/{uid}/{token})" });
        return;
    }
    const valid = await (0, execute_1.validateToken)(uid, token);
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    const body = req.body;
    const requests = Array.isArray(body) ? body : [body];
    const responses = [];
    for (const rpc of requests) {
        const id = (_b = rpc.id) !== null && _b !== void 0 ? _b : null;
        const method = (_c = rpc.method) !== null && _c !== void 0 ? _c : "";
        if (id === null && method.startsWith("notifications/"))
            continue;
        if (method === "initialize") {
            responses.push({
                jsonrpc: "2.0", id,
                result: {
                    protocolVersion: "2024-11-05",
                    capabilities: { tools: {}, prompts: {} },
                    serverInfo: { name: "productivitwo", version: "1.0.0" },
                },
            });
        }
        else if (method === "ping") {
            responses.push({ jsonrpc: "2.0", id, result: {} });
        }
        else if (method === "prompts/list") {
            responses.push({ jsonrpc: "2.0", id, result: { prompts: prompts_1.MCP_PROMPTS } });
        }
        else if (method === "prompts/get") {
            const promptName = (_e = (_d = rpc.params) === null || _d === void 0 ? void 0 : _d.name) !== null && _e !== void 0 ? _e : "";
            const promptArgs = (_g = (_f = rpc.params) === null || _f === void 0 ? void 0 : _f.arguments) !== null && _g !== void 0 ? _g : {};
            const prompt = prompts_1.MCP_PROMPTS.find((p) => p.name === promptName);
            if (!prompt) {
                responses.push({ jsonrpc: "2.0", id, error: { code: -32601, message: `Prompt inconnu : ${promptName}` } });
            }
            else {
                responses.push({
                    jsonrpc: "2.0", id,
                    result: { description: prompt.description, messages: (0, prompts_1.getPromptMessages)(promptName, promptArgs) },
                });
            }
        }
        else if (method === "tools/list") {
            responses.push({
                jsonrpc: "2.0", id,
                result: {
                    tools: [
                        tools_1.GET_USER_CONTEXT_TOOL, tools_1.GET_DAY_BLOCKS_TOOL,
                        tools_1.LIST_PROJECTS_TOOL, tools_1.GET_PROJECT_TOOL, tools_1.PUSH_GANTT_MCP_TOOL,
                        tools_1.ARCHIVE_PROJECT_TOOL, tools_1.DELETE_PROJECT_TOOL, tools_1.UPDATE_ACTIVITY_GOAL_TOOL,
                        tools_1.SET_ACTIVITY_TARGETS_TOOL, tools_1.COMPUTE_TIME_BUDGET_TOOL, tools_1.SWEEP_INBOX_TOOL,
                        tools_1.PROPOSE_CHANGE_TOOL,
                        tools_1.CREATE_ROUTINE_TOOL, tools_1.DELETE_ROUTINE_TOOL,
                        tools_1.CREATE_ACTIVITY_TOOL, tools_1.UPDATE_ACTIVITY_TOOL, tools_1.UPDATE_TASK_STATUS_TOOL,
                        tools_1.UPDATE_PROJECT_TOOL, tools_1.DELETE_ACTIVITY_TOOL,
                        tools_1.GET_DOCUMENT_TEMPLATE_TOOL, tools_1.SAVE_DOCUMENT_TOOL, tools_1.GET_DOCUMENTS_TOOL,
                        tools_1.DELETE_DOCUMENT_TOOL, tools_1.GET_ARCHIVES_TOOL, tools_1.RESTORE_ITEM_TOOL,
                        tools_1.CREATE_DOMAIN_TOOL, tools_1.DELETE_DOMAIN_TOOL, tools_1.PUSH_ASSISTANT_MESSAGE_TOOL,
                        tools_1.GET_ASSISTANT_MESSAGES_TOOL, tools_1.DELETE_ASSISTANT_MESSAGE_TOOL,
                        tools_1.GET_DAY_SCHEDULE_TOOL, tools_1.SCHEDULE_DAY_TOOL, tools_1.ADD_PREP_BLOCK_TOOL,
                        tools_1.SAVE_DOMAIN_DEFINITION_TOOL,
                        tools_1.PLAN_DAY_TOOL, tools_1.PLAN_WEEK_TOOL, tools_1.SYNC_CALENDAR_TOOL,
                        tools_1.ADD_TASK_TOOL, tools_1.UPDATE_TASK_TOOL, tools_1.MARK_ACTION_DONE_TOOL,
                        tools_1.LINK_ACTION_TO_ACTIVITY_TOOL, tools_1.ADD_ACTIVITY_ACTION_TOOL,
                        tools_1.LOG_ROUTINE_HIT_TOOL, tools_1.MARK_BLOCK_DONE_TOOL,
                    ],
                },
            });
        }
        else if (method === "tools/call") {
            const rl = await (0, execute_1.checkRateLimit)(uid, "mcpToolCall", 100);
            if (rl.limited) {
                responses.push({ jsonrpc: "2.0", id, error: { code: -32000, message: `Rate limit dépassé — réessaie dans ${rl.retryAfterSecs}s` } });
                continue;
            }
            const toolName = (_j = (_h = rpc.params) === null || _h === void 0 ? void 0 : _h.name) !== null && _j !== void 0 ? _j : "";
            const args = (_m = (_l = rpc.params) === null || _l === void 0 ? void 0 : _l.arguments) !== null && _m !== void 0 ? _m : {};
            try {
                let text = "";
                if (toolName === "get_user_context") {
                    text = await (0, execute_1.executeGetUserContext)(uid);
                }
                else if (toolName === "get_day_blocks") {
                    text = await (0, execute_1.executeGetDayBlocks)(uid);
                }
                else if (toolName === "list_projects") {
                    text = await (0, execute_1.executeListProjects)(uid);
                }
                else if (toolName === "get_project") {
                    text = await (0, execute_1.executeGetProject)(uid, args.projectId);
                }
                else if (toolName === "push_gantt") {
                    text = await (0, execute_1.executePushGantt)(uid, Object.assign({ uid }, args));
                }
                else if (toolName === "update_project") {
                    text = await (0, execute_1.executeUpdateProject)(uid, args.projectId, args);
                }
                else if (toolName === "update_task_status") {
                    text = await (0, execute_1.executeUpdateTaskStatus)(uid, args.projectId, args.taskId, args.status);
                }
                else if (toolName === "archive_project") {
                    text = await (0, execute_1.executeArchiveProject)(uid, args.projectId, (_o = args.restore) !== null && _o !== void 0 ? _o : false);
                }
                else if (toolName === "delete_project") {
                    text = await (0, execute_1.executeDeleteProject)(uid, args.projectId, (_p = args.deleteObjective) !== null && _p !== void 0 ? _p : false);
                }
                else if (toolName === "create_activity") {
                    text = await (0, execute_1.executeCreateActivity)(uid, args);
                }
                else if (toolName === "update_activity") {
                    text = await (0, execute_1.executeUpdateActivity)(uid, args.activityId, args);
                }
                else if (toolName === "update_activity_goal") {
                    text = await (0, execute_1.executeUpdateActivityGoal)(uid, args.activityId, args);
                }
                else if (toolName === "set_activity_targets") {
                    text = await (0, execute_1.executeSetActivityTargets)(uid, args);
                }
                else if (toolName === "compute_time_budget") {
                    text = await (0, execute_1.executeComputeTimeBudget)(uid);
                }
                else if (toolName === "sweep_inbox") {
                    const r = await (0, orion_inbox_1.processInboxToProjects)(uid, { force: true });
                    text = r
                        ? `✅ Inbox balayée (uid ${uid}) : ${r.found} idée(s) trouvée(s) → ${r.created} projet(s) créé(s), ${r.appended} tâche(s) ajoutée(s), ${r.skipped} idée(s) laissée(s).`
                        : "Routage indisponible (erreur LLM). Réessaie.";
                }
                else if (toolName === "propose_change") {
                    // Exposé au connecteur MCP distant (routine mails → propositions à valider)
                    text = await (0, execute_1.executeProposeChange)(uid, args);
                }
                else if (toolName === "delete_activity") {
                    text = await (0, execute_1.executeDeleteActivity)(uid, args.activityId);
                }
                else if (toolName === "create_routine") {
                    text = await (0, execute_1.executeCreateRoutine)(uid, args);
                }
                else if (toolName === "delete_routine") {
                    text = await (0, execute_1.executeDeleteRoutine)(uid, args.routineId);
                }
                else if (toolName === "create_domain") {
                    text = await (0, execute_1.executeCreateDomain)(uid, args);
                }
                else if (toolName === "delete_domain") {
                    text = await (0, execute_1.executeDeleteDomain)(uid, args.domainId);
                }
                else if (toolName === "get_document_template") {
                    text = (0, prompts_1.executeGetDocumentTemplate)();
                }
                else if (toolName === "save_document") {
                    text = await (0, execute_1.executeSaveDocument)(uid, args);
                }
                else if (toolName === "get_documents") {
                    text = await (0, execute_1.executeGetDocuments)(uid, args.projectId, args.taskId);
                }
                else if (toolName === "delete_document") {
                    const ref = db_1.db.collection(`users/${uid}/documents`).doc(args.documentId);
                    const snap = await ref.get();
                    if (!snap.exists) {
                        text = `Document introuvable : ${args.documentId}`;
                    }
                    else {
                        const title = (_r = (_q = snap.data()) === null || _q === void 0 ? void 0 : _q.title) !== null && _r !== void 0 ? _r : args.documentId;
                        await ref.update({ deleted: true });
                        text = `✅ Document "${title}" supprimé.`;
                    }
                }
                else if (toolName === "get_archives") {
                    text = await (0, execute_1.executeGetArchives)(uid);
                }
                else if (toolName === "restore_item") {
                    text = await (0, execute_1.executeRestoreItem)(uid, args.collection, args.itemId);
                }
                else if (toolName === "push_assistant_message") {
                    text = await (0, execute_1.executePushAssistantMessage)(uid, args);
                }
                else if (toolName === "get_assistant_messages") {
                    text = await (0, execute_1.executeGetAssistantMessages)(uid);
                }
                else if (toolName === "delete_assistant_message") {
                    text = await (0, execute_1.executeDeleteAssistantMessage)(uid, args.messageId);
                }
                else if (toolName === "get_day_schedule") {
                    text = await (0, execute_1.executeGetDaySchedule)(uid, args.date);
                }
                else if (toolName === "schedule_day") {
                    text = await (0, execute_1.executeScheduleDay)(uid, args.date, args.blocks);
                }
                else if (toolName === "add_prep_block") {
                    text = await (0, execute_1.executeAddPrepBlock)(uid, args);
                }
                else if (toolName === "save_domain_definition") {
                    text = await (0, execute_1.executeSaveDomainDefinition)(uid, args);
                }
                else if (toolName === "plan_day") {
                    text = await (0, execute_1.executePlanDay)(uid, args);
                }
                else if (toolName === "plan_week") {
                    text = await (0, execute_1.executePlanWeek)(uid, args);
                }
                else if (toolName === "sync_calendar") {
                    text = await (0, execute_1.executeSyncCalendar)(uid, args.date);
                }
                else if (toolName === "add_task") {
                    text = await (0, execute_1.executeAddTask)(uid, args.projectId, args);
                }
                else if (toolName === "update_task") {
                    text = await (0, execute_1.executeUpdateTask)(uid, args.projectId, args.taskId, args);
                }
                else if (toolName === "mark_action_done") {
                    text = await (0, execute_1.executeMarkActionDone)(uid, args.projectId, args.taskId, args.actionId, args.done);
                }
                else if (toolName === "link_action_to_activity") {
                    text = await (0, execute_1.executeLinkActionToActivity)(uid, args.projectId, args.taskId, args.actionId, args.activityId);
                }
                else if (toolName === "add_activity_action") {
                    text = await (0, execute_1.executeAddActivityAction)(uid, args.activityId, args.title);
                }
                else if (toolName === "log_routine_hit") {
                    text = await (0, execute_1.executeLogRoutineHit)(uid, args.activityId, args.delta === undefined ? 1 : args.delta);
                }
                else if (toolName === "mark_block_done") {
                    text = await (0, execute_1.executeMarkBlockDone)(uid, args.date, args.blockId, args.done === undefined ? true : args.done);
                }
                else {
                    responses.push({ jsonrpc: "2.0", id, error: { code: -32601, message: `Outil inconnu : ${toolName}` } });
                    continue;
                }
                responses.push({ jsonrpc: "2.0", id, result: { content: [{ type: "text", text }] } });
            }
            catch (e) {
                const msg = e instanceof Error ? e.message : String(e);
                responses.push({ jsonrpc: "2.0", id, result: { content: [{ type: "text", text: `Erreur : ${msg}` }], isError: true } });
            }
        }
        else {
            responses.push({ jsonrpc: "2.0", id, error: { code: -32601, message: `Méthode inconnue : ${method}` } });
        }
    }
    res.setHeader("Content-Type", "application/json");
    res.status(200).json(responses.length === 1 ? responses[0] : responses);
});
// ── orionWebhook ──────────────────────────────────────────────────────────────
//
// POST https://orionwebhook-dzos75b65q-uc.a.run.app
// Body: { uid, token }
// Déclenché par l'app sur actions clés (save config, tâche validée, réponse user)
exports.orionWebhook = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["ANTHROPIC_API_KEY"] }, async (req, res) => {
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const { uid, token, taskId } = req.body;
    if (!uid || !token) {
        res.status(400).json({ error: "uid et token requis" });
        return;
    }
    const valid = await (0, execute_1.validateToken)(uid, token);
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    try {
        if (taskId) {
            // Tâche déterministe — pas d'appel LLM, coût $0
            const result = await (0, orion_tasks_1.runDeterministicTask)(uid, taskId);
            await (0, orion_1.writeCycleLog)(uid, Object.assign(Object.assign({ userNeeds: `[déterministe] ${taskId}`, userReply: "" }, result), { skipped: result.skipped }));
            res.status(200).json(Object.assign({ success: true }, result));
        }
        else {
            const result = await (0, orion_1.runOrionCycle)(uid);
            res.status(200).json(Object.assign({ success: true }, result));
        }
    }
    catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error(`ORION webhook erreur uid=${uid}:`, msg);
        res.status(500).json({ error: msg });
    }
});
// ── orionSaveConfig ───────────────────────────────────────────────────────────
//
// POST { uid, token, userNeeds?, userReply? }
// Sauvegarde la config ORION puis déclenche un cycle.
// ── githubWebhook — notif push quand une PR est ouverte ─────────────────────
//
// Configuré dans GitHub (repo Settings → Webhooks), content-type application/json,
// event "Pull requests". Vérifie X-Hub-Signature-256 (HMAC du rawBody avec
// GITHUB_WEBHOOK_SECRET), puis pousse une notif FCM au dev (uid = GITHUB_NOTIFY_UID).
function verifyGithubSignature(raw, header, secret) {
    if (!secret || !header.startsWith("sha256="))
        return false;
    const expected = "sha256=" + (0, crypto_1.createHmac)("sha256", secret).update(raw).digest("hex");
    const a = Buffer.from(header);
    const b = Buffer.from(expected);
    return a.length === b.length && (0, crypto_1.timingSafeEqual)(a, b);
}
/// Comparaison de secrets en temps constant (via digest sha256 : gère les
/// longueurs différentes sans fuite de timing). À utiliser pour TOUTE
/// vérification de secret partagé — jamais `===` sur le secret brut.
function secretsMatch(provided, expected) {
    const p = (provided !== null && provided !== void 0 ? provided : "").trim();
    const e = (expected !== null && expected !== void 0 ? expected : "").trim();
    if (!p || !e)
        return false;
    const hp = (0, crypto_1.createHash)("sha256").update(p).digest();
    const he = (0, crypto_1.createHash)("sha256").update(e).digest();
    return (0, crypto_1.timingSafeEqual)(hp, he);
}
exports.githubWebhook = (0, https_1.onRequest)({ invoker: "public", secrets: ["GITHUB_WEBHOOK_SECRET"] }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g;
    if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
    }
    const secret = (_a = process.env.GITHUB_WEBHOOK_SECRET) !== null && _a !== void 0 ? _a : "";
    const sig = (_b = req.get("x-hub-signature-256")) !== null && _b !== void 0 ? _b : "";
    const raw = req.rawBody;
    if (!raw || !verifyGithubSignature(raw, sig, secret)) {
        res.status(401).send("Invalid signature");
        return;
    }
    if (req.get("x-github-event") !== "pull_request") {
        res.status(200).send("ignored");
        return;
    }
    const body = req.body;
    if (body.action !== "opened" && body.action !== "ready_for_review") {
        res.status(200).send("ignored");
        return;
    }
    const uid = process.env.GITHUB_NOTIFY_UID;
    if (uid) {
        const num = (_c = body.number) !== null && _c !== void 0 ? _c : 0;
        const title = (_e = (_d = body.pull_request) === null || _d === void 0 ? void 0 : _d.title) !== null && _e !== void 0 ? _e : "";
        const url = (_g = (_f = body.pull_request) === null || _f === void 0 ? void 0 : _f.html_url) !== null && _g !== void 0 ? _g : "";
        await (0, execute_1.sendFcmPush)(uid, `📥 PR #${num} à valider`, title, { type: "github_pr", url });
    }
    res.status(200).send("ok");
});
exports.orionSaveConfig = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["ANTHROPIC_API_KEY"] }, async (req, res) => {
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const { uid, token, userNeeds, userReply, isOnboarding } = req.body;
    if (!uid || !token) {
        res.status(400).json({ error: "uid et token requis" });
        return;
    }
    const valid = await (0, execute_1.validateToken)(uid, token);
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    await (0, orion_1.saveOrionConfig)(uid, { userNeeds, userReply });
    try {
        const result = await (0, orion_1.runOrionCycle)(uid, { skipCount: isOnboarding === true });
        res.status(200).json(Object.assign({ success: true, configSaved: true }, result));
    }
    catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error(`ORION saveConfig erreur uid=${uid}:`, msg);
        res.status(500).json({ error: msg });
    }
});
// ── orionRunCount ─────────────────────────────────────────────────────────────
//
// GET ?uid=&token= — retourne le nombre de cycles ORION du jour
exports.orionRunCount = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    const uid = (_a = req.query.uid) !== null && _a !== void 0 ? _a : "";
    const token = (_b = req.query.token) !== null && _b !== void 0 ? _b : "";
    if (!uid || !token) {
        res.status(400).json({ error: "uid et token requis" });
        return;
    }
    const valid = await (0, execute_1.validateToken)(uid, token);
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    const today = (0, execute_1.todayInParis)();
    const count = await (0, orion_1.getOrionRunCount)(uid, today);
    res.status(200).json({ count, max: 5, date: today });
});
// ── ORION Brief (v2) ──────────────────────────────────────────────────────────
// Auth via Firebase ID token. Une seule fonction, méthode dans le body :
//   { action: "getBrief" | "setFocus" | "setFeedback", ... }
exports.orionBrief = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["ANTHROPIC_API_KEY"] }, async (req, res) => {
    var _a;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const authHeader = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
    }
    const idToken = authHeader.slice(7).trim();
    let uid;
    try {
        uid = (await admin.auth().verifyIdToken(idToken)).uid;
    }
    catch (_b) {
        res.status(401).json({ error: "Token invalide ou expiré" });
        return;
    }
    const { action, focus, feedback, date, limit } = req.body;
    try {
        if (action === "getFocus") {
            const f = await (0, orion_brief_1.getFocus)(uid);
            res.status(200).json({ focus: f });
            return;
        }
        if (action === "setFocus") {
            const newFocus = (focus !== null && focus !== void 0 ? focus : "").trim();
            if (!newFocus) {
                res.status(400).json({ error: "focus requis" });
                return;
            }
            if (newFocus.length > 280) {
                res.status(400).json({ error: "focus trop long (max 280)" });
                return;
            }
            await (0, orion_brief_1.setFocus)(uid, newFocus);
            res.status(200).json({ success: true, focus: newFocus });
            return;
        }
        if (action === "history") {
            const briefs = await (0, orion_brief_1.listBriefs)(uid, Math.min(limit !== null && limit !== void 0 ? limit : 30, 90));
            res.status(200).json({ briefs });
            return;
        }
        if (action === "setFeedback") {
            if (!date || !feedback) {
                res.status(400).json({ error: "date et feedback requis" });
                return;
            }
            if (feedback !== "useful" && feedback !== "skip") {
                res.status(400).json({ error: "feedback doit être 'useful' ou 'skip'" });
                return;
            }
            await (0, orion_brief_1.setBriefFeedback)(uid, date, feedback);
            res.status(200).json({ success: true });
            return;
        }
        // Default : getBrief
        const brief = await (0, orion_brief_1.getOrCreateBrief)(uid);
        res.status(200).json(brief);
    }
    catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        if (msg === "FOCUS_NOT_SET") {
            res.status(412).json({ code: "FOCUS_NOT_SET", error: "Définis ton focus du moment d'abord." });
            return;
        }
        console.error("orionBrief error:", msg);
        res.status(500).json({ error: msg });
    }
});
// ── orionCron — DÉSACTIVÉ (remplacé par orionBrief lazy-generation) ──────────
//
// L'ancien cycle ORION (avec les 20 conditions, messages dispersés) est mis en
// sommeil. La nouvelle expérience passe par `orionBrief` qui génère un brief
// quotidien à la demande quand l'utilisateur ouvre l'app.
//
// Le schedule est conservé mais le body retourne early — économise les tokens
// tout en gardant la structure pour rollback éventuel.
exports.orionCron = (0, scheduler_1.onSchedule)({ schedule: "every 24 hours", timeZone: "Europe/Paris", secrets: ["ANTHROPIC_API_KEY"] }, async () => {
    console.log("ORION cron (legacy) : désactivé — remplacé par orionBrief");
    return;
});
// ── structureProject ──────────────────────────────────────────────────────────
//
// POST https://structureproject-dzos75b65q-uc.a.run.app
// Headers: Authorization: Bearer <firebase-id-token>
// Body: { title, domainName?, domainId?, endDate (YYYY-MM-DD), ideas }
//
// Consomme 1 action stratégique ORION. Crée le projet structuré dans Firestore.
const STRUCTURE_MAX_RUNS = 5; // quota journalier dédié création de projets (partagé avec ORION)
exports.structureProject = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["ANTHROPIC_API_KEY"] }, async (req, res) => {
    var _a;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    // Auth via Firebase ID token
    const authHeader = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
    }
    const idToken = authHeader.slice(7).trim();
    let uid;
    try {
        const decoded = await admin.auth().verifyIdToken(idToken);
        uid = decoded.uid;
    }
    catch (_b) {
        res.status(401).json({ error: "Token invalide ou expiré" });
        return;
    }
    const { title, domainName, domainId, endDate, ideas } = req.body;
    if (!title || !endDate || !ideas) {
        res.status(400).json({ error: "Champs requis : title, endDate, ideas" });
        return;
    }
    // Quota journalier
    const today = (0, execute_1.todayInParis)();
    const count = await (0, orion_1.getOrionRunCount)(uid, today);
    if (count >= STRUCTURE_MAX_RUNS) {
        res.status(429).json({ error: `Limite journalière atteinte (${count}/${STRUCTURE_MAX_RUNS} actions stratégiques)` });
        return;
    }
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
        res.status(500).json({ error: "ANTHROPIC_API_KEY non configurée" });
        return;
    }
    // Appel Claude
    const client = new sdk_1.default({ apiKey });
    const prompt = `Tu es ORION, l'assistant stratégique de Productivitwo.
L'utilisateur crée un nouveau projet. Transforme ses idées brutes en plan structuré.

Titre : ${title}
${domainName ? `Domaine : ${domainName}` : ""}
Date cible : ${endDate}
Aujourd'hui : ${today}

Idées de l'utilisateur :
${ideas}

Génère un plan réaliste en JSON. Règles :
- 2 à 4 phases couvrant la période ${today} → ${endDate}
- 3 à 6 tâches par phase, formulées en verbe + objet
- 2 à 4 sous-actions par tâche (étapes concrètes et séquentielles, formulées comme des instructions courtes)
- isMilestone: true uniquement pour les livrables ou validations clés
- Toutes les dates entre ${today} et ${endDate}

Retourne UNIQUEMENT ce JSON valide, sans aucun texte autour :
{
  "phases": [
    { "label": "Nom de la phase", "startDate": "YYYY-MM-DD", "endDate": "YYYY-MM-DD" }
  ],
  "tasks": [
    { "title": "Verbe + action concrète", "phaseIndex": 0, "startDate": "YYYY-MM-DD", "endDate": "YYYY-MM-DD", "isMilestone": false, "actions": ["Étape 1", "Étape 2", "Étape 3"] }
  ]
}`;
    const structureModel = (0, models_1.getModel)("structure_project");
    const message = await client.messages.create({
        model: structureModel,
        max_tokens: 4096,
        messages: [{ role: "user", content: prompt }],
    });
    (0, models_1.logTokenUsage)("structure_project", structureModel, message.usage);
    const raw = message.content
        .filter((b) => b.type === "text")
        .map((b) => b.text)
        .join("")
        .trim();
    const jsonMatch = raw.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
        res.status(500).json({ error: "ORION n'a pas retourné de JSON valide" });
        return;
    }
    const structured = JSON.parse(jsonMatch[0]);
    // Construire le projet avec IDs
    const projectId = (0, uuid_1.v4)();
    const phases = structured.phases.map((p) => ({
        id: (0, uuid_1.v4)(),
        label: p.label,
        color: null,
        startDate: p.startDate,
        endDate: p.endDate,
    }));
    const tasks = structured.tasks.map((t) => {
        var _a, _b, _c, _d;
        return ({
            id: (0, uuid_1.v4)(),
            title: t.title,
            description: null,
            phaseId: (_b = (_a = phases[t.phaseIndex]) === null || _a === void 0 ? void 0 : _a.id) !== null && _b !== void 0 ? _b : null,
            groupLabel: null,
            startDate: t.startDate,
            endDate: t.endDate,
            isMilestone: (_c = t.isMilestone) !== null && _c !== void 0 ? _c : false,
            color: null,
            barLabel: null,
            status: "pending",
            actions: ((_d = t.actions) !== null && _d !== void 0 ? _d : []).map((a) => ({
                id: (0, uuid_1.v4)(),
                title: a,
                done: false,
                doneAt: null,
                createdAt: new Date().toISOString(),
            })),
        });
    });
    await db_1.db.collection(`users/${uid}/projects`).doc(projectId).set({
        id: projectId,
        title,
        description: null,
        strategicObjectiveId: null,
        domainId: domainId !== null && domainId !== void 0 ? domainId : null,
        startDate: today,
        endDate,
        status: "draft",
        phases,
        tasks,
        createdBy: uid,
        sourceType: "orion_mobile",
        createdAt: db_1.FieldValue.serverTimestamp(),
        updatedAt: db_1.FieldValue.serverTimestamp(),
    });
    // Consommer 1 action stratégique
    await (0, orion_1.incrementOrionRunCount)(uid, today);
    res.status(200).json({
        success: true,
        projectId,
        phasesCount: phases.length,
        tasksCount: tasks.length,
    });
});
// ── onboardingChat ────────────────────────────────────────────────────────────
//
// POST { token, message, history }
// Conversation multi-tours guidée par Claude pour co-construire la vision de
// vie de l'utilisateur et configurer Productivitwo en temps réel.
const REVISION_SYSTEM_PROMPT = `Tu es Productivitwo Guide en mode révision.

Aujourd'hui : {{TODAY}}

L'utilisateur a déjà fait son onboarding Productivitwo. Voici sa configuration actuelle :

{{CURRENT_CONFIG}}

━━━ TON RÔLE ━━━

Session courte (~20 min, 6-8 échanges). Aider l'utilisateur à faire évoluer sa vision et sa configuration — pas la refaire de zéro.

DÉROULÉ :
1. Ouvre avec UNE seule question : "Depuis ton dernier bilan, qu'est-ce qui a changé dans ta vie ou ta façon de voir les choses ?" — puis écoute vraiment.
2. Reformule les changements clés que tu entends (2-3 phrases max).
3. Propose des ajustements précis et limités : renommer un domaine, ajouter une activité, archiver ce qui n'est plus d'actualité, ajuster un projet Gantt.
4. Valide avec l'utilisateur avant chaque modification.
5. Maximum 3-4 changements par session — ne pas tout refaire, juste ce qui a vraiment bougé.

━━━ POUSSER LA RÉFLEXION (CRITIQUE) ━━━

Si l'utilisateur donne une réponse brève ou vague, NE WRAP PAS — creuse :
- "OK mais concrètement, qu'est-ce qui a bougé dans tes priorités du moment ?"
- "Ton focus principal a-t-il changé depuis le dernier bilan ?"
- "Y a-t-il un domaine que tu négliges et qui mérite plus d'attention ?"
- "Un projet qui a glissé ou pris une autre direction ?"
- "Une activité qui n'est plus pertinente et qu'il faudrait archiver ?"

Tu DOIS pousser au moins 2-3 questions avant d'envisager de clôturer. La valeur de la révision = forcer un vrai recul, pas valider que "tout va bien".

━━━ RÈGLES ABSOLUES ━━━

- NE RECRÉE JAMAIS ce qui existe déjà (vérifie la config ci-dessus)
- NE SUPPRIME / N'ARCHIVE rien sans que l'utilisateur l'ait dit explicitement
- Si un domaine doit être renommé : utilise update_domain
- Si un domaine n'est plus pertinent : utilise archive_domain (après validation)
- Si une nouvelle activité émerge : utilise create_activity liée au bon domaine existant
- Pour un projet existant : utilise update_project ou archive_project (PAS push_gantt qui crée un nouveau)

━━━ CLÔTURE (IMPORTANT) ━━━

Quand l'utilisateur indique qu'il a fait le tour ("c'est bon", "rien d'autre", "ça suffit"), termine par UN message de clôture spécifique à la révision — JAMAIS "ta configuration est prête" (ça c'était l'onboarding).

Modèles selon le cas :
- Si modifications effectuées : "Voilà tes ajustements appliqués : [récap court]. On se revoit pour la prochaine vision dans 30 jours pour faire un nouveau point."
- Si AUCUNE modification : "Pas de changement majeur depuis le dernier bilan — c'est aussi une info précieuse. Ton focus reste solide. On se revoit dans 30 jours."

━━━ STYLE ━━━

- Tutoiement naturel
- Bref — l'utilisateur connaît déjà l'outil
- Focalise sur les changements, pas sur la re-découverte
- NE DEMANDE PAS le prénom ni les informations de base — tu as déjà la config complète ci-dessus
- Commence directement avec ta question d'ouverture, sans introduction ni reformulation de la config`;
const REVISION_TOOLS = [
    {
        name: "update_domain",
        description: "Renomme ou recolore un domaine existant. Utilise le nom actuel du domaine.",
        input_schema: {
            type: "object",
            properties: {
                currentName: { type: "string", description: "Nom actuel exact du domaine" },
                newName: { type: "string", description: "Nouveau nom (si renommage)" },
                color: { type: "string", description: "Nouvelle couleur hex (si changement de couleur)" },
            },
            required: ["currentName"],
        },
    },
    {
        name: "archive_domain",
        description: "Archive (soft-delete) un domaine qui n'est plus pertinent. Uniquement sur demande explicite de l'utilisateur.",
        input_schema: {
            type: "object",
            properties: {
                name: { type: "string", description: "Nom exact du domaine à archiver" },
            },
            required: ["name"],
        },
    },
    {
        name: "create_domain",
        description: "Crée un nouveau domaine de vie (uniquement si vraiment nouveau).",
        input_schema: {
            type: "object",
            properties: {
                name: { type: "string" },
                color: { type: "string", description: "Couleur hex" },
            },
            required: ["name", "color"],
        },
    },
    {
        name: "create_activity",
        description: "Crée une nouvelle activité dans un domaine existant. type 'time' = suivi de durée (goalMin). type 'habit' = suivi de fréquence (habitFreq + habitTarget).",
        input_schema: {
            type: "object",
            properties: {
                name: { type: "string" },
                domainName: { type: "string", description: "Nom exact du domaine existant" },
                type: { type: "string", enum: ["time", "habit"] },
                goalMin: { type: "number", description: "Objectif quotidien en minutes (type time)" },
                habitFreq: { type: "string", enum: ["daily", "weekly", "monthly"], description: "Période de la fréquence (type habit)" },
                habitTarget: { type: "number", description: "Cible par période (type habit) — ex: 3 = 3×/semaine, 8 = 8×/jour, 1 = mensuel" },
                unit: { type: "string", description: "Unité optionnelle (ex: verres, pages, km)" },
            },
            required: ["name", "domainName", "type"],
        },
    },
    {
        name: "update_project",
        description: "Renomme, change le statut ou met à jour les dates d'un projet existant. Utilise l'id retourné dans la config.",
        input_schema: {
            type: "object",
            properties: {
                projectId: { type: "string", description: "id du projet (fourni dans la config injectée)" },
                title: { type: "string", description: "Nouveau titre (optionnel)" },
                description: { type: "string", description: "Nouvelle description (optionnel)" },
                startDate: { type: "string", description: "YYYY-MM-DD (optionnel)" },
                endDate: { type: "string", description: "YYYY-MM-DD (optionnel)" },
                status: { type: "string", enum: ["active", "archived", "completed"], description: "Nouveau statut (optionnel)" },
            },
            required: ["projectId"],
        },
    },
    {
        name: "archive_project",
        description: "Archive un projet (terminé ou abandonné). Soft-delete — récupérable.",
        input_schema: {
            type: "object",
            properties: {
                projectId: { type: "string", description: "id du projet (fourni dans la config injectée)" },
            },
            required: ["projectId"],
        },
    },
    {
        name: "add_task",
        description: "Ajoute une tâche à un projet existant (sans remplacer le projet entier).",
        input_schema: {
            type: "object",
            properties: {
                projectId: { type: "string" },
                title: { type: "string" },
                startDate: { type: "string", description: "YYYY-MM-DD" },
                endDate: { type: "string", description: "YYYY-MM-DD" },
                isMilestone: { type: "boolean" },
                actions: { type: "array", items: { type: "string" } },
            },
            required: ["projectId", "title", "startDate"],
        },
    },
    {
        name: "push_gantt",
        description: "Crée un NOUVEAU projet Gantt (uniquement si un objectif vraiment nouveau a émergé). Pour modifier un projet existant, utilise plutôt update_project.",
        input_schema: {
            type: "object",
            properties: {
                title: { type: "string" },
                startDate: { type: "string" },
                endDate: { type: "string" },
                phases: { type: "array", items: { type: "object", properties: { label: { type: "string" }, startDate: { type: "string" }, endDate: { type: "string" } } } },
                tasks: { type: "array", items: { type: "object", properties: { title: { type: "string" }, phaseIndex: { type: "number" }, startDate: { type: "string" }, endDate: { type: "string" }, isMilestone: { type: "boolean" }, actions: { type: "array", items: { type: "string" } } } } },
            },
            required: ["title", "startDate", "endDate", "phases", "tasks"],
        },
    },
];
const ONBOARDING_SYSTEM_PROMPT = `Tu es Productivitwo Guide — l'assistant d'onboarding personnel de Productivitwo.

Aujourd'hui : {{TODAY}}

{{USER_CONTEXT}}

Ta mission : conduire une conversation chaleureuse mais EFFICACE qui aboutit à un système Productivitwo réellement prêt à l'emploi — l'utilisateur doit pouvoir, dès l'ouverture de l'app, tracker concrètement ce qu'il fait.

Deux livrables comptent autant : (1) qu'il se sente vraiment compris, (2) qu'il reparte avec un VRAI système trackable (domaines + activités calibrées + 1er projet Gantt), pas un échantillon creux. Ces deux objectifs ne s'opposent PAS : garde une vraie conversation exploratoire et chaleureuse — c'est elle qui crée le sentiment d'écoute. Le "trop de blabla pour trop peu" se corrige en Phase 3, où cette écoute se convertit en un système réellement rempli (balayage des activités), PAS en raccourcissant l'exploration.

⚖️ DENSITÉ ADAPTATIVE — calibre-toi sur la personne, jamais sur un quota :
- Jauge son appétit en formulant le choix par la COUVERTURE, jamais par l'effort : "Tu veux qu'on capture TOUT ce que tu fais au quotidien (système complet), ou plutôt l'essentiel — quelques indicateurs clés pour démarrer ?" ⚠️ Ne dis JAMAIS "beaucoup d'activités" / "suivre en détail" : ça suggère à tort qu'il faudra cliquer davantage. Un système complet = il reflète ta vie, pas un surcroît de saisie (on logue seulement ce qu'on fait).
- Capture ce qu'elle fait VRAIMENT — n'invente pas pour remplir, ne plafonne pas un power-user non plus.
- Plafond souple : ~5 activités/domaine pendant l'onboarding (le reste s'ajoute dans l'app). Profil "essentiel" : 1-3 suffisent.
- Rappelle qu'on peut tout enrichir plus tard, à tout moment.

━━━ PHASES ━━━

PHASE 1 — ÉTAT PRÉSENT (4-5 échanges)
Explore la vie actuelle avec curiosité — c'est ce temps d'écoute qui fait que l'utilisateur se sent compris. Tu veux comprendre :
- Ses activités pro et perso au quotidien
- Ce qui lui prend du temps (subi vs choisi)
- Comment il structure (ou ne structure pas) sa semaine
- Ses frustrations d'organisation actuelles
Jauge aussi, au fil de l'échange, son appétit : système complet (capturer tout ce qu'il fait) vs essentiel (quelques indicateurs clés). Formule toujours par la couverture, pas par l'effort.
Pose 1-2 questions ouvertes par message. Écoute vraiment, reformule ce que tu comprends.
Ne passe pas à la Phase 2 tant que tu n'as pas une image claire et nuancée.

PHASE 2 — VISION FUTURE (3-4 échanges)
Explore ce qu'il veut construire dans les 6-12 prochains mois :
- Objectifs concrets (business, vie perso, santé, famille...)
- À quoi ressemblerait sa semaine idéale
- Ce qu'il veut arrêter / commencer / amplifier
Le delta entre Phase 1 et Phase 2 deviendra son premier projet Gantt.

PHASE 3 — STRUCTURATION PAR CATALOGUE DE DOMAINES (1 domaine à la fois)

ANNONCE D'OUVERTURE OBLIGATOIRE — commence la Phase 3 par ce message (adapte le ton, garde le fond) :
"Passons maintenant à la structure. On va explorer tes domaines de vie ensemble — jusqu'à 10 catégories, une par une. Pour chaque espace, je te propose quelques noms, tu choisis celui qui te parle ou tu donnes le tien.

Voici les catégories qu'on va parcourir :
Vie pro · Santé · Sport · Maison · Famille · Relations · Finances · Développement perso · Loisirs · Intériorité

Prends le temps qu'il te faut. Si tu dois t'arrêter, ta session est sauvegardée — tu peux revenir exactement là où on en est. Pour finir quand tu es prêt, dis-moi juste 'stop' ou 'c'est bon'.

On commence ?"

DÉROULÉ pour chaque domaine :
  1. Annonce le domaine, propose 4-5 noms + "Autre" → l'utilisateur choisit/valide. DÈS qu'il valide le nom → appelle set_structure_preview (le domaine apparaît dans la mindmap).
  2. BALAYAGE DES ACTIVITÉS — c'est ICI qu'on construit le vrai système trackable.
     Demande concrètement ce qu'il fait (ou veut suivre) dans ce domaine, avec les DEUX lentilles :
       • DURÉE (type "time") : ce qu'on mesure en temps — ex: Sport, Stratégie, Cuisiner → propose TOUJOURS un goalMin réaliste (infère une valeur sensée selon l'activité et ANNONCE-la, ex: "Cuisiner ~30 min/j", "Sieste ~20 min" ; l'utilisateur ajuste s'il veut). Ne laisse JAMAIS une activité temps sans durée.
       • FRÉQUENCE (type "habit") : ce qu'on coche — ex: Boire de l'eau (daily ×8), Footing (weekly ×3), Ménage (weekly), Laver la voiture (monthly) → habitFreq + habitTarget.
     Pour chaque activité, déduis la bonne lentille ; si habit, déduis fréquence + cible. Si une cible est importante et incertaine, demande — ne devine pas.
  3. Vise jusqu'à ~5 activités/domaine selon son appétit — sans remplir artificiellement, sans plafonner un power-user (il complétera dans l'app).
  4. Reformule la courte liste ("Dans X, tu suivras : … — ça te va ?"), puis passe au domaine suivant.

L'utilisateur peut dire "passe" pour sauter un domaine, "stop"/"c'est bon" pour valider et aller en Phase 4.
Maximum 6-7 domaines — propose de fusionner s'il en veut trop.

━━━ PAIRE FRÉQUENCE + TEMPS (PAR DÉFAUT) ━━━
Pour que l'utilisateur puisse tout tracer sans frustration ("je l'ai fait, mais où je note le temps ?"), dès qu'une habitude correspond à une action qui prend un temps mesurable, crée DEUX activités appairées :
  • FRÉQUENCE (type "habit") — forme VERBALE (l'action) : "Faire la vaisselle", "Boire de l'eau", "Lire", "Aller à la mer" → l'utilisateur coche.
  • TEMPS (type "time") — le NOM sans verbe (la chose) : "Vaisselle", "Hydratation", "Lecture", "Bain de mer" → l'utilisateur chronomètre.
C'est le comportement PAR DÉFAUT (ne demande pas à chaque fois ; mentionne-le brièvement une fois en début de balayage). N'appaire pas ce qui n'a aucune durée sensée (ex: peser son poids). Pour un appétit "essentiel", reste plus léger sur le doublement.

━━━ CAS SOMMEIL (et activités à très longue durée) ━━━
Si l'utilisateur veut suivre son SOMMEIL, crée un DOMAINE dédié "Sommeil" (et non une activité dans Santé). Raison : ~7-8h/nuit écraseraient le temps de toutes les autres activités du domaine et fausseraient sa vision du temps réellement réparti. Même logique pour toute activité au temps disproportionné.

━━━ MINDMAP LIVE (set_structure_preview) — APPEL FRÉQUENT, DÈS LE DÉBUT ━━━
L'utilisateur voit une mindmap se dessiner EN DIRECT à côté du chat. C'est OBLIGATOIRE et FRÉQUENT.
⚠️ IMPORTANT : set_structure_preview ne crée RIEN en base — c'est juste l'APERÇU VISUEL. La règle "ne rien créer avant validation" NE s'applique PAS à cet outil. Appelle-le LIBREMENT et SOUVENT, pendant toute la conversation, BIEN AVANT la Phase 4.
Quand l'appeler (envoie TOUJOURS la structure complète à jour) :
  - DÈS qu'un domaine est nommé/validé (même sans activités encore) → le domaine apparaît dans la mindmap.
  - Après le balayage des activités de chaque domaine (avec les paires fréquence/temps).
  - Après tout ajout/ajustement.
Mets center = le prénom de l'utilisateur si tu le connais, sinon "Ma vie". C'est le moment fort : voir sa vie s'organiser au fil de l'échange.

━━━ RÈGLE CRITIQUE — BESOIN ÉMOTIONNEL vs ACTIVITÉ TRACKABLE ━━━

Quand l'utilisateur exprime un ressenti (solitude, anxiété, manque, désir...) :
→ NE crée PAS automatiquement un domaine ou une activité pour "résoudre" ce ressenti.

Procédure en 3 temps :
  1. Accueille le ressenti simplement ("c'est important ce que tu partages...")
  2. DEMANDE si c'est quelque chose qu'il veut structurer : "Est-ce que tu veux en faire un espace de vie à suivre dans Productivitwo, ou c'est plutôt un désir de fond ?"
  3. Si OUI → creuse : "Qu'est-ce qui te viendrait comme indicateur concret ? Une sortie par semaine ? Du temps pour toi ? Des moments de plaisir ?" L'utilisateur choisit lui-même ce qu'il veut mesurer.
     Si NON → passe à la suite sans créer de domaine pour ce ressenti.

Exemple : "Je me sens seul" → NE PAS créer "Joie & Connexion" avec "Activité : Rencontres".
         → DEMANDER : "Tu as dit que tu veux plus de connexion. Tu veux qu'on en fasse un domaine à suivre, ou c'est un objectif de fond ?"

Un domaine doit répondre à la question : "est-ce que cette personne a des comportements concrets à tracker ici ?" Si la réponse est floue, demande.

━━━ CATALOGUE DES 10 DOMAINES DE VIE ━━━

1. VIE PROFESSIONNELLE
   Question : "Ton activité principale — comment tu gagnes ta vie ?"
   Noms : "Business" | "Travail" | "Vie pro" | "Mission" | Autre

2. SANTÉ & CORPS
   Question : "Ton énergie physique, ta santé — c'est quoi la réalité là ?"
   Noms : "Santé" | "Corps" | "Vitalité" | "Bien-être" | Autre
   (Si peu sportif : propose de fusionner Sport ici)

3. SPORT & MOUVEMENT
   Question : "Tu bouges comment ? Régulier, irrégulier, absent ?"
   Noms : "Sport" | "Mouvement" | "Fitness" | "Énergie physique" | Autre
   (Passe si déjà fusionné avec Santé)

4. MAISON & ENVIRONNEMENT
   Question : "Ton espace de vie — il te ressource ou il te pèse ?"
   Noms : "Maison" | "Foyer" | "Espace de vie" | "Environnement" | Autre

5. FAMILLE & PROCHES
   Question : "Ta famille, tes proches — c'est quoi la dynamique en ce moment ?"
   Noms : "Famille" | "Proches" | "Cercle proche" | "Liens familiaux" | Autre

6. VIE SOCIALE & RELATIONS
   Question : "Tes amis, ton réseau — nourris ou délaissés ?"
   Noms : "Social" | "Relations" | "Vie sociale" | "Amis & Réseau" | Autre

7. FINANCES
   Question : "Ta situation financière — sécurité, tension, ou flou ?"
   Noms : "Finances" | "Argent" | "Gestion financière" | "Patrimoine" | Autre

8. DÉVELOPPEMENT PERSONNEL
   Question : "Tu te formes, tu évolues — ou tu stagnes sur ce plan ?"
   Noms : "Développement" | "Croissance" | "Apprentissage" | "Évolution" | Autre

9. LOISIRS & RESSOURCEMENT
   Question : "Ce qui te fait du bien, te ressource — t'y accèdes comment ?"
   Noms : "Loisirs" | "Plaisirs" | "Ressourcement" | "Fun & Aventures" | Autre

10. INTÉRIORITÉ & MENTAL
    Question : "Ton mental, ta paix intérieure — c'est quoi le bruit de fond ?"
    Noms : "Mental" | "Intériorité" | "Spiritualité" | "Équilibre" | Autre

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️ NE CRÉE RIEN DANS PRODUCTIVITWO (create_domain, create_activity, push_gantt) AVANT QUE L'UTILISATEUR DISE "stop", "c'est bon", "go", "parfait" ou équivalent. (EXCEPTION : set_structure_preview — l'aperçu visuel — s'appelle librement et souvent AVANT validation ; il ne crée rien en base.)

PHASE 4 — CRÉATION (UN SEUL appel create_workspace, après validation)
La structure a été co-construite (domaines + activités + routines via le balayage ; projet présenté/validé si applicable). Pour tout créer, appelle **create_workspace UNE SEULE FOIS** avec l'ensemble :
- domains[] : chaque domaine avec SES activités.
- Pour chaque activité : type "time" (goalMin réaliste 15-30) OU type "habit" (TOUJOURS habitFreq daily/weekly/monthly + habitTarget ; jamais "daily ×1" par défaut sans raison).
- ⚠️ ROUTINES / PAIRES — ESSENTIEL, ne livre JAMAIS un système sans ses routines : pour chaque activité ayant une durée sensée, inclus la PAIRE — l'activité "time" (nom, ex "Vaisselle") ET la routine "habit" (verbe, ex "Faire la vaisselle") avec linkedActivityName = le nom de l'activité temps. ("Boire de l'eau" → linkedActivityName "Hydratation".) Pas de paire pour ce qui n'a pas de durée (ex: peser son poids).
- project (optionnel) : UNIQUEMENT si un objectif ~3 mois a été validé (cf. ci-dessous) — strategicObjective {title, kpiTarget}, phases, tasks (dates YYYY-MM-DD), durée ~3 mois.

⚠️ N'utilise PAS create_domain / create_activity / push_gantt séparément : create_workspace fait tout d'un coup (rapide, fiable).

DÉCISION PROJET (pendant la conversation, AVANT create_workspace) :
- Demande : "Y a-t-il un objectif concret que tu aimerais atteindre d'ici ~3 mois ?"
- Si OUI → présente le plan (phases = étapes + 3-5 tâches/phase) dans ta réponse texte ; le Gantt se dessine en direct sous le chat → laisse-le ajuster (1-2 échanges) → une fois validé, inclus ce projet dans l'appel create_workspace.
- Si NON/flou → pas de project ; dis-lui qu'il pourra en lancer un plus tard avec l'assistant.

Message final enthousiaste (juste après create_workspace) : annonce que le système est prêt, et explique la suite en 3 points :
   • Ouvre l'app et commence à tracker ce que tu fais.
   • Pour créer autant de projets Gantt que tu veux et aller plus loin au quotidien : connecte Claude depuis l'app web et travaille directement avec lui (il peut créer/ajuster tes projets, programmes, etc.).
   • Reviens ici dans "Vision" une fois par mois pour faire évoluer ta stratégie, tes domaines et tes activités.

━━━ STYLE ━━━
- Tutoiement naturel et chaleureux
- Phrases courtes, questions ouvertes
- Reformule avant de proposer (montre que tu as écouté)
- En Phase 3 : utilise une mise en forme claire pour les domaines proposés
- En Phase 4 : sois enthousiaste, c'est le moment fort de l'expérience
- TOUJOURS terminer ton tour par un message à l'utilisateur (au moins une phrase qui confirme/enchaîne, ex: "Noté ✓ — on continue ?"). Ne réponds JAMAIS uniquement par un appel d'outil silencieux : même quand tu mets à jour la mindmap, accompagne-le d'un mot.`;
const ONBOARDING_TOOLS = [
    {
        name: "create_domain",
        description: "Crée un domaine de vie dans Productivitwo. À appeler seulement après validation explicite de la structure par l'utilisateur.",
        input_schema: {
            type: "object",
            properties: {
                name: { type: "string", description: "Nom du domaine (reflète l'identité de l'utilisateur, pas générique)" },
                color: { type: "string", description: "Couleur hex cohérente avec le thème du domaine (ex: #4A90E2)" },
            },
            required: ["name", "color"],
        },
    },
    {
        name: "create_activity",
        description: "Crée une activité de tracking dans un domaine. Utilise le nom du domaine (pas son ID). 'time' = suivi de durée ; 'habit' = suivi de fréquence (routines, gestes quotidiens/hebdo/mensuels).",
        input_schema: {
            type: "object",
            properties: {
                name: { type: "string", description: "Nom de l'activité" },
                domainName: { type: "string", description: "Nom exact du domaine dans lequel créer l'activité" },
                type: { type: "string", enum: ["time", "habit"], description: "time = tracking durée, habit = tracking fréquence" },
                goalMin: { type: "number", description: "Objectif quotidien en minutes (type time)" },
                habitFreq: { type: "string", enum: ["daily", "weekly", "monthly"], description: "Période de la fréquence (type habit) — quotidien / hebdo / mensuel" },
                habitTarget: { type: "number", description: "Cible par période (type habit) — ex: 3 = 3×/semaine, 8 = 8×/jour, 1 = 1×/mois" },
                unit: { type: "string", description: "Unité optionnelle (ex: verres, pages, km)" },
                linkedActivityName: { type: "string", description: "Pour une ROUTINE appairée : le nom EXACT de l'activité TEMPS parente (déjà créée juste avant). Ex: routine 'Faire la vaisselle' → linkedActivityName 'Vaisselle'. Permet de retrouver la routine en lançant l'activité." },
            },
            required: ["name", "domainName", "type"],
        },
    },
    {
        name: "push_gantt",
        description: "Crée le premier projet Gantt représentant la progression état présent → vision future.",
        input_schema: {
            type: "object",
            properties: {
                title: { type: "string", description: "Titre du projet (personnalisé, pas générique)" },
                startDate: { type: "string", description: "YYYY-MM-DD (aujourd'hui)" },
                endDate: { type: "string", description: "YYYY-MM-DD (6-9 mois)" },
                strategicObjective: {
                    type: "object",
                    description: "Objectif stratégique = le RÉSULTAT visé du projet (le 'pourquoi', au-dessus des étapes/tâches). À fournir systématiquement.",
                    properties: {
                        title: { type: "string", description: "Le résultat visé formulé comme un cap (ex: 'Lancer mon activité de coaching')" },
                        kpiTarget: { type: "string", description: "Indicateur de succès mesurable (ex: '5 clients réguliers', '10k€/mois')" },
                    },
                    required: ["title"],
                },
                phases: {
                    type: "array",
                    items: {
                        type: "object",
                        properties: {
                            label: { type: "string" },
                            startDate: { type: "string" },
                            endDate: { type: "string" },
                        },
                    },
                },
                tasks: {
                    type: "array",
                    items: {
                        type: "object",
                        properties: {
                            title: { type: "string" },
                            phaseIndex: { type: "number" },
                            startDate: { type: "string" },
                            endDate: { type: "string" },
                            isMilestone: { type: "boolean" },
                            actions: { type: "array", items: { type: "string" } },
                        },
                    },
                },
            },
            required: ["title", "startDate", "endDate", "phases", "tasks"],
        },
    },
    {
        name: "set_structure_preview",
        description: "Met à jour la MINDMAP visuelle affichée à l'utilisateur EN LIVE pendant la conversation. Appelle-le dès que la structure proposée évolue (un domaine nommé, les activités d'un domaine balayées, un ajustement). Envoie TOUJOURS la structure COMPLÈTE et à jour (tous les domaines + activités connus jusque-là), jamais un delta.",
        input_schema: {
            type: "object",
            properties: {
                center: { type: "string", description: "Libellé du nœud central (prénom de l'utilisateur, ou 'Ma vie')" },
                domains: {
                    type: "array",
                    items: {
                        type: "object",
                        properties: {
                            name: { type: "string" },
                            activities: {
                                type: "array",
                                items: {
                                    type: "object",
                                    properties: {
                                        name: { type: "string" },
                                        type: { type: "string", enum: ["time", "habit"] },
                                        goalMin: { type: "number", description: "Minutes/jour visées (activités type 'time' uniquement, si une durée a été évoquée)" },
                                        parent: { type: "string", description: "Pour une routine appairée : nom de l'activité TEMPS parente (nichage visuel). Ex: 'Faire la vaisselle' → parent 'Vaisselle'." },
                                    },
                                },
                            },
                        },
                    },
                },
            },
            required: ["domains"],
        },
    },
    {
        name: "create_workspace",
        description: "Crée TOUTE la structure validée d'un seul coup (domaines + activités + routines + projet Gantt optionnel). À utiliser POUR L'ONBOARDING à la place de create_domain/create_activity/push_gantt : appelle-le UNE seule fois, après validation de l'utilisateur. Rapide et atomique. Déclenche la fin de l'onboarding.",
        input_schema: {
            type: "object",
            properties: {
                domains: {
                    type: "array",
                    items: {
                        type: "object",
                        properties: {
                            name: { type: "string" },
                            color: { type: "string", description: "Couleur hex optionnelle (ex: #4A90E2)" },
                            activities: {
                                type: "array",
                                items: {
                                    type: "object",
                                    properties: {
                                        name: { type: "string" },
                                        type: { type: "string", enum: ["time", "habit"] },
                                        goalMin: { type: "number", description: "Minutes/jour (type time)" },
                                        habitFreq: { type: "string", enum: ["daily", "weekly", "monthly"], description: "Période (type habit)" },
                                        habitTarget: { type: "number", description: "Cible par période (type habit) — ex: 3 = 3×/sem" },
                                        unit: { type: "string" },
                                        linkedActivityName: { type: "string", description: "Pour une ROUTINE : nom de l'activité temps parente (présente dans ce même appel)" },
                                    },
                                    required: ["name", "type"],
                                },
                            },
                        },
                        required: ["name"],
                    },
                },
                project: {
                    type: "object",
                    description: "Projet Gantt — seulement si un objectif ~3 mois a été validé.",
                    properties: {
                        title: { type: "string" },
                        startDate: { type: "string", description: "YYYY-MM-DD" },
                        endDate: { type: "string", description: "YYYY-MM-DD" },
                        strategicObjective: { type: "object", properties: { title: { type: "string" }, kpiTarget: { type: "string" } } },
                        phases: { type: "array", items: { type: "object", properties: { name: { type: "string" }, startDate: { type: "string" }, endDate: { type: "string" } } } },
                        tasks: { type: "array", items: { type: "object", properties: { name: { type: "string" }, phase: { type: "string" }, startDate: { type: "string" }, endDate: { type: "string" }, milestone: { type: "boolean" }, actions: { type: "array", items: { type: "string" } } } } },
                    },
                },
            },
            required: ["domains"],
        },
    },
    {
        name: "complete_onboarding",
        description: "Clôture l'onboarding une fois la structure créée (domaines + activités, et projet SI pertinent). À appeler en DERNIER, juste avant le message final. Marque la config comme terminée — indépendant de la création d'un projet.",
        input_schema: {
            type: "object",
            properties: {
                summary: { type: "string", description: "Récap en 1 phrase de ce qui a été mis en place (optionnel)" },
            },
        },
    },
];
async function executeOnboardingTool(uid, toolName, input, domainMap, activityMap = {}) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _l, _m, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x, _y, _z, _0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _10, _11;
    if (toolName === "create_workspace") {
        const ws = input;
        // Robustesse : le modèle envoie parfois `domains`/`project`/`activities` en string JSON
        // au lieu de tableaux/objets. Sans coercition, `for...of` sur une string itère caractère
        // par caractère → des milliers de docs sans nom (incident 2026-05-31 : 9987 domaines vides).
        // On coerce, on valide la forme, et on n'écrit JAMAIS un doc sans nom non vide.
        const coerce = (v) => {
            if (typeof v === "string") {
                try {
                    return JSON.parse(v);
                }
                catch (_a) {
                    return undefined;
                }
            }
            return v;
        };
        const asNamedArray = (v) => {
            const arr = coerce(v);
            if (!Array.isArray(arr))
                return [];
            return arr.filter((x) => !!x && typeof x === "object" && typeof x.name === "string" && x.name.trim().length > 0);
        };
        const domains = asNamedArray(ws.domains);
        // Garde-fou anti-emballement : un onboarding normal produit ~5-15 domaines.
        if (domains.length > 100) {
            return {
                notification: `⚠️ create_workspace ignoré (${domains.length} domaines — anormal)`,
                output: `Erreur : ${domains.length} domaines reçus, payload probablement malformé. Rien n'a été créé. Renvoie une structure normale (≤ ~15 domaines, en tableau JSON et non en chaîne).`,
            };
        }
        const project = coerce(ws.project);
        const batch = db_1.db.batch();
        const freqMap = { daily: 0, weekly: 1, monthly: 2 };
        const dMap = {};
        const aMap = {};
        let nDom = 0, nAct = 0;
        for (const d of domains) {
            const id = (0, uuid_1.v4)();
            dMap[d.name] = id;
            nDom++;
            batch.set(db_1.db.collection(`users/${uid}/domains`).doc(id), {
                id, name: d.name, goalMinDay: null, autoGoal: true,
                colorValue: d.color ? hexToColorValue(d.color) : null,
                createdAt: db_1.FieldValue.serverTimestamp(),
            });
        }
        const allActs = [];
        for (const d of domains)
            for (const a of asNamedArray(d.activities))
                allActs.push({ a, domainId: (_a = dMap[d.name]) !== null && _a !== void 0 ? _a : null });
        // 2 passes : activités temps d'abord (pour résoudre linkedActivityName), puis habitudes.
        for (const pass of ["time", "habit"]) {
            for (const { a, domainId } of allActs) {
                const isHabit = a.type === "habit";
                if ((pass === "time") === isHabit)
                    continue;
                const id = (0, uuid_1.v4)();
                aMap[a.name] = id;
                nAct++;
                batch.set(db_1.db.collection(`users/${uid}/activities`).doc(id), {
                    id, name: a.name, domainId,
                    type: isHabit ? "habit" : "time", role: "generic",
                    goalMin: (_b = a.goalMin) !== null && _b !== void 0 ? _b : 1, unit: (_c = a.unit) !== null && _c !== void 0 ? _c : null,
                    habitFreq: isHabit ? ((_e = freqMap[(_d = a.habitFreq) !== null && _d !== void 0 ? _d : "daily"]) !== null && _e !== void 0 ? _e : 0) : null,
                    habitTarget: isHabit ? ((_f = a.habitTarget) !== null && _f !== void 0 ? _f : 1) : null,
                    manualTarget: isHabit, autoTune: !isHabit,
                    linkedActivityId: a.linkedActivityName ? ((_g = aMap[a.linkedActivityName]) !== null && _g !== void 0 ? _g : null) : null,
                    createdAt: db_1.FieldValue.serverTimestamp(), lastTuneAt: null, order: 0, iconCode: null, deleted: false,
                });
            }
        }
        let projectMsg = "";
        if (project && project.title) {
            const arr = (v) => { const c = coerce(v); return Array.isArray(c) ? c : []; };
            const p = Object.assign(Object.assign({}, project), { phases: arr(project.phases), tasks: arr(project.tasks) });
            const today = (0, execute_1.todayInParis)();
            const projectId = (0, uuid_1.v4)();
            let strategicObjectiveId = null;
            if (p.strategicObjective && p.strategicObjective.title) {
                strategicObjectiveId = (0, uuid_1.v4)();
                batch.set(db_1.db.collection(`users/${uid}/strategic_objectives`).doc(strategicObjectiveId), {
                    id: strategicObjectiveId, title: p.strategicObjective.title, kpiTarget: (_h = p.strategicObjective.kpiTarget) !== null && _h !== void 0 ? _h : null,
                    description: null, domainId: null, horizonLabel: null,
                    startDate: (_j = p.startDate) !== null && _j !== void 0 ? _j : null, endDate: (_l = p.endDate) !== null && _l !== void 0 ? _l : null,
                    status: "active", projectIds: [projectId], createdAt: db_1.FieldValue.serverTimestamp(),
                });
            }
            const phases = ((_m = p.phases) !== null && _m !== void 0 ? _m : []).map((ph) => { var _a, _b, _c, _d; return ({ id: (0, uuid_1.v4)(), label: ph.name, color: null, startDate: (_b = (_a = ph.startDate) !== null && _a !== void 0 ? _a : p.startDate) !== null && _b !== void 0 ? _b : today, endDate: (_d = (_c = ph.endDate) !== null && _c !== void 0 ? _c : p.endDate) !== null && _d !== void 0 ? _d : today }); });
            const phaseIdByName = {};
            ((_o = p.phases) !== null && _o !== void 0 ? _o : []).forEach((ph, i) => { phaseIdByName[ph.name] = phases[i].id; });
            const tasks = ((_p = p.tasks) !== null && _p !== void 0 ? _p : []).map((t) => {
                var _a, _b, _c, _d, _e, _f;
                return ({
                    id: (0, uuid_1.v4)(), title: t.name,
                    phaseId: t.phase ? ((_a = phaseIdByName[t.phase]) !== null && _a !== void 0 ? _a : null) : null,
                    groupLabel: null, description: null,
                    startDate: (_c = (_b = t.startDate) !== null && _b !== void 0 ? _b : p.startDate) !== null && _c !== void 0 ? _c : today, endDate: (_d = t.endDate) !== null && _d !== void 0 ? _d : null,
                    isMilestone: (_e = t.milestone) !== null && _e !== void 0 ? _e : false, color: null, barLabel: null, status: "pending",
                    actions: ((_f = t.actions) !== null && _f !== void 0 ? _f : []).map((x) => ({ id: (0, uuid_1.v4)(), title: x, done: false, doneAt: null, createdAt: new Date().toISOString() })),
                });
            });
            batch.set(db_1.db.collection(`users/${uid}/projects`).doc(projectId), {
                id: projectId, title: p.title, description: null,
                strategicObjectiveId, domainId: null,
                startDate: (_q = p.startDate) !== null && _q !== void 0 ? _q : today, endDate: (_r = p.endDate) !== null && _r !== void 0 ? _r : null,
                status: "active", phases, tasks,
                createdBy: uid, sourceType: "formation_onboarding",
                createdAt: db_1.FieldValue.serverTimestamp(), updatedAt: db_1.FieldValue.serverTimestamp(),
            });
            projectMsg = " + 1 projet Gantt";
        }
        await batch.commit();
        return { notification: `✓ ${nDom} domaines, ${nAct} activités créés${projectMsg}`, output: `Workspace créé : ${nDom} domaines, ${nAct} activités${projectMsg}.` };
    }
    if (toolName === "create_domain") {
        const id = (0, uuid_1.v4)();
        const name = input.name;
        const colorVal = input.color ? hexToColorValue(input.color) : null;
        await db_1.db.collection(`users/${uid}/domains`).doc(id).set({
            id, name,
            goalMinDay: null, autoGoal: true,
            colorValue: colorVal,
            createdAt: db_1.FieldValue.serverTimestamp(),
        });
        domainMap[name] = id;
        return { notification: `✓ Domaine "${name}" créé`, output: `Domaine créé — id: ${id}` };
    }
    if (toolName === "create_activity") {
        const id = (0, uuid_1.v4)();
        const name = input.name;
        const domainName = input.domainName;
        const domainId = (_s = domainMap[domainName]) !== null && _s !== void 0 ? _s : null;
        const isHabit = input.type === "habit";
        const freqMap = { daily: 0, weekly: 1, monthly: 2 };
        const freqKey = (_t = input.habitFreq) !== null && _t !== void 0 ? _t : "daily";
        const habitFreq = isHabit ? ((_u = freqMap[freqKey]) !== null && _u !== void 0 ? _u : 0) : null;
        const habitTarget = isHabit ? ((_v = input.habitTarget) !== null && _v !== void 0 ? _v : 1) : null;
        // Si le guide a précisé fréquence/cible, on fige la cible (pas d'auto-tune qui l'écrase).
        const manualHabit = isHabit && (input.habitFreq !== undefined || input.habitTarget !== undefined);
        // Lien routine → activité temps parente (cf. linkedActivityId : "lancer l'activité → ses routines").
        const linkedName = input.linkedActivityName;
        const linkedActivityId = linkedName ? ((_w = activityMap[linkedName]) !== null && _w !== void 0 ? _w : null) : null;
        await db_1.db.collection(`users/${uid}/activities`).doc(id).set({
            id, name, domainId,
            type: isHabit ? "habit" : "time",
            role: "generic",
            goalMin: (_x = input.goalMin) !== null && _x !== void 0 ? _x : 1,
            unit: (_y = input.unit) !== null && _y !== void 0 ? _y : null,
            habitFreq,
            habitTarget,
            manualTarget: manualHabit,
            autoTune: !manualHabit,
            linkedActivityId,
            createdAt: db_1.FieldValue.serverTimestamp(),
            lastTuneAt: null, order: 0, iconCode: null, deleted: false,
        });
        activityMap[name] = id; // pour résoudre les liens des routines créées ensuite
        const detail = isHabit ? ` (${freqKey} ×${habitTarget})` : (input.goalMin ? ` (${input.goalMin}min/j)` : "");
        return { notification: `✓ Activité "${name}"${detail} créée`, output: `Activité créée — id: ${id}` };
    }
    if (toolName === "create_routine") {
        const id = (0, uuid_1.v4)();
        const name = input.name;
        const domainName = input.domainName;
        const domainId = (_z = domainMap[domainName]) !== null && _z !== void 0 ? _z : ((_0 = Object.values(domainMap)[0]) !== null && _0 !== void 0 ? _0 : null);
        await db_1.db.collection(`users/${uid}/activities`).doc(id).set({
            id, name, domainId,
            type: "habit", role: "generic",
            goalMin: (_1 = input.dureeMin) !== null && _1 !== void 0 ? _1 : 15,
            unit: null, habitFreq: 0, habitTarget: 1,
            manualTarget: false, autoTune: false,
            createdAt: db_1.FieldValue.serverTimestamp(),
            lastTuneAt: null, order: 0, iconCode: null, deleted: false,
        });
        return { notification: `✓ Routine "${name}" créée`, output: `Routine créée — id: ${id}` };
    }
    if (toolName === "push_gantt") {
        const projectId = (0, uuid_1.v4)();
        const ganttInput = input;
        const phases = ganttInput.phases.map((p) => ({ id: (0, uuid_1.v4)(), label: p.label, color: null, startDate: p.startDate, endDate: p.endDate }));
        const tasks = ganttInput.tasks.map((t) => {
            var _a, _b, _c, _d;
            return ({
                id: (0, uuid_1.v4)(), title: t.title,
                phaseId: (_b = (_a = phases[t.phaseIndex]) === null || _a === void 0 ? void 0 : _a.id) !== null && _b !== void 0 ? _b : null,
                groupLabel: null, description: null,
                startDate: t.startDate, endDate: t.endDate,
                isMilestone: (_c = t.isMilestone) !== null && _c !== void 0 ? _c : false,
                color: null, barLabel: null, status: "pending",
                actions: ((_d = t.actions) !== null && _d !== void 0 ? _d : []).map((a) => ({ id: (0, uuid_1.v4)(), title: a, done: false, doneAt: null, createdAt: new Date().toISOString() })),
            });
        });
        // Objectif stratégique (le résultat visé) — affiché en tête du Gantt
        let strategicObjectiveId = null;
        if ((_2 = ganttInput.strategicObjective) === null || _2 === void 0 ? void 0 : _2.title) {
            strategicObjectiveId = (0, uuid_1.v4)();
            await db_1.db.collection(`users/${uid}/strategic_objectives`).doc(strategicObjectiveId).set({
                id: strategicObjectiveId,
                title: ganttInput.strategicObjective.title,
                kpiTarget: (_3 = ganttInput.strategicObjective.kpiTarget) !== null && _3 !== void 0 ? _3 : null,
                description: null, domainId: null, horizonLabel: null,
                startDate: ganttInput.startDate, endDate: ganttInput.endDate,
                status: "active", projectIds: [projectId],
                createdAt: db_1.FieldValue.serverTimestamp(),
            });
        }
        await db_1.db.collection(`users/${uid}/projects`).doc(projectId).set({
            id: projectId, title: ganttInput.title,
            description: null, strategicObjectiveId, domainId: null,
            startDate: ganttInput.startDate, endDate: ganttInput.endDate,
            status: "active", phases, tasks,
            createdBy: uid, sourceType: "formation_onboarding",
            createdAt: db_1.FieldValue.serverTimestamp(), updatedAt: db_1.FieldValue.serverTimestamp(),
        });
        return { notification: `✓ Projet Gantt "${ganttInput.title}" créé`, output: `Projet créé — id: ${projectId}` };
    }
    if (toolName === "set_structure_preview") {
        return { notification: "", output: "Aperçu de la structure mis à jour." };
    }
    if (toolName === "complete_onboarding") {
        return { notification: "✓ Configuration terminée", output: "Onboarding marqué comme terminé." };
    }
    if (toolName === "update_domain") {
        const currentName = input.currentName;
        const newName = input.newName;
        const newColor = input.color;
        const domainId = domainMap[currentName];
        if (!domainId)
            return { notification: `Domaine "${currentName}" introuvable`, output: `Erreur: "${currentName}" pas dans le domainMap` };
        const updates = {};
        if (newName)
            updates.name = newName;
        if (newColor)
            updates.colorValue = hexToColorValue(newColor);
        if (Object.keys(updates).length > 0) {
            await db_1.db.collection(`users/${uid}/domains`).doc(domainId).update(updates);
        }
        if (newName) {
            domainMap[newName] = domainId;
            delete domainMap[currentName];
        }
        const label = newName ? `"${currentName}" → "${newName}"` : `"${currentName}"`;
        return { notification: `✓ Domaine ${label} mis à jour`, output: `Domaine mis à jour — id: ${domainId}` };
    }
    if (toolName === "archive_domain") {
        const name = input.name;
        const domainId = domainMap[name];
        if (!domainId)
            return { notification: `Domaine "${name}" introuvable`, output: "Erreur" };
        await db_1.db.collection(`users/${uid}/domains`).doc(domainId).update({ deleted: true });
        delete domainMap[name];
        return { notification: `✓ Domaine "${name}" archivé`, output: `Archivé — id: ${domainId}` };
    }
    if (toolName === "update_project") {
        const projectId = input.projectId;
        const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
        const snap = await ref.get();
        if (!snap.exists)
            return { notification: `Projet introuvable`, output: `Erreur: projet ${projectId} non trouvé` };
        const updates = { updatedAt: db_1.FieldValue.serverTimestamp() };
        if (input.title)
            updates.title = input.title;
        if (input.description)
            updates.description = input.description;
        if (input.startDate)
            updates.startDate = input.startDate;
        if (input.endDate)
            updates.endDate = input.endDate;
        if (input.status)
            updates.status = input.status;
        await ref.update(updates);
        const newTitle = (_6 = (_4 = input.title) !== null && _4 !== void 0 ? _4 : (_5 = snap.data()) === null || _5 === void 0 ? void 0 : _5.title) !== null && _6 !== void 0 ? _6 : projectId;
        return { notification: `✓ Projet "${newTitle}" mis à jour`, output: `Projet mis à jour` };
    }
    if (toolName === "archive_project") {
        const projectId = input.projectId;
        const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
        const snap = await ref.get();
        if (!snap.exists)
            return { notification: `Projet introuvable`, output: `Erreur` };
        const title = (_8 = (_7 = snap.data()) === null || _7 === void 0 ? void 0 : _7.title) !== null && _8 !== void 0 ? _8 : projectId;
        await ref.update({ status: "archived", updatedAt: db_1.FieldValue.serverTimestamp() });
        return { notification: `✓ Projet "${title}" archivé`, output: `Archivé` };
    }
    if (toolName === "add_task") {
        const projectId = input.projectId;
        const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
        const snap = await ref.get();
        if (!snap.exists)
            return { notification: `Projet introuvable`, output: `Erreur` };
        const newTask = {
            id: (0, uuid_1.v4)(),
            title: input.title,
            description: null,
            phaseId: null,
            groupLabel: null,
            startDate: input.startDate,
            endDate: (_9 = input.endDate) !== null && _9 !== void 0 ? _9 : null,
            isMilestone: (_10 = input.isMilestone) !== null && _10 !== void 0 ? _10 : false,
            color: null,
            barLabel: null,
            status: "pending",
            actions: ((_11 = input.actions) !== null && _11 !== void 0 ? _11 : []).map((a) => ({
                id: (0, uuid_1.v4)(), title: a, done: false, doneAt: null, createdAt: new Date().toISOString(),
            })),
        };
        await ref.update({
            tasks: db_1.FieldValue.arrayUnion(newTask),
            updatedAt: db_1.FieldValue.serverTimestamp(),
        });
        return { notification: `✓ Tâche "${newTask.title}" ajoutée`, output: `Tâche créée — id: ${newTask.id}` };
    }
    return { notification: "", output: `Outil inconnu : ${toolName}` };
}
// Mindmap (filet de sécurité, INCRÉMENTAL) : part de la structure connue + le dernier
// échange, renvoie la structure mise à jour. Input petit et constant (pas tout le
// transcript) → bien moins cher, et plus fiable (on ne perd rien).
async function extractStructurePreview(client, prevStructure, userMessage, assistantText) {
    try {
        const prevJson = JSON.stringify(prevStructure !== null && prevStructure !== void 0 ? prevStructure : { center: "Ma vie", domains: [] });
        const r = await client.messages.create({
            model: (0, models_1.getModel)("structure_preview"),
            max_tokens: 4096,
            system: "Tu maintiens une structure de vie pour une mindmap. On te donne la structure ACTUELLE (JSON) et le DERNIER échange. " +
                "Renvoie la structure MISE À JOUR en appliquant le dernier échange : AJOUTE les nouveaux éléments, RENOMME ou SUPPRIME ceux que l'utilisateur demande explicitement de changer/retirer, et conserve À L'IDENTIQUE tout le reste (ne perds rien par inadvertance). UNIQUEMENT du JSON, rien d'autre. " +
                "Format exact : {\"center\": string, \"domains\": [{\"name\": string, \"activities\": [{\"name\": string, \"type\": \"time\"|\"habit\", \"goalMin\": number, \"parent\": string}]}], \"gantt\": {\"title\": string, \"startDate\": \"YYYY-MM-DD\", \"endDate\": \"YYYY-MM-DD\", \"phases\": [{\"name\": string, \"startDate\": \"YYYY-MM-DD\", \"endDate\": \"YYYY-MM-DD\"}], \"tasks\": [{\"name\": string, \"phase\": string, \"startDate\": \"YYYY-MM-DD\", \"endDate\": \"YYYY-MM-DD\", \"milestone\": boolean}]}}. " +
                "type 'time' = durée (goalMin minutes/jour ; estime si non dit : cuisiner 30, sieste 20, sport 45, lecture 20) ; 'habit' = fréquence. " +
                "parent = pour une routine appairée à une activité temps, le nom de cette activité (ex: 'Faire la vaisselle' → parent 'Vaisselle'). Omets si pas de jumelle. " +
                "gantt = UNIQUEMENT si un objectif concret à ~3 mois, avec des étapes (phases) et des tâches, est en cours de construction. Sinon N'INCLUS PAS le champ gantt. 'phase' d'une tâche = le nom de sa phase parente. Dates au format YYYY-MM-DD. " +
                "center = prénom si connu, sinon \"Ma vie\". N'ajoute QUE des domaines/activités/éléments explicitement nommés/validés.",
            messages: [{ role: "user", content: `Structure actuelle:\n${prevJson}\n\nDernier échange:\nuser: ${userMessage}\nassistant: ${assistantText}\n\nRenvoie la structure mise à jour (JSON uniquement).` }],
        });
        (0, models_1.logTokenUsage)("structure_preview", (0, models_1.getModel)("structure_preview"), r.usage);
        const txt = r.content.filter((b) => b.type === "text").map((b) => b.text).join("");
        const m = txt.match(/\{[\s\S]*\}/);
        if (!m)
            return null;
        const parsed = JSON.parse(m[0]);
        if (parsed && Array.isArray(parsed.domains) && parsed.domains.length > 0)
            return parsed;
        return null;
    }
    catch (_) {
        return null;
    }
}
exports.onboardingChat = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["FORMATION_JWT_SECRET", "ANTHROPIC_API_KEY"], timeoutSeconds: 300, memory: "512MiB" }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const { token, message, history, userContext, action } = req.body;
    if (!token) {
        res.status(400).json({ error: "token requis" });
        return;
    }
    const decoded = verifyFormationToken(token, process.env.FORMATION_JWT_SECRET);
    if (!decoded) {
        res.status(401).json({ error: "Token invalide ou expiré" });
        return;
    }
    const { uid } = decoded;
    // ── Vérification statut onboarding ────────────────────────────────────────
    // Toujours chargé — sert pour checkSession, chat ET révision
    const accessDoc = await db_1.db.collection("formation_access").doc(uid).get();
    const accessData = (_a = accessDoc.data()) !== null && _a !== void 0 ? _a : {};
    const onboardingDone = accessData.onboardingDone === true;
    const isPro = (0, db_1.effectivePro)(accessData);
    // ── Actions hors-chat ─────────────────────────────────────────────────────
    if (action === "checkSession") {
        const snap = await db_1.db.collection("formation_sessions").doc(uid).get();
        const base = { onboardingDone, isPro };
        if (!snap.exists) {
            res.status(200).json(Object.assign(Object.assign({}, base), { hasSession: false }));
            return;
        }
        const data = snap.data();
        const savedAt = (_b = data.savedAt) === null || _b === void 0 ? void 0 : _b.toDate();
        const ageMs = savedAt ? Date.now() - savedAt.getTime() : Infinity;
        if (ageMs > 7 * 24 * 60 * 60 * 1000) {
            res.status(200).json(Object.assign(Object.assign({}, base), { hasSession: false }));
            return;
        }
        res.status(200).json(Object.assign(Object.assign({}, base), { hasSession: true, mode: (_c = data.mode) !== null && _c !== void 0 ? _c : "onboarding", history: (_d = data.history) !== null && _d !== void 0 ? _d : [], userContext: (_e = data.userContext) !== null && _e !== void 0 ? _e : null, turnCount: (_f = data.turnCount) !== null && _f !== void 0 ? _f : 0, savedAt: savedAt === null || savedAt === void 0 ? void 0 : savedAt.toISOString(), structure: (_g = data.structure) !== null && _g !== void 0 ? _g : null }));
        return;
    }
    if (action === "clearSession") {
        await db_1.db.collection("formation_sessions").doc(uid).delete();
        res.status(200).json({ cleared: true });
        return;
    }
    // ── Révision ──────────────────────────────────────────────────────────────
    if (action === "startRevision" || action === "revision_chat") {
        if (!isPro) {
            res.status(403).json({ code: "REVISION_PRO_REQUIRED" });
            return;
        }
        // Marque le début d'une nouvelle vision — déclenche le countdown 30j
        if (action === "startRevision") {
            await db_1.db.collection("formation_access").doc(uid).set({ lastVisionAt: db_1.FieldValue.serverTimestamp() }, { merge: true });
        }
        const apiKey2 = process.env.ANTHROPIC_API_KEY;
        if (!apiKey2) {
            res.status(500).json({ error: "ANTHROPIC_API_KEY manquante" });
            return;
        }
        const client2 = new sdk_1.default({ apiKey: apiKey2 });
        const today2 = (0, execute_1.todayInParis)();
        // Lecture config existante (pour startRevision ou premier tour)
        const [domainsSnap, activitiesSnap, projectsSnap] = await Promise.all([
            db_1.db.collection(`users/${uid}/domains`).get(),
            db_1.db.collection(`users/${uid}/activities`).get(),
            db_1.db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
        ]);
        // Construction par domaine pour que Claude voie bien les liens
        const liveDomains = domainsSnap.docs.filter(d => !d.data().deleted);
        const liveActivities = activitiesSnap.docs.filter(d => !d.data().deleted);
        const domainSections = [];
        for (const dom of liveDomains) {
            const dData = dom.data();
            const acts = liveActivities
                .filter(a => a.data().domainId === dom.id)
                .map(a => {
                const aData = a.data();
                const isHabit = aData.type === "habit";
                return `    · ${aData.name} (${isHabit ? "routine/habit" : "tracking temps"})`;
            });
            domainSections.push(`  · ${dData.name}\n${acts.length ? acts.join("\n") : "    (aucune activité)"}`);
        }
        // Activités orphelines (sans domaine ou domaine supprimé)
        const orphanActs = liveActivities
            .filter(a => !liveDomains.some(d => d.id === a.data().domainId))
            .map(a => `    · ${a.data().name} (${a.data().type === "habit" ? "routine/habit" : "tracking temps"})`);
        if (orphanActs.length) {
            domainSections.push(`  · (Activités sans domaine)\n${orphanActs.join("\n")}`);
        }
        const projectsList = projectsSnap.docs.map(d => {
            var _a, _b;
            const data = d.data();
            const tasks = (_a = data.tasks) !== null && _a !== void 0 ? _a : [];
            const done = tasks.filter(t => t.status === "done").length;
            const total = tasks.length;
            return `  · "${data.title}" (id: ${d.id}) — ${done}/${total} tâches, fin ${(_b = data.endDate) !== null && _b !== void 0 ? _b : "non définie"}`;
        }).join("\n");
        const currentConfig = `Domaines & activités :\n${domainSections.length ? domainSections.join("\n") : "  Aucun"}\n\nProjets actifs (utilise les id pour update_project/archive_project/add_task) :\n${projectsList || "  Aucun"}`;
        const revSystemPrompt = REVISION_SYSTEM_PROMPT
            .replace("{{TODAY}}", today2)
            .replace("{{CURRENT_CONFIG}}", currentConfig);
        // Pré-populer la domainMap avec les domaines existants
        const revDomainMap = {};
        for (const doc of domainsSnap.docs) {
            const d = doc.data();
            if (!d.deleted)
                revDomainMap[d.name] = doc.id;
        }
        const revMessages = [
            ...(history !== null && history !== void 0 ? history : []).map((m) => ({ role: m.role, content: m.content })),
            { role: "user", content: action === "startRevision" ? "Je suis prêt pour ma session de révision." : (message !== null && message !== void 0 ? message : "") },
        ];
        const revNotifications = [];
        let revComplete = false;
        // Plafond de tours : sans lui, un modèle qui n'émet jamais end_turn
        // boucle jusqu'au timeout de la fonction (coût non borné).
        const REV_MAX_TURNS = 10;
        for (let revTurn = 0; revTurn < REV_MAX_TURNS; revTurn++) {
            const response = await client2.messages.create({
                model: (0, models_1.getModel)("onboarding"),
                max_tokens: 1536,
                system: revSystemPrompt,
                tools: REVISION_TOOLS,
                messages: revMessages,
            });
            (0, models_1.logTokenUsage)("onboarding_revision", (0, models_1.getModel)("onboarding"), response.usage);
            if (response.stop_reason === "end_turn") {
                const text2 = response.content.filter((b) => b.type === "text").map((b) => b.text).join("");
                // Sauvegarde session révision
                const newHistory = [
                    ...(history !== null && history !== void 0 ? history : []),
                    { role: "user", content: action === "startRevision" ? "Je suis prêt pour ma session de révision." : (message !== null && message !== void 0 ? message : "") },
                    { role: "assistant", content: text2 },
                ];
                db_1.db.collection("formation_sessions").doc(uid).set({ uid, history: newHistory, mode: "revision", turnCount: newHistory.length / 2, savedAt: db_1.FieldValue.serverTimestamp() }).catch(() => { });
                res.status(200).json({ message: text2, notifications: revNotifications, revisionComplete: revComplete, mode: "revision" });
                return;
            }
            if (response.stop_reason === "tool_use") {
                revMessages.push({ role: "assistant", content: response.content });
                const toolResults = [];
                for (const block of response.content) {
                    if (block.type === "tool_use") {
                        const result = await executeOnboardingTool(uid, block.name, block.input, revDomainMap);
                        if (result.notification)
                            revNotifications.push(result.notification);
                        toolResults.push({ type: "tool_result", tool_use_id: block.id, content: result.output });
                    }
                }
                revMessages.push({ role: "user", content: toolResults });
                continue;
            }
            break;
        }
        res.status(500).json({ error: "Erreur boucle révision" });
        return;
    }
    // ── Guard — onboarding déjà complété ──────────────────────────────────────
    // Bloque toute nouvelle session de chat si l'onboarding est terminé.
    if (onboardingDone) {
        res.status(403).json({ code: "ONBOARDING_DONE", isPro });
        return;
    }
    if (!message) {
        res.status(400).json({ error: "message requis" });
        return;
    }
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
        res.status(500).json({ error: "ANTHROPIC_API_KEY manquante" });
        return;
    }
    const client = new sdk_1.default({ apiKey });
    const today = (0, execute_1.todayInParis)();
    // Bloc de contexte pré-rempli injecté dans le prompt si formulaire rempli
    const uc = userContext;
    const contextBlock = (uc && Object.values(uc).some(v => typeof v === "string" && v.trim())) ? `
━━━ CONTEXTE PRÉ-REMPLI (formulaire avant session) ━━━
L'utilisateur a déjà rempli un formulaire. Tu CONNAIS ces informations — NE LES REDEMANDE JAMAIS. Pars de là pour aller immédiatement en profondeur.

Prénom : ${uc.prenom || "—"}
Activité principale : ${uc.activite || "—"}
Situation : ${uc.situation || "—"}
Ce qui lui prend le plus d'énergie en ce moment : ${uc.energie || "—"}
Ce qu'il veut pouvoir faire dans 3 mois : ${uc.objectif || "—"}
Son plus grand frein à l'organisation : ${uc.frein || "—"}

Commence ta première réponse en reformulant en 2-3 phrases ce que tu comprends de sa situation (montre que tu as vraiment lu), puis pose UNE seule question pour aller plus loin sur le point le plus révélateur.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━` : "";
    const systemPrompt = ONBOARDING_SYSTEM_PROMPT
        .replace("{{TODAY}}", today)
        .replace("{{USER_CONTEXT}}", contextBlock);
    const firstUserMsg = (history !== null && history !== void 0 ? history : []).length === 0 && contextBlock
        ? `${message}\n\n[Contexte formulaire déjà dans le system prompt — je suis prêt à démarrer.]`
        : message;
    const messages = [
        ...(history !== null && history !== void 0 ? history : []).map((m) => ({ role: m.role, content: m.content })),
        { role: "user", content: firstUserMsg },
    ];
    const notifications = [];
    const domainMap = {};
    const activityMap = {};
    let onboardingComplete = false;
    let structurePreview = null;
    let assistantText = ""; // accumule le texte de TOUS les tours (évite les messages vides quand le modèle répond ET appelle un outil dans le même tour)
    // Boucle agentique : continue jusqu'à end_turn (réponse texte finale).
    // Plafond de tours : sans lui, un modèle qui n'émet jamais end_turn boucle
    // jusqu'au timeout de la fonction (coût non borné) ; au-delà on renvoie le
    // texte accumulé (fallthrough gracieux ci-dessous).
    const ONBOARDING_MAX_TURNS = 12;
    for (let obTurn = 0; obTurn < ONBOARDING_MAX_TURNS; obTurn++) {
        const response = await client.messages.create({
            model: (0, models_1.getModel)("onboarding"),
            max_tokens: 8192, // create_workspace = un gros payload unique (≈40 activités + projet)
            system: systemPrompt,
            tools: ONBOARDING_TOOLS,
            messages: messages,
        });
        (0, models_1.logTokenUsage)("onboarding", (0, models_1.getModel)("onboarding"), response.usage);
        if (response.stop_reason === "end_turn") {
            assistantText += response.content
                .filter((b) => b.type === "text")
                .map((b) => b.text)
                .join("");
            const text = assistantText.trim();
            // Lit la structure déjà connue UNE fois (sert à l'extraction incrémentale + à la fusion).
            let prevStruct = null;
            if (!onboardingComplete) {
                try {
                    const prevSnap = await db_1.db.collection("formation_sessions").doc(uid).get();
                    prevStruct = prevSnap.exists ? ((_j = (_h = prevSnap.data()) === null || _h === void 0 ? void 0 : _h.structure) !== null && _j !== void 0 ? _j : null) : null;
                }
                catch (_) { /* prevStruct reste null */ }
            }
            // Filet de sécurité : si le guide n'a pas mis à jour la mindmap, on l'alimente
            // par extraction incrémentale (structure connue + dernier échange).
            if (!structurePreview && !onboardingComplete) {
                structurePreview = await extractStructurePreview(client, prevStruct, message !== null && message !== void 0 ? message : "", text);
            }
            // Pas de fusion des domaines : l'extraction incrémentale fait foi (applique
            // ajouts ET renommages/suppressions). MAIS on préserve le Gantt déjà construit
            // si l'extraction l'a omis ce tour-ci (sinon il disparaît en éditant un domaine).
            if (structurePreview && prevStruct) {
                const sp = structurePreview;
                const pp = prevStruct;
                if (!sp.gantt && pp.gantt)
                    sp.gantt = pp.gantt;
            }
            if (onboardingComplete) {
                // set(merge) et non update : pour un compte magic-link, le doc formation_access
                // n'existe pas forcément (pas créé par le webhook) → update échouerait silencieusement
                // et l'utilisateur ne serait jamais marqué "terminé".
                await db_1.db.collection("formation_access").doc(uid).set({
                    uid,
                    onboardingDone: true,
                    onboardingDoneAt: db_1.FieldValue.serverTimestamp(),
                    lastVisionAt: db_1.FieldValue.serverTimestamp(),
                }, { merge: true }).catch(() => { });
                // Nettoie la session après completion
                db_1.db.collection("formation_sessions").doc(uid).delete().catch(() => { });
            }
            else {
                // Sauvegarde la session après chaque échange (fire & forget)
                const historyToSave = [
                    ...(history !== null && history !== void 0 ? history : []),
                    { role: "user", content: message },
                    { role: "assistant", content: text },
                ];
                db_1.db.collection("formation_sessions").doc(uid).set(Object.assign({ uid, history: historyToSave, userContext: userContext !== null && userContext !== void 0 ? userContext : null, turnCount: (history !== null && history !== void 0 ? history : []).length / 2 + 1, savedAt: db_1.FieldValue.serverTimestamp() }, (structurePreview ? { structure: structurePreview } : {})), { merge: true }).catch(() => { });
            }
            res.status(200).json({ message: text, notifications, onboardingComplete, structure: structurePreview });
            return;
        }
        if (response.stop_reason === "tool_use") {
            messages.push({ role: "assistant", content: response.content });
            // Récupère le texte émis DANS ce tour (le modèle répond souvent ET appelle un outil
            // dans le même tour) — sinon ce texte serait perdu → bulle vide côté chat.
            assistantText += response.content
                .filter((b) => b.type === "text")
                .map((b) => b.text)
                .join("");
            const toolResults = [];
            for (const block of response.content) {
                if (block.type === "tool_use") {
                    const result = await executeOnboardingTool(uid, block.name, block.input, domainMap, activityMap);
                    if (result.notification)
                        notifications.push(result.notification);
                    if (block.name === "push_gantt" || block.name === "complete_onboarding" || block.name === "create_workspace")
                        onboardingComplete = true;
                    if (block.name === "set_structure_preview")
                        structurePreview = block.input;
                    toolResults.push({ type: "tool_result", tool_use_id: block.id, content: result.output });
                }
            }
            messages.push({ role: "user", content: toolResults });
            continue;
        }
        // stop_reason inattendu (ex: max_tokens) — on sort de la boucle
        break;
    }
    // Au lieu d'échouer : on renvoie ce qu'on a accumulé (texte + structure).
    res.status(200).json({
        message: assistantText.trim() || "Désolé, peux-tu reformuler ? (réponse interrompue)",
        notifications,
        onboardingComplete,
        structure: structurePreview,
    });
});
// ── adminProductivitwo (sessions de co-dev avec Claude Code) ──────────────────
//
// Endpoint protégé par secret pour permettre à Claude Code d'inspecter et
// pousser dans Productivitwo pendant les sessions de travail (sans passe-plat
// avec le MCP de Claude.ai). Secret stocké en Firebase Secret Manager.
// Entitlement RevenueCat surveillé (doit matcher kEntitlementPro côté app).
const kEntitlementPro = "pro";
// ── revenueCatWebhook ─────────────────────────────────────────────────────────
//
// Webhook RevenueCat (iOS ET Android — RevenueCat unifie les deux stores).
// Configuré dans RevenueCat → Integrations → Webhooks, avec un header
// Authorization: Bearer <REVENUECAT_WEBHOOK_SECRET>.
//
// On écrit l'expiration de l'entitlement `pro` dans formation_access/{uid}.
// subscriptionUntil → effectivePro la lit. Le app_user_id RevenueCat = le
// Firebase uid (on appelle Purchases.logIn(uid) côté app). Pas de logique par
// type d'event : on stocke expiration_at, la comparaison > now fait le reste.
exports.revenueCatWebhook = (0, https_1.onRequest)({ invoker: "public", secrets: ["REVENUECAT_WEBHOOK_SECRET"] }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const auth = (_a = req.headers["authorization"]) === null || _a === void 0 ? void 0 : _a.trim();
    const bearer = (auth === null || auth === void 0 ? void 0 : auth.startsWith("Bearer ")) ? auth.slice(7) : undefined;
    if (!secretsMatch(bearer, process.env.REVENUECAT_WEBHOOK_SECRET)) {
        res.status(401).json({ error: "Unauthorized" });
        return;
    }
    try {
        const event = ((_c = (_b = req.body) === null || _b === void 0 ? void 0 : _b.event) !== null && _c !== void 0 ? _c : {});
        const uid = (_d = event.app_user_id) === null || _d === void 0 ? void 0 : _d.trim();
        const type = (_e = event.type) !== null && _e !== void 0 ? _e : "UNKNOWN";
        if (!uid) {
            res.status(200).json({ ok: true, skipped: "no app_user_id" });
            return;
        }
        const entitlements = (_f = event.entitlement_ids) !== null && _f !== void 0 ? _f : null;
        const concernsPro = entitlements === null || entitlements.includes(kEntitlementPro);
        const expMs = event.expiration_at_ms;
        const patch = {
            rcLastEvent: type,
            rcUpdatedAt: db_1.FieldValue.serverTimestamp(),
        };
        if (concernsPro && typeof expMs === "number") {
            patch.subscriptionUntil = admin.firestore.Timestamp.fromMillis(expMs);
            patch.subscriptionStore = (_g = event.store) !== null && _g !== void 0 ? _g : null;
            patch.subscriptionProductId = (_h = event.product_id) !== null && _h !== void 0 ? _h : null;
        }
        await db_1.db.collection("formation_access").doc(uid).set(patch, { merge: true });
        res.status(200).json({ ok: true });
    }
    catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error("revenueCatWebhook error:", msg);
        res.status(500).json({ error: "fail" });
    }
});
// Throttle anti-brute-force du secret admin : au-delà de N échecs d'auth dans
// la fenêtre, l'instance répond 429 à tout le monde jusqu'à la fin de la
// fenêtre. En mémoire (par instance) — pas parfait, mais l'endpoint donne
// deleteUser/setPro/dump des emails : mieux vaut un garde-fou simple que rien.
let _adminFailWindowStart = 0;
let _adminFailCount = 0;
const _ADMIN_FAIL_MAX = 10;
const _ADMIN_FAIL_WINDOW_MS = 10 * 60 * 1000;
exports.adminProductivitwo = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["ADMIN_PUSH_SECRET"] }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _l, _m, _o, _p, _q, _r, _s, _t, _u, _v, _w;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const { adminSecret, uid, action, payload } = req.body;
    const now = Date.now();
    if (now - _adminFailWindowStart > _ADMIN_FAIL_WINDOW_MS) {
        _adminFailWindowStart = now;
        _adminFailCount = 0;
    }
    if (_adminFailCount >= _ADMIN_FAIL_MAX) {
        res.status(429).json({ error: "Trop de tentatives — réessaie plus tard" });
        return;
    }
    if (!secretsMatch(adminSecret, process.env.ADMIN_PUSH_SECRET)) {
        _adminFailCount++;
        console.warn(`adminProductivitwo: échec d'auth (${_adminFailCount}/${_ADMIN_FAIL_MAX} dans la fenêtre), ip=${(_a = req.ip) !== null && _a !== void 0 ? _a : "?"}`);
        res.status(401).json({ error: "Secret invalide" });
        return;
    }
    // ── Actions globales (sans uid) : gestion des utilisateurs / allowlist ──────
    try {
        if (action === "listUsers") {
            const [authList, allowSnap, faSnap] = await Promise.all([
                admin.auth().listUsers(1000),
                db_1.db.collection("allowlist").get(),
                db_1.db.collection("formation_access").get(),
            ]);
            const allowEmails = new Set(allowSnap.docs.map((d) => d.id.toLowerCase()));
            const allowGroups = {};
            allowSnap.docs.forEach((d) => { var _a; allowGroups[d.id.toLowerCase()] = (_a = d.data().groups) !== null && _a !== void 0 ? _a : []; });
            const faByUid = {};
            faSnap.docs.forEach((d) => { faByUid[d.id] = d.data(); });
            const tsToIso = (v) => v && typeof v.toDate === "function"
                ? v.toDate().toISOString() : null;
            const nowMs = Date.now();
            const tActive = (v) => {
                const t = v;
                return !!t && typeof t.toMillis === "function" && t.toMillis() > nowMs;
            };
            const seen = new Set();
            const users = await Promise.all(authList.users.map(async (u) => {
                var _a, _b, _c, _d, _e, _f;
                const email = ((_a = u.email) !== null && _a !== void 0 ? _a : "").toLowerCase();
                seen.add(email);
                const providers = u.providerData.map((p) => p.providerId);
                const fa = faByUid[u.uid];
                const anonymous = !u.email && providers.length === 0;
                // Compteurs de données (aggregation .count() — ne lit pas les docs).
                const [projects, activities] = await Promise.all([
                    db_1.db.collection(`users/${u.uid}/projects`).count().get().then((s) => s.data().count).catch(() => 0),
                    db_1.db.collection(`users/${u.uid}/activities`).count().get().then((s) => s.data().count).catch(() => 0),
                ]);
                return {
                    uid: u.uid,
                    email: (_b = u.email) !== null && _b !== void 0 ? _b : null,
                    providers,
                    source: providers.includes("apple.com") ? "iOS (Apple)"
                        : providers.includes("google.com") ? "Web (Google)"
                            : anonymous ? "Anonyme (app)"
                                : (fa && fa.purchasedAt) ? "Formation" : "Web (email)",
                    anonymous,
                    createdAt: (_c = u.metadata.creationTime) !== null && _c !== void 0 ? _c : null,
                    lastSignIn: (_d = u.metadata.lastSignInTime) !== null && _d !== void 0 ? _d : null,
                    formation: !!fa,
                    purchasedAt: fa ? tsToIso(fa.purchasedAt) : null,
                    onboardingDone: (fa === null || fa === void 0 ? void 0 : fa.onboardingDone) === true,
                    isPro: (0, db_1.effectivePro)(fa),
                    proUntil: fa ? tsToIso(fa.proUntil) : null,
                    proSource: !(0, db_1.effectivePro)(fa) ? null
                        : tActive(fa === null || fa === void 0 ? void 0 : fa.subscriptionUntil) ? "Abo"
                            : tActive(fa === null || fa === void 0 ? void 0 : fa.proUntil) ? "Grant" : "Legacy",
                    subscriptionUntil: fa ? tsToIso(fa.subscriptionUntil) : null,
                    lastVisionAt: fa ? tsToIso(fa.lastVisionAt) : null,
                    allowlisted: allowEmails.has(email),
                    groups: Array.from(new Set([
                        ...(((_e = fa === null || fa === void 0 ? void 0 : fa.groups) !== null && _e !== void 0 ? _e : [])),
                        ...((_f = allowGroups[email]) !== null && _f !== void 0 ? _f : []),
                    ])),
                    projects,
                    activities,
                };
            }));
            // Emails dans l'allowlist sans compte encore créé (invités en attente).
            const invited = [...allowEmails].filter((e) => !seen.has(e)).map((e) => {
                var _a;
                return ({
                    uid: null, email: e, providers: [], source: "Invité (allowlist)",
                    createdAt: null, lastSignIn: null, formation: false, purchasedAt: null,
                    onboardingDone: false, isPro: false, lastVisionAt: null, allowlisted: true,
                    groups: (_a = allowGroups[e]) !== null && _a !== void 0 ? _a : [],
                });
            });
            res.status(200).json({ users: [...users, ...invited] });
            return;
        }
        if (action === "addAllowlist") {
            const email = ((_b = payload === null || payload === void 0 ? void 0 : payload.email) !== null && _b !== void 0 ? _b : "").trim().toLowerCase();
            if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
                res.status(400).json({ error: "Email invalide" });
                return;
            }
            await db_1.db.collection("allowlist").doc(email).set({ addedAt: db_1.FieldValue.serverTimestamp(), addedBy: "admin" }, { merge: true });
            res.status(200).json({ success: true, email });
            return;
        }
        if (action === "removeAllowlist") {
            const email = ((_c = payload === null || payload === void 0 ? void 0 : payload.email) !== null && _c !== void 0 ? _c : "").trim().toLowerCase();
            await db_1.db.collection("allowlist").doc(email).delete();
            res.status(200).json({ success: true, email });
            return;
        }
        if (action === "setPro") {
            // Accorde / révoque un grant Pro daté sur formation_access/{uid}.
            // until = "YYYY-MM-DD" → Pro jusqu'à cette date (incluse) ; null → révoque.
            const targetUid = (_d = payload === null || payload === void 0 ? void 0 : payload.uid) === null || _d === void 0 ? void 0 : _d.trim();
            if (!targetUid) {
                res.status(400).json({ error: "uid requis" });
                return;
            }
            const untilStr = (_e = payload === null || payload === void 0 ? void 0 : payload.until) !== null && _e !== void 0 ? _e : null;
            const patch = {
                proSource: "admin",
                proUpdatedAt: db_1.FieldValue.serverTimestamp(),
            };
            if (untilStr) {
                if (!/^\d{4}-\d{2}-\d{2}$/.test(untilStr)) {
                    res.status(400).json({ error: "Date invalide (YYYY-MM-DD)" });
                    return;
                }
                const d = new Date(`${untilStr}T23:59:59`);
                if (isNaN(d.getTime())) {
                    res.status(400).json({ error: "Date invalide" });
                    return;
                }
                // SEULEMENT proUntil (pas isPro:true) — sinon le grant n'expirerait
                // jamais (effectivePro retomberait sur le fallback Legacy).
                patch.proUntil = admin.firestore.Timestamp.fromDate(d);
                patch.isPro = db_1.FieldValue.delete();
            }
            else {
                patch.proUntil = db_1.FieldValue.delete();
                patch.isPro = db_1.FieldValue.delete();
            }
            await db_1.db.collection("formation_access").doc(targetUid).set(patch, { merge: true });
            res.status(200).json({ success: true, uid: targetUid, until: untilStr });
            return;
        }
        if (action === "setGroups") {
            // Gère les groupes/tags d'un user. Compte → formation_access/{uid} ;
            // invité (sans compte) → allowlist/{email}. payload : set[] (remplace)
            // OU add (1 groupe) OU remove (1 groupe).
            const targetUid = (_f = payload === null || payload === void 0 ? void 0 : payload.uid) === null || _f === void 0 ? void 0 : _f.trim();
            const email = ((_g = payload === null || payload === void 0 ? void 0 : payload.email) !== null && _g !== void 0 ? _g : "").trim().toLowerCase();
            if (!targetUid && !email) {
                res.status(400).json({ error: "uid ou email requis" });
                return;
            }
            const ref = targetUid
                ? db_1.db.collection("formation_access").doc(targetUid)
                : db_1.db.collection("allowlist").doc(email);
            const set = payload === null || payload === void 0 ? void 0 : payload.set;
            const add = (_h = payload === null || payload === void 0 ? void 0 : payload.add) === null || _h === void 0 ? void 0 : _h.trim();
            const remove = (_j = payload === null || payload === void 0 ? void 0 : payload.remove) === null || _j === void 0 ? void 0 : _j.trim();
            if (set !== undefined) {
                await ref.set({ groups: set.map((s) => s.trim()).filter(Boolean) }, { merge: true });
            }
            else if (add) {
                await ref.set({ groups: db_1.FieldValue.arrayUnion(add) }, { merge: true });
            }
            else if (remove) {
                await ref.set({ groups: db_1.FieldValue.arrayRemove(remove) }, { merge: true });
            }
            else {
                res.status(400).json({ error: "set, add ou remove requis" });
                return;
            }
            res.status(200).json({ success: true });
            return;
        }
        if (action === "checkAccess") {
            // Rejoue la logique du gate sendMagicLink pour un email donné.
            const email = ((_l = payload === null || payload === void 0 ? void 0 : payload.email) !== null && _l !== void 0 ? _l : "").trim().toLowerCase();
            if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
                res.status(400).json({ error: "Email invalide" });
                return;
            }
            let hasAccount = false;
            let targetUid = null;
            let providers = [];
            try {
                const u = await admin.auth().getUserByEmail(email);
                hasAccount = true;
                targetUid = u.uid;
                providers = u.providerData.map((p) => p.providerId);
            }
            catch ( /* pas de compte */_x) { /* pas de compte */ }
            const allowlisted = (await db_1.db.collection("allowlist").doc(email).get()).exists;
            const pass = hasAccount || allowlisted;
            const reason = hasAccount ? "compte existant" : allowlisted ? "allowlisté" : "aucun compte, pas d'allowlist";
            res.status(200).json({ email, pass, reason, hasAccount, allowlisted, uid: targetUid, providers });
            return;
        }
        if (action === "deleteUser") {
            // Suppression DÉFINITIVE : compte Auth + toutes les données Firestore du
            // user + son formation_access + son entrée allowlist. Irréversible.
            const targetUid = (_m = payload === null || payload === void 0 ? void 0 : payload.uid) === null || _m === void 0 ? void 0 : _m.trim();
            const email = ((_o = payload === null || payload === void 0 ? void 0 : payload.email) !== null && _o !== void 0 ? _o : "").trim().toLowerCase();
            if (!targetUid && !email) {
                res.status(400).json({ error: "uid ou email requis" });
                return;
            }
            const done = [];
            if (targetUid) {
                await db_1.db.recursiveDelete(db_1.db.doc(`users/${targetUid}`));
                done.push("données users/*");
                await db_1.db.collection("formation_access").doc(targetUid).delete().catch(() => { });
                done.push("formation_access");
                await admin.auth().deleteUser(targetUid).catch(() => { });
                done.push("compte Auth");
            }
            if (email) {
                await db_1.db.collection("allowlist").doc(email).delete().catch(() => { });
                done.push("allowlist");
            }
            res.status(200).json({ success: true, uid: targetUid !== null && targetUid !== void 0 ? targetUid : null, email: email || null, done });
            return;
        }
    }
    catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error("admin global action error:", msg);
        res.status(500).json({ error: msg });
        return;
    }
    if (!uid) {
        res.status(400).json({ error: "uid requis" });
        return;
    }
    try {
        if (action === "inspect") {
            const [domainsSnap, activitiesSnap, projectsSnap] = await Promise.all([
                db_1.db.collection(`users/${uid}/domains`).get(),
                db_1.db.collection(`users/${uid}/activities`).get(),
                db_1.db.collection(`users/${uid}/projects`).get(),
            ]);
            const domains = domainsSnap.docs
                .filter(d => !d.data().deleted)
                .map(d => (Object.assign({ id: d.id }, d.data())));
            const activities = activitiesSnap.docs
                .filter(d => !d.data().deleted)
                .map(d => (Object.assign({ id: d.id }, d.data())));
            const projects = projectsSnap.docs.map(d => {
                var _a;
                const data = d.data();
                const tasks = (_a = data.tasks) !== null && _a !== void 0 ? _a : [];
                return {
                    id: d.id,
                    title: data.title,
                    description: data.description,
                    status: data.status,
                    startDate: data.startDate,
                    endDate: data.endDate,
                    domainId: data.domainId,
                    tasks: tasks.map(t => ({
                        id: t.id, title: t.title, status: t.status,
                        startDate: t.startDate, endDate: t.endDate,
                        isMilestone: t.isMilestone,
                        actionsCount: Array.isArray(t.actions) ? t.actions.length : 0,
                        actionsDone: Array.isArray(t.actions) ? t.actions.filter(a => a.done).length : 0,
                        actions: Array.isArray(t.actions) ? t.actions.map(a => { var _a; return ({ id: a.id, title: a.title, done: (_a = a.done) !== null && _a !== void 0 ? _a : false }); }) : [],
                    })),
                };
            });
            res.status(200).json({ domains, activities, projects });
            return;
        }
        if (action === "updateTask") {
            const { projectId, taskId, startDate, endDate, title, status } = payload;
            const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
            const snap = await ref.get();
            if (!snap.exists) {
                res.status(404).json({ error: "Projet introuvable" });
                return;
            }
            const rawTasks = (_q = (_p = snap.data()) === null || _p === void 0 ? void 0 : _p.tasks) !== null && _q !== void 0 ? _q : [];
            const tasks = rawTasks.map(t => JSON.parse(JSON.stringify(t, (_k, v) => v && typeof v === "object" && typeof v.toDate === "function" ? v.toDate().toISOString() : v)));
            const idx = tasks.findIndex(t => t.id === taskId);
            if (idx === -1) {
                res.status(404).json({ error: "Tâche introuvable" });
                return;
            }
            const patch = {};
            if (startDate)
                patch.startDate = startDate;
            if (endDate)
                patch.endDate = endDate;
            if (title)
                patch.title = title;
            if (status)
                patch.status = status;
            tasks[idx] = Object.assign(Object.assign({}, tasks[idx]), patch);
            await ref.update({ tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
            res.status(200).json({ success: true });
            return;
        }
        if (action === "addTask") {
            const { projectId, title, startDate, endDate, isMilestone, actions, phaseId, status, actionsAllDone } = payload;
            const newTask = {
                id: (0, uuid_1.v4)(), title, description: null,
                phaseId: phaseId !== null && phaseId !== void 0 ? phaseId : null, groupLabel: null,
                startDate, endDate: endDate !== null && endDate !== void 0 ? endDate : null,
                isMilestone: isMilestone !== null && isMilestone !== void 0 ? isMilestone : false,
                color: null, barLabel: null, status: status !== null && status !== void 0 ? status : "pending",
                actions: (actions !== null && actions !== void 0 ? actions : []).map(a => ({
                    id: (0, uuid_1.v4)(), title: a,
                    done: actionsAllDone === true, doneAt: actionsAllDone === true ? new Date().toISOString() : null,
                    createdAt: new Date().toISOString(),
                })),
            };
            await db_1.db.collection(`users/${uid}/projects`).doc(projectId).update({
                tasks: db_1.FieldValue.arrayUnion(newTask),
                updatedAt: db_1.FieldValue.serverTimestamp(),
            });
            res.status(200).json({ success: true, taskId: newTask.id });
            return;
        }
        if (action === "addActionToTask") {
            const { projectId, taskId, title } = payload;
            const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
            const snap = await ref.get();
            if (!snap.exists) {
                res.status(404).json({ error: "Projet introuvable" });
                return;
            }
            const tasks = ((_s = (_r = snap.data()) === null || _r === void 0 ? void 0 : _r.tasks) !== null && _s !== void 0 ? _s : []).map(t => JSON.parse(JSON.stringify(t, (_k, v) => v && typeof v === "object" && typeof v.toDate === "function" ? v.toDate().toISOString() : v)));
            const idx = tasks.findIndex(t => t.id === taskId);
            if (idx === -1) {
                res.status(404).json({ error: "Tâche introuvable" });
                return;
            }
            const actions = ((_t = tasks[idx].actions) !== null && _t !== void 0 ? _t : []).slice();
            const newAction = { id: (0, uuid_1.v4)(), title, done: false, doneAt: null, createdAt: new Date().toISOString() };
            actions.push(newAction);
            tasks[idx] = Object.assign(Object.assign({}, tasks[idx]), { actions });
            await ref.update({ tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
            res.status(200).json({ success: true, actionId: newAction.id });
            return;
        }
        if (action === "markActionDone") {
            const { projectId, taskId, actionId, done } = payload;
            const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
            const snap = await ref.get();
            if (!snap.exists) {
                res.status(404).json({ error: "Projet introuvable" });
                return;
            }
            const tasks = ((_v = (_u = snap.data()) === null || _u === void 0 ? void 0 : _u.tasks) !== null && _v !== void 0 ? _v : []).map(t => JSON.parse(JSON.stringify(t, (_k, v) => v && typeof v === "object" && typeof v.toDate === "function" ? v.toDate().toISOString() : v)));
            const tIdx = tasks.findIndex(t => t.id === taskId);
            if (tIdx === -1) {
                res.status(404).json({ error: "Tâche introuvable" });
                return;
            }
            const actions = ((_w = tasks[tIdx].actions) !== null && _w !== void 0 ? _w : []).slice();
            const aIdx = actions.findIndex(a => a.id === actionId);
            if (aIdx === -1) {
                res.status(404).json({ error: "Action introuvable" });
                return;
            }
            actions[aIdx] = Object.assign(Object.assign({}, actions[aIdx]), { done, doneAt: done ? new Date().toISOString() : null });
            tasks[tIdx] = Object.assign(Object.assign({}, tasks[tIdx]), { actions });
            await ref.update({ tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
            res.status(200).json({ success: true });
            return;
        }
        if (action === "addProject") {
            const { title, description, startDate, endDate, domainId, phases, tasks } = payload;
            const projectId = (0, uuid_1.v4)();
            const phasesData = (phases !== null && phases !== void 0 ? phases : []).map(p => ({ id: (0, uuid_1.v4)(), label: p.label, color: null, startDate: p.startDate, endDate: p.endDate }));
            const tasksData = (tasks !== null && tasks !== void 0 ? tasks : []).map(t => {
                var _a, _b, _c, _d;
                return ({
                    id: (0, uuid_1.v4)(), title: t.title, description: null,
                    phaseId: t.phaseIndex !== undefined ? (_b = (_a = phasesData[t.phaseIndex]) === null || _a === void 0 ? void 0 : _a.id) !== null && _b !== void 0 ? _b : null : null,
                    groupLabel: null,
                    startDate: t.startDate, endDate: (_c = t.endDate) !== null && _c !== void 0 ? _c : null,
                    isMilestone: false, color: null, barLabel: null, status: "pending",
                    actions: ((_d = t.actions) !== null && _d !== void 0 ? _d : []).map(a => ({
                        id: (0, uuid_1.v4)(), title: a, done: false, doneAt: null, createdAt: new Date().toISOString(),
                    })),
                });
            });
            await db_1.db.collection(`users/${uid}/projects`).doc(projectId).set({
                id: projectId, title,
                description: description !== null && description !== void 0 ? description : null, strategicObjectiveId: null,
                domainId: domainId !== null && domainId !== void 0 ? domainId : null,
                startDate, endDate: endDate !== null && endDate !== void 0 ? endDate : null,
                status: "active", phases: phasesData, tasks: tasksData,
                createdBy: uid, sourceType: "claude_code_session",
                createdAt: db_1.FieldValue.serverTimestamp(), updatedAt: db_1.FieldValue.serverTimestamp(),
            });
            res.status(200).json({ success: true, projectId });
            return;
        }
        if (action === "setSchedule") {
            const { date, blocks } = payload;
            const normalizedBlocks = blocks.map(b => {
                var _a, _b, _c;
                return ({
                    id: (0, uuid_1.v4)(),
                    startTime: b.startTime,
                    durationMin: b.durationMin,
                    title: b.title,
                    category: b.category,
                    projectId: (_a = b.projectId) !== null && _a !== void 0 ? _a : null,
                    taskId: (_b = b.taskId) !== null && _b !== void 0 ? _b : null,
                    activityId: (_c = b.activityId) !== null && _c !== void 0 ? _c : null,
                    status: "pending",
                    doneAt: null,
                });
            });
            await db_1.db.collection(`users/${uid}/daily_schedules`).doc(date).set({
                date,
                generatedBy: "claude_code_session",
                generatedAt: db_1.FieldValue.serverTimestamp(),
                blocks: normalizedBlocks,
            });
            res.status(200).json({ success: true, blocksCount: normalizedBlocks.length });
            return;
        }
        if (action === "updateProject") {
            const _y = payload, { projectId } = _y, updates = __rest(_y, ["projectId"]);
            await db_1.db.collection(`users/${uid}/projects`).doc(projectId).update(Object.assign(Object.assign({}, updates), { updatedAt: db_1.FieldValue.serverTimestamp() }));
            res.status(200).json({ success: true });
            return;
        }
        res.status(400).json({ error: `Action inconnue : ${action}` });
    }
    catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        res.status(500).json({ error: msg });
    }
});
// ── Formation helpers ─────────────────────────────────────────────────────────
const FORMATION_URL = "https://app.productivitwo.com/formation";
function createFormationToken(uid, email, secret) {
    const cleanSecret = secret.trim();
    const payload = Buffer.from(JSON.stringify({
        uid,
        email,
        exp: Date.now() + 30 * 24 * 60 * 60 * 1000,
    })).toString("base64url");
    const sig = (0, crypto_1.createHmac)("sha256", cleanSecret).update(payload).digest("base64url");
    return `${payload}.${sig}`;
}
function verifyFormationToken(token, secret) {
    const cleanSecret = secret.trim();
    const dot = token.lastIndexOf(".");
    if (dot < 0)
        return null;
    const payload = token.slice(0, dot);
    const sig = token.slice(dot + 1);
    const expected = (0, crypto_1.createHmac)("sha256", cleanSecret).update(payload).digest("base64url");
    // Accepte aussi l'ancienne signature (avec \n) pour ne pas invalider les tokens en circulation
    const legacy = (0, crypto_1.createHmac)("sha256", secret).update(payload).digest("base64url");
    if (sig !== expected && sig !== legacy)
        return null;
    try {
        const data = JSON.parse(Buffer.from(payload, "base64url").toString());
        if (!data.exp || data.exp < Date.now())
            return null;
        return { uid: data.uid, email: data.email };
    }
    catch (_a) {
        return null;
    }
}
function hexToColorValue(hex) {
    const clean = hex.replace("#", "");
    if (clean.length !== 6)
        return null;
    return parseInt("FF" + clean.toUpperCase(), 16);
}
// ── generateFormationAccess ───────────────────────────────────────────────────
//
// POST — appelé par systeme.io après un achat.
// Secret accepté : header x-webhook-secret OU body.webhookSecret (le query
// param ?secret= n'est plus accepté — fuite dans les logs d'URL)
// Email accepté : body.email OU body.contact_email OU body.contact.email
// Retourne { accessUrl } à inclure dans l'email de confirmation systeme.io.
exports.generateFormationAccess = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["FORMATION_JWT_SECRET", "SYSTEME_IO_WEBHOOK_SECRET"] }, async (req, res) => {
    var _a, _b, _c, _d;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    // Secret : header ou body (compatible systeme.io qui ne supporte pas les
    // headers custom). Le query param `?secret=` n'est PLUS accepté : une URL
    // finit dans les logs proxy/CDN/referer — l'endpoint crée des comptes.
    const body = req.body;
    const providedSecret = (_a = req.headers["x-webhook-secret"]) !== null && _a !== void 0 ? _a : body === null || body === void 0 ? void 0 : body.webhookSecret;
    if (!secretsMatch(providedSecret, process.env.SYSTEME_IO_WEBHOOK_SECRET)) {
        res.status(401).json({ error: "Secret invalide" });
        return;
    }
    // Email : essaie les différents formats que systeme.io peut envoyer
    const contact = body === null || body === void 0 ? void 0 : body.contact;
    const rawEmail = (_d = (_c = (_b = body === null || body === void 0 ? void 0 : body.email) !== null && _b !== void 0 ? _b : body === null || body === void 0 ? void 0 : body.contact_email) !== null && _c !== void 0 ? _c : contact === null || contact === void 0 ? void 0 : contact.email) !== null && _d !== void 0 ? _d : "";
    const email = rawEmail.trim().toLowerCase();
    if (!email || !email.includes("@")) {
        res.status(400).json({ error: "email requis", received: body });
        return;
    }
    let uid;
    try {
        const existing = await admin.auth().getUserByEmail(email);
        uid = existing.uid;
    }
    catch (_e) {
        const created = await admin.auth().createUser({ email });
        uid = created.uid;
    }
    const token = createFormationToken(uid, email, process.env.FORMATION_JWT_SECRET);
    await db_1.db.collection("formation_access").doc(uid).set({ uid, email, purchasedAt: db_1.FieldValue.serverTimestamp(), onboardingDone: false }, { merge: true });
    const accessUrl = `${FORMATION_URL}?token=${encodeURIComponent(token)}`;
    res.status(200).json({ success: true, accessUrl, uid });
});
// ── getVisionAccess ───────────────────────────────────────────────────────────
//
// POST — Header: Authorization: Bearer <Firebase ID token>
// Retourne le statut Vision pour l'utilisateur authentifié + URL d'accès si dispo.
// Utilisé par le bouton Vision dans l'app web.
const VISION_INTERVAL_DAYS = 30;
exports.getVisionAccess = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["FORMATION_JWT_SECRET"] }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST" && req.method !== "GET") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const authHeader = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
    }
    const idToken = authHeader.slice(7).trim();
    let uid;
    let email;
    try {
        const decoded = await admin.auth().verifyIdToken(idToken);
        uid = decoded.uid;
        email = (_b = decoded.email) !== null && _b !== void 0 ? _b : "";
    }
    catch (_g) {
        res.status(401).json({ error: "Token invalide ou expiré" });
        return;
    }
    const accessDoc = await db_1.db.collection("formation_access").doc(uid).get();
    const accessData = (_c = accessDoc.data()) !== null && _c !== void 0 ? _c : {};
    const isPro = (0, db_1.effectivePro)(accessData);
    const onboardingDone = accessData.onboardingDone === true;
    const lastVisionAt = (_d = accessData.lastVisionAt) === null || _d === void 0 ? void 0 : _d.toDate();
    const now = Date.now();
    const intervalMs = VISION_INTERVAL_DAYS * 24 * 60 * 60 * 1000;
    const nextAvailableAt = lastVisionAt ? new Date(lastVisionAt.getTime() + intervalMs) : null;
    const available = !lastVisionAt || (nextAvailableAt && now >= nextAvailableAt.getTime());
    const result = {
        isPro,
        onboardingDone,
        lastVisionAt: (_e = lastVisionAt === null || lastVisionAt === void 0 ? void 0 : lastVisionAt.toISOString()) !== null && _e !== void 0 ? _e : null,
        nextAvailableAt: (_f = nextAvailableAt === null || nextAvailableAt === void 0 ? void 0 : nextAvailableAt.toISOString()) !== null && _f !== void 0 ? _f : null,
        available: available === true,
        intervalDays: VISION_INTERVAL_DAYS,
    };
    // Génère un access URL frais vers la formation :
    // - première session d'onboarding : toujours accessible (gratuite)
    // - révisions mensuelles suivantes : réservées aux Pro quand disponible
    if (!onboardingDone || (isPro && available)) {
        const token = createFormationToken(uid, email, process.env.FORMATION_JWT_SECRET);
        result.accessUrl = `https://app.productivitwo.com/vision?token=${encodeURIComponent(token)}`;
    }
    res.status(200).json(result);
});
exports.applyFormationProfile = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["FORMATION_JWT_SECRET"] }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const { token, profile } = req.body;
    if (!token || !profile) {
        res.status(400).json({ error: "token et profile requis" });
        return;
    }
    const decoded = verifyFormationToken(token, process.env.FORMATION_JWT_SECRET);
    if (!decoded) {
        res.status(401).json({ error: "Token invalide ou expiré" });
        return;
    }
    const { uid } = decoded;
    // Idempotence : ne pas recréer si l'onboarding est déjà fait
    const accessDoc = await db_1.db.collection("formation_access").doc(uid).get();
    if (accessDoc.exists && ((_a = accessDoc.data()) === null || _a === void 0 ? void 0 : _a.onboardingDone)) {
        res.status(200).json({ success: true, uid, alreadyApplied: true });
        return;
    }
    // Domaines
    const domainIds = [];
    for (const d of ((_b = profile.domaines) !== null && _b !== void 0 ? _b : [])) {
        const id = (0, uuid_1.v4)();
        domainIds.push(id);
        await db_1.db.collection(`users/${uid}/domains`).doc(id).set({
            id,
            name: d.name,
            goalMinDay: null,
            autoGoal: true,
            colorValue: d.color ? hexToColorValue(d.color) : null,
            createdAt: db_1.FieldValue.serverTimestamp(),
        });
    }
    // Activités de tracking (type time)
    for (const a of ((_c = profile.activites) !== null && _c !== void 0 ? _c : [])) {
        const id = (0, uuid_1.v4)();
        const domainId = (_e = domainIds[(_d = a.domaine_index) !== null && _d !== void 0 ? _d : 0]) !== null && _e !== void 0 ? _e : null;
        const isHabit = a.type === "habit";
        await db_1.db.collection(`users/${uid}/activities`).doc(id).set({
            id,
            name: a.name,
            domainId,
            type: isHabit ? "habit" : "time",
            role: "generic",
            goalMin: (_f = a.goalMin) !== null && _f !== void 0 ? _f : 1,
            unit: null,
            habitFreq: isHabit ? 0 : null,
            habitTarget: isHabit ? 1 : null,
            manualTarget: false,
            autoTune: true,
            createdAt: db_1.FieldValue.serverTimestamp(),
            lastTuneAt: null,
            order: 0,
            iconCode: null,
            deleted: false,
        });
    }
    // Routines (habit activities dans le 1er domaine)
    for (const r of ((_g = profile.routines) !== null && _g !== void 0 ? _g : [])) {
        const id = (0, uuid_1.v4)();
        await db_1.db.collection(`users/${uid}/activities`).doc(id).set({
            id,
            name: r.name,
            domainId: (_h = domainIds[0]) !== null && _h !== void 0 ? _h : null,
            type: "habit",
            role: "generic",
            goalMin: (_j = r.dureeMin) !== null && _j !== void 0 ? _j : 15,
            unit: null,
            habitFreq: 0,
            habitTarget: 1,
            manualTarget: false,
            autoTune: false,
            createdAt: db_1.FieldValue.serverTimestamp(),
            lastTuneAt: null,
            order: 0,
            iconCode: null,
            deleted: false,
        });
    }
    await db_1.db.collection("formation_access").doc(uid).update({
        onboardingDone: true,
        onboardingDoneAt: db_1.FieldValue.serverTimestamp(),
    });
    res.status(200).json({ success: true, uid });
});
// ── Couche sociale/jeu supprimée (pivot productivité) ────────────────────────
// Les 16 fonctions de social.ts (leaderboards, défis partagés, batailles,
// invasions, crons superOrion/recomputeLeaderboards) ont été retirées.
// Code récupérable sur la branche archive/couche-jeu-complete-2026-07.
// Au prochain `firebase deploy --only functions`, la CLI proposera de
// supprimer ces fonctions du projet — accepter.
// ── Mode démo ────────────────────────────────────────────────────────────────
const DEMO_UID = "demo-productivitwo";
async function _seedDemoData(uid) {
    const base = `users/${uid}`;
    const cols = ["domains", "activities", "sessions", "habitHits", "projects", "daily_schedules"];
    for (const col of cols) {
        const snap = await db_1.db.collection(`${base}/${col}`).get();
        if (snap.docs.length === 0)
            continue;
        const b = db_1.db.batch();
        snap.docs.forEach((d) => b.delete(d.ref));
        await b.commit();
    }
    const now = new Date();
    const today = now.toISOString().slice(0, 10);
    const domTravail = (0, uuid_1.v4)();
    const domSante = (0, uuid_1.v4)();
    const domApprentissage = (0, uuid_1.v4)();
    const actDeepWork = (0, uuid_1.v4)();
    const actRunning = (0, uuid_1.v4)();
    const actLecture = (0, uuid_1.v4)();
    const actMeditation = (0, uuid_1.v4)();
    const proj1 = (0, uuid_1.v4)();
    const proj2 = (0, uuid_1.v4)();
    const phase1a = (0, uuid_1.v4)(), phase1b = (0, uuid_1.v4)();
    const phase2a = (0, uuid_1.v4)(), phase2b = (0, uuid_1.v4)();
    const t1 = (0, uuid_1.v4)(), t2 = (0, uuid_1.v4)(), t3 = (0, uuid_1.v4)(), t4 = (0, uuid_1.v4)();
    const t5 = (0, uuid_1.v4)(), t6 = (0, uuid_1.v4)(), t7 = (0, uuid_1.v4)();
    const batch = db_1.db.batch();
    // Domaines
    batch.set(db_1.db.doc(`${base}/domains/${domTravail}`), {
        id: domTravail, name: "Travail", goalMinDay: 120, autoGoal: false,
        colorValue: 0xFF2196F3, deleted: false,
    });
    batch.set(db_1.db.doc(`${base}/domains/${domSante}`), {
        id: domSante, name: "Santé", goalMinDay: 60, autoGoal: false,
        colorValue: 0xFF4CAF50, deleted: false,
    });
    batch.set(db_1.db.doc(`${base}/domains/${domApprentissage}`), {
        id: domApprentissage, name: "Apprentissage", goalMinDay: 30, autoGoal: false,
        colorValue: 0xFFFF9800, deleted: false,
    });
    // Activités
    batch.set(db_1.db.doc(`${base}/activities/${actDeepWork}`), {
        id: actDeepWork, name: "Deep Work", domainId: domTravail,
        type: "time", role: "generic", goalMin: 120, unit: null,
        habitFreq: null, habitTarget: null, manualTarget: false, autoTune: true,
        targetSource: "default", linkedActivityId: null,
        createdAt: db_1.FieldValue.serverTimestamp(), lastTuneAt: null,
        order: 0, iconCode: null, deleted: false, todayFlag: true, timerMin: null,
    });
    batch.set(db_1.db.doc(`${base}/activities/${actRunning}`), {
        id: actRunning, name: "Running", domainId: domSante,
        type: "habit", role: "generic", goalMin: 30, unit: null,
        habitFreq: 0, habitTarget: 1, manualTarget: false, autoTune: true,
        targetSource: "default", linkedActivityId: null,
        createdAt: db_1.FieldValue.serverTimestamp(), lastTuneAt: null,
        order: 1, iconCode: null, deleted: false, todayFlag: false, timerMin: null,
    });
    batch.set(db_1.db.doc(`${base}/activities/${actLecture}`), {
        id: actLecture, name: "Lecture", domainId: domApprentissage,
        type: "time", role: "generic", goalMin: 30, unit: null,
        habitFreq: null, habitTarget: null, manualTarget: false, autoTune: true,
        targetSource: "default", linkedActivityId: null,
        createdAt: db_1.FieldValue.serverTimestamp(), lastTuneAt: null,
        order: 2, iconCode: null, deleted: false, todayFlag: false, timerMin: null,
    });
    batch.set(db_1.db.doc(`${base}/activities/${actMeditation}`), {
        id: actMeditation, name: "Méditation", domainId: domSante,
        type: "habit", role: "generic", goalMin: 15, unit: null,
        habitFreq: 0, habitTarget: 1, manualTarget: false, autoTune: true,
        targetSource: "default", linkedActivityId: null,
        createdAt: db_1.FieldValue.serverTimestamp(), lastTuneAt: null,
        order: 3, iconCode: null, deleted: false, todayFlag: false, timerMin: null,
    });
    // Sessions Deep Work — 7 derniers jours (ISO string, pas Timestamp)
    for (let i = 6; i >= 0; i--) {
        const d = new Date(now);
        d.setDate(d.getDate() - i);
        const durMin = i === 0 ? 90 : (i % 2 === 0 ? 120 : 105);
        const startAt = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 9, 0, 0);
        const endAt = new Date(startAt.getTime() + durMin * 60000);
        const sessId = (0, uuid_1.v4)();
        batch.set(db_1.db.doc(`${base}/sessions/${sessId}`), {
            id: sessId, activityId: actDeepWork,
            startAt: startAt.toISOString(),
            endAt: endAt.toISOString(),
        });
    }
    // Sessions Lecture — jours pairs sur 7 jours
    for (let i = 6; i >= 1; i -= 2) {
        const d = new Date(now);
        d.setDate(d.getDate() - i);
        const startAt = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 21, 0, 0);
        const endAt = new Date(startAt.getTime() + 35 * 60000);
        const sessId = (0, uuid_1.v4)();
        batch.set(db_1.db.doc(`${base}/sessions/${sessId}`), {
            id: sessId, activityId: actLecture,
            startAt: startAt.toISOString(),
            endAt: endAt.toISOString(),
        });
    }
    // HabitHits Running — 6/7 (skip i=3)
    for (let i = 6; i >= 0; i--) {
        if (i === 3)
            continue;
        const d = new Date(now);
        d.setDate(d.getDate() - i);
        const ts = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 7, 30, 0);
        const hitId = (0, uuid_1.v4)();
        batch.set(db_1.db.doc(`${base}/habitHits/${hitId}`), {
            id: hitId, habitId: actRunning,
            ts: ts.toISOString(),
            contextActivityId: null,
        });
    }
    // HabitHits Méditation — 5/7 (skip i=2 et i=5)
    for (let i = 6; i >= 0; i--) {
        if (i === 2 || i === 5)
            continue;
        const d = new Date(now);
        d.setDate(d.getDate() - i);
        const ts = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 8, 0, 0);
        const hitId = (0, uuid_1.v4)();
        batch.set(db_1.db.doc(`${base}/habitHits/${hitId}`), {
            id: hitId, habitId: actMeditation,
            ts: ts.toISOString(),
            contextActivityId: null,
        });
    }
    const proj1Start = new Date(now.getTime() - 21 * 86400000);
    const proj1End = new Date(now.getTime() + 35 * 86400000);
    const proj2Start = new Date(now.getTime() - 7 * 86400000);
    const proj2End = new Date(now.getTime() + 28 * 86400000);
    batch.set(db_1.db.doc(`${base}/projects/${proj1}`), {
        id: proj1, title: "Application mobile v2",
        description: "Refonte complète de l'interface mobile avec nouvelles features gamification",
        domainId: domTravail, parentProjectId: null,
        startDate: proj1Start.toISOString(), endDate: proj1End.toISOString(),
        status: "active",
        phases: [
            { id: phase1a, name: "Design", order: 0 },
            { id: phase1b, name: "Développement", order: 1 },
        ],
        tasks: [
            {
                id: t1, title: "Wireframes & maquettes", phaseId: phase1a,
                startDate: proj1Start.toISOString(),
                endDate: new Date(now.getTime() - 14 * 86400000).toISOString(),
                status: "done", isMilestone: false, todayFlag: false, actions: [],
                description: null, groupLabel: null, color: null, barLabel: null,
            },
            {
                id: t2, title: "Design system", phaseId: phase1a,
                startDate: new Date(now.getTime() - 14 * 86400000).toISOString(),
                endDate: new Date(now.getTime() - 2 * 86400000).toISOString(),
                status: "done", isMilestone: false, todayFlag: false, actions: [],
                description: null, groupLabel: null, color: null, barLabel: null,
            },
            {
                id: t3, title: "Développement écrans", phaseId: phase1b,
                startDate: new Date(now.getTime() - 3 * 86400000).toISOString(),
                endDate: new Date(now.getTime() + 21 * 86400000).toISOString(),
                status: "pending", isMilestone: false, todayFlag: true,
                description: null, groupLabel: null, color: null, barLabel: null,
                actions: [
                    { id: (0, uuid_1.v4)(), title: "Écran d'accueil", done: true },
                    { id: (0, uuid_1.v4)(), title: "Vue projets", done: true },
                    { id: (0, uuid_1.v4)(), title: "Vue programme", done: false },
                    { id: (0, uuid_1.v4)(), title: "Vue statistiques", done: false },
                ],
            },
            {
                id: t4, title: "Tests & publication", phaseId: phase1b,
                startDate: new Date(now.getTime() + 21 * 86400000).toISOString(),
                endDate: proj1End.toISOString(),
                status: "pending", isMilestone: false, todayFlag: false, actions: [],
                description: null, groupLabel: null, color: null, barLabel: null,
            },
        ],
        createdBy: uid, sourceType: "manual", source: "user", originIdeas: [],
        createdAt: proj1Start.toISOString(), updatedAt: null,
    });
    batch.set(db_1.db.doc(`${base}/projects/${proj2}`), {
        id: proj2, title: "Lancement marketing",
        description: "Stratégie de contenu et acquisition pour le lancement beta",
        domainId: domTravail, parentProjectId: null,
        startDate: proj2Start.toISOString(), endDate: proj2End.toISOString(),
        status: "active",
        phases: [
            { id: phase2a, name: "Contenu", order: 0 },
            { id: phase2b, name: "Distribution", order: 1 },
        ],
        tasks: [
            {
                id: t5, title: "Landing page", phaseId: phase2a,
                startDate: proj2Start.toISOString(),
                endDate: new Date(now.getTime() + 7 * 86400000).toISOString(),
                status: "pending", isMilestone: false, todayFlag: false,
                description: null, groupLabel: null, color: null, barLabel: null,
                actions: [
                    { id: (0, uuid_1.v4)(), title: "Rédaction copywriting", done: true },
                    { id: (0, uuid_1.v4)(), title: "Design maquette", done: false },
                ],
            },
            {
                id: t6, title: "Série d'emails beta", phaseId: phase2a,
                startDate: new Date(now.getTime() + 7 * 86400000).toISOString(),
                endDate: new Date(now.getTime() + 14 * 86400000).toISOString(),
                status: "pending", isMilestone: false, todayFlag: false, actions: [],
                description: null, groupLabel: null, color: null, barLabel: null,
            },
            {
                id: t7, title: "Campagne LinkedIn", phaseId: phase2b,
                startDate: new Date(now.getTime() + 14 * 86400000).toISOString(),
                endDate: proj2End.toISOString(),
                status: "pending", isMilestone: false, todayFlag: false, actions: [],
                description: null, groupLabel: null, color: null, barLabel: null,
            },
        ],
        createdBy: uid, sourceType: "manual", source: "user", originIdeas: [],
        createdAt: proj2Start.toISOString(), updatedAt: null,
    });
    // Programme du jour
    batch.set(db_1.db.doc(`${base}/daily_schedules/${today}`), {
        date: today,
        generatedBy: "claude",
        generatedAt: db_1.FieldValue.serverTimestamp(),
        blocks: [
            {
                id: (0, uuid_1.v4)(), startTime: "09:00", durationMin: 90,
                title: "Deep Work — Application mobile",
                category: "project", projectId: proj1, taskId: t3,
                activityId: actDeepWork, status: "done",
                doneAt: new Date(now.getFullYear(), now.getMonth(), now.getDate(), 10, 30, 0).toISOString(),
                challenge: false, reminders: [],
            },
            {
                id: (0, uuid_1.v4)(), startTime: "10:45", durationMin: 30,
                title: "Running matinal",
                category: "routine", projectId: null, taskId: null,
                activityId: actRunning, status: "pending",
                doneAt: null, challenge: false, reminders: [],
            },
            {
                id: (0, uuid_1.v4)(), startTime: "14:00", durationMin: 120,
                title: "Développement — Écrans mobiles",
                category: "project", projectId: proj1, taskId: t3,
                activityId: null, status: "pending",
                doneAt: null, challenge: false, reminders: [],
            },
            {
                id: (0, uuid_1.v4)(), startTime: "20:30", durationMin: 30,
                title: "Lecture",
                category: "routine", projectId: null, taskId: null,
                activityId: actLecture, status: "pending",
                doneAt: null, challenge: false, reminders: [],
            },
        ],
    });
    batch.set(db_1.db.doc(`${base}/meta/demo`), {
        seededAt: db_1.FieldValue.serverTimestamp(),
        today,
        schemaVersion: 3,
    });
    // ── Méta gamification (économie d'or + expédition) ────────────────────────
    // users/{uid}/data/meta = document lu par FirestoreSync.pull()
    batch.set(db_1.db.doc(`${base}/data/meta`), {
        // Or et niveau
        gold: 247,
        goldLifetime: 1640,
        goldLastProcessedDay: today,
        goldEpochYmd: new Date(now.getTime() - 30 * 86400000).toISOString().slice(0, 10),
        goldTodayGain: 42,
        goldTodayGainYmd: today,
        unlockedLevel: 3,
        // Inventaire de consommables
        goldInventory: { gel: 1, sursis: 0, joker: 0, shield: 1, boost: 0 },
        goldGelDays: [],
        goldTaskShieldDays: [],
        goldBoostDays: [],
        // Armes dépensées (les armes GAGNÉES sont dérivées des données)
        weaponsSpent: { sandale: 2, arc: 1, epee: 1 },
        // Kills de nuisibles
        pestKills: { spider: 3, scorpion: 1, snake: 0 },
        // Combats engagés : araignée sur Running, scorpion sur Méditation
        engagedEnemies: [`spider~${actRunning}`, `scorpion~${actMeditation}`],
        // Exploration overworld
        expeditionDonjonLevel: 0,
        expeditionGuardianKilledLevel: 0,
        expeditionCleared: [],
        expeditionRevealed: ["2_2", "2_3", "3_2", "3_3", "2_1"],
        expeditionPos: "2_2",
        expeditionPicked: [],
        expeditionEntities: [],
        expeditionChallenges: [],
        lastFreeStepYmd: today,
        lastPestDrainAt: null,
        // Défis
        challengesDone: 5,
        challengeStreak: 3,
        lastChallengeYmd: today,
        questStreak: 2,
        lastQuestClaimedYmd: today,
        // Collections
        collection: [],
        collectionMeta: {},
        cosmeticsOwned: [],
        activeTitle: null,
        activeAvatar: null,
        // Divers
        onboardingDone: true,
        ganttActionsByDay: { [today.replace(/-/g, "")]: 2 },
        challengeWinsByDay: {},
        weeklyScoreTarget: 80,
        notifEnabled: false,
        donjonKeysUsed: [],
        donjonKeysYmd: today,
    });
    await batch.commit();
}
exports.getDemoToken = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c, _d;
    try {
        const today = new Date().toISOString().slice(0, 10);
        const metaRef = db_1.db.doc(`users/${DEMO_UID}/meta/demo`);
        const meta = await metaRef.get();
        const SCHEMA_VERSION = 3;
        if (!meta.exists || ((_b = (_a = meta.data()) === null || _a === void 0 ? void 0 : _a.today) !== null && _b !== void 0 ? _b : "") !== today || ((_d = (_c = meta.data()) === null || _c === void 0 ? void 0 : _c.schemaVersion) !== null && _d !== void 0 ? _d : 0) < SCHEMA_VERSION) {
            await _seedDemoData(DEMO_UID);
        }
        const token = await admin.auth().createCustomToken(DEMO_UID, { demo: true });
        res.json({ token });
    }
    catch (e) {
        console.error("getDemoToken error:", e);
        res.status(500).json({ error: String(e) });
    }
});
exports.resetDemoData = (0, scheduler_1.onSchedule)("0 4 * * *", async () => {
    await _seedDemoData(DEMO_UID);
});
//# sourceMappingURL=index.js.map