"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PUSH_GANTT_MCP_TOOL = exports.GET_PROJECT_TOOL = exports.LIST_PROJECTS_TOOL = exports.DELETE_PROJECT_TOOL = exports.ARCHIVE_PROJECT_TOOL = exports.PLAN_DAY_TOOL = exports.GET_DAY_PLAN_TOOL = exports.GET_DAY_BLOCKS_TOOL = exports.CLEAR_DAY_PLAN_TOOL = exports.DELETE_GOAL_TOOL = exports.DELETE_ROUTINE_TOOL = exports.LINK_GOAL_TO_TASK_TOOL = exports.UPDATE_ACTIVITY_TOOL = exports.UPDATE_TASK_STATUS_TOOL = exports.UPDATE_PROJECT_TOOL = exports.DELETE_ACTIVITY_TOOL = exports.DELETE_ACTION_TOOL = exports.RESTORE_ITEM_TOOL = exports.GET_ARCHIVES_TOOL = exports.DELETE_DOCUMENT_TOOL = exports.GET_DOCUMENTS_TOOL = exports.SAVE_DOCUMENT_TOOL = exports.GET_DOCUMENT_TEMPLATE_TOOL = exports.DELETE_DOMAIN_TOOL = exports.PUSH_ASSISTANT_MESSAGE_TOOL = exports.CREATE_DOMAIN_TOOL = exports.CREATE_ACTIVITY_TOOL = exports.ADD_TO_DAY_PLAN_TOOL = exports.CREATE_ROUTINE_TOOL = exports.UPDATE_ACTIVITY_GOAL_TOOL = exports.GET_USER_CONTEXT_TOOL = exports.DELETE_ASSISTANT_MESSAGE_TOOL = exports.GET_ASSISTANT_MESSAGES_TOOL = void 0;
const GET_USER_CONTEXT_TOOL = {
    name: "get_user_context",
    description: "APPELLE CET OUTIL EN PREMIER dans toute conversation liée à la productivité. " +
        "Retourne : domaines de vie, activités + objectifs quotidiens, routines actives, " +
        "objectifs GTD, ET l'activité réelle des 7 derniers jours. " +
        "\n\n" +
        "⚡ WORKFLOW OBLIGATOIRE — quelle que soit la demande de l'utilisateur :\n\n" +
        "⏱️ ANNONCE D'ABORD (avant tout tool call) :\n" +
        "  → Dire à l'utilisateur : \"Je prépare ton programme — ça prend environ 1-2 min. Je t'envoie une notification dès que c'est prêt.\"\n" +
        "  → Cela évite que l'utilisateur interrompe le process en pensant que rien ne se passe.\n\n" +
        "ÉTAPE 1 — Présenter le programme (AVANT de créer quoi que ce soit dans Productivitwo) :\n" +
        "  → Appeler get_document_template pour récupérer le template HTML de référence.\n" +
        "  → Générer un programme HTML complet en utilisant ce template (adapter couleur au domaine).\n" +
        "  → Le montrer à l'utilisateur et attendre sa validation explicite ('ok', 'c'est bon', 'crée ça').\n" +
        "  → NE PAS appeler save_document ni créer d'éléments Productivitwo avant validation.\n\n" +
        "📅 PROPOSITION AGENDA (juste après validation du programme, avant l'étape 2) :\n" +
        "  → Demander : \"Veux-tu que je vérifie ton agenda pour intégrer des créneaux concrets ?\"\n" +
        "  → Si oui : appeler list_events (Google Calendar), identifier les créneaux libres, les proposer clairement, puis create_event après accord.\n" +
        "  → Si non : passer directement à l'étape 2.\n\n" +
        "ÉTAPE 2 — Après validation, créer la structure dans cet ordre :\n" +
        "1. Identifier ou créer le domaine concerné.\n" +
        "2. Identifier ou créer UNE OU PLUSIEURS activités temps selon les dimensions de l'objectif. " +
        "   Ex: 'prendre de la masse' → Musculation (temps) + Nutrition (temps). " +
        "   Chaque routine/action sera liée à l'activité la plus pertinente.\n" +
        "3. Créer le projet Gantt (push_gantt) couvrant AU MINIMUM la semaine en cours " +
        "   avec un jalon 'Bilan' le dimanche et un objectif KPI mesurable.\n" +
        "4. Sauvegarder le programme HTML avec save_document lié au projectId créé. " +
        "   Toujours renseigner domainId et subtitle. " +
        "   Si un document existe déjà pour ce projet (get_documents avant), passer son documentId pour éviter les doublons.\n" +
        "5. Créer les routines (create_routine) — TOUTES liées à l'activityId de l'étape 2.\n" +
        "6. Envoyer une push_notification : \"[Titre du programme] créé ✅\"\n\n" +
        "Structure garantie : Domaine → Activités temps → Projet Gantt (+ KPI + Bilan dim.) → Programme HTML sauvegardé → Routines & Actions liées.\n" +
        "Ne jamais créer une routine ou action sans activityId et sans projet associé.",
    inputSchema: { type: "object", properties: {} },
};
exports.GET_USER_CONTEXT_TOOL = GET_USER_CONTEXT_TOOL;
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
exports.UPDATE_ACTIVITY_GOAL_TOOL = UPDATE_ACTIVITY_GOAL_TOOL;
const CREATE_ROUTINE_TOOL = {
    name: "create_routine",
    description: "Crée une **routine** : habitude trackée avec compteur ou fréquence (ex: Méditation, Gainage, Eau). " +
        "⚠️ activityId OBLIGATOIRE — créer d'abord l'activité temps avec create_activity si elle n'existe pas. " +
        "⚠️ NE PAS confondre avec create_activity (tracking de temps/chrono).",
    inputSchema: {
        type: "object",
        required: ["name", "domainId", "activityId"],
        properties: {
            name: { type: "string", description: "Nom de la routine (ex: Méditation, Gainage)" },
            domainId: { type: "string", description: "id du domaine (get_user_context)" },
            activityId: { type: "string", description: "id de l'activité temps associée (OBLIGATOIRE — créer avec create_activity si absente)" },
            unit: { type: "string", description: "Unité comptée (ex: fois, verres, séries)" },
            habitFreq: { type: "number", description: "Fréquence : 0=daily, 1=weekly, 2=monthly" },
            habitTarget: { type: "number", description: "Cible par période (ex: 3 fois/semaine)" },
        },
    },
};
exports.CREATE_ROUTINE_TOOL = CREATE_ROUTINE_TOOL;
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
exports.ADD_TO_DAY_PLAN_TOOL = ADD_TO_DAY_PLAN_TOOL;
const CREATE_ACTIVITY_TOOL = {
    name: "create_activity",
    description: "Crée une **activité** : tracking de temps avec chrono (ex: Deep Work, Running, Lecture). " +
        "Utilise cet outil quand l'utilisateur veut mesurer le temps passé sur quelque chose. " +
        "⚠️ NE PAS utiliser pour tracker une fréquence/compteur → create_routine. " +
        "⚠️ NE PAS utiliser pour une tâche récurrente sans tracking → create_recurring_action. " +
        "Demande confirmation avant de créer.",
    inputSchema: {
        type: "object",
        required: ["name", "domainId"],
        properties: {
            name: { type: "string", description: "Nom de l'activité (ex: Deep Work, Running)" },
            domainId: { type: "string", description: "id du domaine (get_user_context)" },
            goalMin: { type: "number", description: "Objectif en minutes/jour" },
        },
    },
};
exports.CREATE_ACTIVITY_TOOL = CREATE_ACTIVITY_TOOL;
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
exports.CREATE_DOMAIN_TOOL = CREATE_DOMAIN_TOOL;
const PUSH_ASSISTANT_MESSAGE_TOOL = {
    name: "push_assistant_message",
    description: "Écrit un message pour l'assistant Productivitwo — visible dans le web app sous forme de conseil animé. " +
        "Utilise cet outil pour planifier des nudges proactifs sur des jours futurs. " +
        "Le message ne s'affiche QUE si sa condition est vraie le jour J. " +
        "Appelle get_user_context d'abord pour avoir les IDs nécessaires aux conditions.",
    inputSchema: {
        type: "object",
        required: ["targetDate", "text", "condition"],
        properties: {
            targetDate: {
                type: "string",
                description: "Date cible YYYY-MM-DD — jour où la condition sera évaluée",
            },
            text: {
                type: "string",
                description: "Texte affiché par l'assistant (style direct, 1-3 phrases max)",
            },
            condition: {
                type: "object",
                required: ["type"],
                description: "Condition d'activation évaluée localement dans l'app",
                properties: {
                    type: {
                        type: "string",
                        enum: [
                            "always",
                            "overdue_count",
                            "day_plan_empty",
                            "project_inactive_days",
                            "activity_behind_target",
                            "goal_undone_actions",
                            "habit_streak_broken",
                            "inbox_overflow",
                            "project_deadline_near",
                            "no_now_focus",
                            "routine_completion_low",
                            "day_plan_overloaded",
                            "no_activity_logged_today",
                            "project_milestone_today",
                            "week_start",
                            "week_end",
                            "activity_streak",
                            "goal_near_deadline",
                            "first_open_of_day",
                            "custom_date",
                        ],
                        description: "always · overdue_count(min) · day_plan_empty · project_inactive_days(projectId,days) · " +
                            "activity_behind_target(activityId) · goal_undone_actions(activityId,min) · habit_streak_broken(habitId) · " +
                            "inbox_overflow(min) · project_deadline_near(projectId,daysBefore) · no_now_focus(beforeHour) · " +
                            "routine_completion_low(maxPercent) · day_plan_overloaded(min) · no_activity_logged_today · " +
                            "project_milestone_today(projectId) · week_start · week_end · " +
                            "activity_streak(activityId,minDays) · goal_near_deadline(goalId,daysBefore) · " +
                            "first_open_of_day · custom_date(date)",
                    },
                    min: { type: "number", description: "Seuil minimum (overdue_count, goal_undone_actions, inbox_overflow, day_plan_overloaded)" },
                    projectId: { type: "string", description: "ID projet (project_inactive_days, project_deadline_near, project_milestone_today)" },
                    days: { type: "number", description: "Jours d'inactivité (project_inactive_days)" },
                    daysBefore: { type: "number", description: "Jours avant deadline (project_deadline_near, goal_near_deadline)" },
                    activityId: { type: "string", description: "ID activité (activity_behind_target, goal_undone_actions, activity_streak)" },
                    habitId: { type: "string", description: "ID habitude (habit_streak_broken)" },
                    beforeHour: { type: "number", description: "Heure limite 0-23 (no_now_focus) — ex: 10 = avant 10h" },
                    maxPercent: { type: "number", description: "Taux de complétion max en % (routine_completion_low) — ex: 50 = moins de 50%" },
                    minDays: { type: "number", description: "Nombre de jours consécutifs minimum (activity_streak)" },
                    goalId: { type: "string", description: "ID objectif GTD (goal_near_deadline)" },
                    date: { type: "string", description: "Date exacte YYYY-MM-DD (custom_date)" },
                },
            },
            expiresAfterDays: {
                type: "number",
                description: "Expiration automatique si non vu après N jours (défaut: 2)",
            },
            characterName: {
                type: "string",
                description: "Nom affiché du personnage (défaut: ORION)",
            },
            priority: {
                type: "number",
                description: "Ordre d'affichage si plusieurs messages le même jour (1=plus prioritaire)",
            },
            action: {
                type: "object",
                description: "Bouton d'action optionnel affiché sous le texte",
                properties: {
                    type: {
                        type: "string",
                        enum: ["open_day_plan", "open_project", "open_gantt_task", "open_activity", "open_goals"],
                        description: "Deep link — open_gantt_task ouvre la fiche de la tâche directement (payload: { projectId, taskId })",
                    },
                    label: { type: "string", description: "Libellé du bouton (ex: 'Voir le plan')" },
                    payload: {
                        type: "object",
                        description: "Données complémentaires (ex: { projectId: 'abc' })",
                    },
                },
            },
        },
    },
};
exports.PUSH_ASSISTANT_MESSAGE_TOOL = PUSH_ASSISTANT_MESSAGE_TOOL;
const DELETE_DOMAIN_TOOL = {
    name: "delete_domain",
    description: "Archive un domaine de vie et toutes ses activités + routines (cascade). " +
        "L'élément reste récupérable depuis les Archives — la suppression définitive " +
        "est réservée à l'utilisateur depuis le web app. " +
        "Demande toujours confirmation avant d'appeler.",
    inputSchema: {
        type: "object",
        required: ["domainId"],
        properties: {
            domainId: { type: "string", description: "id du domaine (get_user_context)" },
        },
    },
};
exports.DELETE_DOMAIN_TOOL = DELETE_DOMAIN_TOOL;
const GET_DOCUMENT_TEMPLATE_TOOL = {
    name: "get_document_template",
    description: "Retourne le template HTML de référence pour créer un programme Productivitwo. " +
        "TOUJOURS appeler cet outil avant de générer un programme HTML. " +
        "Adapter le template au contenu du programme et aux couleurs du domaine (variable --gold).",
    inputSchema: { type: "object", properties: {} },
};
exports.GET_DOCUMENT_TEMPLATE_TOOL = GET_DOCUMENT_TEMPLATE_TOOL;
const SAVE_DOCUMENT_TOOL = {
    name: "save_document",
    description: "Sauvegarde ou met à jour un document HTML dans Productivitwo (programme, plan, bilan, fiche, brief, livrable). " +
        "Pour MODIFIER un document existant : passer son documentId (obtenu via get_documents) — évite les doublons. " +
        "Pour CRÉER un nouveau document : ne pas passer documentId. " +
        "Toujours lier au projectId et taskId si disponibles — utilisés pour l'affichage dans l'app. " +
        "Renseigner category pour classer le document dans le bon dossier de la tâche. " +
        "Renseigner subtitle avec un résumé court (ex: 'Phase 1 · 4 séances/semaine · Mois 1-2'). " +
        "Après chaque save_document réussi, envoyer une push_notification pour informer l'utilisateur.",
    inputSchema: {
        type: "object",
        required: ["title", "content"],
        properties: {
            title: { type: "string", description: "Titre du document (ex: Programme Prise de Masse 6 mois)" },
            content: { type: "string", description: "Contenu HTML complet du document" },
            projectId: { type: "string", description: "id du projet Gantt associé (obtenu via list_projects ou get_project)" },
            taskId: { type: "string", description: "id de la tâche Gantt associée (obtenu via get_project → tasks[].id). Toujours renseigner si le document concerne une tâche spécifique." },
            category: { type: "string", enum: ["programme", "brief", "recherche", "livrable", "notes"], description: "Catégorie du document : 'programme' = plan structuré, 'brief' = cahier des charges, 'recherche' = analyse/veille, 'livrable' = output final, 'notes' = notes de travail. Défaut : 'notes'." },
            documentId: { type: "string", description: "id du document existant à mettre à jour — obtenu via get_documents. NE PAS passer pour une création." },
            domainId: { type: "string", description: "id du domaine (obtenu via get_user_context) — utilisé pour la couleur de la carte dans l'app" },
            subtitle: { type: "string", description: "Résumé court affiché sur la carte preview (ex: 'Phase 1 · 4 séances/semaine · Mois 1-2')" },
        },
    },
};
exports.SAVE_DOCUMENT_TOOL = SAVE_DOCUMENT_TOOL;
const GET_DOCUMENTS_TOOL = {
    name: "get_documents",
    description: "Récupère les documents sauvegardés (programmes, plans, bilans, briefs, livrables). " +
        "Utilise cet outil pour relire un document et le comparer à l'état actuel, ou pour vérifier si un document existe avant d'en créer un nouveau. " +
        "Retourne la liste avec titres, catégories et dates.",
    inputSchema: {
        type: "object",
        properties: {
            projectId: { type: "string", description: "Filtrer par projet (optionnel)" },
            taskId: { type: "string", description: "Filtrer par tâche Gantt (optionnel) — retourne uniquement les documents associés à cette tâche" },
        },
    },
};
exports.GET_DOCUMENTS_TOOL = GET_DOCUMENTS_TOOL;
const DELETE_DOCUMENT_TOOL = {
    name: "delete_document",
    description: "Supprime définitivement un document sauvegardé (programme, bilan, fiche). " +
        "Utilise get_documents pour obtenir le documentId avant d'appeler cet outil. " +
        "Demande confirmation à l'utilisateur avant de supprimer.",
    inputSchema: {
        type: "object",
        required: ["documentId"],
        properties: {
            documentId: { type: "string", description: "id du document à supprimer (obtenu via get_documents)" },
        },
    },
};
exports.DELETE_DOCUMENT_TOOL = DELETE_DOCUMENT_TOOL;
const GET_ARCHIVES_TOOL = {
    name: "get_archives",
    description: "Liste tous les éléments archivés (deleted:true) : domaines, activités, routines. " +
        "Utilise cet outil pour voir ce qui a été supprimé et pouvoir restaurer en cas d'erreur.",
    inputSchema: { type: "object", properties: {} },
};
exports.GET_ARCHIVES_TOOL = GET_ARCHIVES_TOOL;
const RESTORE_ITEM_TOOL = {
    name: "restore_item",
    description: "Restaure un élément archivé (annule la suppression). " +
        "Utilise get_archives pour obtenir l'id. " +
        "collection: 'domains' ou 'activities'.",
    inputSchema: {
        type: "object",
        required: ["collection", "itemId"],
        properties: {
            collection: {
                type: "string",
                enum: ["domains", "activities"],
                description: "La collection Firestore",
            },
            itemId: { type: "string", description: "id de l'élément à restaurer" },
        },
    },
};
exports.RESTORE_ITEM_TOOL = RESTORE_ITEM_TOOL;
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
exports.DELETE_ACTION_TOOL = DELETE_ACTION_TOOL;
const DELETE_ACTIVITY_TOOL = {
    name: "delete_activity",
    description: "Archive une activité et ses routines liées (cascade). " +
        "L'élément reste récupérable depuis les Archives — la suppression définitive " +
        "est réservée à l'utilisateur depuis le web app. " +
        "Demande toujours confirmation avant d'appeler.",
    inputSchema: {
        type: "object",
        required: ["activityId"],
        properties: {
            activityId: { type: "string", description: "id de l'activité (get_user_context)" },
        },
    },
};
exports.DELETE_ACTIVITY_TOOL = DELETE_ACTIVITY_TOOL;
const UPDATE_PROJECT_TOOL = {
    name: "update_project",
    description: "Modifie les métadonnées d'un projet Gantt existant sans toucher aux tâches/phases. " +
        "Utilise cet outil pour changer le domaine, le titre, la description ou le statut. " +
        "Utilise list_projects pour obtenir le projectId.",
    inputSchema: {
        type: "object",
        required: ["projectId"],
        properties: {
            projectId: { type: "string", description: "id du projet (list_projects)" },
            domainId: { type: "string", description: "id du domaine (get_user_context)" },
            title: { type: "string" },
            description: { type: "string" },
            status: { type: "string", enum: ["active", "archived", "done"] },
        },
    },
};
exports.UPDATE_PROJECT_TOOL = UPDATE_PROJECT_TOOL;
const UPDATE_TASK_STATUS_TOOL = {
    name: "update_task_status",
    description: "Met à jour le statut d'une tâche Gantt (pending → done, skipped, etc.). " +
        "Utilise list_projects + get_project pour obtenir projectId et taskId. " +
        "Beaucoup plus rapide que de recréer tout le projet.",
    inputSchema: {
        type: "object",
        required: ["projectId", "taskId", "status"],
        properties: {
            projectId: { type: "string", description: "id du projet (list_projects)" },
            taskId: { type: "string", description: "id de la tâche (get_project)" },
            status: { type: "string", enum: ["pending", "done", "skipped"], description: "Nouveau statut" },
        },
    },
};
exports.UPDATE_TASK_STATUS_TOOL = UPDATE_TASK_STATUS_TOOL;
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
exports.UPDATE_ACTIVITY_TOOL = UPDATE_ACTIVITY_TOOL;
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
exports.LINK_GOAL_TO_TASK_TOOL = LINK_GOAL_TO_TASK_TOOL;
const DELETE_ROUTINE_TOOL = {
    name: "delete_routine",
    description: "Archive une action récurrente. L'élément reste récupérable depuis les Archives — " +
        "la suppression définitive est réservée à l'utilisateur depuis le web app. " +
        "Demande toujours confirmation avant d'appeler.",
    inputSchema: {
        type: "object",
        required: ["routineId"],
        properties: {
            routineId: { type: "string", description: "id de la routine (obtenu via get_user_context)" },
        },
    },
};
exports.DELETE_ROUTINE_TOOL = DELETE_ROUTINE_TOOL;
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
exports.DELETE_GOAL_TOOL = DELETE_GOAL_TOOL;
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
exports.CLEAR_DAY_PLAN_TOOL = CLEAR_DAY_PLAN_TOOL;
const GET_DAY_BLOCKS_TOOL = {
    name: "get_day_blocks",
    description: "Retourne les blocs de journée (Miracle Morning, Matinée, Midi, Soir…) avec horaires. " +
        "Appelle cet outil AVANT plan_day pour connaître la structure de la journée. " +
        "Respecte toujours les blocs existants : ne place pas une tâche de concentration " +
        "dans un bloc 'Soir' si 'Matinée' est disponible.",
    inputSchema: { type: "object", properties: {} },
};
exports.GET_DAY_BLOCKS_TOOL = GET_DAY_BLOCKS_TOOL;
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
exports.GET_DAY_PLAN_TOOL = GET_DAY_PLAN_TOOL;
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
exports.PLAN_DAY_TOOL = PLAN_DAY_TOOL;
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
exports.ARCHIVE_PROJECT_TOOL = ARCHIVE_PROJECT_TOOL;
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
exports.DELETE_PROJECT_TOOL = DELETE_PROJECT_TOOL;
const LIST_PROJECTS_TOOL = {
    name: "list_projects",
    description: "Liste les projets Gantt existants dans Productivitwo. " +
        "Appelle cet outil avant de modifier un projet afin de récupérer son id.",
    inputSchema: { type: "object", properties: {} },
};
exports.LIST_PROJECTS_TOOL = LIST_PROJECTS_TOOL;
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
exports.GET_PROJECT_TOOL = GET_PROJECT_TOOL;
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
                    domainId: { type: "string", description: "id du domaine (get_user_context)" },
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
                                actions: { type: "array", items: { type: "string" }, description: "2 à 4 sous-actions opérationnelles (étapes courtes, verbe d'action)" },
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
exports.PUSH_GANTT_MCP_TOOL = PUSH_GANTT_MCP_TOOL;
exports.GET_ASSISTANT_MESSAGES_TOOL = {
    name: "get_assistant_messages",
    description: "Retourne les messages ORION déjà programmés (pending) et les 10 derniers affichés (shown). " +
        "APPELLE CET OUTIL AVANT push_assistant_message pour éviter les doublons et voir ce qui est déjà planifié. " +
        "Utilise-le aussi pour auditer, mettre à jour ou supprimer des messages existants.",
    inputSchema: { type: "object", properties: {} },
};
exports.DELETE_ASSISTANT_MESSAGE_TOOL = {
    name: "delete_assistant_message",
    description: "Supprime ou expire un message ORION existant. " +
        "Utilise get_assistant_messages pour obtenir le messageId. " +
        "Utile pour retirer un message obsolète ou incorrect avant d'en créer un nouveau.",
    inputSchema: {
        type: "object",
        required: ["messageId"],
        properties: {
            messageId: { type: "string", description: "id du message (obtenu via get_assistant_messages)" },
        },
    },
};
//# sourceMappingURL=tools.js.map