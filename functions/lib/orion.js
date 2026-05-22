"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getOrionConfig = getOrionConfig;
exports.saveOrionConfig = saveOrionConfig;
exports.getOrionRunCount = getOrionRunCount;
exports.runOrionCycle = runOrionCycle;
exports.getAllActiveUserIds = getAllActiveUserIds;
const sdk_1 = require("@anthropic-ai/sdk");
const db_1 = require("./db");
const execute_1 = require("./execute");
const ORION_MAX_RUNS = 5;
const ORION_MODEL = "claude-haiku-4-5-20251001";
// ── Config utilisateur ────────────────────────────────────────────────────────
async function getOrionConfig(uid) {
    var _a, _b, _c, _d;
    const snap = await db_1.db.collection(`users/${uid}/orion_config`).doc("main").get();
    if (!snap.exists)
        return { userNeeds: "", userReply: "", replyTimestamp: null };
    const d = (_a = snap.data()) !== null && _a !== void 0 ? _a : {};
    return {
        userNeeds: (_b = d.userNeeds) !== null && _b !== void 0 ? _b : "",
        userReply: (_c = d.userReply) !== null && _c !== void 0 ? _c : "",
        replyTimestamp: (_d = d.replyTimestamp) !== null && _d !== void 0 ? _d : null,
    };
}
async function saveOrionConfig(uid, fields) {
    const update = { updatedAt: db_1.FieldValue.serverTimestamp() };
    if (fields.userNeeds !== undefined)
        update.userNeeds = fields.userNeeds;
    if (fields.userReply !== undefined) {
        update.userReply = fields.userReply;
        update.replyTimestamp = new Date().toISOString().slice(0, 10);
    }
    await db_1.db.collection(`users/${uid}/orion_config`).doc("main").set(update, { merge: true });
}
// ── Rate limiting ─────────────────────────────────────────────────────────────
async function getOrionRunCount(uid, date) {
    var _a, _b;
    const snap = await db_1.db.collection("orion_runs").doc(`${uid}_${date}`).get();
    return snap.exists ? ((_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.count) !== null && _b !== void 0 ? _b : 0) : 0;
}
async function incrementOrionRunCount(uid, date) {
    await db_1.db
        .collection("orion_runs")
        .doc(`${uid}_${date}`)
        .set({ count: db_1.FieldValue.increment(1), uid, date }, { merge: true });
}
// ── Cycle ORION ───────────────────────────────────────────────────────────────
async function runOrionCycle(uid) {
    var _a;
    const today = new Date().toISOString().slice(0, 10);
    const count = await getOrionRunCount(uid, today);
    if (count >= ORION_MAX_RUNS) {
        return { skipped: true, reason: `Limite journalière atteinte (${count}/${ORION_MAX_RUNS})` };
    }
    // Incrémenter avant l'appel Claude (évite les doublons en cas de retry)
    await incrementOrionRunCount(uid, today);
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey)
        throw new Error("ANTHROPIC_API_KEY non configurée dans Firebase Secret Manager");
    const config = await getOrionConfig(uid);
    const client = new sdk_1.default({ apiKey });
    const userContext = [
        config.userNeeds
            ? `Instructions persistantes de l'utilisateur :\n${config.userNeeds}`
            : "",
        config.userReply
            ? `Dernière réponse de l'utilisateur à ORION (${(_a = config.replyTimestamp) !== null && _a !== void 0 ? _a : "récent"}) :\n${config.userReply}`
            : "",
    ]
        .filter(Boolean)
        .join("\n\n");
    const systemPrompt = `Tu es ORION, l'assistant IA autonome de Productivitwo. Tu fonctionnes silencieusement en arrière-plan pour soutenir l'utilisateur dans sa productivité et ses objectifs.

Date du jour : ${today}${userContext ? `\n\n${userContext}` : ""}

Mission pour ce cycle :
1. Appelle get_assistant_messages — vérifie les messages ORION en attente pour éviter les doublons.
2. Appelle get_user_context — analyse l'état actuel (activités, objectifs, projets, plan du jour).
3. Génère 1 ou 2 messages ORION pertinents et non-redondants via push_assistant_message.

Règles impératives :
- Aucun doublon avec les messages pending existants.
- Messages courts (< 180 caractères), bienveillants, concrets, actionnables.
- Utilise des conditions contextuelles adaptées (project_deadline_near, overdue_count, week_start, etc.).
- targetDate = aujourd'hui (${today}) ou demain au maximum.
- characterName toujours "ORION".
- Si userReply est fourni, adapte le message en tenant compte de ce retour utilisateur.`;
    // Tools ORION : lecture + push uniquement
    const tools = [
        {
            name: "get_user_context",
            description: "Retourne le contexte complet de l'utilisateur (activités, objectifs, plan du jour, projets).",
            input_schema: { type: "object", properties: {}, required: [] },
        },
        {
            name: "get_assistant_messages",
            description: "Liste les messages ORION en attente et récents. Appeler en premier pour éviter les doublons.",
            input_schema: { type: "object", properties: {}, required: [] },
        },
        {
            name: "push_assistant_message",
            description: "Planifie un message ORION contextuel pour l'utilisateur.",
            input_schema: {
                type: "object",
                properties: {
                    targetDate: { type: "string", description: "Date YYYY-MM-DD" },
                    text: { type: "string", description: "Texte du message (max 180 chars)" },
                    condition: {
                        type: "object",
                        description: "Condition d'affichage. Ex: {type:'always'} ou {type:'overdue_count',min:2}",
                    },
                    expiresAfterDays: { type: "number", description: "Durée d'expiration en jours (défaut: 2)" },
                    priority: { type: "number", description: "Priorité 1 (haute) à 5 (basse)" },
                },
                required: ["targetDate", "text", "condition"],
            },
            // Cache les tool schemas (statiques entre appels)
            cache_control: { type: "ephemeral" },
        },
    ];
    const messages = [
        { role: "user", content: "Effectue ton analyse et génère les messages ORION pour aujourd'hui." },
    ];
    let pushedCount = 0;
    let continueLoop = true;
    while (continueLoop) {
        const response = await client.beta.promptCaching.messages.create({
            model: ORION_MODEL,
            max_tokens: 1024,
            system: [
                {
                    type: "text",
                    text: systemPrompt,
                    cache_control: { type: "ephemeral" },
                },
            ],
            tools,
            messages,
        });
        messages.push({ role: "assistant", content: response.content });
        if (response.stop_reason === "end_turn") {
            continueLoop = false;
            break;
        }
        if (response.stop_reason === "tool_use") {
            const toolResults = [];
            for (const block of response.content) {
                if (block.type !== "tool_use")
                    continue;
                let result = "";
                try {
                    if (block.name === "get_user_context") {
                        result = await (0, execute_1.executeGetUserContext)(uid);
                    }
                    else if (block.name === "get_assistant_messages") {
                        result = await (0, execute_1.executeGetAssistantMessages)(uid);
                    }
                    else if (block.name === "push_assistant_message") {
                        result = await (0, execute_1.executePushAssistantMessage)(uid, block.input);
                        pushedCount++;
                    }
                    else {
                        result = `Outil non disponible dans ORION : ${block.name}`;
                    }
                }
                catch (e) {
                    result = `Erreur outil ${block.name} : ${e instanceof Error ? e.message : String(e)}`;
                }
                toolResults.push({
                    type: "tool_result",
                    tool_use_id: block.id,
                    content: result,
                });
            }
            messages.push({ role: "user", content: toolResults });
        }
        else {
            continueLoop = false;
        }
    }
    return { skipped: false, pushed: pushedCount };
}
// ── Itération sur tous les users actifs (pour le cron) ────────────────────────
async function getAllActiveUserIds() {
    const snap = await db_1.db
        .collectionGroup("api_tokens")
        .where("active", "==", true)
        .get();
    const uids = new Set();
    for (const doc of snap.docs) {
        // path : users/{uid}/api_tokens/{id}
        const parts = doc.ref.path.split("/");
        if (parts.length >= 2)
            uids.add(parts[1]);
    }
    return [...uids];
}
//# sourceMappingURL=orion.js.map