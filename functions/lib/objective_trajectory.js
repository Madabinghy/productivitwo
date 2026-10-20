"use strict";
// ── Trajectoire d'un objectif (moyens cumulés + métrique vs attendu) ─────────
// Même sémantique que lib/utils/objective_trajectory.dart (garder alignés) :
//  • MOYENS   : minutes cumulées sur les activités engagées depuis le début de
//               l'objectif vs Σ weeklyMin × semaines écoulées (linéaire).
//  • RÉSULTAT : dernier relevé de la métrique vs droite startValue → targetValue
//               entre startDate et endDate (linéaire).
// Début = startDate, sinon createdAt. Statut : ≥ 110 % = ahead, ≥ 85 % = onTrack,
// sinon behind. Fonctions pures (dates en YYYY-MM-DD, Europe/Paris en amont).
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseMetric = parseMetric;
exports.parseReadings = parseReadings;
exports.latestReading = latestReading;
exports.upsertReading = upsertReading;
exports.expectedMetricAt = expectedMetricAt;
exports.expectedMinutesAt = expectedMinutesAt;
exports.objectiveStartYmd = objectiveStartYmd;
exports.isReadingDue = isReadingDue;
exports.summarizeTrajectory = summarizeTrajectory;
exports.formatReadingsDue = formatReadingsDue;
const DAY = 86400000;
function dayMs(ymd) {
    return new Date(`${ymd}T12:00:00Z`).getTime();
}
function daysBetween(fromYmd, toYmd) {
    return Math.round((dayMs(toYmd) - dayMs(fromYmd)) / DAY);
}
function parseMetric(v) {
    var _a;
    if (!v || typeof v !== "object")
        return null;
    const m = v;
    const target = Number(m.targetValue);
    if (!Number.isFinite(target))
        return null;
    const start = Number(m.startValue);
    return {
        label: String((_a = m.label) !== null && _a !== void 0 ? _a : ""),
        unit: typeof m.unit === "string" ? m.unit : null,
        startValue: Number.isFinite(start) ? start : 0,
        targetValue: target,
    };
}
function parseReadings(v) {
    var _a;
    if (!Array.isArray(v))
        return [];
    const out = [];
    for (const r of v) {
        if (!r || typeof r !== "object")
            continue;
        const value = Number(r.value);
        const date = String((_a = r.date) !== null && _a !== void 0 ? _a : "");
        if (!Number.isFinite(value) || !/^\d{4}-\d{2}-\d{2}$/.test(date))
            continue;
        out.push({
            id: typeof r.id === "string" ? r.id : undefined,
            date,
            value,
            note: typeof r.note === "string" ? r.note : null,
            createdAt: typeof r.createdAt === "string" ? r.createdAt : null,
        });
    }
    return out.sort((a, b) => a.date.localeCompare(b.date));
}
function latestReading(readings) {
    var _a, _b;
    let best = null;
    for (const r of readings) {
        if (!best || r.date > best.date ||
            (r.date === best.date && String((_a = r.createdAt) !== null && _a !== void 0 ? _a : "") > String((_b = best.createdAt) !== null && _b !== void 0 ? _b : ""))) {
            best = r;
        }
    }
    return best;
}
/** Ajoute ou remplace le relevé du jour (un seul par jour). */
function upsertReading(readings, r) {
    return [...readings.filter((x) => x.date !== r.date), r].sort((a, b) => a.date.localeCompare(b.date));
}
function pct(start, target, v) {
    const span = target - start;
    if (span === 0)
        return v === target ? 1 : 0;
    return Math.min(1, Math.max(0, (v - start) / span));
}
function statusOf(ratio) {
    if (!Number.isFinite(ratio))
        return "unknown";
    if (ratio >= 1.1)
        return "ahead";
    if (ratio >= 0.85)
        return "onTrack";
    return "behind";
}
function expectedMetricAt(m, start, end, at) {
    if (!end || end <= start)
        return m.startValue;
    const t = Math.min(1, Math.max(0, daysBetween(start, at) / daysBetween(start, end)));
    return m.startValue + (m.targetValue - m.startValue) * t;
}
function expectedMinutesAt(weeklyMinTotal, start, end, at) {
    const until = end && at > end ? end : at;
    const days = daysBetween(start, until);
    if (days <= 0)
        return 0;
    return Math.round(weeklyMinTotal * (days / 7));
}
/** Début de l'objectif en YYYY-MM-DD : startDate, sinon createdAt, sinon aujourd'hui. */
function objectiveStartYmd(o, todayStr, toYmd) {
    var _a;
    if (typeof o.startDate === "string" && /^\d{4}-\d{2}-\d{2}/.test(o.startDate))
        return o.startDate.slice(0, 10);
    return (_a = toYmd(o.createdAt)) !== null && _a !== void 0 ? _a : todayStr;
}
function isReadingDue(o, startYmd, todayStr) {
    var _a;
    if (!parseMetric(o.metric) || String((_a = o.status) !== null && _a !== void 0 ? _a : "active") !== "active")
        return false;
    const every = Math.max(1, Math.round(Number(o.checkInEvery) || 7));
    const last = latestReading(parseReadings(o.readings));
    return daysBetween(last ? last.date : startYmd, todayStr) >= every;
}
/**
 * Trajectoire complète. `minutesByActivitySinceStart` = minutes réellement
 * passées depuis startYmd, par activité (calculées par l'appelant depuis les
 * sessions vivantes).
 */
