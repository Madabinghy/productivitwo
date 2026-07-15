"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CREATE_SESSION_TEMPLATE_TOOL = exports.LIST_SESSION_TEMPLATES_TOOL = exports.ADD_EVENT_TOOL = exports.ADD_PREP_BLOCK_TOOL = exports.SAVE_OBJECTIVE_TOOL = exports.LIST_OBJECTIVES_TOOL = exports.SAVE_DOMAIN_DEFINITION_TOOL = exports.SCHEDULE_DAY_TOOL = exports.GET_DAY_SCHEDULE_TOOL = exports.SYNC_CALENDAR_TOOL = exports.PLAN_WEEK_TOOL = exports.PLAN_DAY_TOOL = exports.GENERATE_WEEKLY_REPORT_TOOL = exports.MARK_BLOCK_DONE_TOOL = exports.LOG_ROUTINE_HIT_TOOL = exports.ADD_ACTIVITY_ACTION_TOOL = exports.LINK_ACTION_TO_ACTIVITY_TOOL = exports.MARK_ACTION_DONE_TOOL = exports.UPDATE_TASK_TOOL = exports.ADD_TASK_TOOL = exports.PUSH_GANTT_MCP_TOOL = exports.GET_PROJECT_TOOL = exports.LIST_PROJECTS_TOOL = exports.DELETE_PROJECT_TOOL = exports.ARCHIVE_PROJECT_TOOL = exports.GET_DAY_BLOCKS_TOOL = exports.DELETE_ROUTINE_TOOL = exports.UPDATE_ACTIVITY_TOOL = exports.UPDATE_TASK_STATUS_TOOL = exports.UPDATE_PROJECT_TOOL = exports.DELETE_ACTIVITY_TOOL = exports.RESTORE_ITEM_TOOL = exports.GET_ARCHIVES_TOOL = exports.DELETE_DOCUMENT_TOOL = exports.GET_DOCUMENTS_TOOL = exports.SAVE_DOCUMENT_TOOL = exports.GET_DOCUMENT_TEMPLATE_TOOL = exports.DELETE_DOMAIN_TOOL = exports.PUSH_ASSISTANT_MESSAGE_TOOL = exports.CREATE_DOMAIN_TOOL = exports.CREATE_ACTIVITY_TOOL = exports.CREATE_ROUTINE_TOOL = exports.PROPOSE_CHANGE_TOOL = exports.SWEEP_INBOX_TOOL = exports.COMPUTE_TIME_BUDGET_TOOL = exports.SET_ACTIVITY_TARGETS_TOOL = exports.UPDATE_ACTIVITY_GOAL_TOOL = exports.GET_USER_CONTEXT_TOOL = exports.DELETE_ASSISTANT_MESSAGE_TOOL = exports.GET_ASSISTANT_MESSAGES_TOOL = void 0;
exports.UPDATE_SESSION_TEMPLATE_TOOL = void 0;
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
        "   Une routine pourra être liée à l'activité la plus pertinente (optionnel).\n" +
        "3. Créer le projet Gantt (push_gantt) couvrant AU MINIMUM la semaine en cours " +
        "   avec un jalon 'Bilan' le dimanche et un objectif KPI mesurable.\n" +
        "4. Sauvegarder le programme HTML avec save_document lié au projectId créé. " +
        "   Toujours renseigner domainId et subtitle. " +
        "   Si un document existe déjà pour ce projet (get_documents avant), passer son documentId pour éviter les doublons.\n" +
        "5. Créer les routines (create_routine) — mesurables (habitFreq + habitTarget), rattachées au domaine ; activityId facultatif.\n" +
        "6. Envoyer une push_notification : \"[Titre du programme] créé ✅\"\n\n" +
        "Structure garantie : Domaine → Activités temps → Projet Gantt (+ KPI + Bilan dim.) → Programme HTML sauvegardé → Routines mesurables.\n" +
        "Toute routine doit être mesurable (fréquence + cible) et rattachée à un domaine.",
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
const SET_ACTIVITY_TARGETS_TOOL = {
    name: "set_activity_targets",
    description: "Pose ou ajuste l'INTENTION de temps quotidienne (goalMin, en minutes) de plusieurs activités 'time' en un seul appel. " +
        "Sert à (1) remplacer la valeur d'onboarding par défaut (30 min) par une cible réaliste dès le démarrage, " +
        "et (2) recalibrer dans la durée selon l'écart entre l'intention et le réalisé (timeLogged de get_user_context). " +
        "N'écrase JAMAIS une cible épinglée à la main par l'utilisateur (targetSource='user'). " +
        "N'affecte PAS le score de productivité — uniquement la jauge de temps. Sois conservateur (sous-engage au début, monte par paliers).",
    inputSchema: {
        type: "object",
        required: ["targets"],
        properties: {
            targets: {
                type: "array",
                description: "Liste des cibles à poser",
                items: {
                    type: "object",
                    required: ["activityId", "goalMin"],
                    properties: {
                        activityId: { type: "string", description: "id de l'activité time (via get_user_context)" },
                        goalMin: { type: "number", description: "Intention de minutes/jour (réaliste, conservatrice)" },
                    },
                },
            },
        },
    },
};
exports.SET_ACTIVITY_TARGETS_TOOL = SET_ACTIVITY_TARGETS_TOOL;
const COMPUTE_TIME_BUDGET_TOOL = {
    name: "compute_time_budget",
    description: "Analyse 12 semaines de sessions et retourne, par activité 'time', la cible quotidienne recommandée (recommendedGoalMin) : MÉDIANE des jours actifs si < 30 jours loggués (échantillon trop petit pour un p90 fiable), p90 si ≥ 30 jours. Sommeil découplé (8h par défaut). Retourne aussi un champ 'workflow'. À chaîner avec set_activity_targets pour appliquer les cibles.",
    inputSchema: { type: "object", properties: {}, required: [] },
};
exports.COMPUTE_TIME_BUDGET_TOOL = COMPUTE_TIME_BUDGET_TOOL;
const SWEEP_INBOX_TOOL = {
    name: "sweep_inbox",
    description: "Balaie la boîte à idées (inbox) : les idées stratégiques deviennent des PROPOSITIONS de projets Gantt / de tâches sur un projet actif (file « À valider »), les idées ACTIONNABLES en un coup (corvée, course, appel) deviennent des DÉFIS 🔥 datés posés directement dans le programme des prochains jours (refusables d'un swipe), et les notes vagues sont laissées. " +
        "Force l'exécution même si déjà fait aujourd'hui (utile pour tester).",
    inputSchema: { type: "object", properties: {}, required: [] },
};
exports.SWEEP_INBOX_TOOL = SWEEP_INBOX_TOOL;
const PROPOSE_CHANGE_TOOL = {
    name: "propose_change",
    description: "Au lieu de modifier directement les projets, ENREGISTRE une proposition que l'utilisateur " +
        "validera dans la file « À valider » de la Revue de la semaine (accepter / refuser / rediriger). " +
        "Tu NE crées PAS le projet/la tâche/la phase/l'action toi-même — l'app applique la mutation à " +
        "l'acceptation. À utiliser pour TOUTE proposition issue d'une source externe (ex: mails) : créer " +
        "un projet, rattacher une idée comme tâche, créer un sous-projet, ajouter une phase à un projet, " +
        "ajouter une action à une tâche, ou archiver un projet inactif. Un appel = une proposition. " +
        "Mets dans 'title' un résumé humain court et dans 'rationale' la justification en 1 phrase " +
        "(cite l'objet/l'expéditeur du mail pour la traçabilité).",
    inputSchema: {
        type: "object",
        required: ["kind", "title", "rationale"],
        properties: {
            kind: {
                type: "string",
                enum: ["new_project", "attach_idea_as_task", "create_subproject", "archive_project", "add_phase", "attach_action_to_task"],
                description: "new_project = nouveau projet · attach_idea_as_task = ajouter une tâche à un projet existant · " +
                    "create_subproject = sous-projet d'un projet existant · archive_project = archiver un projet inactif · " +
                    "add_phase = ajouter une phase à un projet existant · attach_action_to_task = ajouter une action (sous-étape) à une tâche existante",
            },
            title: { type: "string", description: "Résumé humain court, ex: 'Créer le projet « Refonte site »'" },
            rationale: { type: "string", description: "Pourquoi, en 1 phrase" },
            sourceCaptureId: { type: "string", description: "Optionnel : id de l'idée inbox d'origine (la capture passera en 'proposed')" },
            payload: {
                type: "object",
                description: "Données pour appliquer la mutation selon kind : " +
                    "new_project={projectTitle, domainId?, description?} · " +
                    "attach_idea_as_task={projectId, taskTitle, description?} · " +
                    "create_subproject={parentProjectId, projectTitle, domainId?} · " +
                    "archive_project={projectId} · " +
                    "add_phase={projectId, phaseLabel, startDate?, endDate?, color?} · " +
                    "attach_action_to_task={projectId, taskId, actionLabel}",
                properties: {
                    projectId: { type: "string" },
                    parentProjectId: { type: "string" },
                    taskId: { type: "string" },
                    projectTitle: { type: "string" },
                    taskTitle: { type: "string" },
                    phaseLabel: { type: "string" },
                    actionLabel: { type: "string" },
                    domainId: { type: "string" },
                    description: { type: "string" },
                    startDate: { type: "string", description: "YYYY-MM-DD" },
                    endDate: { type: "string", description: "YYYY-MM-DD" },
                    color: { type: "string" },
                },
            },
        },
    },
};
exports.PROPOSE_CHANGE_TOOL = PROPOSE_CHANGE_TOOL;
const CREATE_ROUTINE_TOOL = {
    name: "create_routine",
    description: "Crée une **routine** : habitude mesurable trackée avec compteur ou fréquence (ex: Méditation, Gainage, Eau). " +
        "Liée à un domaine ; toujours mesurable (habitFreq + habitTarget). " +
        "⚠️ NE PAS confondre avec create_activity (tracking de temps/chrono).",
    inputSchema: {
        type: "object",
        required: ["name", "domainId"],
        properties: {
            name: { type: "string", description: "Nom de la routine (ex: Méditation, Gainage)" },
            domainId: { type: "string", description: "id du domaine (get_user_context)" },
            activityId: { type: "string", description: "id d'une activité temps à associer (OPTIONNEL — lien facultatif)" },
            unit: { type: "string", description: "Unité comptée (ex: fois, verres, séries)" },
            habitFreq: { type: "number", description: "Fréquence : 0=daily, 1=weekly, 2=monthly" },
            habitTarget: { type: "number", description: "Cible par période (ex: 3 fois/semaine)" },
        },
    },
};
exports.CREATE_ROUTINE_TOOL = CREATE_ROUTINE_TOOL;
const CREATE_ACTIVITY_TOOL = {
    name: "create_activity",
    description: "Crée une **activité** : tracking de temps avec chrono (ex: Deep Work, Running, Lecture). " +
        "Utilise cet outil quand l'utilisateur veut mesurer le temps passé sur quelque chose. " +
        "⚠️ NE PAS utiliser pour tracker une fréquence/compteur → create_routine. " +
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
                            "first_open_of_day",
                            "custom_date",
                        ],
                        description: "always · overdue_count(min) · day_plan_empty · project_inactive_days(projectId,days) · " +
                            "activity_behind_target(activityId) · habit_streak_broken(habitId) · " +
                            "inbox_overflow(min) · project_deadline_near(projectId,daysBefore) · no_now_focus(beforeHour) · " +
                            "routine_completion_low(maxPercent) · day_plan_overloaded(min) · no_activity_logged_today · " +
                            "project_milestone_today(projectId) · week_start · week_end · " +
                            "activity_streak(activityId,minDays) · " +
                            "first_open_of_day · custom_date(date)",
                    },
                    min: { type: "number", description: "Seuil minimum (overdue_count, inbox_overflow, day_plan_overloaded)" },
                    projectId: { type: "string", description: "ID projet (project_inactive_days, project_deadline_near, project_milestone_today)" },
                    days: { type: "number", description: "Jours d'inactivité (project_inactive_days)" },
                    daysBefore: { type: "number", description: "Jours avant deadline (project_deadline_near)" },
                    activityId: { type: "string", description: "ID activité (activity_behind_target, activity_streak)" },
                    habitId: { type: "string", description: "ID habitude (habit_streak_broken)" },
                    beforeHour: { type: "number", description: "Heure limite 0-23 (no_now_focus) — ex: 10 = avant 10h" },
                    maxPercent: { type: "number", description: "Taux de complétion max en % (routine_completion_low) — ex: 50 = moins de 50%" },
                    minDays: { type: "number", description: "Nombre de jours consécutifs minimum (activity_streak)" },
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
                        enum: ["open_day_plan", "open_project", "open_gantt_task", "open_activity"],
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
            content: { type: "string", description: "Contenu du document. HTML complet pour les catégories classiques. Pour category 'playbook' : MARKDOWN interactif (voir la description de category)." },
            projectId: { type: "string", description: "id du projet Gantt associé (obtenu via list_projects ou get_project)" },
            taskId: { type: "string", description: "id de la tâche Gantt associée (obtenu via get_project → tasks[].id). Toujours renseigner si le document concerne une tâche spécifique." },
            category: { type: "string", enum: ["programme", "brief", "recherche", "livrable", "notes", "playbook"], description: "Catégorie du document : 'programme' = plan structuré, 'brief' = cahier des charges, 'recherche' = analyse/veille, 'livrable' = output final, 'notes' = notes de travail, 'playbook' = document de pilotage INTERACTIF affiché sous le Gantt du projet. Défaut : 'notes'.\n\nPour 'playbook' (MARKDOWN, JAMAIS de HTML, TOUJOURS passer projectId) : ⚠️ le playbook est un MIROIR AUTOMATIQUE du Gantt — l'app le crée et le resynchronise toute seule à chaque ouverture. La STRUCTURE (1 carte par tâche, 1 case par action, titres, état coché) vient du GANTT : pour ajouter/renommer/supprimer une étape, modifie le GANTT (push_gantt / add_task / update_task), PAS le document. Tu n'as normalement PAS besoin de créer un playbook à la main.\n\nÀ quoi sert save_document sur un playbook : enrichir la COUCHE DE NOTES que le Gantt n'a pas (objectif de bloc, points de vigilance, descriptions). L'app conserve ces notes PAR ID d'action lors du resync. Workflow : get_documents(category 'playbook') pour lire le content → ajoute/ajuste les notes sur les lignes voulues EN GARDANT leur ref '^task:TASKID/ACTIONID' → save_document avec le documentId. ⚠️ Une case SANS ref ^task: est SUPPRIMÉE au prochain resync (l'app ne réémet que les actions réelles du Gantt) — garde TOUJOURS la ref sur chaque case.\n\nConventions de rendu (style « hero » auto : bannière, barre de progression, cartes) :\n- '# Titre' (UN seul, en tête, avec emoji) = bannière hero ; la 1ʳᵉ ligne '> ...' juste après = sous-titre.\n- '## 🎬 Nom du bloc' = une CARTE (= une tâche Gantt ; au resync le titre est repris du Gantt).\n- '_texte en italique_' (ligne entière, juste sous un '##') = ligne « objectif » du bloc.\n- '- [ ] Titre — description ^task:TASKID/ACTIONID' = case LIÉE à une action (état coché synchronisé DANS LES DEUX SENS doc↔Gantt). Le ' — ' sépare un TITRE gras et une DESCRIPTION grise. '- [x]' = cochée.\n- une ligne INDENTÉE de 2 espaces juste sous un item = note de cet item, colorée selon l'emoji de tête ('  ⚠️' orange, '  ★' or, '  ✅' vert). Sers-t'en pour les points de vigilance par étape.\n- '> ⚠️/✅/💡 texte' (non indenté) = bloc « point d'attention » pleine largeur.\nRécupère TASKID via tasks[].id et ACTIONID via tasks[].actions[].id avec get_project. Ex d'item enrichi : '- [ ] Brancher Claude — connecter le connecteur MCP ^task:abc-123/def-456\\n  ⚠️ nécessite Claude Pro'." },
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
            habitTarget: { type: "number", description: "cible par période — avec finalTarget, c'est le PALIER courant" },
            finalTarget: { type: "number", description: "cap de progression d'une routine quotidienne (ex: 50 pompes/j) — habitTarget devient le palier courant, démarré bas, ajusté chaque lundi selon les hits réels. 0 = retirer la progression" },
            timeContext: { type: "string", description: "contexte horaire de la routine : morning|midday|afternoon|evening|meal|day|allday|any — fenêtre naturelle (hygiène du soir=evening, boire de l'eau=allday). Vide = revenir à l'auto (catalogue)" },
        },
    },
};
exports.UPDATE_ACTIVITY_TOOL = UPDATE_ACTIVITY_TOOL;
const DELETE_ROUTINE_TOOL = {
    name: "delete_routine",
    description: "Archive une routine. L'élément reste récupérable depuis les Archives — " +
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
const GET_DAY_BLOCKS_TOOL = {
    name: "get_day_blocks",
    description: "Retourne les blocs de journée (Miracle Morning, Matinée, Midi, Soir…) avec horaires. " +
        "Utile avant schedule_day pour adapter les blocs horaires à la structure de la journée.",
    inputSchema: { type: "object", properties: {} },
};
exports.GET_DAY_BLOCKS_TOOL = GET_DAY_BLOCKS_TOOL;
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
                    id: { type: "string", description: "id du projet existant à mettre à jour (obtenu via list_projects). Omets pour créer un nouveau projet." },
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
                                actions: {
                                    type: "array",
                                    items: { type: "string" },
                                    description: "Sous-actions opérationnelles. " +
                                        "Pour une tâche de développement, utiliser le format mini-spec en 4 lignes :\n" +
                                        "  1. \"Objectif : <ce que la tâche doit accomplir>\"\n" +
                                        "  2. \"Fichiers : <fichiers ou zones concernés, ex: lib/web/gantt_screen.dart, functions/src/execute.ts>\"\n" +
                                        "  3. \"Critères : <liste des critères d'acceptation vérifiables>\"\n" +
                                        "  4. \"Contraintes : <limites techniques, libs interdites, rétrocompatibilité…>\"\n" +
                                        "Pour une tâche non-dev : 2 à 4 étapes courtes avec verbe d'action.",
                                },
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
const ADD_TASK_TOOL = {
    name: "add_task",
    description: "Ajoute une seule tâche à un projet Gantt existant sans réécrire tout le projet. " +
        "Utilise list_projects + get_project pour obtenir projectId et les phaseId. " +
        "Préférer cet outil à push_gantt quand on ajoute une tâche isolée.",
    inputSchema: {
        type: "object",
        required: ["projectId", "title", "startDate"],
        properties: {
            projectId: { type: "string", description: "id du projet (list_projects)" },
            title: { type: "string" },
            phaseId: { type: "string", description: "id de la phase (get_project)" },
            groupLabel: { type: "string" },
            startDate: { type: "string", description: "YYYY-MM-DD" },
            endDate: { type: "string", description: "YYYY-MM-DD" },
            isMilestone: { type: "boolean" },
            color: { type: "string" },
            barLabel: { type: "string" },
            status: { type: "string", enum: ["pending", "done", "skipped"] },
            actions: {
                type: "array",
                items: { type: "string" },
                description: "Sous-actions opérationnelles. " +
                    "Pour une tâche de développement, utiliser le format mini-spec en 4 lignes :\n" +
                    "  1. \"Objectif : <ce que la tâche doit accomplir>\"\n" +
                    "  2. \"Fichiers : <fichiers ou zones concernés, ex: lib/web/gantt_screen.dart, functions/src/execute.ts>\"\n" +
                    "  3. \"Critères : <liste des critères d'acceptation vérifiables>\"\n" +
                    "  4. \"Contraintes : <limites techniques, libs interdites, rétrocompatibilité…>\"\n" +
                    "Pour une tâche non-dev : 2 à 4 étapes courtes avec verbe d'action.",
            },
        },
    },
};
exports.ADD_TASK_TOOL = ADD_TASK_TOOL;
const UPDATE_TASK_TOOL = {
    name: "update_task",
    description: "Modifie les champs d'une tâche Gantt existante (titre, dates, actions, phase…). " +
        "Ne modifie que les champs fournis, laisse les autres inchangés. " +
        "Utilise list_projects + get_project pour obtenir projectId et taskId.",
    inputSchema: {
        type: "object",
        required: ["projectId", "taskId"],
        properties: {
            projectId: { type: "string", description: "id du projet" },
            taskId: { type: "string", description: "id de la tâche (get_project)" },
            title: { type: "string" },
            phaseId: { type: "string" },
            groupLabel: { type: "string" },
            startDate: { type: "string", description: "YYYY-MM-DD" },
            endDate: { type: "string", description: "YYYY-MM-DD" },
            isMilestone: { type: "boolean" },
            color: { type: "string" },
            barLabel: { type: "string" },
            status: { type: "string", enum: ["pending", "done", "skipped"] },
            actions: { type: "array", items: { type: "string" }, description: "Remplace toutes les sous-actions" },
        },
    },
};
exports.UPDATE_TASK_TOOL = UPDATE_TASK_TOOL;
const MARK_ACTION_DONE_TOOL = {
    name: "mark_action_done",
    description: "Coche/décoche une sous-action individuelle d'une tâche Gantt sans toucher au reste. " +
        "Préfère cet outil à update_task quand l'utilisateur progresse sur une action précise. " +
        "Récupère projectId, taskId et actionId via get_project.",
    inputSchema: {
        type: "object",
        required: ["projectId", "taskId", "actionId", "done"],
        properties: {
            projectId: { type: "string", description: "id du projet (list_projects)" },
            taskId: { type: "string", description: "id de la tâche (get_project)" },
            actionId: { type: "string", description: "id de la sous-action (get_project)" },
            done: { type: "boolean", description: "true pour marquer faite, false pour démarquer" },
        },
    },
};
exports.MARK_ACTION_DONE_TOOL = MARK_ACTION_DONE_TOOL;
const LINK_ACTION_TO_ACTIVITY_TOOL = {
    name: "link_action_to_activity",
    description: "Associe une sous-action d'une tâche Gantt à une activité-temps (pose linkedActivityId). " +
        "Le chrono lancé depuis cette action sera alors ciblé (le temps est loggué sur l'activité). " +
        "À PROPOSER quand une action n'est PAS déjà liée à une activité et qu'une activité-temps du même " +
        "domaine existe (vois activities + leur domainId via get_user_context). Ne ré-associe pas une action déjà liée.",
    inputSchema: {
        type: "object",
        required: ["projectId", "taskId", "actionId", "activityId"],
        properties: {
            projectId: { type: "string", description: "id du projet (list_projects)" },
            taskId: { type: "string", description: "id de la tâche (get_project)" },
            actionId: { type: "string", description: "id de la sous-action à lier (get_project)" },
            activityId: { type: "string", description: "id de l'activité-temps cible (get_user_context, même domaine de préférence)" },
        },
    },
};
exports.LINK_ACTION_TO_ACTIVITY_TOOL = LINK_ACTION_TO_ACTIVITY_TOOL;
const ADD_ACTIVITY_ACTION_TOOL = {
    name: "add_activity_action",
    description: "Crée une action PROPRE sur une activité-temps : une sous-action qui appartient directement à " +
        "l'activité (sans tâche/projet). Utile pour matérialiser une action récurrente ou ponctuelle liée " +
        "à une activité, puis la PROGRAMMER via schedule_day (activityId + actionId retourné). " +
        "N'utilise PAS cet outil pour une action qui relève d'un projet Gantt (utilise add_task/update_task).",
    inputSchema: {
        type: "object",
        required: ["activityId", "title"],
        properties: {
            activityId: { type: "string", description: "id de l'activité-temps propriétaire (get_user_context)" },
            title: { type: "string", description: "intitulé court et actionnable de l'action" },
        },
    },
};
exports.ADD_ACTIVITY_ACTION_TOOL = ADD_ACTIVITY_ACTION_TOOL;
const LOG_ROUTINE_HIT_TOOL = {
    name: "log_routine_hit",
    description: "Incrémente (ou décrémente) d'une unité une routine (habit) pour aujourd'hui : ajoute ou " +
        "retire un HabitHit et ajuste la progression du jour. Utilisé notamment par le widget iOS " +
        "quand l'utilisateur coche/décoche une routine depuis l'écran d'accueil. " +
        "Récupère activityId via get_user_context.",
    inputSchema: {
        type: "object",
        required: ["activityId"],
        properties: {
            activityId: { type: "string", description: "id de l'activité routine (type habit)" },
            delta: { type: "number", description: "+1 (défaut) pour cocher, -1 pour décocher (retire un hit)" },
        },
    },
};
exports.LOG_ROUTINE_HIT_TOOL = LOG_ROUTINE_HIT_TOOL;
const MARK_BLOCK_DONE_TOOL = {
    name: "mark_block_done",
    description: "Marque (ou démarque) un bloc du programme horaire du jour comme fait, sans toucher au reste " +
        "du programme. Préfère cet outil à schedule_day quand l'utilisateur valide un seul bloc. " +
        "Récupère blockId via get_day_schedule.",
    inputSchema: {
        type: "object",
        required: ["date", "blockId"],
        properties: {
            date: { type: "string", description: "jour du programme, format YYYY-MM-DD" },
            blockId: { type: "string", description: "id du bloc (get_day_schedule)" },
            done: { type: "boolean", description: "true (défaut) pour marquer fait, false pour démarquer" },
        },
    },
};
exports.MARK_BLOCK_DONE_TOOL = MARK_BLOCK_DONE_TOOL;
const GENERATE_WEEKLY_REPORT_TOOL = {
    name: "generate_weekly_report",
    description: "(Ré)génère le rapport hebdo d'une semaine : agrégats 100 % déterministes (engagements, vital " +
        "par domaine — séances ET heures logguées —, motifs, hygiène) + narratif. Écrase le doc " +
        "weekly_reports/{lundi} existant. Utile pour recalculer un rapport après correction des " +
        "données ou du calcul. Max 3 générations/jour.",
    inputSchema: {
        type: "object",
        properties: {
            weekStart: {
                type: "string",
                description: "Lundi de la semaine, format YYYY-MM-DD (défaut : semaine courante). " +
                    "Une date en milieu de semaine est ramenée à son lundi.",
            },
        },
    },
};
exports.GENERATE_WEEKLY_REPORT_TOOL = GENERATE_WEEKLY_REPORT_TOOL;
exports.PLAN_DAY_TOOL = {
    name: "plan_day",
    description: "Agrège tout le contexte nécessaire pour planifier une journée : contexte utilisateur, " +
        "programme existant, et détail de tous les projets Gantt actifs avec leurs tâches. " +
        "Retourne le contexte consolidé + les instructions de workflow à suivre pour générer " +
        "le programme et le synchroniser dans Google Calendar.\n\n" +
        "Workflow attendu après cet appel :\n" +
        "1. Lire list_events() Google Calendar pour la date (éviter les conflits)\n" +
        "2. Générer les blocs horaires en tenant compte des tâches Gantt, routines et pauses\n" +
        "3. Appeler schedule_day(date, blocks[])\n" +
        "4. Si syncToCalendar=true : créer les events dans le calendrier Google 'Productivitwo'",
    inputSchema: {
        type: "object",
        properties: {
            date: { type: "string", description: "YYYY-MM-DD (défaut: aujourd'hui)" },
            startHour: { type: "number", description: "Heure de début (défaut: 7)" },
            endHour: { type: "number", description: "Heure de fin (défaut: 20)" },
            syncToCalendar: { type: "boolean", description: "Synchroniser dans Google Calendar après schedule_day (défaut: true)" },
        },
    },
};
exports.PLAN_WEEK_TOOL = {
    name: "plan_week",
    description: "Agrège le contexte complet pour planifier une semaine de 5 jours ouvrés : contexte utilisateur, " +
        "programmes existants pour chaque jour, et tous les projets Gantt actifs. " +
        "Retourne le contexte consolidé + les instructions pour répartir les tâches sur la semaine " +
        "et synchroniser dans Google Calendar.\n\n" +
        "Workflow attendu : générer 5 programmes via schedule_day(), un par jour, " +
        "en répartissant les tâches Gantt (deadline proche = priorité, max ~6h/jour).",
    inputSchema: {
        type: "object",
        properties: {
            startDate: { type: "string", description: "YYYY-MM-DD du lundi de début (défaut: lundi prochain, ou aujourd'hui si lundi)" },
            syncToCalendar: { type: "boolean", description: "Synchroniser dans Google Calendar après schedule_day (défaut: true)" },
        },
    },
};
exports.SYNC_CALENDAR_TOOL = {
    name: "sync_calendar",
    description: "Lit le programme Productivitwo d'une journée et retourne les instructions exactes " +
        "pour synchroniser ce programme dans Google Calendar (sans regénérer le programme). " +
        "Utile quand le programme a été modifié manuellement dans l'app Flutter.\n\n" +
        "Workflow attendu :\n" +
        "1. Trouver le calendrier 'Productivitwo' via list_calendars()\n" +
        "2. Supprimer les events existants avec 'source: productivitwo' dans la description\n" +
        "3. Créer les events listés dans la réponse de cet outil",
    inputSchema: {
        type: "object",
        properties: {
            date: { type: "string", description: "YYYY-MM-DD (défaut: aujourd'hui)" },
        },
    },
};
exports.GET_DAY_SCHEDULE_TOOL = {
    name: "get_day_schedule",
    description: "Retourne le programme horaire d'une journée (généré par Claude ou ORION). " +
        "Appelle cet outil avant schedule_day pour vérifier si un programme existe déjà.",
    inputSchema: {
        type: "object",
        required: ["date"],
        properties: {
            date: { type: "string", description: "YYYY-MM-DD" },
        },
    },
};
exports.SCHEDULE_DAY_TOOL = {
    name: "schedule_day",
    description: "Génère ou remplace le programme horaire d'une journée dans Productivitwo. " +
        "Chaque bloc est un créneau horaire avec une action concrète. " +
        "⚠️ Pour la date du JOUR, ne JAMAIS créer de blocs à des heures déjà passées " +
        "(planifie à partir de l'heure actuelle) ; les blocs passés existants restent intacts. " +
        "Un bloc peut porter uniquement activityId (sans projet/tâche) → temps bloqué " +
        "sur une activité, chrono ciblé au lancement. " +
        "⚠️ Un bloc = UNE SEULE routine/activité avec SON activityId — ne JAMAIS " +
        "regrouper plusieurs routines dans un bloc (« Ménage + hygiène » interdit : " +
        "ça casse le chrono ciblé et le ✓ par routine). Deux routines = deux blocs. " +
        "Étapes recommandées : (1) get_user_context pour récupérer projets et routines actifs, " +
        "(2) get_day_schedule pour vérifier si un programme existe déjà, " +
        "(3) schedule_day pour créer ou remplacer le programme.",
    inputSchema: {
        type: "object",
        required: ["date", "blocks"],
        properties: {
            date: { type: "string", description: "YYYY-MM-DD — date du programme" },
            blocks: {
                type: "array",
                description: "Liste des blocs horaires dans l'ordre chronologique",
                items: {
                    type: "object",
                    required: ["startTime", "durationMin", "title", "category"],
                    properties: {
                        startTime: { type: "string", description: "Heure de début HH:mm (ex: '09:30')" },
                        durationMin: { type: "integer", description: "Durée en minutes" },
                        title: { type: "string", description: "Intitulé court et actionnable (verbe d'action)" },
                        category: {
                            type: "string",
                            enum: ["project", "routine", "personal", "break"],
                            description: "project = tâche Gantt · routine = activité trackée · personal = perso/maison · break = pause",
                        },
                        projectId: { type: "string", description: "id du projet Gantt lié (si category=project, obtenu via list_projects)" },
                        taskId: { type: "string", description: "id de la tâche Gantt liée (obtenu via get_project)" },
                        activityId: { type: "string", description: "id de l'activité liée (si category=routine, ou activité-temps d'une action propre)" },
                        actionId: { type: "string", description: "id de l'action ciblée — action PROPRE d'une activité (avec son activityId) OU sous-action d'une tâche de projet (avec projectId+taskId). Le chrono lancé depuis ce bloc pointera sur cette action." },
                        sessionTemplateId: { type: "string", description: "id d'un déroulé réutilisable (séance, via list_session_templates) — à poser AVEC l'activityId du déroulé : ▶ lance le chrono sur l'activité et ouvre le player d'étapes sur cette séance." },
                        kind: { type: "string", enum: ["normal", "prep"], description: "défaut 'normal'. 'prep' = mini-bloc de préparation la veille lié à un bloc du lendemain (préfère l'outil add_prep_block pour ajouter une prep sans remplacer le programme)." },
                        prepForDate: { type: "string", description: "si kind=prep : YYYY-MM-DD du bloc cible préparé (souvent J+1)" },
                        prepForBlockId: { type: "string", description: "si kind=prep : id du bloc cible dans le programme de prepForDate" },
                        skipReason: { type: "string", description: "pourquoi l'engagement a sauté (écrit par le check-in du soir — ne pas remplir à la planification)" },
                    },
                },
            },
        },
    },
};
exports.SAVE_DOMAIN_DEFINITION_TOOL = {
    name: "save_domain_definition",
    description: "Écrit la définition d'un domaine de vie (intention, minimum vital, modalités, artefacts voulus) " +
        "sur la collection domains EXISTANTE — appelé par la session de définition à CHAQUE élément validé " +
        "par l'utilisateur (jamais en bloc à la fin : la fiche doit refléter l'état réel, « reprendre plus " +
        "tard » doit être gratuit). L'intention est LES MOTS DE L'UTILISATEUR, jamais reformulée. " +
        "vitalMinimum : uniquement du mesurable (metric/target/period) — omettre les vœux invérifiables. " +
        "Upsert : domainId si connu, sinon match par nom (insensible à la casse), sinon création en draft. " +
        "finalize:true à la fin de session → definitionStatus:'active' + definedAt.",
    inputSchema: {
        type: "object",
        required: ["name"],
        properties: {
            domainId: { type: "string", description: "id du domaine si connu (sinon match par nom / création)" },
            name: { type: "string", description: "nom du domaine, ex: 'Santé'" },
            intention: { type: "string", description: "l'intention, une phrase, dans les mots exacts de l'utilisateur" },
            vitalMinimum: {
                type: "array",
                description: "le plancher non négociable, traduit en métriques mesurables",
                items: {
                    type: "object",
                    required: ["label"],
                    properties: {
                        label: { type: "string", description: "ex: '2 séances / sem'" },
                        metric: { type: "string", description: "sessions_week | sessions_day | hours_week | hours_day | minutes_week | minutes_day — omettre si non mesurable (sessions* = nb de séances ≥ 10 min ; hours*/minutes* = temps réel loggué sur les activités du domaine)" },
                        target: { type: "number" },
                        period: { type: "string", enum: ["week", "day"] },
                    },
                },
            },
            modalities: {
                type: "array", items: { type: "string" },
                description: "créneaux/fréquences concrets — ce que la renégociation fera évoluer, ex: 'séances le matin 7h15 (prep la veille)'",
            },
            wantedArtifacts: {
                type: "array", items: { type: "string" },
                description: "artefacts à générer ensuite, ex: 'Plan de reprise — 6 semaines'",
            },
            tracking: {
                type: "string", enum: ["timed", "declared"],
                description: "suivi du vital : 'timed' (défaut — sessions/blocs mesurés) ou 'declared' (vie privée : pas de chrono, pas de blocs, pas de score — le vital est demandé en 1-2 questions binaires au rapport hebdo, c'est tout)",
            },
            protectedSlots: {
                type: "array", items: { type: "string" },
                description: "territoire défendu — créneaux où la proposition ne pose JAMAIS rien, quel que soit le retard ailleurs. Codes '{mon|tue|wed|thu|fri|sat|sun}_{morning|afternoon|evening|day}', ex: ['fri_evening','sat_evening','sun_day']",
            },
            finalize: { type: "boolean", description: "true en fin de session → domaine actif + definedAt" },
        },
    },
};
exports.LIST_OBJECTIVES_TOOL = {
    name: "list_objectives",
    description: "Liste les objectifs stratégiques ACTIFS avec leur progression hebdomadaire : pour chaque objectif, " +
        "le résultat visé (kpiTarget), l'horizon, et l'avancement de chaque engagement opérationnel " +
        "(minutes loggées vs engagement temps hebdo, hits vs cible de routine, onTrack). " +
        "Appelle-le au début d'une session de définition/révision d'objectifs, ou quand l'utilisateur " +
        "demande « où j'en suis sur mes objectifs ».",
    inputSchema: { type: "object", properties: {} },
};
exports.SAVE_OBJECTIVE_TOOL = {
    name: "save_objective",
    description: "Crée ou met à jour un objectif stratégique (SMART) relié à ses moyens opérationnels. " +
        "Appelé par la session de définition à CHAQUE élément validé par l'utilisateur (jamais en bloc à la fin). " +
        "Un objectif complet exige : un titre SPÉCIFIQUE dans les mots de l'utilisateur, un kpiTarget MESURABLE " +
        "(chiffre + unité, ex: '100 clients payants · MRR 500€'), une échéance (endDate ou horizonLabel), " +
        "et AU MOINS un moyen opérationnel : timeCommitment (engagement de minutes/semaine sur une activité-temps " +
        "existante — ids via get_user_context) et/ou routineCommitment (routine dont la cible vit déjà sur " +
        "habitFreq/habitTarget) et/ou projectIds (projets Gantt). weeklyMin RÉALISTE : sous-engager au début, " +
        "la révision est gratuite. Upsert : objectiveId si connu, sinon match par titre (insensible à la casse), " +
        "sinon création. status:'archived' = suppression (soft) — jamais de suppression physique.",
    inputSchema: {
        type: "object",
        required: ["title"],
        properties: {
            objectiveId: { type: "string", description: "id de l'objectif si connu (sinon match par titre / création)" },
            title: { type: "string", description: "résultat visé, spécifique, dans les mots de l'utilisateur" },
            description: { type: "string", description: "pourquoi cet objectif compte (motivation, contexte)" },
            domainId: { type: "string", description: "domaine de vie rattaché (ids via get_user_context)" },
            kpiTarget: { type: "string", description: "indicateur MESURABLE du succès, ex: '100 payants · MRR 500€'" },
            horizonLabel: { type: "string", description: "horizon lisible, ex: '3 mois', 'Q2 2026'" },
            startDate: { type: "string", description: "YYYY-MM-DD — début de l'objectif" },
            endDate: { type: "string", description: "YYYY-MM-DD — échéance" },
            status: { type: "string", enum: ["active", "done", "archived"], description: "archived = suppression soft ; done = objectif atteint" },
            projectIds: { type: "array", items: { type: "string" }, description: "projets Gantt rattachés (arrayUnion — n'enlève jamais)" },
            timeCommitments: {
                type: "array",
                description: "engagements de temps hebdo sur des activités type 'time' — REMPLACE la liste existante si fourni",
                items: {
                    type: "object",
                    required: ["activityId", "weeklyMin"],
                    properties: {
                        activityId: { type: "string", description: "id d'une activité-temps existante" },
                        weeklyMin: { type: "integer", description: "minutes par semaine (1..3000) — réaliste, révisable" },
                    },
                },
            },
            routineCommitments: {
                type: "array",
                description: "routines suivies par cet objectif (leur cible reste habitFreq/habitTarget) — REMPLACE la liste existante si fourni",
                items: {
                    type: "object",
                    required: ["activityId"],
                    properties: {
                        activityId: { type: "string", description: "id d'une routine (activité type 'habit') existante" },
                    },
                },
            },
        },
    },
};
exports.ADD_PREP_BLOCK_TOOL = {
    name: "add_prep_block",
    description: "Ajoute UN bloc de préparation la veille (kind:'prep') au programme d'une journée SANS remplacer " +
        "le reste (contrairement à schedule_day). Sert à armer un bloc matinal du lendemain qui exige du " +
        "matériel ou de la logistique (sport, déplacement, cuisine) : le user coche la prep le soir en un " +
        "tap, et le lendemain matin le système peut affirmer un fait tracké (« affaires prêtes depuis hier »). " +
        "Idempotent : si un bloc prep non supprimé pointant déjà vers (prepForDate, prepForBlockId) existe, " +
        "il n'est pas dupliqué. Crée le doc du jour au besoin.",
    inputSchema: {
        type: "object",
        required: ["date", "startTime", "title", "prepForDate", "prepForBlockId"],
        properties: {
            date: { type: "string", description: "YYYY-MM-DD — jour où placer le bloc de prep (souvent la veille du bloc cible)" },
            startTime: { type: "string", description: "Heure de début HH:mm (défaut recommandé : 21:45)" },
            durationMin: { type: "integer", description: "Durée en minutes (défaut : 5)" },
            title: { type: "string", description: "Intitulé, ex: 'Préparer les affaires de sport'" },
            prepForDate: { type: "string", description: "YYYY-MM-DD du bloc cible préparé (souvent J+1)" },
            prepForBlockId: { type: "string", description: "id du bloc cible dans le programme de prepForDate (via get_day_schedule)" },
        },
    },
};
exports.ADD_EVENT_TOOL = {
    name: "add_event",
    description: "Pose un ÉVÉNEMENT daté dans le programme du jour concerné (« J'accompagne maman le 12 à son RDV " +
        "à 14h ») SANS remplacer le reste. ⚠️ La durée est un fait utilisateur : si durationMin manque, " +
        "l'outil refuse — demande « Combien de temps estimes-tu ? » PUIS rappelle l'outil. La réponse " +
        "inclut les instructions Google Calendar (connecteur GCal) si syncToCalendar n'est pas false. " +
        "Idempotent : même titre à la même heure le même jour → rien ajouté. Crée le doc du jour au besoin.",
    inputSchema: {
        type: "object",
        required: ["date", "startTime", "title"],
        properties: {
            date: { type: "string", description: "YYYY-MM-DD — jour de l'événement" },
            startTime: { type: "string", description: "Heure de début HH:mm" },
            title: { type: "string", description: "Intitulé, ex: 'Accompagner maman — RDV médecin'" },
            durationMin: { type: "integer", description: "Durée estimée en minutes — TOUJOURS demandée à l'utilisateur, jamais inventée" },
            syncToCalendar: { type: "boolean", description: "false = pas d'instructions Google Calendar (défaut : true)" },
        },
    },
};
// ── Déroulés réutilisables (session_templates) ────────────────────────────────
const SESSION_STEPS_SCHEMA = {
    type: "array",
    description: "Étapes dans l'ordre d'exécution de la séance",
    items: {
        type: "object",
        required: ["title"],
        properties: {
            title: { type: "string", description: "Intitulé de l'étape" },
            routineId: {
                type: "string",
                description: "id d'une routine existante (via get_user_context) → étape-routine : son compteur, son palier et son streak restent chez elle",
            },
            checklist: {
                type: "array",
                items: { type: "string" },
                description: "sous-items d'une étape simple (ex: 'ranger le matos' → ['vider le bac', 'nettoyer la lame'])",
            },
        },
    },
};
exports.LIST_SESSION_TEMPLATES_TOOL = {
    name: "list_session_templates",
    description: "Liste les déroulés réutilisables (séances) : la playlist ordonnée d'étapes d'une séance sur une activité-temps. " +
        "Utilise leurs ids pour update_session_template, ou pose un bloc schedule_day avec sessionTemplateId + activityId → ▶ = chrono + player d'étapes.",
    inputSchema: { type: "object", properties: {} },
};
exports.CREATE_SESSION_TEMPLATE_TOOL = {
    name: "create_session_template",
    description: "Crée un déroulé réutilisable (séance) sur une activité-temps : le chrono trace le temps sur l'activité pendant que le player de Maintenant égrène les étapes. " +
        "Étape simple = titre (+ checklist optionnelle) ; étape-routine = routineId (compteur − / +, palier, streak). " +
        "Idéal pour construire des programmes d'entraînement (Séance A / Séance B…) ou des procédures (Couper les herbes : préparer → couper → souffler → ranger).",
    inputSchema: {
        type: "object",
        required: ["activityId", "title", "steps"],
        properties: {
            activityId: { type: "string", description: "id de l'activité-temps propriétaire du chrono (via get_user_context)" },
            title: { type: "string", description: "Nom de la séance (ex: 'Séance A — haut du corps')" },
            steps: SESSION_STEPS_SCHEMA,
        },
    },
};
exports.UPDATE_SESSION_TEMPLATE_TOOL = {
    name: "update_session_template",
    description: "Modifie un déroulé existant : titre, remplacement COMPLET des étapes, ou archivage (soft-delete). id via list_session_templates.",
    inputSchema: {
        type: "object",
        required: ["templateId"],
        properties: {
            templateId: { type: "string" },
            title: { type: "string" },
            steps: SESSION_STEPS_SCHEMA,
            archived: { type: "boolean", description: "true = archiver la séance" },
        },
    },
};
//# sourceMappingURL=tools.js.map