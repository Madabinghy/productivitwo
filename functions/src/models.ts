export const MODELS = {
  HAIKU:  "claude-haiku-4-5-20251001",
  SONNET: "claude-sonnet-4-6",
} as const;

type TaskType =
  | "orion_cycle"
  | "structure_project"
  | "plan_day"
  | "plan_week"
  | "sync_calendar"
  | "chat"
  | "generate_document"
  | "analyze_week"
  | "coaching"
  | "onboarding";

const MODEL_ROUTING: Record<TaskType, string> = {
  orion_cycle:       MODELS.HAIKU,
  structure_project: MODELS.HAIKU,
  plan_day:          MODELS.HAIKU,
  plan_week:         MODELS.HAIKU,
  sync_calendar:     MODELS.HAIKU,
  chat:              MODELS.SONNET,
  generate_document: MODELS.SONNET,
  analyze_week:      MODELS.SONNET,
  coaching:          MODELS.SONNET,
  onboarding:        MODELS.SONNET,
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
