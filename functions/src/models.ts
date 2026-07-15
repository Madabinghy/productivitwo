export const MODELS = {
  HAIKU:  "claude-haiku-4-5-20251001",
  SONNET: "claude-sonnet-4-6",
  OPUS:   "claude-opus-4-8",
} as const;

type TaskType =
  | "orion_cycle"
  | "structure_project"
  | "structure_preview"
  | "plan_day"
  | "plan_proposal"
  | "define_domain"
  | "generate_artifact"
  | "weekly_report"
  | "plan_week"
  | "sync_calendar"
  | "chat"
  | "generate_document"
  | "analyze_week"
  | "coaching"
  | "onboarding"
  | "inbox_routing"
  | "restructure_project";

const MODEL_ROUTING: Record<TaskType, string> = {
  orion_cycle:       MODELS.HAIKU, // aligné sur le modèle réellement utilisé (orion.ts)
  structure_project: MODELS.OPUS,  // moment "wow" (5/j max, ~2k tokens) — la qualité du plan prime
  structure_preview: MODELS.HAIKU, // mindmap live onboarding : appels fréquents, JSON incrémental
  plan_day:          MODELS.HAIKU,
  plan_proposal:     MODELS.HAIKU, // écran de planification : 1 appel JSON / ouverture (cycle quotidien)
  define_domain:     MODELS.OPUS,  // session de définition — moment fondateur, faible volume plafonné (pattern structure_project)
  generate_artifact: MODELS.HAIKU, // plan/menu : 1 appel JSON par génération (classe quotidienne)
  weekly_report:     MODELS.HAIKU, // rapport hebdo : agrégats déterministes + 1 appel narratif
  plan_week:         MODELS.HAIKU,
  sync_calendar:     MODELS.HAIKU,
  chat:              MODELS.SONNET,
  generate_document: MODELS.SONNET,
  analyze_week:      MODELS.SONNET,
  coaching:          MODELS.SONNET,
  onboarding:        MODELS.SONNET,
  inbox_routing:     MODELS.SONNET, // routage/agrégation idées→projets (jugement sémantique)
  restructure_project: MODELS.HAIKU, // Direction C.3 : diff de restructuration JSON, tâche automatique
};

export function getModel(taskType: TaskType): string {
  return MODEL_ROUTING[taskType] ?? MODELS.HAIKU;
}

interface TokenUsage {
  input_tokens?: number;
  output_tokens?: number;
  cache_creation_input_tokens?: number;
  cache_read_input_tokens?: number;
}

export function logTokenUsage(taskType: string, model: string, usage: TokenUsage): void {
  const input  = usage?.input_tokens ?? 0;
  const output = usage?.output_tokens ?? 0;
  const cached = usage?.cache_read_input_tokens ?? 0;
  const created = usage?.cache_creation_input_tokens ?? 0;
  console.log(JSON.stringify({
    event: "token_usage",
    taskType,
    model,
    inputTokens: input,
    outputTokens: output,
    cacheReadTokens: cached,
    cacheCreationTokens: created,
    totalTokens: input + output,
  }));
}
