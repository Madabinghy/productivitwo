const GET_USER_CONTEXT_TOOL = {
  name: "get_user_context",
  description:
    "APPELLE CET OUTIL EN PREMIER dans toute conversation liée à la productivité. " +
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

const UPDATE_ACTIVITY_GOAL_TOOL = {
  name: "update_activity_goal",
  description:
    "Modifie l'objectif quotidien d'une activité (temps ou fréquence). " +
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
  description:
    "Crée une **routine** : habitude trackée avec compteur ou fréquence (ex: Méditation, Gainage, Eau). " +
    "⚠️ activityId OBLIGATOIRE — créer d'abord l'activité temps avec create_activity si elle n'existe pas. " +
    "⚠️ NE PAS confondre avec create_activity (tracking de temps/chrono).",
  inputSchema: {
    type: "object",
    required: ["name", "domainId", "activityId"],
    properties: {
      name:        { type: "string", description: "Nom de la routine (ex: Méditation, Gainage)" },
      domainId:    { type: "string", description: "id du domaine (get_user_context)" },
      activityId:  { type: "string", description: "id de l'activité temps associée (OBLIGATOIRE — créer avec create_activity si absente)" },
      unit:        { type: "string", description: "Unité comptée (ex: fois, verres, séries)" },
      habitFreq:   { type: "number", description: "Fréquence : 0=daily, 1=weekly, 2=monthly" },
      habitTarget: { type: "number", description: "Cible par période (ex: 3 fois/semaine)" },
    },
  },
};


const CREATE_ACTIVITY_TOOL = {
  name: "create_activity",
  description:
    "Crée une **activité** : tracking de temps avec chrono (ex: Deep Work, Running, Lecture). " +
    "Utilise cet outil quand l'utilisateur veut mesurer le temps passé sur quelque chose. " +
    "⚠️ NE PAS utiliser pour tracker une fréquence/compteur → create_routine. " +
    "Demande confirmation avant de créer.",
  inputSchema: {
    type: "object",
    required: ["name", "domainId"],
    properties: {
      name:    { type: "string", description: "Nom de l'activité (ex: Deep Work, Running)" },
      domainId: { type: "string", description: "id du domaine (get_user_context)" },
      goalMin: { type: "number", description: "Objectif en minutes/jour" },
    },
  },
};

const CREATE_DOMAIN_TOOL = {
  name: "create_domain",
  description:
    "Crée un nouveau domaine de vie dans Productivitwo (ex: Santé, Travail, Famille). " +
    "Utilise get_user_context pour vérifier qu'un domaine similaire n'existe pas déjà. " +
    "Demande confirmation avant de créer.",
  inputSchema: {
    type: "object",
    required: ["name"],
    properties: {
      name:        { type: "string", description: "Nom du domaine (ex: Santé, Travail, Famille)" },
      goalMinDay:  { type: "number", description: "Objectif quotidien en minutes (null = auto depuis les activités)" },
      autoGoal:    { type: "boolean", description: "true = objectif calculé depuis les activités (défaut: true)" },
      colorValue:  { type: "number", description: "Valeur entière Flutter Color.value (optionnel)" },
    },
  },
};

const PUSH_ASSISTANT_MESSAGE_TOOL = {
  name: "push_assistant_message",
  description:
    "Écrit un message pour l'assistant Productivitwo — visible dans le web app sous forme de conseil animé. " +
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
            description:
              "always · overdue_count(min) · day_plan_empty · project_inactive_days(projectId,days) · " +
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

const DELETE_DOMAIN_TOOL = {
  name: "delete_domain",
  description:
    "Archive un domaine de vie et toutes ses activités + routines (cascade). " +
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

const GET_DOCUMENT_TEMPLATE_TOOL = {
  name: "get_document_template",
  description:
    "Retourne le template HTML de référence pour créer un programme Productivitwo. " +
    "TOUJOURS appeler cet outil avant de générer un programme HTML. " +
    "Adapter le template au contenu du programme et aux couleurs du domaine (variable --gold).",
  inputSchema: { type: "object", properties: {} },
};

const SAVE_DOCUMENT_TOOL = {
  name: "save_document",
  description:
    "Sauvegarde ou met à jour un document HTML dans Productivitwo (programme, plan, bilan, fiche, brief, livrable). " +
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
      title:      { type: "string", description: "Titre du document (ex: Programme Prise de Masse 6 mois)" },
      content:    { type: "string", description: "Contenu du document. HTML complet pour les catégories classiques. Pour category 'playbook' : MARKDOWN interactif (voir la description de category)." },
      projectId:  { type: "string", description: "id du projet Gantt associé (obtenu via list_projects ou get_project)" },
      taskId:     { type: "string", description: "id de la tâche Gantt associée (obtenu via get_project → tasks[].id). Toujours renseigner si le document concerne une tâche spécifique." },
      category:   { type: "string", enum: ["programme", "brief", "recherche", "livrable", "notes", "playbook"], description: "Catégorie du document : 'programme' = plan structuré, 'brief' = cahier des charges, 'recherche' = analyse/veille, 'livrable' = output final, 'notes' = notes de travail, 'playbook' = document de pilotage INTERACTIF affiché sous le Gantt du projet. Défaut : 'notes'.\n\nPour 'playbook' : le content est du MARKDOWN (PAS du HTML), TOUJOURS passer projectId, et suivre ces conventions (le rendu app applique automatiquement un style « hero » : bannière, barre de progression, cartes par bloc) :\n- '# Titre' (UN seul, en tête, avec emoji) = bannière hero. La 1ʳᵉ ligne '> ...' juste après devient le sous-titre.\n- '## 🎬 Nom du bloc' = ouvre une CARTE encadrée (mets un emoji pertinent par bloc).\n- '_texte en italique_' (ligne entière, juste sous un '##') = ligne « objectif » du bloc.\n- '- [ ] Titre court — description' = case à cocher. Le ' — ' (tiret cadratin) sépare un TITRE gras et une DESCRIPTION grise. '- [x] ...' = cochée.\n- une ligne INDENTÉE de 2 espaces juste sous un item = note de cet item, colorée selon l'emoji de tête ('  ⚠️ ...' orange, '  ★ ...' or, '  ✅ ...' vert). Sers-t'en pour les points de vigilance par étape.\n- '> ⚠️/✅/💡 texte' (non indenté) = bloc « point d'attention » coloré pleine largeur, pour un point critique du bloc.\nStructure soignée et scannable. Exemple d'item : '- [ ] Brancher Claude — connecter le connecteur MCP\\n  ⚠️ nécessite Claude Pro'.\n\nLIER une case à une action Gantt (l'état coché se synchronise dans LES DEUX SENS doc↔Gantt) : ajoute en FIN de ligne ' ^task:TASKID/ACTIONID' (récupère TASKID via tasks[].id et ACTIONID via tasks[].actions[].id avec get_project). Ex : '- [ ] 1.2 · Tourner la séquence ^task:abc-123/def-456'. Utilise les liens quand une étape du playbook correspond à une action existante de la tâche.\n\nIMPORTANT — cohérence : le playbook n'est PAS régénéré automatiquement quand la structure du projet change. Si tu ajoutes/supprimes des tâches ou actions d'un projet qui possède déjà un playbook (vérifie via get_documents category 'playbook'), METS AUSSI À JOUR le playbook (save_document avec son documentId) pour qu'il reste cohérent." },
      documentId: { type: "string", description: "id du document existant à mettre à jour — obtenu via get_documents. NE PAS passer pour une création." },
      domainId:   { type: "string", description: "id du domaine (obtenu via get_user_context) — utilisé pour la couleur de la carte dans l'app" },
      subtitle:   { type: "string", description: "Résumé court affiché sur la carte preview (ex: 'Phase 1 · 4 séances/semaine · Mois 1-2')" },
    },
  },
};

const GET_DOCUMENTS_TOOL = {
  name: "get_documents",
  description:
    "Récupère les documents sauvegardés (programmes, plans, bilans, briefs, livrables). " +
    "Utilise cet outil pour relire un document et le comparer à l'état actuel, ou pour vérifier si un document existe avant d'en créer un nouveau. " +
    "Retourne la liste avec titres, catégories et dates.",
  inputSchema: {
    type: "object",
    properties: {
      projectId: { type: "string", description: "Filtrer par projet (optionnel)" },
      taskId:    { type: "string", description: "Filtrer par tâche Gantt (optionnel) — retourne uniquement les documents associés à cette tâche" },
    },
  },
};

const DELETE_DOCUMENT_TOOL = {
  name: "delete_document",
  description:
    "Supprime définitivement un document sauvegardé (programme, bilan, fiche). " +
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

const GET_ARCHIVES_TOOL = {
  name: "get_archives",
  description:
    "Liste tous les éléments archivés (deleted:true) : domaines, activités, routines. " +
    "Utilise cet outil pour voir ce qui a été supprimé et pouvoir restaurer en cas d'erreur.",
  inputSchema: { type: "object", properties: {} },
};

const RESTORE_ITEM_TOOL = {
  name: "restore_item",
  description:
    "Restaure un élément archivé (annule la suppression). " +
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


const DELETE_ACTIVITY_TOOL = {
  name: "delete_activity",
  description:
    "Archive une activité et ses routines liées (cascade). " +
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

const UPDATE_PROJECT_TOOL = {
  name: "update_project",
  description:
    "Modifie les métadonnées d'un projet Gantt existant sans toucher aux tâches/phases. " +
    "Utilise cet outil pour changer le domaine, le titre, la description ou le statut. " +
    "Utilise list_projects pour obtenir le projectId.",
  inputSchema: {
    type: "object",
    required: ["projectId"],
    properties: {
      projectId:   { type: "string", description: "id du projet (list_projects)" },
      domainId:    { type: "string", description: "id du domaine (get_user_context)" },
      title:       { type: "string" },
      description: { type: "string" },
      status:      { type: "string", enum: ["active", "archived", "done"] },
    },
  },
};

const UPDATE_TASK_STATUS_TOOL = {
  name: "update_task_status",
  description:
    "Met à jour le statut d'une tâche Gantt (pending → done, skipped, etc.). " +
    "Utilise list_projects + get_project pour obtenir projectId et taskId. " +
    "Beaucoup plus rapide que de recréer tout le projet.",
  inputSchema: {
    type: "object",
    required: ["projectId", "taskId", "status"],
    properties: {
      projectId: { type: "string", description: "id du projet (list_projects)" },
      taskId:    { type: "string", description: "id de la tâche (get_project)" },
      status:    { type: "string", enum: ["pending", "done", "skipped"], description: "Nouveau statut" },
    },
  },
};

const UPDATE_ACTIVITY_TOOL = {
  name: "update_activity",
  description:
    "Modifie une activité existante (nom, domaine, type, objectif, unité). " +
    "Utilise get_user_context pour obtenir l'activityId. " +
    "Ne modifie que les champs fournis, laisse les autres inchangés.",
  inputSchema: {
    type: "object",
    required: ["activityId"],
    properties: {
      activityId:  { type: "string", description: "id de l'activité (get_user_context)" },
      name:        { type: "string" },
      domainId:    { type: "string" },
      goalMin:     { type: "number" },
      unit:        { type: "string" },
      habitFreq:   { type: "number", description: "0=daily, 1=weekly, 2=monthly" },
      habitTarget: { type: "number" },
    },
  },
};

const DELETE_ROUTINE_TOOL = {
  name: "delete_routine",
  description:
    "Archive une action récurrente. L'élément reste récupérable depuis les Archives — " +
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

const GET_DAY_BLOCKS_TOOL = {
  name: "get_day_blocks",
  description:
    "Retourne les blocs de journée (Miracle Morning, Matinée, Midi, Soir…) avec horaires. " +
    "Utile avant schedule_day pour adapter les blocs horaires à la structure de la journée.",
  inputSchema: { type: "object", properties: {} },
};

const ARCHIVE_PROJECT_TOOL = {
  name: "archive_project",
  description:
    "Met un projet Gantt en veille (archived) ou le réactive (active). " +
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
  description:
    "Supprime définitivement un projet Gantt et son objectif stratégique associé. " +
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
  description:
    "Liste les projets Gantt existants dans Productivitwo. " +
    "Appelle cet outil avant de modifier un projet afin de récupérer son id.",
  inputSchema: { type: "object", properties: {} },
};

const GET_PROJECT_TOOL = {
  name: "get_project",
  description:
    "Retourne le détail complet d'un projet Gantt (phases, tâches, jalons). " +
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
  description:
    "Crée ou met à jour un projet Gantt dans Productivitwo. " +
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
          id:          { type: "string", description: "id du projet existant à mettre à jour (obtenu via list_projects). Omets pour créer un nouveau projet." },
          title:       { type: "string" },
          description: { type: "string" },
          domainId:    { type: "string", description: "id du domaine (get_user_context)" },
          startDate:   { type: "string", description: "YYYY-MM-DD" },
          endDate:     { type: "string", description: "YYYY-MM-DD" },
          phases: {
            type: "array",
            items: {
              type: "object",
              required: ["label", "startDate", "endDate"],
              properties: {
                label:     { type: "string" },
                color:     { type: "string" },
                startDate: { type: "string" },
                endDate:   { type: "string" },
              },
            },
          },
          tasks: {
            type: "array",
            items: {
              type: "object",
              required: ["title", "startDate"],
              properties: {
                title:       { type: "string" },
                groupLabel:  { type: "string" },
                startDate:   { type: "string" },
                endDate:     { type: "string" },
                isMilestone: { type: "boolean" },
                color:       { type: "string" },
                barLabel:    { type: "string" },
                status:      { type: "string", enum: ["pending", "done", "skipped"] },
                actions:     {
                  type: "array",
                  items: { type: "string" },
                  description:
                    "Sous-actions opérationnelles. " +
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
          title:        { type: "string" },
          kpiTarget:    { type: "string" },
          horizonLabel: { type: "string" },
        },
      },
    },
  },
};

export const GET_ASSISTANT_MESSAGES_TOOL = {
  name: "get_assistant_messages",
  description:
    "Retourne les messages ORION déjà programmés (pending) et les 10 derniers affichés (shown). " +
    "APPELLE CET OUTIL AVANT push_assistant_message pour éviter les doublons et voir ce qui est déjà planifié. " +
    "Utilise-le aussi pour auditer, mettre à jour ou supprimer des messages existants.",
  inputSchema: { type: "object", properties: {} },
};

export const DELETE_ASSISTANT_MESSAGE_TOOL = {
  name: "delete_assistant_message",
  description:
    "Supprime ou expire un message ORION existant. " +
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
  description:
    "Ajoute une seule tâche à un projet Gantt existant sans réécrire tout le projet. " +
    "Utilise list_projects + get_project pour obtenir projectId et les phaseId. " +
    "Préférer cet outil à push_gantt quand on ajoute une tâche isolée.",
  inputSchema: {
    type: "object",
    required: ["projectId", "title", "startDate"],
    properties: {
      projectId:   { type: "string", description: "id du projet (list_projects)" },
      title:       { type: "string" },
      phaseId:     { type: "string", description: "id de la phase (get_project)" },
      groupLabel:  { type: "string" },
      startDate:   { type: "string", description: "YYYY-MM-DD" },
      endDate:     { type: "string", description: "YYYY-MM-DD" },
      isMilestone: { type: "boolean" },
      color:       { type: "string" },
      barLabel:    { type: "string" },
      status:      { type: "string", enum: ["pending", "done", "skipped"] },
      actions:     {
        type: "array",
        items: { type: "string" },
        description:
          "Sous-actions opérationnelles. " +
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

const UPDATE_TASK_TOOL = {
  name: "update_task",
  description:
    "Modifie les champs d'une tâche Gantt existante (titre, dates, actions, phase…). " +
    "Ne modifie que les champs fournis, laisse les autres inchangés. " +
    "Utilise list_projects + get_project pour obtenir projectId et taskId.",
  inputSchema: {
    type: "object",
    required: ["projectId", "taskId"],
    properties: {
      projectId:   { type: "string", description: "id du projet" },
      taskId:      { type: "string", description: "id de la tâche (get_project)" },
      title:       { type: "string" },
      phaseId:     { type: "string" },
      groupLabel:  { type: "string" },
      startDate:   { type: "string", description: "YYYY-MM-DD" },
      endDate:     { type: "string", description: "YYYY-MM-DD" },
      isMilestone: { type: "boolean" },
      color:       { type: "string" },
      barLabel:    { type: "string" },
      status:      { type: "string", enum: ["pending", "done", "skipped"] },
      actions:     { type: "array", items: { type: "string" }, description: "Remplace toutes les sous-actions" },
    },
  },
};

const MARK_ACTION_DONE_TOOL = {
  name: "mark_action_done",
  description:
    "Coche/décoche une sous-action individuelle d'une tâche Gantt sans toucher au reste. " +
    "Préfère cet outil à update_task quand l'utilisateur progresse sur une action précise. " +
    "Récupère projectId, taskId et actionId via get_project.",
  inputSchema: {
    type: "object",
    required: ["projectId", "taskId", "actionId", "done"],
    properties: {
      projectId: { type: "string", description: "id du projet (list_projects)" },
      taskId:    { type: "string", description: "id de la tâche (get_project)" },
      actionId:  { type: "string", description: "id de la sous-action (get_project)" },
      done:      { type: "boolean", description: "true pour marquer faite, false pour démarquer" },
    },
  },
};

export {
GET_USER_CONTEXT_TOOL,
UPDATE_ACTIVITY_GOAL_TOOL,
CREATE_ROUTINE_TOOL,
CREATE_ACTIVITY_TOOL,
CREATE_DOMAIN_TOOL,
PUSH_ASSISTANT_MESSAGE_TOOL,
DELETE_DOMAIN_TOOL,
GET_DOCUMENT_TEMPLATE_TOOL,
SAVE_DOCUMENT_TOOL,
GET_DOCUMENTS_TOOL,
DELETE_DOCUMENT_TOOL,
GET_ARCHIVES_TOOL,
RESTORE_ITEM_TOOL,
DELETE_ACTIVITY_TOOL,
UPDATE_PROJECT_TOOL,
UPDATE_TASK_STATUS_TOOL,
UPDATE_ACTIVITY_TOOL,
DELETE_ROUTINE_TOOL,
GET_DAY_BLOCKS_TOOL,
ARCHIVE_PROJECT_TOOL,
DELETE_PROJECT_TOOL,
LIST_PROJECTS_TOOL,
GET_PROJECT_TOOL,
PUSH_GANTT_MCP_TOOL,
ADD_TASK_TOOL,
UPDATE_TASK_TOOL,
MARK_ACTION_DONE_TOOL,
};

export const PLAN_DAY_TOOL = {
  name: "plan_day",
  description:
    "Agrège tout le contexte nécessaire pour planifier une journée : contexte utilisateur, " +
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
      date:            { type: "string", description: "YYYY-MM-DD (défaut: aujourd'hui)" },
      startHour:       { type: "number", description: "Heure de début (défaut: 7)" },
      endHour:         { type: "number", description: "Heure de fin (défaut: 20)" },
      syncToCalendar:  { type: "boolean", description: "Synchroniser dans Google Calendar après schedule_day (défaut: true)" },
    },
  },
};

export const PLAN_WEEK_TOOL = {
  name: "plan_week",
  description:
    "Agrège le contexte complet pour planifier une semaine de 5 jours ouvrés : contexte utilisateur, " +
    "programmes existants pour chaque jour, et tous les projets Gantt actifs. " +
    "Retourne le contexte consolidé + les instructions pour répartir les tâches sur la semaine " +
    "et synchroniser dans Google Calendar.\n\n" +
    "Workflow attendu : générer 5 programmes via schedule_day(), un par jour, " +
    "en répartissant les tâches Gantt (deadline proche = priorité, max ~6h/jour).",
  inputSchema: {
    type: "object",
    properties: {
      startDate:       { type: "string", description: "YYYY-MM-DD du lundi de début (défaut: lundi prochain, ou aujourd'hui si lundi)" },
      syncToCalendar:  { type: "boolean", description: "Synchroniser dans Google Calendar après schedule_day (défaut: true)" },
    },
  },
};

export const SYNC_CALENDAR_TOOL = {
  name: "sync_calendar",
  description:
    "Lit le programme Productivitwo d'une journée et retourne les instructions exactes " +
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

export const GET_DAY_SCHEDULE_TOOL = {
  name: "get_day_schedule",
  description:
    "Retourne le programme horaire d'une journée (généré par Claude ou ORION). " +
    "Appelle cet outil avant schedule_day pour vérifier si un programme existe déjà.",
  inputSchema: {
    type: "object",
    required: ["date"],
    properties: {
      date: { type: "string", description: "YYYY-MM-DD" },
    },
  },
};

export const SCHEDULE_DAY_TOOL = {
  name: "schedule_day",
  description:
    "Génère ou remplace le programme horaire d'une journée dans Productivitwo. " +
    "Chaque bloc est un créneau horaire avec une action concrète. " +
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
            startTime:   { type: "string", description: "Heure de début HH:mm (ex: '09:30')" },
            durationMin: { type: "integer", description: "Durée en minutes" },
            title:       { type: "string", description: "Intitulé court et actionnable (verbe d'action)" },
            category:    {
              type: "string",
              enum: ["project", "routine", "personal", "break"],
              description: "project = tâche Gantt · routine = activité trackée · personal = perso/maison · break = pause",
            },
            projectId:   { type: "string", description: "id du projet Gantt lié (si category=project, obtenu via list_projects)" },
            taskId:      { type: "string", description: "id de la tâche Gantt liée (obtenu via get_project)" },
            activityId:  { type: "string", description: "id de l'activité liée (si category=routine, obtenu via get_user_context)" },
          },
        },
      },
    },
  },
};
