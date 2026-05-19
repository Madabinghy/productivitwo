"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.mcpHandler = exports.getCustomToken = exports.pushGantt = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const firestore_1 = require("firebase-admin/firestore");
const uuid_1 = require("uuid");
admin.initializeApp();
const db = admin.firestore();
// ── Helpers ───────────────────────────────────────────────────────────────────
function normalizePhases(phases) {
    if (!phases)
        return [];
    return phases.map((p) => (Object.assign(Object.assign({}, p), { id: p.id || (0, uuid_1.v4)() })));
}
function normalizeTasks(tasks) {
    if (!tasks)
        return [];
    return tasks.map((t) => {
        var _a, _b;
        return (Object.assign(Object.assign({}, t), { id: t.id || (0, uuid_1.v4)(), isMilestone: (_a = t.isMilestone) !== null && _a !== void 0 ? _a : false, status: (_b = t.status) !== null && _b !== void 0 ? _b : "pending" }));
    });
}
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
    // 1. Bearer token
    const authHeader = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
    }
    const rawToken = authHeader.slice(7).trim();
    // 2. Validation du corps
    const body = req.body;
    if (!body.uid || !((_b = body.project) === null || _b === void 0 ? void 0 : _b.title) || !((_c = body.project) === null || _c === void 0 ? void 0 : _c.startDate)) {
        res.status(400).json({ error: "Missing required fields: uid, project.title, project.startDate" });
        return;
    }
    const { uid, project, strategicObjective } = body;
    // 3. Vérification du token
    const tokenQuery = await db
        .collection(`users/${uid}/api_tokens`)
        .where("token", "==", rawToken)
        .where("active", "==", true)
        .limit(1)
        .get();
    if (tokenQuery.empty) {
        res.status(401).json({ error: "Invalid or revoked token" });
        return;
    }
    // 4. Mise à jour lastUsedAt
    tokenQuery.docs[0].ref.update({ lastUsedAt: firestore_1.FieldValue.serverTimestamp() });
    // 5. Objectif stratégique
    let strategicObjectiveId;
    if (strategicObjective) {
        const objId = strategicObjective.id || (0, uuid_1.v4)();
        strategicObjectiveId = objId;
        await db.collection(`users/${uid}/strategic_objectives`).doc(objId).set(Object.assign(Object.assign({}, strategicObjective), { id: objId, status: "active", updatedAt: firestore_1.FieldValue.serverTimestamp(), createdAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true });
    }
    // 6. Projet
    const projectId = project.id || (0, uuid_1.v4)();
    const projectDoc = Object.assign(Object.assign(Object.assign(Object.assign({}, project), { id: projectId, phases: normalizePhases(project.phases), tasks: normalizeTasks(project.tasks), createdBy: uid, sourceType: "claude_api", status: "active" }), (strategicObjectiveId ? { strategicObjectiveId } : {})), { updatedAt: firestore_1.FieldValue.serverTimestamp(), createdAt: firestore_1.FieldValue.serverTimestamp() });
    await db.collection(`users/${uid}/projects`).doc(projectId).set(projectDoc, { merge: true });
    // 7. Lier projet → objectif
    if (strategicObjectiveId) {
        await db
            .collection(`users/${uid}/strategic_objectives`)
            .doc(strategicObjectiveId)
            .update({ projectIds: firestore_1.FieldValue.arrayUnion(projectId) });
    }
    res.status(200).json({ success: true, projectId, strategicObjectiveId: strategicObjectiveId !== null && strategicObjectiveId !== void 0 ? strategicObjectiveId : null });
});
// ── MCP Prompts ───────────────────────────────────────────────────────────────
const today = () => new Date().toISOString().split("T")[0];
const MCP_PROMPTS = [
    {
        name: "programme-du-jour",
        description: "Crée mon programme personnalisé pour aujourd'hui ou une date donnée",
        arguments: [
            { name: "date", description: "Date YYYY-MM-DD (défaut: aujourd'hui)", required: false },
        ],
    },
    {
        name: "bilan-semaine",
        description: "Bilan de la semaine : réalisé, écarts, ajustements suggérés",
        arguments: [],
    },
    {
        name: "aligner-gantt",
        description: "Aligne mon planning des prochains jours avec mes projets Gantt actifs",
        arguments: [],
    },
];
function getPromptMessages(name, args) {
    const date = args.date || today();
    if (name === "programme-du-jour") {
        return [
            {
                role: "user",
                content: {
                    type: "text",
                    text: `Crée mon programme pour le ${date}.\n\n` +
                        `Étapes à suivre dans l'ordre :\n` +
                        `1. Appelle get_user_context pour connaître mes objectifs et ce que j'ai fait cette semaine.\n` +
                        `2. Appelle get_day_blocks pour connaître mes blocs de journée.\n` +
                        `3. Appelle get_day_plan(${date}) pour voir ce qui est déjà prévu.\n` +
                        `4. Appelle list_events (Google Calendar) pour voir mes rendez-vous.\n` +
                        `5. Crée un programme cohérent avec plan_day :\n` +
                        `   - Respecte mes blocs\n` +
                        `   - Priorise les tâches Gantt en retard\n` +
                        `   - Ajoute des créneaux "Rendez-vous avec [objectif]" pour mes goals GTD\n` +
                        `   - Commente les actions non faites de la semaine si pertinent\n` +
                        `6. Ajoute les créneaux importants dans Google Calendar.`,
                },
            },
        ];
    }
    if (name === "bilan-semaine") {
        return [
            {
                role: "user",
                content: {
                    type: "text",
                    text: `Fais mon bilan de la semaine.\n\n` +
                        `1. Appelle get_user_context — analyse recentActivity en détail :\n` +
                        `   - Qu'est-ce que j'ai accompli (completedActions) ?\n` +
                        `   - Qu'est-ce que j'avais prévu mais pas fait (pendingActions) ?\n` +
                        `   - Quelles habitudes sont en dessous de leur cible (habitCompletion) ?\n` +
                        `   - Quelles activités manquent de temps loggué vs objectif (timeLogged) ?\n` +
                        `2. Appelle list_projects pour voir l'état des Gantts actifs.\n` +
                        `3. Présente un bilan structuré : ce qui va bien, ce qui bloque, 3 actions prioritaires pour la semaine prochaine.\n` +
                        `4. Propose des ajustements concrets (update_activity_goal si un objectif est irréaliste).`,
                },
            },
        ];
    }
    if (name === "aligner-gantt") {
        return [
            {
                role: "user",
                content: {
                    type: "text",
                    text: `Aligne mon planning des prochains jours avec mes projets Gantt.\n\n` +
                        `1. Appelle get_user_context.\n` +
                        `2. Appelle list_projects puis get_project pour chaque projet actif.\n` +
                        `3. Identifie les tâches Gantt :\n` +
                        `   - En retard (endDate dépassée, status != done)\n` +
                        `   - À venir dans les 7 prochains jours\n` +
                        `   - Des jalons proches\n` +
                        `4. Pour chaque tâche urgente, propose de la planifier via plan_day sur les prochains jours.\n` +
                        `5. Si une tâche Gantt devrait générer des routines régulières, propose create_routine.`,
                },
            },
        ];
    }
    return [];
}
// ── Remote MCP Handler ────────────────────────────────────────────────────────
//
// URL : /mcp/{uid}/{token}
// Implémente le protocole MCP JSON-RPC 2.0 (Streamable HTTP, stateless).
// Compatible Claude Desktop et Claude.ai web (Integrations).
// ── Outils contexte utilisateur + écriture agenda ────────────────────────────
const GET_USER_CONTEXT_TOOL = {
    name: "get_user_context",
    description: "APPELLE CET OUTIL EN PREMIER dans toute conversation liée à la productivité. " +
        "Retourne : domaines de vie, activités + objectifs quotidiens, routines actives, " +
        "objectifs GTD, ET l'activité réelle des 7 derniers jours (actions faites, actions " +
        "non faites, taux de complétion des habitudes, temps loggué par activité). " +
        "Analyse l'écart entre 'completedActions' et 'pendingActions' pour détecter " +
        "les blocages récurrents. Compare 'timeLogged' aux objectifs des activités " +
        "pour identifier les domaines sous-investis. Signale proactivement tout écart > 30%.",
    inputSchema: { type: "object", properties: {} },
};
const UPDATE_ACTIVITY_GOAL_TOOL = {
    name: "update_activity_goal",
    description: "Modifie l'objectif quotidien d'une activité (temps ou fréquence). " +
        "Utilise cet outil pour ajuster la charge de travail en fonction du Gantt ou de la réalité de l'utilisateur.",
    inputSchema: {
        type: "object",
        required: ["activityId"],
        properties: {
            activityId: { type: "string", description: "id de l'activité (obtenu via get_user_context)" },
            goalMin: { type: "number", description: "Nouvel objectif en minutes/jour (activités 'time')" },
            habitTarget: { type: "number", description: "Nouvelle cible de fréquence (activités 'habit')" },
            habitFreq: { type: "number", description: "0=daily, 1=weekly, 2=monthly" },
        },
    },
};
const CREATE_ROUTINE_TOOL = {
    name: "create_routine",
    description: "Crée une action récurrente. Demande TOUJOURS confirmation avant de créer. " +
        "Si la routine est liée à une phase Gantt, renseigne startDate/endDate pour " +
        "qu'elle expire automatiquement en fin de phase. " +
        "Exemple : routine 'Séance muscu' du 2026-06-01 au 2026-08-31 liée à la phase Intensification. " +
        "Préfère les jours spécifiques (specificDays) aux routines quotidiennes sauf si vraiment pertinent.",
    inputSchema: {
        type: "object",
        required: ["title"],
        properties: {
            title: { type: "string", description: "Intitulé de l'action récurrente" },
            domainId: { type: "string", description: "id du domaine associé (optionnel)" },
            activityId: { type: "string", description: "id de l'activité associée (optionnel)" },
            recurrenceType: {
                type: "string",
                enum: ["daily", "specificDays"],
                description: "'daily' = tous les jours, 'specificDays' = jours choisis",
            },
            weekdays: {
                type: "array",
                items: { type: "number" },
                description: "Jours actifs si specificDays : 1=Lun, 2=Mar … 7=Dim",
            },
            startDate: { type: "string", description: "Date d'activation ISO YYYY-MM-DD (optionnel)" },
            endDate: { type: "string", description: "Date d'expiration ISO YYYY-MM-DD (optionnel)" },
            projectTaskId: { type: "string", description: "id de la tâche Gantt liée (optionnel)" },
        },
    },
};
const ADD_TO_DAY_PLAN_TOOL = {
    name: "add_to_day_plan",
    description: "Ajoute une action au plan quotidien de l'utilisateur pour une date donnée. " +
        "Utilise cet outil pour planifier des actions spécifiques dans l'agenda.",
    inputSchema: {
        type: "object",
        required: ["title", "date"],
        properties: {
            title: { type: "string", description: "Titre de l'action" },
            date: { type: "string", description: "Date ISO YYYY-MM-DD" },
            domainId: { type: "string" },
            activityId: { type: "string" },
            projectId: { type: "string" },
            projectTaskId: { type: "string" },
        },
    },
};
const CREATE_ACTIVITY_TOOL = {
    name: "create_activity",
    description: "Crée une nouvelle activité dans Productivitwo. " +
        "Utilise get_user_context pour trouver le bon domainId. " +
        "type 'time' = suivi du temps (chrono), 'habit' = routine à comptabiliser. " +
        "Demande confirmation avant de créer.",
    inputSchema: {
        type: "object",
        required: ["name", "domainId", "type"],
        properties: {
            name: { type: "string", description: "Nom de l'activité" },
            domainId: { type: "string", description: "id du domaine (get_user_context)" },
            type: { type: "string", enum: ["time", "habit"], description: "'time' = chrono, 'habit' = compteur" },
            goalMin: { type: "number", description: "Objectif minutes/jour (type time)" },
            unit: { type: "string", description: "Unité pour les habitudes (ex: verres, km, pages)" },
            habitFreq: { type: "number", description: "Fréquence : 0=daily, 1=weekly, 2=monthly" },
            habitTarget: { type: "number", description: "Cible par période" },
        },
    },
};
const CREATE_DOMAIN_TOOL = {
    name: "create_domain",
    description: "Crée un nouveau domaine de vie dans Productivitwo (ex: Santé, Travail, Famille). " +
        "Utilise get_user_context pour vérifier qu'un domaine similaire n'existe pas déjà. " +
        "Demande confirmation avant de créer.",
    inputSchema: {
        type: "object",
        required: ["name"],
        properties: {
            name: { type: "string", description: "Nom du domaine (ex: Santé, Travail, Famille)" },
            goalMinDay: { type: "number", description: "Objectif quotidien en minutes (null = auto depuis les activités)" },
            autoGoal: { type: "boolean", description: "true = objectif calculé depuis les activités (défaut: true)" },
            colorValue: { type: "number", description: "Valeur entière Flutter Color.value (optionnel)" },
        },
    },
};
const DELETE_DOMAIN_TOOL = {
    name: "delete_domain",
    description: "Supprime définitivement un domaine de vie. Irréversible — demande toujours confirmation. " +
        "Par défaut les activités du domaine sont conservées (domainId mis à null). " +
        "Utilise get_user_context pour obtenir le domainId.",
    inputSchema: {
        type: "object",
        required: ["domainId"],
        properties: {
            domainId: { type: "string", description: "id du domaine (get_user_context)" },
            deleteActivities: {
                type: "boolean",
                description: "Si true, supprime aussi toutes les activités du domaine (défaut: false)",
            },
        },
    },
};
const DELETE_ACTION_TOOL = {
    name: "delete_action",
    description: "Supprime une action individuelle du plan quotidien. " +
        "Utilise get_day_plan(date) pour obtenir l'id de l'action. " +
        "Demande confirmation si l'action est déjà faite (done=true).",
    inputSchema: {
        type: "object",
        required: ["actionId"],
        properties: {
            actionId: { type: "string", description: "id de l'action (obtenu via get_day_plan)" },
        },
    },
};
const DELETE_ACTIVITY_TOOL = {
    name: "delete_activity",
    description: "Supprime définitivement une activité. Irréversible — demande toujours confirmation. " +
        "Utilise get_user_context pour obtenir l'activityId.",
    inputSchema: {
        type: "object",
        required: ["activityId"],
        properties: {
            activityId: { type: "string", description: "id de l'activité (get_user_context)" },
        },
    },
};
const UPDATE_ACTIVITY_TOOL = {
    name: "update_activity",
    description: "Modifie une activité existante (nom, domaine, type, objectif, unité). " +
        "Utilise get_user_context pour obtenir l'activityId. " +
        "Ne modifie que les champs fournis, laisse les autres inchangés.",
    inputSchema: {
        type: "object",
        required: ["activityId"],
        properties: {
            activityId: { type: "string", description: "id de l'activité (get_user_context)" },
            name: { type: "string" },
            domainId: { type: "string" },
            goalMin: { type: "number" },
            unit: { type: "string" },
            habitFreq: { type: "number", description: "0=daily, 1=weekly, 2=monthly" },
            habitTarget: { type: "number" },
        },
    },
};
const LINK_GOAL_TO_TASK_TOOL = {
    name: "link_goal_to_task",
    description: "Lie un objectif GTD (Goal) à une tâche Gantt. " +
        "Le goal devient le détail opérationnel de la tâche stratégique. " +
        "Utilise get_user_context pour les goalId et list_projects+get_project pour les taskId. " +
        "Passe null pour délier.",
    inputSchema: {
        type: "object",
        required: ["goalId"],
        properties: {
            goalId: { type: "string", description: "id du Goal GTD" },
            projectId: { type: "string", description: "id du projet Gantt (null pour délier)" },
            projectTaskId: { type: "string", description: "id de la tâche Gantt (null pour délier)" },
        },
    },
};
const DELETE_ROUTINE_TOOL = {
    name: "delete_routine",
    description: "Supprime une action récurrente. Demande toujours confirmation avant d'appeler. " +
        "Utilise get_user_context pour obtenir l'id de la routine.",
    inputSchema: {
        type: "object",
        required: ["routineId"],
        properties: {
            routineId: { type: "string", description: "id de la routine (obtenu via get_user_context)" },
        },
    },
};
const DELETE_GOAL_TOOL = {
    name: "delete_goal",
    description: "Archive ou supprime définitivement un objectif GTD. " +
        "Préfère 'archive' (status archived) pour conserver l'historique. " +
        "Demande confirmation avant d'appeler.",
    inputSchema: {
        type: "object",
        required: ["goalId"],
        properties: {
            goalId: { type: "string", description: "id du goal (obtenu via get_user_context)" },
            action: {
                type: "string",
                enum: ["archive", "delete"],
                description: "'archive' = marque comme archivé (recommandé), 'delete' = suppression définitive",
            },
        },
    },
};
const CLEAR_DAY_PLAN_TOOL = {
    name: "clear_day_plan",
    description: "Supprime les actions non faites du plan d'un jour donné. " +
        "Utile pour vider une journée avant de la replanifier. " +
        "Ne supprime jamais les actions déjà faites (done=true).",
    inputSchema: {
        type: "object",
        required: ["date"],
        properties: {
            date: { type: "string", description: "Date ISO YYYY-MM-DD" },
        },
    },
};
const GET_DAY_BLOCKS_TOOL = {
    name: "get_day_blocks",
    description: "Retourne les blocs de journée (Miracle Morning, Matinée, Midi, Soir…) avec horaires. " +
        "Appelle cet outil AVANT plan_day pour connaître la structure de la journée. " +
        "Respecte toujours les blocs existants : ne place pas une tâche de concentration " +
        "dans un bloc 'Soir' si 'Matinée' est disponible.",
    inputSchema: { type: "object", properties: {} },
};
const GET_DAY_PLAN_TOOL = {
    name: "get_day_plan",
    description: "Retourne le plan d'un jour donné (actions planifiées, faites, reportées). " +
        "Appelle cet outil avant plan_day pour éviter les doublons et identifier " +
        "les créneaux libres. Si le plan est déjà chargé, ne replanifie que ce qui manque.",
    inputSchema: {
        type: "object",
        required: ["date"],
        properties: {
            date: { type: "string", description: "Date ISO YYYY-MM-DD" },
        },
    },
};
const PLAN_DAY_TOOL = {
    name: "plan_day",
    description: "OUTIL PRINCIPAL du coach : crée le programme personnalisé d'une journée. " +
        "Workflow obligatoire avant d'appeler cet outil : " +
        "1) get_user_context → connaître les objectifs et le réalisé récent, " +
        "2) get_day_blocks → connaître la structure de la journée, " +
        "3) get_day_plan → voir ce qui est déjà prévu, " +
        "4) list_events (Google Calendar) → voir les rendez-vous existants. " +
        "Ensuite : place les actions urgentes en matinée, les routines dans leurs blocs, " +
        "crée des 'Rendez-vous avec [objectif]' pour les goals GTD prioritaires, " +
        "et intègre les tâches Gantt en retard.",
    inputSchema: {
        type: "object",
        required: ["date", "items"],
        properties: {
            date: { type: "string", description: "Date ISO YYYY-MM-DD" },
            clearExisting: {
                type: "boolean",
                description: "Si true, efface le plan existant avant d'ajouter (défaut: false)",
            },
            items: {
                type: "array",
                description: "Liste des actions à planifier",
                items: {
                    type: "object",
                    required: ["title"],
                    properties: {
                        title: { type: "string", description: "Titre de l'action ou du créneau" },
                        blockId: { type: "string", description: "id du bloc (obtenu via get_day_blocks)" },
                        domainId: { type: "string" },
                        activityId: { type: "string" },
                        projectId: { type: "string" },
                        projectTaskId: { type: "string" },
                        durationNote: { type: "string", description: "Note de durée visible (ex: '45 min')" },
                    },
                },
            },
        },
    },
};
const ARCHIVE_PROJECT_TOOL = {
    name: "archive_project",
    description: "Met un projet Gantt en veille (archived) ou le réactive (active). " +
        "Un projet en veille reste visible dans la section 'En veille' du web app " +
        "mais n'apparaît plus dans le focus principal. " +
        "Utilise cet outil plutôt que delete_project pour les projets à reprendre plus tard.",
    inputSchema: {
        type: "object",
        required: ["projectId"],
        properties: {
            projectId: { type: "string", description: "id du projet" },
            restore: {
                type: "boolean",
                description: "true = réactiver le projet, false/absent = mettre en veille",
            },
        },
    },
};
const DELETE_PROJECT_TOOL = {
    name: "delete_project",
    description: "Supprime définitivement un projet Gantt et son objectif stratégique associé. " +
        "Utilise list_projects pour trouver l'id avant de supprimer. " +
        "Demande toujours confirmation à l'utilisateur avant d'appeler cet outil.",
    inputSchema: {
        type: "object",
        required: ["projectId"],
        properties: {
            projectId: { type: "string", description: "id du projet à supprimer" },
            deleteObjective: {
                type: "boolean",
                description: "Si true, supprime aussi l'objectif stratégique lié (défaut: false)",
            },
        },
    },
};
const LIST_PROJECTS_TOOL = {
    name: "list_projects",
    description: "Liste les projets Gantt existants dans Productivitwo. " +
        "Appelle cet outil avant de modifier un projet afin de récupérer son id.",
    inputSchema: { type: "object", properties: {} },
};
const GET_PROJECT_TOOL = {
    name: "get_project",
    description: "Retourne le détail complet d'un projet Gantt (phases, tâches, jalons). " +
        "Utilise cet outil pour lire un projet avant de le modifier.",
    inputSchema: {
        type: "object",
        required: ["projectId"],
        properties: {
            projectId: { type: "string", description: "L'id du projet (obtenu via list_projects)" },
        },
    },
};
const PUSH_GANTT_MCP_TOOL = {
    name: "push_gantt",
    description: "Crée ou met à jour un projet Gantt dans Productivitwo. " +
        "Pour modifier un projet existant, fournis son id (obtenu via list_projects + get_project) " +
        "avec le contenu complet mis à jour. Pour créer un nouveau projet, omets l'id.",
    inputSchema: {
        type: "object",
        required: ["project"],
        properties: {
            project: {
                type: "object",
                required: ["title", "startDate"],
                properties: {
                    title: { type: "string" },
                    description: { type: "string" },
                    startDate: { type: "string", description: "YYYY-MM-DD" },
                    endDate: { type: "string", description: "YYYY-MM-DD" },
                    phases: {
                        type: "array",
                        items: {
                            type: "object",
                            required: ["label", "startDate", "endDate"],
                            properties: {
                                label: { type: "string" },
                                color: { type: "string" },
                                startDate: { type: "string" },
                                endDate: { type: "string" },
                            },
                        },
                    },
                    tasks: {
                        type: "array",
                        items: {
                            type: "object",
                            required: ["title", "startDate"],
                            properties: {
                                title: { type: "string" },
                                groupLabel: { type: "string" },
                                startDate: { type: "string" },
                                endDate: { type: "string" },
                                isMilestone: { type: "boolean" },
                                color: { type: "string" },
                                barLabel: { type: "string" },
                                status: { type: "string", enum: ["pending", "done", "skipped"] },
                            },
                        },
                    },
                },
            },
            strategicObjective: {
                type: "object",
                properties: {
                    title: { type: "string" },
                    kpiTarget: { type: "string" },
                    horizonLabel: { type: "string" },
                },
            },
        },
    },
};
async function validateToken(uid, rawToken) {
    const q = await db
        .collection(`users/${uid}/api_tokens`)
        .where("token", "==", rawToken)
        .where("active", "==", true)
        .limit(1)
        .get();
    if (!q.empty) {
        q.docs[0].ref.update({ lastUsedAt: firestore_1.FieldValue.serverTimestamp() });
        return true;
    }
    return false;
}
async function executeGetUserContext(uid) {
    // Fenêtre glissante : 7 derniers jours
    const now = new Date();
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const ymdFrom = sevenDaysAgo.toISOString().slice(0, 10).replace(/-/g, "");
    const [domainsSnap, activitiesSnap, routinesSnap, goalsSnap, dayPlanSnap, habitHitsSnap, sessionsSnap] = await Promise.all([
        db.collection(`users/${uid}/domains`).get(),
        db.collection(`users/${uid}/activities`).get(),
        db.collection(`users/${uid}/recurringActions`).get(),
        db.collection(`users/${uid}/goals`).where("status", "==", "active").get(),
        // Actions planifiées et réalisées sur 7 jours
        db.collection(`users/${uid}/dayPlan`)
            .where("yyyymmdd", ">=", ymdFrom)
            .get(),
        // Incréments de routines/habitudes sur 7 jours
        db.collection(`users/${uid}/habitHits`)
            .where("ts", ">=", sevenDaysAgo)
            .get(),
        // Sessions de temps loggué sur 7 jours
        db.collection(`users/${uid}/sessions`)
            .where("startAt", ">=", sevenDaysAgo.toISOString())
            .get(),
    ]);
    const domains = domainsSnap.docs.map((d) => {
        const v = d.data();
        return { id: v.id, name: v.name };
    });
    const activityMap = new Map();
    const activities = activitiesSnap.docs.map((d) => {
        const v = d.data();
        activityMap.set(v.id, v.name);
        return {
            id: v.id,
            name: v.name,
            type: v.type,
            domainId: v.domainId,
            goalMin: v.goalMin,
            habitFreq: v.habitFreq,
            habitTarget: v.habitTarget,
        };
    });
    const activeRoutines = routinesSnap.docs
        .map((d) => d.data())
        .filter((r) => r.active)
        .map((r) => ({
        id: r.id,
        title: r.title,
        type: r.type,
        weekdays: r.weekdays || [],
        startDate: r.startDate || null,
        endDate: r.endDate || null,
        domainId: r.domainId || null,
        activityId: r.activityId || null,
    }));
    const activeGoals = goalsSnap.docs.map((d) => {
        const v = d.data();
        const actions = (v.actions || []);
        return {
            id: v.id,
            title: v.title,
            domainId: v.domainId,
            dueDate: v.dueDate || null,
            progress: `${actions.filter((a) => a.done).length}/${actions.length}`,
        };
    });
    // ── Réalisé des 7 derniers jours ──────────────────────────────────────────
    // Actions complétées (dayPlan done)
    const completedActions = dayPlanSnap.docs
        .map((d) => d.data())
        .filter((it) => it.done)
        .map((it) => ({
        title: it.title,
        date: it.yyyymmdd,
        domainId: it.domainId || null,
    }));
    // Actions planifiées non faites (pour identifier les écarts)
    const pendingActions = dayPlanSnap.docs
        .map((d) => d.data())
        .filter((it) => !it.done && !it.archived && it.status !== "archived")
        .map((it) => ({ title: it.title, date: it.yyyymmdd }));
    // Taux de complétion des habitudes/routines (habitHits groupés par habitId)
    const hitsByHabit = new Map();
    for (const doc of habitHitsSnap.docs) {
        const v = doc.data();
        hitsByHabit.set(v.habitId, (hitsByHabit.get(v.habitId) || 0) + 1);
    }
    const habitCompletion = Array.from(hitsByHabit.entries()).map(([id, count]) => ({
        activityId: id,
        name: activityMap.get(id) || id,
        hitsLast7Days: count,
    }));
    // Temps loggué par activité (sessions)
    const minByActivity = new Map();
    for (const doc of sessionsSnap.docs) {
        const v = doc.data();
        if (!v.endAt)
            continue;
        const start = new Date(v.startAt);
        const end = new Date(v.endAt);
        const mins = Math.round((end.getTime() - start.getTime()) / 60000);
        if (mins > 0) {
            minByActivity.set(v.activityId, (minByActivity.get(v.activityId) || 0) + mins);
        }
    }
    const timeLogged = Array.from(minByActivity.entries()).map(([id, mins]) => ({
        activityId: id,
        name: activityMap.get(id) || id,
        minutesLast7Days: mins,
        hoursLast7Days: Math.round(mins / 6) / 10, // arrondi 1 décimale
    }));
    const recentActivity = {
        period: "7 derniers jours",
        completedActions,
        pendingActions,
        habitCompletion,
        timeLogged,
    };
    return JSON.stringify({ domains, activities, activeRoutines, activeGoals, recentActivity }, null, 2);
}
async function executeUpdateActivityGoal(uid, activityId, updates) {
    var _a, _b;
    const ref = db.collection(`users/${uid}/activities`).doc(activityId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Activité introuvable : ${activityId}`;
    const patch = {};
    if (updates.goalMin !== undefined)
        patch.goalMin = updates.goalMin;
    if (updates.habitTarget !== undefined)
        patch.habitTarget = updates.habitTarget;
    if (updates.habitFreq !== undefined)
        patch.habitFreq = updates.habitFreq;
    await ref.update(patch);
    const name = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.name) !== null && _b !== void 0 ? _b : activityId;
    return `✅ Objectif de "${name}" mis à jour. Visible dans Productivitwo à la prochaine synchronisation.`;
}
async function executeCreateRoutine(uid, args) {
    const id = (0, uuid_1.v4)();
    await db.collection(`users/${uid}/recurringActions`).doc(id).set({
        id,
        title: args.title,
        domainId: args.domainId || null,
        activityId: args.activityId || null,
        blockId: null,
        type: args.recurrenceType === "specificDays" ? "specificDays" : "daily",
        weekdays: args.weekdays || [],
        active: true,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        startDate: args.startDate || null,
        endDate: args.endDate || null,
        projectTaskId: args.projectTaskId || null,
    });
    const period = args.startDate && args.endDate
        ? ` du ${args.startDate} au ${args.endDate}`
        : args.startDate ? ` à partir du ${args.startDate}`
            : args.endDate ? ` jusqu'au ${args.endDate}`
                : "";
    return `✅ Routine "${args.title}" créée${period}. Elle apparaîtra dans le plan quotidien dès la prochaine ouverture de l'app.`;
}
async function executeAddToDayPlan(uid, args) {
    // Valider le format de date
    if (!/^\d{4}-\d{2}-\d{2}$/.test(args.date)) {
        return `Date invalide : ${args.date}. Format attendu : YYYY-MM-DD`;
    }
    const yyyymmdd = args.date.replace(/-/g, "");
    const id = (0, uuid_1.v4)();
    await db.collection(`users/${uid}/dayPlan`).doc(id).set({
        id,
        kind: "action",
        title: args.title,
        yyyymmdd,
        done: false,
        doneCount: 0,
        allDay: false,
        isNowFocus: false,
        order: 9999,
        toPlan: false,
        archived: false,
        status: "active",
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        domainId: args.domainId || null,
        activityId: args.activityId || null,
        projectId: args.projectId || null,
        projectTaskId: args.projectTaskId || null,
    });
    return `✅ "${args.title}" ajouté au plan du ${args.date}.`;
}
async function executeGetDayBlocks(uid) {
    const snap = await db.collection(`users/${uid}/blocks`).orderBy("order").get();
    if (snap.empty)
        return "Aucun bloc de journée configuré.";
    const blocks = snap.docs.map((d) => {
        var _a, _b;
        const v = d.data();
        return {
            id: v.id,
            name: v.name,
            emoji: v.emoji || null,
            order: v.order,
            startHour: (_a = v.startHour) !== null && _a !== void 0 ? _a : null,
            startMinute: (_b = v.startMinute) !== null && _b !== void 0 ? _b : null,
            activityIds: v.activityIds || [],
        };
    });
    return JSON.stringify({ blocks }, null, 2);
}
async function executeGetDayPlan(uid, date) {
    const yyyymmdd = date.replace(/-/g, "");
    const snap = await db.collection(`users/${uid}/dayPlan`)
        .where("yyyymmdd", "==", yyyymmdd)
        .get();
    if (snap.empty)
        return `Aucune action planifiée le ${date}.`;
    const items = snap.docs.map((d) => {
        const v = d.data();
        return {
            id: v.id,
            title: v.title,
            done: v.done,
            blockId: v.blockId || null,
            domainId: v.domainId || null,
            activityId: v.activityId || null,
            status: v.status || "active",
            order: v.order || 0,
        };
    }).sort((a, b) => a.order - b.order);
    const done = items.filter((it) => it.done).length;
    return JSON.stringify({
        date,
        summary: `${done}/${items.length} actions faites`,
        items,
    }, null, 2);
}
async function executePlanDay(uid, date, items, clearExisting) {
    const yyyymmdd = date.replace(/-/g, "");
    if (clearExisting) {
        // Supprimer les items non-faits du jour
        const existing = await db.collection(`users/${uid}/dayPlan`)
            .where("yyyymmdd", "==", yyyymmdd)
            .where("done", "==", false)
            .get();
        const batch = db.batch();
        for (const doc of existing.docs)
            batch.delete(doc.ref);
        if (!existing.empty)
            await batch.commit();
    }
    const addBatch = db.batch();
    items.forEach((item, i) => {
        const id = (0, uuid_1.v4)();
        const title = item.durationNote
            ? `${item.title} (${item.durationNote})`
            : item.title;
        addBatch.set(db.collection(`users/${uid}/dayPlan`).doc(id), {
            id,
            kind: "action",
            title,
            yyyymmdd,
            done: false,
            doneCount: 0,
            allDay: false,
            isNowFocus: false,
            order: 9000 + i,
            toPlan: false,
            archived: false,
            status: "active",
            createdAt: firestore_1.FieldValue.serverTimestamp(),
            blockId: item.blockId || null,
            domainId: item.domainId || null,
            activityId: item.activityId || null,
            projectId: item.projectId || null,
            projectTaskId: item.projectTaskId || null,
        });
    });
    await addBatch.commit();
    return (`✅ Programme du ${date} créé — ${items.length} action(s) planifiée(s).\n` +
        items.map((it, i) => `  ${i + 1}. ${it.title}${it.blockId ? ` → bloc ${it.blockId}` : ""}`).join("\n"));
}
async function executeCreateActivity(uid, args) {
    var _a, _b, _c, _d;
    const id = (0, uuid_1.v4)();
    await db.collection(`users/${uid}/activities`).doc(id).set({
        id,
        name: args.name,
        domainId: args.domainId,
        type: args.type,
        role: "generic",
        goalMin: (_a = args.goalMin) !== null && _a !== void 0 ? _a : 1,
        unit: (_b = args.unit) !== null && _b !== void 0 ? _b : null,
        habitFreq: (_c = args.habitFreq) !== null && _c !== void 0 ? _c : null,
        habitTarget: (_d = args.habitTarget) !== null && _d !== void 0 ? _d : null,
        manualTarget: false,
        autoTune: true,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        lastTuneAt: null,
        order: 0,
        iconCode: null,
    });
    return `✅ Activité "${args.name}" créée (${args.type}). Elle apparaîtra dans Productivitwo à la prochaine synchronisation.`;
}
async function executeDeleteAction(uid, actionId) {
    var _a, _b;
    const ref = db.collection(`users/${uid}/dayPlan`).doc(actionId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Action introuvable : ${actionId}`;
    const title = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.title) !== null && _b !== void 0 ? _b : actionId;
    // Archiver plutôt que supprimer pour que le merge Flutter respecte la suppression
    await ref.update({ archived: true, status: "archived" });
    return `✅ Action "${title}" supprimée du plan.`;
}
async function executeCreateDomain(uid, args) {
    var _a, _b, _c;
    const id = (0, uuid_1.v4)();
    await db.collection(`users/${uid}/domains`).doc(id).set({
        id,
        name: args.name,
        goalMinDay: (_a = args.goalMinDay) !== null && _a !== void 0 ? _a : null,
        autoGoal: (_b = args.autoGoal) !== null && _b !== void 0 ? _b : true,
        colorValue: (_c = args.colorValue) !== null && _c !== void 0 ? _c : null,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
    });
    return `✅ Domaine "${args.name}" créé (id: ${id}). Il apparaîtra dans Productivitwo à la prochaine synchronisation.`;
}
async function executeDeleteDomain(uid, domainId, deleteActivities) {
    var _a, _b;
    const ref = db.collection(`users/${uid}/domains`).doc(domainId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Domaine introuvable : ${domainId}`;
    const name = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.name) !== null && _b !== void 0 ? _b : domainId;
    await ref.delete();
    const activitiesSnap = await db.collection(`users/${uid}/activities`)
        .where("domainId", "==", domainId)
        .get();
    if (!activitiesSnap.empty) {
        const batch = db.batch();
        for (const doc of activitiesSnap.docs) {
            if (deleteActivities)
                batch.delete(doc.ref);
            else
                batch.update(doc.ref, { domainId: null });
        }
        await batch.commit();
        if (deleteActivities) {
            return `✅ Domaine "${name}" et ses ${activitiesSnap.size} activité(s) supprimés définitivement.`;
        }
        return `✅ Domaine "${name}" supprimé. ${activitiesSnap.size} activité(s) conservée(s) sans domaine.`;
    }
    return `✅ Domaine "${name}" supprimé.`;
}
async function executeDeleteActivity(uid, activityId) {
    var _a, _b;
    const ref = db.collection(`users/${uid}/activities`).doc(activityId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Activité introuvable : ${activityId}`;
    const name = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.name) !== null && _b !== void 0 ? _b : activityId;
    await ref.delete();
    // Délier les day plan items non faits qui référencent cette activité
    const planSnap = await db.collection(`users/${uid}/dayPlan`)
        .where("activityId", "==", activityId)
        .where("done", "==", false)
        .get();
    if (!planSnap.empty) {
        const batch = db.batch();
        for (const doc of planSnap.docs)
            batch.update(doc.ref, { activityId: null });
        await batch.commit();
    }
    return `✅ Activité "${name}" supprimée${planSnap.size > 0 ? ` (${planSnap.size} action(s) du plan déliée(s))` : ""}.`;
}
async function executeUpdateActivity(uid, activityId, updates) {
    var _a, _b;
    const ref = db.collection(`users/${uid}/activities`).doc(activityId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Activité introuvable : ${activityId}`;
    const currentName = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.name) !== null && _b !== void 0 ? _b : activityId;
    const patch = {};
    if (updates.name !== undefined)
        patch.name = updates.name;
    if (updates.domainId !== undefined)
        patch.domainId = updates.domainId;
    if (updates.goalMin !== undefined)
        patch.goalMin = updates.goalMin;
    if (updates.unit !== undefined)
        patch.unit = updates.unit;
    if (updates.habitFreq !== undefined)
        patch.habitFreq = updates.habitFreq;
    if (updates.habitTarget !== undefined)
        patch.habitTarget = updates.habitTarget;
    await ref.update(patch);
    return `✅ Activité "${currentName}" mise à jour.`;
}
async function executeLinkGoalToTask(uid, goalId, projectId, projectTaskId) {
    var _a, _b;
    const ref = db.collection(`users/${uid}/goals`).doc(goalId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Objectif introuvable : ${goalId}`;
    const title = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.title) !== null && _b !== void 0 ? _b : goalId;
    await ref.update({ projectId: projectId !== null && projectId !== void 0 ? projectId : null, projectTaskId: projectTaskId !== null && projectTaskId !== void 0 ? projectTaskId : null });
    if (!projectTaskId)
        return `✅ Objectif "${title}" délié de tout projet Gantt.`;
    return `✅ Objectif "${title}" lié à la tâche Gantt ${projectTaskId}.`;
}
async function executeDeleteRoutine(uid, routineId) {
    var _a, _b;
    const ref = db.collection(`users/${uid}/recurringActions`).doc(routineId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Routine introuvable : ${routineId}`;
    const title = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.title) !== null && _b !== void 0 ? _b : routineId;
    await ref.delete();
    // Supprimer aussi les DayPlanItems générés par cette routine (non faits)
    const planSnap = await db.collection(`users/${uid}/dayPlan`)
        .where("recurringActionId", "==", routineId)
        .where("done", "==", false)
        .get();
    if (!planSnap.empty) {
        const batch = db.batch();
        for (const doc of planSnap.docs)
            batch.delete(doc.ref);
        await batch.commit();
    }
    return `✅ Routine "${title}" supprimée (${planSnap.size} occurrence(s) future(s) retirée(s) du plan).`;
}
async function executeDeleteGoal(uid, goalId, action) {
    var _a, _b;
    const ref = db.collection(`users/${uid}/goals`).doc(goalId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Objectif introuvable : ${goalId}`;
    const title = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.title) !== null && _b !== void 0 ? _b : goalId;
    if (action === "delete") {
        await ref.delete();
        return `✅ Objectif "${title}" supprimé définitivement.`;
    }
    // Archive par défaut
    await ref.update({ status: "archived" });
    return `✅ Objectif "${title}" archivé.`;
}
async function executeClearDayPlan(uid, date) {
    const yyyymmdd = date.replace(/-/g, "");
    const snap = await db.collection(`users/${uid}/dayPlan`)
        .where("yyyymmdd", "==", yyyymmdd)
        .where("done", "==", false)
        .get();
    if (snap.empty)
        return `Aucune action non faite à supprimer le ${date}.`;
    // Archiver plutôt que supprimer pour que le merge Flutter respecte la suppression
    const batch = db.batch();
    for (const doc of snap.docs)
        batch.update(doc.ref, { archived: true, status: "archived" });
    await batch.commit();
    return `✅ ${snap.size} action(s) non faite(s) supprimée(s) du plan du ${date}.`;
}
async function executeArchiveProject(uid, projectId, restore) {
    var _a, _b;
    const ref = db.collection(`users/${uid}/projects`).doc(projectId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Projet introuvable : ${projectId}`;
    const title = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.title) !== null && _b !== void 0 ? _b : projectId;
    const newStatus = restore ? "active" : "archived";
    await ref.update({ status: newStatus, updatedAt: firestore_1.FieldValue.serverTimestamp() });
    return restore
        ? `✅ Projet "${title}" réactivé — il apparaît à nouveau dans le focus.`
        : `✅ Projet "${title}" mis en veille — visible dans la section Archives du web app.`;
}
async function executeDeleteProject(uid, projectId, deleteObjective) {
    var _a;
    const projectRef = db.collection(`users/${uid}/projects`).doc(projectId);
    const projectSnap = await projectRef.get();
    if (!projectSnap.exists) {
        return `Projet introuvable : ${projectId}`;
    }
    const projectData = projectSnap.data();
    const title = (_a = projectData.title) !== null && _a !== void 0 ? _a : projectId;
    const objId = projectData.strategicObjectiveId;
    await projectRef.delete();
    if (deleteObjective && objId) {
        await db.collection(`users/${uid}/strategic_objectives`).doc(objId).delete();
        return `✅ Projet "${title}" et son objectif stratégique supprimés.`;
    }
    return `✅ Projet "${title}" supprimé.`;
}
async function executeListProjects(uid) {
    const snap = await db.collection(`users/${uid}/projects`).get();
    if (snap.empty)
        return "Aucun projet trouvé dans Productivitwo.";
    const lines = snap.docs.map((doc) => {
        const d = doc.data();
        const taskCount = (d.tasks || []).length;
        const start = d.startDate || "?";
        const end = d.endDate || "?";
        return `• [${d.id}] ${d.title} (${start} → ${end}, ${taskCount} tâche(s))`;
    });
    return `Projets Productivitwo (${snap.size}) :\n${lines.join("\n")}`;
}
async function executeGetProject(uid, projectId) {
    const doc = await db.collection(`users/${uid}/projects`).doc(projectId).get();
    if (!doc.exists)
        return `Projet introuvable : ${projectId}`;
    const d = doc.data();
    // Retourner le JSON complet pour que Claude puisse le modifier
    return JSON.stringify(d, null, 2);
}
async function executePushGantt(uid, input) {
    const { project, strategicObjective } = input;
    let strategicObjectiveId;
    if (strategicObjective) {
        const objId = strategicObjective.id || (0, uuid_1.v4)();
        strategicObjectiveId = objId;
        await db.collection(`users/${uid}/strategic_objectives`).doc(objId).set(Object.assign(Object.assign({}, strategicObjective), { id: objId, status: "active", updatedAt: firestore_1.FieldValue.serverTimestamp(), createdAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true });
    }
    const projectId = project.id || (0, uuid_1.v4)();
    await db.collection(`users/${uid}/projects`).doc(projectId).set(Object.assign(Object.assign(Object.assign(Object.assign({}, project), { id: projectId, phases: (project.phases || []).map((p) => (Object.assign(Object.assign({}, p), { id: p.id || (0, uuid_1.v4)() }))), tasks: (project.tasks || []).map((t) => { var _a, _b; return (Object.assign(Object.assign({}, t), { id: t.id || (0, uuid_1.v4)(), isMilestone: (_a = t.isMilestone) !== null && _a !== void 0 ? _a : false, status: (_b = t.status) !== null && _b !== void 0 ? _b : "pending" })); }), createdBy: uid, sourceType: "claude_mcp", status: "active" }), (strategicObjectiveId ? { strategicObjectiveId } : {})), { updatedAt: firestore_1.FieldValue.serverTimestamp(), createdAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true });
    if (strategicObjectiveId) {
        await db.collection(`users/${uid}/strategic_objectives`).doc(strategicObjectiveId)
            .update({ projectIds: firestore_1.FieldValue.arrayUnion(projectId) });
    }
    const isUpdate = !!project.id;
    return (`✅ Projet "${project.title}" ${isUpdate ? "mis à jour" : "créé"} dans Productivitwo !\n` +
        `• ${(project.tasks || []).length} tâche(s) · ${(project.phases || []).length} phase(s)\n` +
        `• Voir sur : https://productivitwo-app.web.app\n` +
        `• projectId : ${projectId}`);
}
// ── getCustomToken ────────────────────────────────────────────────────────────
//
// POST { uid, token }
// Valide le token API, retourne un Firebase custom token pour cet UID.
// Permet au web app de se connecter avec le même UID que l'app iOS.
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
    const valid = await validateToken(uid, token);
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    const customToken = await admin.auth().createCustomToken(uid);
    res.status(200).json({ customToken });
});
exports.mcpHandler = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s;
    // CORS preflight
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    // Extraire uid + token du path : /mcp/{uid}/{token}
    // Firebase Hosting conserve le préfixe /mcp/ dans req.path
    const parts = (req.path || "").replace(/^\/+mcp\/*/, "").split("/");
    const uid = parts[0] || "";
    const token = parts[1] || "";
    if (!uid || !token) {
        res.status(401).json({ error: "URL invalide — format attendu : /mcp/{uid}/{token}" });
        return;
    }
    // Valider le token
    const valid = await validateToken(uid, token);
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    // Lire le body JSON-RPC
    const body = req.body;
    const requests = Array.isArray(body) ? body : [body];
    const responses = [];
    for (const rpc of requests) {
        const id = (_a = rpc.id) !== null && _a !== void 0 ? _a : null;
        const method = (_b = rpc.method) !== null && _b !== void 0 ? _b : "";
        // Notifications (pas de réponse attendue)
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
            responses.push({ jsonrpc: "2.0", id, result: { prompts: MCP_PROMPTS } });
        }
        else if (method === "prompts/get") {
            const promptName = (_d = (_c = rpc.params) === null || _c === void 0 ? void 0 : _c.name) !== null && _d !== void 0 ? _d : "";
            const promptArgs = (_f = (_e = rpc.params) === null || _e === void 0 ? void 0 : _e.arguments) !== null && _f !== void 0 ? _f : {};
            const prompt = MCP_PROMPTS.find((p) => p.name === promptName);
            if (!prompt) {
                responses.push({ jsonrpc: "2.0", id, error: { code: -32601, message: `Prompt inconnu : ${promptName}` } });
            }
            else {
                responses.push({
                    jsonrpc: "2.0", id,
                    result: {
                        description: prompt.description,
                        messages: getPromptMessages(promptName, promptArgs),
                    },
                });
            }
        }
        else if (method === "tools/list") {
            responses.push({
                jsonrpc: "2.0", id,
                result: {
                    tools: [
                        GET_USER_CONTEXT_TOOL,
                        GET_DAY_BLOCKS_TOOL,
                        GET_DAY_PLAN_TOOL,
                        PLAN_DAY_TOOL,
                        CLEAR_DAY_PLAN_TOOL,
                        LIST_PROJECTS_TOOL,
                        GET_PROJECT_TOOL,
                        PUSH_GANTT_MCP_TOOL,
                        ARCHIVE_PROJECT_TOOL,
                        DELETE_PROJECT_TOOL,
                        UPDATE_ACTIVITY_GOAL_TOOL,
                        CREATE_ROUTINE_TOOL,
                        DELETE_ROUTINE_TOOL,
                        ADD_TO_DAY_PLAN_TOOL,
                        DELETE_GOAL_TOOL,
                        LINK_GOAL_TO_TASK_TOOL,
                        CREATE_ACTIVITY_TOOL,
                        UPDATE_ACTIVITY_TOOL,
                        DELETE_ACTIVITY_TOOL,
                        DELETE_ACTION_TOOL,
                        CREATE_DOMAIN_TOOL,
                        DELETE_DOMAIN_TOOL,
                    ],
                },
            });
        }
        else if (method === "tools/call") {
            const toolName = (_h = (_g = rpc.params) === null || _g === void 0 ? void 0 : _g.name) !== null && _h !== void 0 ? _h : "";
            const args = (_k = (_j = rpc.params) === null || _j === void 0 ? void 0 : _j.arguments) !== null && _k !== void 0 ? _k : {};
            try {
                let text = "";
                if (toolName === "get_day_blocks") {
                    text = await executeGetDayBlocks(uid);
                }
                else if (toolName === "get_day_plan") {
                    text = await executeGetDayPlan(uid, args.date);
                }
                else if (toolName === "plan_day") {
                    text = await executePlanDay(uid, args.date, args.items, (_l = args.clearExisting) !== null && _l !== void 0 ? _l : false);
                }
                else if (toolName === "create_activity") {
                    text = await executeCreateActivity(uid, args);
                }
                else if (toolName === "update_activity") {
                    text = await executeUpdateActivity(uid, args.activityId, args);
                }
                else if (toolName === "link_goal_to_task") {
                    text = await executeLinkGoalToTask(uid, args.goalId, (_m = args.projectId) !== null && _m !== void 0 ? _m : null, (_o = args.projectTaskId) !== null && _o !== void 0 ? _o : null);
                }
                else if (toolName === "delete_routine") {
                    text = await executeDeleteRoutine(uid, args.routineId);
                }
                else if (toolName === "delete_goal") {
                    text = await executeDeleteGoal(uid, args.goalId, (_p = args.action) !== null && _p !== void 0 ? _p : "archive");
                }
                else if (toolName === "clear_day_plan") {
                    text = await executeClearDayPlan(uid, args.date);
                }
                else if (toolName === "archive_project") {
                    text = await executeArchiveProject(uid, args.projectId, (_q = args.restore) !== null && _q !== void 0 ? _q : false);
                }
                else if (toolName === "delete_project") {
                    text = await executeDeleteProject(uid, args.projectId, (_r = args.deleteObjective) !== null && _r !== void 0 ? _r : false);
                }
                else if (toolName === "get_user_context") {
                    text = await executeGetUserContext(uid);
                }
                else if (toolName === "list_projects") {
                    text = await executeListProjects(uid);
                }
                else if (toolName === "get_project") {
                    text = await executeGetProject(uid, args.projectId);
                }
                else if (toolName === "push_gantt") {
                    text = await executePushGantt(uid, Object.assign({ uid }, args));
                }
                else if (toolName === "update_activity_goal") {
                    text = await executeUpdateActivityGoal(uid, args.activityId, args);
                }
                else if (toolName === "create_routine") {
                    text = await executeCreateRoutine(uid, args);
                }
                else if (toolName === "add_to_day_plan") {
                    text = await executeAddToDayPlan(uid, args);
                }
                else if (toolName === "delete_action") {
                    text = await executeDeleteAction(uid, args.actionId);
                }
                else if (toolName === "create_domain") {
                    text = await executeCreateDomain(uid, args);
                }
                else if (toolName === "delete_domain") {
                    text = await executeDeleteDomain(uid, args.domainId, (_s = args.deleteActivities) !== null && _s !== void 0 ? _s : false);
                }
                else if (toolName === "delete_activity") {
                    text = await executeDeleteActivity(uid, args.activityId);
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
//# sourceMappingURL=index.js.map