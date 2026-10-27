"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MODE_KINDS = exports.MODE_LABELS = void 0;
exports.modeElanValue = modeElanValue;
exports.modeFromElan = modeFromElan;
exports.lastElanMark = lastElanMark;
exports.modeOf = modeOf;
exports.parseRestDomains = parseRestDomains;
exports.isResting = isResting;
exports.activeRests = activeRests;
exports.parseBudgetWindowDays = parseBudgetWindowDays;
exports.isTactical = isTactical;
exports.modeRules = modeRules;
exports.MODE_LABELS = { low: "Flemme", normal: "Normal", high: "En forme" };
exports.MODE_KINDS = ["low", "normal", "high"];
function modeElanValue(m) {
    return m === "low" ? 2 : m === "high" ? 4 : 3;
}
function modeFromElan(value) {
    return value <= 2 ? "low" : value >= 4 ? "high" : "normal";
}
/** Dernier pointage d'élan de la journée vécue [ymd], à [atIso] au plus tard. */
function lastElanMark(marks, ymd, atIso) {
    let best = null;
    for (const m of marks) {
        if (m.kind !== "elan" || m.ymd !== ymd)
            continue;
        if (atIso && m.at > atIso)
            continue;
        if (!best || m.at > best.at)
            best = m;
    }
    return best;
}
function modeOf(marks, ymd) {
    const m = lastElanMark(marks, ymd);
    return m ? { mode: modeFromElan(m.value), since: m.at } : { mode: "normal", since: null };
}
/** `data/meta.restDomains {domainId: "YYYY-MM-DD"}` — veille jusqu'à la date incluse. */
function parseRestDomains(raw) {
    if (!raw || typeof raw !== "object")
        return {};
    const out = {};
    for (const [k, v] of Object.entries(raw)) {
        if (typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v))
            out[k] = v;
    }
    return out;
}
function isResting(domainId, rest, todayYmd) {
    if (!domainId)
        return false;
    const until = rest[domainId];
    return !!until && until >= todayYmd;
}
function activeRests(rest, todayYmd) {
    return Object.fromEntries(Object.entries(rest).filter(([, until]) => until >= todayYmd));
}
function parseBudgetWindowDays(raw) {
    const v = typeof raw === "number" ? raw : Number(raw);
    return v === 14 ? 14 : 7;
}
/** Un objectif tactique (« coup ») : horizon "tactical", 3 à 10 jours. */
function isTactical(o) {
    return o.horizon === "tactical";
}
/** Règles de `plan_day` selon le mode (texte prêt pour le workflow). */
function modeRules(mode) {
    switch (mode) {
        case "low":
            return [
                `   → MODE FLEMME déclaré : blocs COURTS (≤ 30 min), routines et étapes simples d'abord, rien de nouveau ;`,
                `     une seule chose à la fois, pas de deep work, pas de relance sur ce qui n'est pas fait.`,
            ];
        case "high":
            return [
                `   → MODE EN FORME déclaré : UN bloc de deep work ≥ 90 min sur le coup en cours (sinon le projet le plus`,
                `     en retard), pas de dispersion ; les domaines en veille ne sont jamais programmés.`,
            ];
        default:
            return [`   → MODE NORMAL : rythme habituel ; les domaines en veille ne sont jamais programmés.`];
    }
}
//# sourceMappingURL=mode.js.map