function summarizeTrajectory(o, startYmd, minutesByActivitySinceStart, todayStr) {
    var _a, _b;
    const end = typeof o.endDate === "string" && o.endDate ? o.endDate.slice(0, 10) : null;
    const timePct = end && end > startYmd
        ? Math.round(Math.min(1, Math.max(0, daysBetween(startYmd, todayStr) / daysBetween(startYmd, end))) * 100)
        : null;
    const commitments = Array.isArray(o.timeCommitments) ? o.timeCommitments : [];
    let perWeek = 0;
    let done = 0;
    for (const c of commitments) {
        perWeek += Math.max(0, Math.round(Number(c.weeklyMin) || 0));
        done += minutesByActivitySinceStart.get(String((_a = c.activityId) !== null && _a !== void 0 ? _a : "")) || 0;
    }
    const expected = expectedMinutesAt(perWeek, startYmd, end, todayStr);
    const total = end ? expectedMinutesAt(perWeek, startYmd, end, end) : 0;
    const means = {
        doneMin: done,
        expectedMin: expected,
        totalMin: total,
        status: (commitments.length === 0 ? "unknown" : expected <= 0 ? "onTrack" : statusOf(done / expected)),
    };
    const metric = parseMetric(o.metric);
    const readings = parseReadings(o.readings);
    const last = latestReading(readings);
    let result = null;
    if (metric) {
        const exp = expectedMetricAt(metric, startYmd, end, todayStr);
        let status = "unknown";
        if (last) {
            const expPct = pct(metric.startValue, metric.targetValue, exp);
            const realPct = pct(metric.startValue, metric.targetValue, last.value);
            status = expPct <= 0 ? "onTrack" : statusOf(realPct / expPct);
        }
        const raw = last ? last.value - exp : 0;
        result = {
            label: metric.label,
            unit: (_b = metric.unit) !== null && _b !== void 0 ? _b : null,
            startValue: metric.startValue,
            targetValue: metric.targetValue,
            latestValue: last ? last.value : null,
            latestDate: last ? last.date : null,
            expectedValue: Math.round(exp * 100) / 100,
            delta: Math.round((metric.targetValue < metric.startValue ? -raw : raw) * 100) / 100,
            status,
        };
    }
    return {
        start: startYmd,
        end,
        timePct,
        means,
        result,
        // Le départ compte comme première saisie : sans relevé, depuis le début.
        daysSinceReading: last ? daysBetween(last.date, todayStr) : metric ? daysBetween(startYmd, todayStr) : null,
        readingDue: isReadingDue(o, startYmd, todayStr),
        checkInEvery: Math.max(1, Math.round(Number(o.checkInEvery) || 7)),
    };
}
/** Ligne lisible pour weekly_review / plan_week : relevés dus. */
function formatReadingsDue(rows) {
    if (!rows.length)
        return "";
    const lines = rows.map((r) => {
        const since = r.daysSince == null ? "aucun relevé depuis le début" : `dernier relevé il y a ${r.daysSince} j`;
        return `• « ${r.title} » — ${r.label}${r.unit ? ` (${r.unit})` : ""} : ${since} (attendu tous les ${r.every} j)` +
            `\n    → demande la valeur du jour puis log_objective_reading(objectiveId:"${r.id}", value)`;
    });
    return [`── Relevés d'objectif à faire (${rows.length}) ──`, ...lines].join("\n");
}
//# sourceMappingURL=objective_trajectory.js.map