export interface ProjectPhase {
  id?: string;
  label: string;
  color?: string;
  startDate: string;
  endDate: string;
}

export interface TaskActionPayload {
  id?: string;
  title: string;
  done?: boolean;
  doneAt?: string | null;
  createdAt?: string;
  linkedActivityId?: string | null;
  context?: string | null; // contexte GTD (@maison, @bureau…)
}

export interface ProjectTask {
  id?: string;
  title: string;
  phaseId?: string;
  groupLabel?: string;
  startDate: string;
  endDate?: string;
  isMilestone?: boolean;
  color?: string;
  barLabel?: string;
  status?: "pending" | "done" | "skipped";
  actions?: Array<string | TaskActionPayload>;
}

export interface ProjectPayload {
  id?: string;
  title: string;
  description?: string;
  domainId?: string;
  startDate: string;
  endDate?: string;
  phases?: ProjectPhase[];
  tasks?: ProjectTask[];
}

export interface StrategicObjectivePayload {
  id?: string;
  title: string;
  description?: string;
  domainId?: string;
  kpiTarget?: string;
  horizonLabel?: string;
  startDate?: string;
  endDate?: string;
  status?: string; // active | done | archived (archived = suppression soft)
  // Moyens opérationnels : engagements de temps hebdo sur des activités `time`
  // et routines suivies (leur cible vit sur habitFreq/habitTarget).
  timeCommitments?: Array<{ activityId: string; weeklyMin: number }>;
  routineCommitments?: Array<{ activityId: string }>;
}

export interface PushGanttBody {
  uid: string;
  project: ProjectPayload;
  strategicObjective?: StrategicObjectivePayload;
}

// ── Programme horaire journalier (users/{uid}/daily_schedules/{YYYY-MM-DD}) ──

export interface ScheduleBlockPayload {
  id?: string;
  startTime: string; // "HH:mm"
  durationMin: number;
  title: string;
  category: string; // project | routine | personal | break
  projectId?: string | null;
  taskId?: string | null;
  activityId?: string | null;
  actionId?: string | null;
  status?: string; // pending | done | skipped | deleted
  // Préparation la veille (kind:"prep") — cf. add_prep_block.
  // "bilan" = bilan d'essai (renégociation 12c). "session" = session de
  // définition d'un domaine (onboarding 18b, domainId = domaine ciblé).
  // prep/bilan/session survivent au remplacement par schedule_day.
  kind?: string; // "normal" (défaut) | "prep" | "bilan" | "session"
  prepForDate?: string | null;
  prepForBlockId?: string | null;
  domainId?: string | null;
  // Check-in du soir : pourquoi l'engagement a sauté (fait tracké).
  // "imprevu" | "energie" | "sous_estime" | "evite" | texte libre.
  skipReason?: string | null;
  // Raison donnée AU MOMENT du report (skipReason "reporte" garde son sens
  // « demain il passe en premier ») : "pas_sur_place" | … | texte libre.
  reportReason?: string | null;
}

// ── Domaine (users/{uid}/domains/{id}) — intention & minimum vital ───────────
// Extension de la collection domains EXISTANTE (name/colorValue/goalMinDay…) :
// champs optionnels écrits par la session de définition Orion.

export interface VitalMinimumPayload {
  label: string;
  metric?: string; // sessions_week | sessions_day | hours_week | hours_day | minutes_* — omettre si non mesurable
  target?: number;
  period?: "week" | "day";
}

export interface DomainDefinitionPayload {
  domainId?: string;
  name: string;
  intention?: string; // LES MOTS DU USER — jamais reformulée
  vitalMinimum?: VitalMinimumPayload[];
  modalities?: string[]; // stockées en [{label}] côté Firestore
  wantedArtifacts?: string[];
  // Session « sans données » (tour 20) : décider aussi ce qu'on ne mesure pas.
  tracking?: "timed" | "declared"; // declared = vital demandé au rapport, pas de chrono/blocs/score
  protectedSlots?: string[]; // territoire défendu — codes "{mon..sun}_{morning|afternoon|evening|day}"
  finalize?: boolean; // true → definitionStatus:"active" + definedAt
}
// Renégociation (écrite par l'app, lue par proposeDayPlan sur le doc brut) :
// renegotiatedAt (ISO), history [{date, field, from, to, reason}],
// suspendedUntil ("YYYY-MM-DD" — suspension assumée : rien ne se pose dessus).

// ── Artefacts structurés (users/{uid}/artifacts/{id}) ────────────────────────
// Un artefact = une SOURCE DE BLOCS (entries datées instanciables par la
// proposition), pas un document à lire. ⟳ régénère la suite, jamais le passé.

export interface ArtifactEntryPayload {
  date?: string; // "YYYY-MM-DD" (exclusif avec weekday)
  weekday?: string; // "mon".."sun" — motif hebdo (menu)
  time: string; // "HH:mm"
  title: string;
  durationMin: number;
  detail?: string;
  portions?: number;
  optional?: boolean;
}

export interface ArtifactPayload {
  id?: string;
  kind: "training_plan" | "weekly_menu";
  domainId: string;
  params: Record<string, unknown>; // les 3-4 paramètres confirmés au cadrage
  entries: ArtifactEntryPayload[];
  shoppingList?: Array<{ label: string; qty?: string }>; // menu uniquement
  offSlots?: string[]; // « on ne touche pas » — contrainte dure
}

export interface DailySchedulePayload {
  date: string;
  generatedBy?: string;
  blocks: ScheduleBlockPayload[];
  // Check-in du soir : cause globale quand 3+ blocs ont sauté.
  // "imprevu_global" | "energie" | "irrealiste" | texte libre.
  dayReason?: string | null;
  // Planification le jour même après 5h (rattrapage du matin).
  plannedAt?: string | null;
  plannedSameDay?: boolean;
}
