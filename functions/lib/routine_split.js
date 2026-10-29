"use strict";
/**
 * Routines réparties sur plusieurs moments (2026-10-30) — miroir serveur de
 * `splitMomentsOf` / `momentShareOf` (lib/utils/routine_moments.dart, **garder
 * alignés**). `Activity.splitMoments` = moments horaires (morning · midday ·
 * afternoon · evening), deux ou plus ; la cible du jour se partage entre eux
 * (cible ÷ moments, le surplus aux premiers, un moment sans part ignoré).
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.SPLIT_MOMENTS = void 0;
exports.normalizeSplitMoments = normalizeSplitMoments;
exports.splitShares = splitShares;
exports.splitLabel = splitLabel;
exports.SPLIT_MOMENTS = ["morning", "midday", "afternoon", "evening"];
const LABEL = {
    morning: "le matin",
    midday: "le midi",
    afternoon: "l'après-midi",
    evening: "le soir",
};
const ALIASES = {
    morning: "morning", matin: "morning",
    midday: "midday", midi: "midday", dejeuner: "midday", "déjeuner": "midday",
    afternoon: "afternoon", "apres-midi": "afternoon", "après-midi": "afternoon", apresmidi: "afternoon", aprem: "afternoon",
    evening: "evening", soir: "evening", diner: "evening", "dîner": "evening",
};
/**
 * Normalise une liste de moments (clés ou libellés français) dans l'ordre de
 * la journée. Moins de deux moments valides = [] (routine non répartie) ;
 * `unknown` liste ce qui n'a pas été reconnu.
 */
function normalizeSplitMoments(input) {
    const list = Array.isArray(input) ? input : typeof input === "string" ? input.split(/[,+&]|\bet\b/) : [];
    const set = new Set();
    const unknown = [];
    for (const raw of list) {
        const k = String(raw !== null && raw !== void 0 ? raw : "").replace(/[\[\]"']/g, "").trim().toLowerCase();
        if (!k)
            continue;
        const key = ALIASES[k];
        if (key)
            set.add(key);
        else
            unknown.push(String(raw).trim());
    }
    const ordered = exports.SPLIT_MOMENTS.filter((m) => set.has(m));
    return { moments: ordered.length >= 2 ? [...ordered] : [], unknown };
}
/** Parts de la cible du jour par moment : [{moment, share}], sans part nulle. */
function splitShares(target, moments) {
    const n = Math.max(0, Math.floor(target));
    if (moments.length < 2 || n <= 0)
        return [];
    const base = Math.floor(n / moments.length), extra = n % moments.length;
    return moments
        .map((m, i) => ({ moment: m, share: base + (i < extra ? 1 : 0) }))
        .filter((p) => p.share > 0);
}
/** « 10 le matin · 10 le soir » (vide si non répartie). */
function splitLabel(target, moments) {
    return splitShares(target, moments).map((p) => { var _a; return `${p.share} ${(_a = LABEL[p.moment]) !== null && _a !== void 0 ? _a : p.moment}`; }).join(" · ");
}
//# sourceMappingURL=routine_split.js.map