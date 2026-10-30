"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.REST_PERIODS_KEPT = void 0;
exports.parseRestPeriods = parseRestPeriods;
exports.withRestSet = withRestSet;
exports.withRestLifted = withRestLifted;
exports.REST_PERIODS_KEPT = 60;
const YMD = /^\d{4}-\d{2}-\d{2}$/;
function shift(ymd, days) {
    const d = new Date(`${ymd}T12:00:00Z`);
    d.setUTCDate(d.getUTCDate() + days);
    return d.toISOString().slice(0, 10);
}
const covers = (p, ymd) => p.from <= ymd && p.to >= ymd;
function parseRestPeriods(raw) {
    if (!Array.isArray(raw))
        return [];
    const out = [];
    for (const x of raw) {
        if (!x || typeof x !== "object")
            continue;
        const { domainId, from, to } = x;
        if (typeof domainId !== "string" || typeof from !== "string" || typeof to !== "string")
            continue;
        if (!YMD.test(from) || !YMD.test(to) || to < from)
            continue;
        out.push({ domainId, from, to });
    }
    return out;
}
const capped = (l) => (l.length > exports.REST_PERIODS_KEPT ? l.slice(l.length - exports.REST_PERIODS_KEPT) : l);
/** Met le domaine en veille d'aujourd'hui à `until` : prolonge la période en cours, sinon en ouvre une. */
function withRestSet(periods, domainId, todayYmd, untilYmd) {
    if (untilYmd < todayYmd)
        return periods;
    let found = false;
    const next = periods.map((p) => {
        if (!found && p.domainId === domainId && covers(p, todayYmd)) {
            found = true;
            return { domainId, from: p.from, to: untilYmd };
        }
        return p;
    });
    if (!found)
        next.push({ domainId, from: todayYmd, to: untilYmd });
    return capped(next);
}
/** Lève la veille aujourd'hui : la période en cours s'arrête hier, ou disparaît si elle commençait aujourd'hui. */
function withRestLifted(periods, domainId, todayYmd) {
    const yesterday = shift(todayYmd, -1);
    const out = [];
    for (const p of periods) {
        if (p.domainId === domainId && covers(p, todayYmd)) {
            if (p.from <= yesterday)
                out.push({ domainId, from: p.from, to: yesterday });
        }
        else {
            out.push(p);
        }
    }
    return out;
}
//# sourceMappingURL=rest_periods.js.map