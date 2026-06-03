"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getOrionConfig = getOrionConfig;
exports.saveOrionConfig = saveOrionConfig;
exports.getOrionRunCount = getOrionRunCount;
exports.incrementOrionRunCount = incrementOrionRunCount;
exports.writeCycleLog = writeCycleLog;
exports.runOrionCycle = runOrionCycle;
exports.getAllActiveUserIds = getAllActiveUserIds;
const sdk_1 = require("@anthropic-ai/sdk");
const models_1 = require("./models");
const db_1 = require("./db");
const execute_1 = require("./execute");
// Descriptions compactes pour ORION — ~10x moins de tokens que les tools MCP complets
const ORION_TOOLS = [
    { name: "get_orion_context", description: "Contexte utilisateur : domaines, activités, routines, objectifs, projets actifs (tâches urgentes), plan du jour résumé, stats 7j.", input_schema: { type: "object", properties: {}, required: [] } },
    { name: "get_assistant_messages", description: "Messages ORION en attente et récents. Appeler en premier pour éviter les doublons.", input_schema: { type: "object", properties: {}, required: [] } },
    { name: "get_day_blocks", description: "Blocs de journée configurés.", input_schema: { type: "object", properties: {}, required: [] } },
    { name: "get_documents", description: "Documents de l'utilisateur, filtrables par projectId/taskId.", input_schema: { type: "object", properties: { projectId: { type: "string" }, taskId: { type: "string" } }, required: [] } },
    { name: "get_archives", description: "Éléments archivés/supprimés.", input_schema: { type: "object", properties: {}, required: [] } },
    { name: "list_projects", description: "Liste résumée des projets Gantt.", input_schema: { type: "object", properties: {}, required: [] } },
    { name: "get_project", description: "Détail complet d'un projet Gantt (phases, tâches, IDs).", input_schema: { type: "object", properties: { projectId: { type: "string" } }, required: ["projectId"] } },
    { name: "create_activity", description: "Crée une activité (temps ou habitude).", input_schema: { type: "object", properties: { name: { type: "string" }, type: { type: "string" }, domainId: { type: "string" } }, required: ["name", "type", "domainId"] } },
    { name: "update_activity", description: "Met à jour une activité.", input_schema: { type: "object", properties: { activityId: { type: "string" } }, required: ["activityId"] } },
    { name: "update_activity_goal", description: "Met à jour l'objectif quotidien d'une activité.", input_schema: { type: "object", properties: { activityId: { type: "string" }, goalMin: { type: "number" } }, required: ["activityId"] } },
    { name: "set_activity_targets", description: "Pose/ajuste en lot l'intention de temps (goalMin) de plusieurs activités. Respecte les cibles épinglées par l'utilisateur (jamais écrasées). N'affecte PAS le score, seulement la jauge de temps. À utiliser pour le seed de démarrage et le rééquilibrage du budget temps.", input_schema: { type: "object", required: ["targets"], properties: { targets: { type: "array", items: { type: "object", required: ["activityId", "goalMin"], properties: { activityId: { type: "string" }, goalMin: { type: "number" } } } } } } },
    { name: "delete_activity", description: "Supprime (soft-delete) une activité.", input_schema: { type: "object", properties: { activityId: { type: "string" } }, required: ["activityId"] } },
    { name: "create_routine", description: "Crée une routine mesurable (habitude trackée : fréquence + cible).", input_schema: { type: "object", properties: { name: { type: "string" }, domainId: { type: "string" }, unit: { type: "string" }, habitFreq: { type: "number", description: "0=daily, 1=weekly, 2=monthly" }, habitTarget: { type: "number" }, activityId: { type: "string", description: "optionnel" } }, required: ["name", "domainId"] } },
    { name: "delete_routine", description: "Supprime une routine.", input_schema: { type: "object", properties: { routineId: { type: "string" } }, required: ["routineId"] } },
    { name: "create_domain", description: "Crée un domaine de vie.", input_schema: { type: "object", properties: { name: { type: "string" } }, required: ["name"] } },
    { name: "delete_domain", description: "Supprime un domaine.", input_schema: { type: "object", properties: { domainId: { type: "string" } }, required: ["domainId"] } },
    { name: "update_project", description: "Met à jour les champs d'un projet Gantt.", input_schema: { type: "object", properties: { projectId: { type: "string" } }, required: ["projectId"] } },
    { name: "update_task_status", description: "Change le statut d'une tâche (pending/done/skipped).", input_schema: { type: "object", properties: { projectId: { type: "string" }, taskId: { type: "string" }, status: { type: "string" } }, required: ["projectId", "taskId", "status"] } },
    { name: "archive_project", description: "Archive ou restaure un projet.", input_schema: { type: "object", properties: { projectId: { type: "string" }, restore: { type: "boolean" } }, required: ["projectId"] } },
    { name: "delete_project", description: "Supprime définitivement un projet.", input_schema: { type: "object", properties: { projectId: { type: "string" }, deleteObjective: { type: "boolean" } }, required: ["projectId"] } },
    { name: "push_gantt", description: "Crée ou met à jour un projet Gantt. TOUJOURS inclure phases[] ET tasks[] — sans tasks le projet sera vide.", input_schema: { type: "object", required: ["project"], properties: { project: { type: "object", required: ["title", "startDate", "tasks"], properties: { title: { type: "string" }, description: { type: "string" }, domainId: { type: "string" }, startDate: { type: "string", description: "YYYY-MM-DD" }, endDate: { type: "string", description: "YYYY-MM-DD" }, phases: { type: "array", items: { type: "object", required: ["id", "label", "startDate", "endDate"], properties: { id: { type: "string", description: "ex: phase-1" }, label: { type: "string" }, startDate: { type: "string" }, endDate: { type: "string" }, color: { type: "string" } } } }, tasks: { type: "array", description: "OBLIGATOIRE : au moins 2 tâches par phase", items: { type: "object", required: ["id", "title", "startDate"], properties: { id: { type: "string", description: "ex: task-1" }, title: { type: "string" }, phaseId: { type: "string" }, startDate: { type: "string", description: "YYYY-MM-DD" }, endDate: { type: "string", description: "YYYY-MM-DD" }, isMilestone: { type: "boolean" }, status: { type: "string", enum: ["pending", "done", "skipped"] } } } } } } } } },
    { name: "save_document", description: "Sauvegarde un document HTML.", input_schema: { type: "object", properties: { title: { type: "string" }, content: { type: "string" } }, required: ["title", "content"] } },
    { name: "delete_document", description: "Supprime un document.", input_schema: { type: "object", properties: { documentId: { type: "string" } }, required: ["documentId"] } },
    { name: "restore_item", description: "Restaure un élément archivé.", input_schema: { type: "object", properties: { collection: { type: "string" }, itemId: { type: "string" } }, required: ["collection", "itemId"] } },
    { name: "push_assistant_message", description: "Planifie un message ORION contextuel. Utilise requiresReply:true pour les messages de clarification (l'utilisateur doit répondre) — ils s'affichent sans limite et disparaissent dès que l'utilisateur répond.", input_schema: { type: "object", properties: { targetDate: { type: "string" }, text: { type: "string" }, condition: { type: "object" }, expiresAfterDays: { type: "number" }, priority: { type: "number" }, requiresReply: { type: "boolean" } }, required: ["targetDate", "text", "condition"] } },
    { name: "delete_assistant_message", description: "Supprime un message ORION.", input_schema: { type: "object", properties: { messageId: { type: "string" } }, required: ["messageId"] } },
    { name: "get_orion_queue", description: "File de travail : instructions spécifiques que l'utilisateur a envoyées en réponse à un message ORION. À lire EN PREMIER, avant l'inbox. Chaque item est une action concrète à exécuter immédiatement.", input_schema: { type: "object", properties: {}, required: [] } },
    { name: "delete_orion_queue_item", description: "Supprime un item de la file après traitement.", input_schema: { type: "object", properties: { itemId: { type: "string" } }, required: ["itemId"] } },
    { name: "get_inbox", description: "Idées et notes capturées par l'utilisateur en attente de traitement.", input_schema: { type: "object", properties: {}, required: [] } },
    { name: "process_inbox_item", description: "Marque une idée inbox comme traitée avec une note expliquant l'action prise.", input_schema: { type: "object", properties: { itemId: { type: "string" }, note: { type: "string", description: "Ce qu'ORION a fait : ex: 'ajouté comme tâche dans Projet X' ou 'message reminder planifié'" } }, required: ["itemId", "note"] } },
    { name: "get_day_schedule", description: "Lit le programme horaire d'une journée.", input_schema: { type: "object", properties: { date: { type: "string", description: "YYYY-MM-DD" } }, required: ["date"] } },
    { name: "update_schedule_block", description: "Met à jour le statut d'un bloc du programme du jour (done/skipped/deleted/pending) sans écraser tout le programme.", input_schema: { type: "object", properties: { date: { type: "string", description: "YYYY-MM-DD" }, blockTitle: { type: "string", description: "Titre (partiel) du bloc à modifier" }, status: { type: "string", enum: ["done", "skipped", "deleted", "pending"] } }, required: ["date", "blockTitle", "status"] } },
    { name: "compute_time_budget", description: "Calcule le budget temps 24h basé sur 12 semaines de sessions réelles. Retourne le goalMin recommandé par activité (stretch avg×1.10) et le sommeil résiduel pour sommer à 1440 min/j. À appeler le lundi avant update_activity_goal.", input_schema: { type: "object", properties: {}, required: [] } },
    { name: "schedule_day", description: "Crée ou remplace le programme horaire complet d'une journée.", input_schema: { type: "object", properties: { date: { type: "string" }, blocks: { type: "array", items: { type: "object", required: ["startTime", "durationMin", "title", "category"], properties: { startTime: { type: "string" }, durationMin: { type: "number" }, title: { type: "string" }, category: { type: "string", enum: ["project", "routine", "personal", "break"] }, projectId: { type: "string" }, taskId: { type: "string" }, activityId: { type: "string" } } } } }, required: ["date", "blocks"], }, cache_control: { type: "ephemeral" } },
];
const ORION_MAX_FREE = 1; // Gratuit : 1 cycle/jour
const ORION_MAX_PRO = 5; // Pro : 5 cycles/jour
const ORION_MODEL = models_1.MODELS.HAIKU;
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
        update.replyTimestamp = (0, execute_1.todayInParis)();
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
// ── Log de cycle ──────────────────────────────────────────────────────────────
async function writeCycleLog(uid, log) {
    const { v4: uuidv4 } = await Promise.resolve().then(() => require("uuid"));
    await db_1.db.collection(`users/${uid}/orion_logs`).doc(uuidv4()).set(Object.assign(Object.assign({}, log), { cycleAt: db_1.FieldValue.serverTimestamp() }));
}
// ── Cycle ORION — accès complet à tous les tools ──────────────────────────────
async function runOrionCycle(uid, opts) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l;
    const today = (0, execute_1.todayInParis)();
    const count = await getOrionRunCount(uid, today);
    // Limite appliquée CÔTÉ SERVEUR selon le statut Pro effectif (Firestore) —
    // infalsifiable, contrairement à la limite affichée par le client.
    const accessSnap = await db_1.db.collection("formation_access").doc(uid).get();
    const max = (0, db_1.effectivePro)(accessSnap.data()) ? ORION_MAX_PRO : ORION_MAX_FREE;
    if (count >= max) {
        const reason = `Limite journalière atteinte (${count}/${max})`;
        await writeCycleLog(uid, { userNeeds: "", userReply: "", actions: [], pushed: 0, skipped: true, skippedReason: reason });
        return { skipped: true, reason };
    }
    // isOnboarding → on ne décompte pas cette action stratégique
    if (!(opts === null || opts === void 0 ? void 0 : opts.skipCount)) {
        await incrementOrionRunCount(uid, today);
    }
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey)
        throw new Error("ANTHROPIC_API_KEY non configurée dans Firebase Secret Manager");
    const config = await getOrionConfig(uid);
    const client = new sdk_1.default({ apiKey });
    const userContext = [
        config.userNeeds ? `Instructions de l'utilisateur :\n${config.userNeeds}` : "",
        config.userReply
            ? `Dernière réponse de l'utilisateur (${(_a = config.replyTimestamp) !== null && _a !== void 0 ? _a : "récent"}) :\n${config.userReply}`
            : "",
    ]
        .filter(Boolean)
        .join("\n\n");
    const nowParis = new Date().toLocaleString("fr-FR", { timeZone: "Europe/Paris", hour: "2-digit", minute: "2-digit" });
    const hourParis = new Date(new Date().toLocaleString("en-US", { timeZone: "Europe/Paris" })).getHours();
    const timeSlot = hourParis < 10 ? "matin" : hourParis < 13 ? "fin de matinée" : hourParis < 17 ? "après-midi" : hourParis < 21 ? "soirée" : "nuit";
    const systemPrompt = `Tu es ORION, l'assistant d'exécution de Productivitwo. L'utilisateur te donne une demande ; tu l'exécutes avec les outils disponibles, puis tu réponds par UN SEUL message-résumé de ce que tu as fait. Tu n'es PAS un coach qui envoie des conseils spontanés — le proactif (brief quotidien) est géré ailleurs.

Date et heure : ${today} ${nowParis} (${timeSlot})${userContext ? `\n\n${userContext}` : ""}

## Contexte déjà disponible

Le contexte utilisateur et les messages ORION existants sont fournis directement dans le message — tu n'as PAS besoin d'appeler get_orion_context ou get_assistant_messages.

## Workflow OBLIGATOIRE

1. Lis le contexte et les messages existants dans le message fourni.
2. **PRIORITÉ ABSOLUE** : appelle get_orion_queue — si des instructions y sont en attente, exécute-les IMMÉDIATEMENT comme actions concrètes (push_gantt, update_project, create_activity…), puis delete_orion_queue_item pour chaque item traité. Ne passe à l'étape suivante qu'après avoir vidé la file.
3. Appelle get_inbox — si des idées sont en attente, traite-les (voir règles inbox ci-dessous).
4. Exécute la demande de l'utilisateur avec les outils appropriés.
5. **Termine par EXACTEMENT 1 push_assistant_message** = le résumé de ce que tu as fait (la réponse à la demande), à la première personne ("J'ai replanifié…", "J'ai créé…").

## Si tu as besoin d'une clarification

Si — et seulement si — il te manque une information pour exécuter, NE fais PAS le message-résumé : pose plutôt 1 à 2 questions via push_assistant_message avec requiresReply:true (JAMAIS plus de 2). L'utilisateur y répondra directement.

## Traitement de l'inbox

L'utilisateur peut capturer des idées rapides dans son inbox. À chaque cycle, tu lis ces idées et tu les traites selon leur nature :

- **Note ponctuelle** ("acheter du lait", "appeler X", rappel) → push_assistant_message avec condition always pour aujourd'hui ou demain + process_inbox_item(note: "message reminder planifié pour le [date]")
- **Idée liée à un projet existant** → ajoute une sous-action à la tâche pertinente ou mets à jour le projet + process_inbox_item(note: "ajouté comme sous-action dans [projet > tâche]")
- **Nouvelle initiative / projet** → push_gantt pour créer le projet + process_inbox_item(note: "projet '[titre]' créé")
- **Idée vague ou hors scope** → process_inbox_item(note: "noté — pas d'action immédiate") + optionnel: push_assistant_message pour demander de clarifier

Appelle toujours process_inbox_item après avoir traité une idée. Ne laisse jamais une idée pending non traitée.

Ne répète jamais un message récent — vérifie recentShown pour éviter les doublons.

## Types d'instructions et réponses attendues

**"Analyse mes retards / propose un plan de rattrapage"**
→ Lis projects[].urgentTasks dans le contexte
→ Pousse 1 message-résumé listant les retards et un plan d'action concret
→ targetDate = aujourd'hui, condition: {type:"always"}

**"Bilan de semaine / rapport de progression"**
→ Lis habitStats et timeStats dans le contexte
→ Pousse un message résumant les points clés (ce qui a bien marché, ce qui est en retard)

**"Archiver les projets inactifs"**
→ Liste les projets dans get_orion_context, ceux sans tâches urgentes = inactifs
→ Appelle archive_project pour chacun
→ Pousse un message listant ce qui a été archivé

**"Crée un projet [nom]" ou demande de création de projet**
→ Utilise push_gantt pour créer le projet avec une structure raisonnable déduite du contexte : 3-4 phases, 2-4 tâches chacune, dates réalistes à partir d'aujourd'hui
→ Si le domaine n'est pas précisé, choisis le plus cohérent parmi les domaines existants dans le contexte
→ Pousse ensuite un push_assistant_message confirmant ce qui a été créé (titre du projet, nb de phases/tâches)

**Démarrage / activités sans intention de temps (seed J0)**
→ Repère les activités 'time' encore à la valeur d'onboarding par défaut (targetSource:"default", typiquement goalMin=30) et avec peu/pas de temps loggué (timeStats vide).
→ Estime pour chacune une intention RÉALISTE et CONSERVATRICE (sous-engage au début pour créer des wins) à partir de son nom, son domaine et la Vision si disponible. Ex: Méditation 10-15min, Lecture 20-30min, Deep Work 60-90min, Sport 30-45min.
→ Pose-les en UN appel set_activity_targets(targets:[{activityId, goalMin}, …]).
→ push_assistant_message : explique brièvement que tu as posé des intentions de temps de départ, ajustables à la main.

**Lundi matin — rééquilibrage du budget temps 24h**
→ compute_time_budget → set_activity_targets(targets:[{activityId, goalMin=recommendedGoalMin}, …]) pour toutes les activités avec id non-null EN UN SEUL appel (respecte automatiquement les cibles épinglées par l'utilisateur).
→ Si l'activité "Sommeil" est absente (id: null) → create_activity(name="Sommeil", domainId=<domaine Santé/Bien-être>)
→ push_assistant_message : liste concise des objectifs rééquilibrés (ex: "Sport : 45min/j → 49min/j · Sommeil : 7h30")
→ Ne pas exécuter si déjà fait cette semaine (vérifie recentShown pour un message de type "budget")

**Instruction ambiguë (sans supression/delete)**
→ Interprète au mieux, agis, puis pousse un message expliquant ce que tu as fait et demandant si c'est correct

**Instruction destructive (delete, supprimer définitivement)**
→ Ne pas agir — pousse un message demandant confirmation explicite

## RAPPEL ABSOLU : termine toujours par ton message-résumé

Tu dois TOUJOURS appeler push_assistant_message avant end_turn : exactement 1 message-résumé de ce que tu as fait (OU 1-2 questions requiresReply:true si une clarification est nécessaire). Jamais plus.

## Format du message-résumé
- Court (< 200 chars), à la première personne, factuel (ce que TU as fait)
- characterName: "ORION"
- Pas de doublon avec un message pending existant
- targetDate = aujourd'hui (${today}), condition: {type:"always"}`;
    let pushedCount = 0;
    let summaryPushed = 0; // messages-résumé non-reply (max 1)
    let replyPushed = 0; // questions requiresReply (max 2)
    let continueLoop = true;
    const actionLog = [];
    // Pré-fetch contexte + messages existants — évite 2 turns d'API coûteux
    const [orionContext, existingMessages] = await Promise.all([
        (0, execute_1.executeGetOrionContext)(uid),
        (0, execute_1.executeGetAssistantMessages)(uid),
    ]);
    actionLog.push("📖 Lecture du contexte utilisateur");
    actionLog.push("📩 Vérification des messages ORION existants");
    // Tools réduits : le contexte est déjà injecté, pas besoin de le refetcher
    const tools = ORION_TOOLS.filter((t) => !["get_orion_context", "get_assistant_messages"].includes(t.name));
    // Cache sur le dernier tool de la liste filtrée
    if (tools.length > 0 && !tools[tools.length - 1].cache_control) {
        tools[tools.length - 1] = Object.assign(Object.assign({}, tools[tools.length - 1]), { cache_control: { type: "ephemeral" } });
    }
    const firstMessage = [
        `## Contexte utilisateur\n${orionContext}`,
        `## Messages ORION déjà en attente\n${existingMessages}`,
        config.userNeeds ? `## Instruction\n${config.userNeeds}` : "## Instruction\nAnalyse autonome : génère des messages ORION pertinents.",
        config.userReply ? `## Réponse de l'utilisateur au dernier message\n${config.userReply}` : "",
    ].filter(Boolean).join("\n\n");
    const messages = [
        { role: "user", content: firstMessage },
    ];
    while (continueLoop) {
        const response = await client.beta.promptCaching.messages.create({
            model: ORION_MODEL,
            max_tokens: 2048,
            system: [{ type: "text", text: systemPrompt, cache_control: { type: "ephemeral" } }],
            tools,
            messages,
        });
        messages.push({ role: "assistant", content: response.content });
        (0, models_1.logTokenUsage)("orion_cycle", ORION_MODEL, response.usage);
        if (response.stop_reason === "end_turn") {
            continueLoop = false;
            break;
        }
        if (response.stop_reason === "tool_use") {
            const toolResults = [];
            for (const block of response.content) {
                if (block.type !== "tool_use")
                    continue;
                const args = block.input;
                let result = "";
                try {
                    switch (block.name) {
                        // ── Lecture ──────────────────────────────────────────────────
                        case "get_orion_context":
                            result = await (0, execute_1.executeGetOrionContext)(uid);
                            actionLog.push("📖 Lecture du contexte utilisateur");
                            break;
                        case "get_assistant_messages":
                            result = await (0, execute_1.executeGetAssistantMessages)(uid);
                            actionLog.push("📩 Vérification des messages ORION existants");
                            break;
                        case "get_day_blocks":
                            result = await (0, execute_1.executeGetDayBlocks)(uid);
                            break;
                        case "get_documents":
                            result = await (0, execute_1.executeGetDocuments)(uid, args.projectId, args.taskId);
                            break;
                        case "get_document_template":
                            result = (0, execute_1.executeGetDocumentTemplate)();
                            break;
                        case "get_archives":
                            result = await (0, execute_1.executeGetArchives)(uid);
                            break;
                        case "list_projects":
                            result = await (0, execute_1.executeListProjects)(uid);
                            break;
                        case "get_project":
                            result = await (0, execute_1.executeGetProject)(uid, args.projectId);
                            break;
                        // ── Activités ────────────────────────────────────────────────
                        case "create_activity":
                            result = await (0, execute_1.executeCreateActivity)(uid, args);
                            actionLog.push(`✅ Activité créée : ${(_b = args.name) !== null && _b !== void 0 ? _b : ""}`);
                            break;
                        case "update_activity":
                            result = await (0, execute_1.executeUpdateActivity)(uid, args.activityId, args);
                            actionLog.push(`✏️ Activité mise à jour`);
                            break;
                        case "update_activity_goal":
                            result = await (0, execute_1.executeUpdateActivityGoal)(uid, args.activityId, args);
                            actionLog.push(`🎯 Objectif activité mis à jour`);
                            break;
                        case "set_activity_targets":
                            result = await (0, execute_1.executeSetActivityTargets)(uid, args);
                            actionLog.push(`🎯 Intentions de temps posées`);
                            break;
                        case "delete_activity":
                            result = await (0, execute_1.executeDeleteActivity)(uid, args.activityId);
                            actionLog.push(`🗑 Activité supprimée`);
                            break;
                        // ── Routines / Actions ───────────────────────────────────────
                        case "create_routine":
                            result = await (0, execute_1.executeCreateRoutine)(uid, args);
                            actionLog.push(`✅ Routine créée : ${(_c = args.title) !== null && _c !== void 0 ? _c : ""}`);
                            break;
                        case "delete_routine":
                            result = await (0, execute_1.executeDeleteRoutine)(uid, args.routineId);
                            actionLog.push(`🗑 Routine supprimée`);
                            break;
                        // ── Domaines ─────────────────────────────────────────────────
                        case "create_domain":
                            result = await (0, execute_1.executeCreateDomain)(uid, args);
                            actionLog.push(`✅ Domaine créé : ${(_d = args.name) !== null && _d !== void 0 ? _d : ""}`);
                            break;
                        case "delete_domain":
                            result = await (0, execute_1.executeDeleteDomain)(uid, args.domainId);
                            actionLog.push(`🗑 Domaine supprimé`);
                            break;
                        // ── Projets ──────────────────────────────────────────────────
                        case "update_project":
                            result = await (0, execute_1.executeUpdateProject)(uid, args.projectId, args);
                            actionLog.push(`✏️ Projet mis à jour`);
                            break;
                        case "update_task_status":
                            result = await (0, execute_1.executeUpdateTaskStatus)(uid, args.projectId, args.taskId, args.status);
                            actionLog.push(`✏️ Statut tâche → ${args.status} (${args.taskId})`);
                            break;
                        case "archive_project":
                            result = await (0, execute_1.executeArchiveProject)(uid, args.projectId, (_e = args.restore) !== null && _e !== void 0 ? _e : false);
                            actionLog.push(args.restore ? `♻️ Projet restauré` : `🗄 Projet archivé`);
                            break;
                        case "delete_project":
                            result = await (0, execute_1.executeDeleteProject)(uid, args.projectId, (_f = args.deleteObjective) !== null && _f !== void 0 ? _f : false);
                            actionLog.push(`🗑 Projet supprimé`);
                            break;
                        case "push_gantt":
                            result = await (0, execute_1.executePushGantt)(uid, Object.assign({ uid }, args));
                            actionLog.push(`🗂 Projet Gantt créé : ${(_h = (_g = args.project) === null || _g === void 0 ? void 0 : _g.title) !== null && _h !== void 0 ? _h : ""}`);
                            break;
                        // ── Documents ────────────────────────────────────────────────
                        case "save_document":
                            result = await (0, execute_1.executeSaveDocument)(uid, args);
                            actionLog.push(`📄 Document sauvegardé : ${(_j = args.title) !== null && _j !== void 0 ? _j : ""}`);
                            break;
                        case "delete_document": {
                            const ref = db_1.db.collection(`users/${uid}/documents`).doc(args.documentId);
                            const snap = await ref.get();
                            if (!snap.exists) {
                                result = `Document introuvable : ${args.documentId}`;
                                break;
                            }
                            await ref.delete();
                            result = `✅ Document supprimé.`;
                            break;
                        }
                        case "restore_item":
                            result = await (0, execute_1.executeRestoreItem)(uid, args.collection, args.itemId);
                            break;
                        // ── Messages ORION ───────────────────────────────────────────
                        case "push_assistant_message": {
                            const requiresReply = (_k = args.requiresReply) !== null && _k !== void 0 ? _k : false;
                            if (requiresReply && replyPushed >= 2) {
                                result = "Limite atteinte : maximum 2 questions (requiresReply) par cycle. Message ignoré.";
                                break;
                            }
                            if (!requiresReply && summaryPushed >= 1) {
                                result = "Limite atteinte : un seul message-résumé par cycle. Message ignoré.";
                                break;
                            }
                            result = await (0, execute_1.executePushAssistantMessage)(uid, args);
                            if (requiresReply)
                                replyPushed++;
                            else
                                summaryPushed++;
                            const msgText = ((_l = args.text) !== null && _l !== void 0 ? _l : "").slice(0, 80);
                            actionLog.push(`💬 Message ORION planifié : "${msgText}${msgText.length >= 80 ? "…" : ""}"`);
                            pushedCount++;
                            break;
                        }
                        case "delete_assistant_message":
                            result = await (0, execute_1.executeDeleteAssistantMessage)(uid, args.messageId);
                            break;
                        // ── Inbox ─────────────────────────────────────────────────────
                        case "get_orion_queue":
                            result = await (0, execute_1.executeGetOrionQueue)(uid);
                            actionLog.push("📬 Lecture de la file Orion");
                            break;
                        case "delete_orion_queue_item":
                            result = await (0, execute_1.executeDeleteOrionQueueItem)(uid, args.itemId);
                            actionLog.push("✅ Instruction file Orion traitée");
                            break;
                        case "get_inbox":
                            result = await (0, execute_1.executeGetInbox)(uid);
                            break;
                        case "process_inbox_item":
                            result = await (0, execute_1.executeProcessInboxItem)(uid, args.itemId, args.note);
                            actionLog.push(`💡 Idée traitée depuis l'inbox`);
                            break;
                        // ── Programme du jour ──────────────────────────────────────────
                        case "compute_time_budget":
                            result = await (0, execute_1.executeComputeTimeBudget)(uid);
                            actionLog.push("📊 Budget temps 24h calculé (12 semaines)");
                            break;
                        case "get_day_schedule":
                            result = await (0, execute_1.executeGetDaySchedule)(uid, args.date);
                            break;
                        case "update_schedule_block":
                            result = await (0, execute_1.executeUpdateScheduleBlock)(uid, args.date, args.blockTitle, args.status);
                            actionLog.push(`📅 Bloc programme mis à jour`);
                            break;
                        case "schedule_day":
                            result = await (0, execute_1.executeScheduleDay)(uid, args.date, args.blocks);
                            actionLog.push(`📅 Programme du jour enregistré`);
                            break;
                        default:
                            result = `Outil inconnu dans ORION : ${block.name}`;
                    }
                }
                catch (e) {
                    result = `Erreur outil ${block.name} : ${e instanceof Error ? e.message : String(e)}`;
                }
                toolResults.push({ type: "tool_result", tool_use_id: block.id, content: result });
            }
            messages.push({ role: "user", content: toolResults });
        }
        else {
            continueLoop = false;
        }
    }
    await writeCycleLog(uid, {
        userNeeds: config.userNeeds,
        userReply: config.userReply,
        actions: actionLog,
        pushed: pushedCount,
        skipped: false,
    });
    return { skipped: false, pushed: pushedCount };
}
// ── Itération sur tous les users actifs (pour le cron) ────────────────────────
async function getAllActiveUserIds() {
    const uids = new Set();
    // Utilisateurs MCP (avec token API actif)
    const tokenSnap = await db_1.db
        .collectionGroup("api_tokens")
        .where("active", "==", true)
        .get();
    for (const doc of tokenSnap.docs) {
        const parts = doc.ref.path.split("/");
        if (parts.length >= 2)
            uids.add(parts[1]);
    }
    // Utilisateurs app (iOS/Android) inscrits au cron ORION
    const subSnap = await db_1.db
        .collectionGroup("orion_subscription")
        .where("enabled", "==", true)
        .get();
    for (const doc of subSnap.docs) {
        const parts = doc.ref.path.split("/");
        if (parts.length >= 2)
            uids.add(parts[1]);
    }
    return [...uids];
}
//# sourceMappingURL=orion.js.map