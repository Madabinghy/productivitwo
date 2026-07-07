"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MODELS = void 0;
exports.getModel = getModel;
exports.logTokenUsage = logTokenUsage;
exports.MODELS = {
    HAIKU: "claude-haiku-4-5-20251001",
    SONNET: "claude-sonnet-4-6",
    OPUS: "claude-opus-4-8",
};
const MODEL_ROUTING = {
    orion_cycle: exports.MODELS.HAIKU, // aligné sur le modèle réellement utilisé (orion.ts)
    structure_project: exports.MODELS.OPUS, // moment "wow" (5/j max, ~2k tokens) — la qualité du plan prime
    structure_preview: exports.MODELS.HAIKU, // mindmap live onboarding : appels fréquents, JSON incrémental
    plan_day: exports.MODELS.HAIKU,
    plan_week: exports.MODELS.HAIKU,
    sync_calendar: exports.MODELS.HAIKU,
    chat: exports.MODELS.SONNET,
    generate_document: exports.MODELS.SONNET,
    analyze_week: exports.MODELS.SONNET,
    coaching: exports.MODELS.SONNET,
    onboarding: exports.MODELS.SONNET,
    inbox_routing: exports.MODELS.SONNET, // routage/agrégation idées→projets (jugement sémantique)
};
function getModel(taskType) {
    var _a;
    return (_a = MODEL_ROUTING[taskType]) !== null && _a !== void 0 ? _a : exports.MODELS.HAIKU;
}
function logTokenUsage(taskType, model, usage) {
    var _a, _b, _c, _d;
    const input = (_a = usage === null || usage === void 0 ? void 0 : usage.input_tokens) !== null && _a !== void 0 ? _a : 0;
    const output = (_b = usage === null || usage === void 0 ? void 0 : usage.output_tokens) !== null && _b !== void 0 ? _b : 0;
    const cached = (_c = usage === null || usage === void 0 ? void 0 : usage.cache_read_input_tokens) !== null && _c !== void 0 ? _c : 0;
    const created = (_d = usage === null || usage === void 0 ? void 0 : usage.cache_creation_input_tokens) !== null && _d !== void 0 ? _d : 0;
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
//# sourceMappingURL=models.js.map