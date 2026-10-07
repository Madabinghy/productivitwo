"use strict";
// « Planifier la prépa » (brief 2026-10, § 2.3) : pousser les actions de
// préparation d'une intervention dans les trous du programme. Règles
// utilisateur : prépa LA VEILLE AU SOIR de préférence (puis les soirs
// précédents, puis le reste des journées), IMPRESSION SUR PLACE collée au
// début du créneau (pas le matin à la maison), respect des blocs existants
// (rendez-vous Google Agenda compris) et de la journée active. Logique pure ;
// l'écriture passe par schedule_day(mode:"fill") dans execute.ts.
Object.defineProperty(exports, "__esModule", { value: true });
exports.isPrintAction = void 0;
exports.addDays = addDays;
exports.planPrep = planPrep;
const schedule_dedupe_1 = require("./schedule_dedupe");
const isPrintAction = (a) => {
    var _a;
    return ((_a = a.contexts) !== null && _a !== void 0 ? _a : []).some((c) => c.toLowerCase() === "@impression") ||
        a.title.trim().toLowerCase().startsWith("imprimer");
};
exports.isPrintAction = isPrintAction;
const fromMin = (m) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
function addDays(ymd, n) {
    const d = new Date(`${ymd}T00:00:00Z`);
    d.setUTCDate(d.getUTCDate() + n);
    return d.toISOString().slice(0, 10);
}
const daysBetween = (a, b) => Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86400000);
function busyOf(blocks) {
    return blocks
        .filter(schedule_dedupe_1.isOccupying)
        .map((b) => { var _a; return ({ start: (0, schedule_dedupe_1.toMin)(b.startTime), end: (0, schedule_dedupe_1.toMin)(b.startTime) + Number((_a = b.durationMin) !== null && _a !== void 0 ? _a : 0) }); })
        .filter((b) => b.end > b.start);
}
const fits = (busy, start, dur) => !busy.some((b) => start < b.end && b.start < start + dur);
/** Premier début libre ≥ from dans [from, to − dur], par pas de 15 min. */
function firstFree(busy, from, to, dur, step = 15) {
    const base = Math.ceil(from / step) * step;
    for (let s = base; s + dur <= to; s += step) {
        if (fits(busy, s, dur))
            return s;
    }
    return null;
}
/** Dernier début libre ≤ (to − dur) en remontant depuis to, par pas de 15 min. */
function lastFree(busy, from, to, dur, step = 15) {
    const top = Math.floor((to - dur) / step) * step;
    for (let s = top; s >= from; s -= step) {
        if (fits(busy, s, dur))
            return s;
    }
    return null;
}
function planPrep(input) {
    var _a, _b, _c;
    const { intervention, window, today, nowMin } = input;
    const evening = (_a = input.eveningFromMin) !== null && _a !== void 0 ? _a : 18 * 60;
    const lead = (_b = input.printLeadMin) !== null && _b !== void 0 ? _b : 15;
    const defMin = (_c = input.defaultActionMin) !== null && _c !== void 0 ? _c : 30;
    const D = intervention.date;
    const earliest = input.earliest && input.earliest > today ? input.earliest : today;
    const firstDay = addDays(D, -7) > earliest ? addDays(D, -7) : earliest;
    // Occupation mutable par jour (on y ajoute nos propres placements).
    const busy = new Map();
    const busyFor = (date) => {
        var _a;
        if (!busy.has(date))
            busy.set(date, busyOf((_a = input.existing[date]) !== null && _a !== void 0 ? _a : []));
        return busy.get(date);
    };
    const lowerBound = (date) => (date === today ? Math.max(window.startMin, nowMin) : window.startMin);
    const placements = [];
    const unplaced = [];
    const dur = (a) => { var _a; return Math.max(5, (_a = a.estimatedMin) !== null && _a !== void 0 ? _a : defMin); };
    // 1) Impression : sur place, collée au début de la séance.
    const prints = input.actions.filter(exports.isPrintAction);
    if (prints.length) {
        const total = Math.max(lead, prints.reduce((n, a) => { var _a; return n + ((_a = a.estimatedMin) !== null && _a !== void 0 ? _a : 10); }, 0));
        const sessionStart = (0, schedule_dedupe_1.toMin)(intervention.startTime);
        const b = busyFor(D);
        let start = null;
        // Le plus tard possible avant la séance, en reculant si un bloc gêne.
        for (let s = sessionStart - total; s >= window.startMin; s -= 5) {
            if (fits(b, s, total) && !(D === today && s < nowMin)) {
                start = s;
                break;
            }
        }
        if (start !== null) {
            const first = prints[0];
            placements.push({
                date: D, startTime: fromMin(start), durationMin: total, actionId: first.id,
                title: prints.length > 1 ? `🖨 Imprimer sur place — ${intervention.title}` : `🖨 ${first.title}`,
                why: "impression sur place",
            });
            b.push({ start, end: start + total });
        }
        else {
            for (const a of prints)
                unplaced.push({ actionId: a.id, title: a.title, durationMin: dur(a), alternatives: [] });
        }
    }
    // 2) Les autres actions : veille au soir, puis soirs précédents, puis journées.
    const others = input.actions.filter((a) => !(0, exports.isPrintAction)(a));
    const days = [];
    for (let d = addDays(D, -1); d >= firstDay; d = addDays(d, -1))
        days.push(d);
    // Jour J avant la séance (matin) en dernier recours.
    const sessionStart = (0, schedule_dedupe_1.toMin)(intervention.startTime);
    const passes = [
        {
            name: (d) => (d === addDays(D, -1) ? "veille au soir" : `soir J-${daysBetween(d, D)}`),
            range: () => [Math.max(evening, window.startMin), window.endMin],
            dates: days,
            fromEnd: false,
        },
        {
            name: (d) => `journée J-${daysBetween(d, D)}`,
            range: () => [window.startMin, Math.max(evening, window.startMin)],
            dates: days,
            fromEnd: true, // le plus tard possible dans la journée
        },
        {
            name: () => "le jour même, avant la séance",
            range: () => [window.startMin, Math.min(sessionStart - lead, window.endMin)],
            dates: [D],
            fromEnd: true,
        },
    ];
    for (const a of others) {
        const need = dur(a);
        let placed = false;
        for (const pass of passes) {
            for (const date of pass.dates) {
                if (date < earliest)
                    continue;
                const [lo0, hi] = pass.range(date);
                const lo = Math.max(lo0, lowerBound(date));
                if (hi - lo < need)
                    continue;
                const b = busyFor(date);
                const start = pass.fromEnd ? lastFree(b, lo, hi, need) : firstFree(b, lo, hi, need);
                if (start === null)
                    continue;
                placements.push({ date, startTime: fromMin(start), durationMin: need, actionId: a.id, title: a.title, why: pass.name(date) });
                b.push({ start, end: start + need });
                placed = true;
                break;
            }
            if (placed)
                break;
        }
        if (!placed) {
            // Repli : les deux premiers trous de la fenêtre, tous jours confondus.
            const alts = [];
            for (const date of [...days].reverse().concat(D)) {
                if (alts.length >= 2 || date < earliest)
                    continue;
                const b = busyFor(date);
                const hi = date === D ? Math.min(sessionStart - lead, window.endMin) : window.endMin;
                const s = firstFree(b, lowerBound(date), hi, need);
                if (s !== null)
                    alts.push({ date, startTime: fromMin(s) });
            }
            unplaced.push({ actionId: a.id, title: a.title, durationMin: need, alternatives: alts });
        }
    }
    placements.sort((x, y) => (x.date + x.startTime).localeCompare(y.date + y.startTime));
    return { placements, unplaced };
}
//# sourceMappingURL=prep_planner.js.map