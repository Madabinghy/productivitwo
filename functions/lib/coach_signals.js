"use strict";
// Signaux de la semaine pour le coach (maquette validée 2026-11-01 « Cockpit
// coach »). Calculés par l'APP (`lib/utils/coach_signals.dart`) et déposés
// dans `data/badges.signals` ; le serveur ne recalcule rien, il FILTRE selon
// le consentement du coaché :
//   - `games` (parole tenue, Montre suisse, Métronome, posé la veille) : opt-in ;
//     une activité d'un domaine non partagé n'apparaît jamais, même nommée ;
//   - `sleep` : opt-in à part (c'est intime).
// Puis il en tire des lignes de rapport et des points « À aborder en séance »,
// par règles fixes (seuils, comparaisons), jamais par IA.
Object.defineProperty(exports, "__esModule", { value: true });
exports.signalsForCoach = signalsForCoach;
exports.fmtMin = fmtMin;
exports.clockOf = clockOf;
exports.signalTiles = signalTiles;
exports.signalReportLines = signalReportLines;
exports.talkingPoints = talkingPoints;
exports.watchFlag = watchFlag;
const boolDays = (v) => Array.isArray(v) ? v.map((x) => (x === true ? true : x === false ? false : null)) : [];
const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : null);
/** Ce que le coach a le droit de voir, d'après le consentement. null = rien. */
function signalsForCoach(raw, sharing, sharedDomains) {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    if (!raw || typeof raw !== "object")
        return null;
    const r = raw;
    const days = Array.isArray(r.days) ? r.days.map(String) : [];
    if (days.length === 0)
        return null;
    const out = { days };
    if (sharing.games === true) {
        const w = ((_a = r.watch) !== null && _a !== void 0 ? _a : {});
        const blockers = Array.isArray(w.blockers) ? w.blockers : [];
        out.watch = {
            days: boolDays(w.days),
            blockers: blockers
                .filter((b) => typeof b.domainId === "string" && sharedDomains.has(b.domainId))
                .map((b) => { var _a, _b, _c; return ({ name: String((_a = b.name) !== null && _a !== void 0 ? _a : ""), lostDays: (_b = num(b.lostDays)) !== null && _b !== void 0 ? _b : 0, goalMin: (_c = num(b.goalMin)) !== null && _c !== void 0 ? _c : 0 }); }),
        };
        out.metronome = { days: boolDays(((_b = r.metronome) !== null && _b !== void 0 ? _b : {}).days) };
        out.parole = { days: boolDays(((_c = r.parole) !== null && _c !== void 0 ? _c : {}).days) };
        const capDays = ((_d = r.cap) !== null && _d !== void 0 ? _d : {}).days;
        out.cap = { days: Array.isArray(capDays) ? capDays.map((x) => (x === "held" || x === "posed" ? x : null)) : [] };
    }
    if (sharing.sleep === true && r.sleep && typeof r.sleep === "object") {
        const s = r.sleep;
        const imp = s.impact;
        out.sleep = Object.assign({ nights: Array.isArray(s.nights) ? s.nights.map(num) : [], nightsBefore: Array.isArray(s.nightsBefore) ? s.nightsBefore.map(num) : [], targetMin: (_e = num(s.targetMin)) !== null && _e !== void 0 ? _e : 450, avgMin: num(s.avgMin), debtMin: (_f = num(s.debtMin)) !== null && _f !== void 0 ? _f : 0, avgBed: num(s.avgBed), spreadMin: num(s.spreadMin), plannedBed: num(s.plannedBed) }, (imp && num(imp.longLowPct) != null && num(imp.shortLowPct) != null
            ? { impact: { longLowPct: num(imp.longLowPct), shortLowPct: num(imp.shortLowPct), longDays: (_g = num(imp.longDays)) !== null && _g !== void 0 ? _g : 0, shortDays: (_h = num(imp.shortDays)) !== null && _h !== void 0 ? _h : 0 } }
            : {}));
    }
    return out.watch || out.sleep ? out : null;
}
/** « 6 h 10 » / « 45 min ». */
function fmtMin(m) {
    if (m <= 0)
        return "0 min";
    return m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, "0")}`;
}
/** Horloge autour de minuit (−20 = 23:40) → « 23:40 ». */
function clockOf(m) {
    const v = ((m % 1440) + 1440) % 1440;
    return `${String(Math.floor(v / 60)).padStart(2, "0")}:${String(v % 60).padStart(2, "0")}`;
}
const count = (xs, v) => xs.filter((x) => x === v).length;
const measured = (xs) => xs.filter((x) => x !== null && x !== undefined).length;
function signalTiles(s) {
    var _a, _b;
    const t = {};
    if (s.sleep) {
        const ns = s.sleep.nights.filter((n) => n != null);
        t.sleep = { avgMin: s.sleep.avgMin, debtMin: s.sleep.debtMin, shortNights: ns.filter((n) => n < s.sleep.targetMin - 30).length, nights: ns.length };
    }
    if (s.parole)
        t.parole = { held: count(s.parole.days, true), given: measured(s.parole.days) };
    if (s.watch)
        t.watch = { won: count(s.watch.days, true), measured: measured(s.watch.days), blocker: (_b = (_a = s.watch.blockers[0]) === null || _a === void 0 ? void 0 : _a.name) !== null && _b !== void 0 ? _b : null };
    if (s.metronome)
        t.metronome = { won: count(s.metronome.days, true), measured: measured(s.metronome.days) };
    if (s.cap)
        t.cap = { posed: measured(s.cap.days), held: count(s.cap.days, "held") };
    return t;
}
/** Lignes ajoutées au rapport de pré-séance. */
function signalReportLines(s) {
    var _a;
    const t = signalTiles(s);
    const lines = [];
    if (s.sleep && t.sleep && t.sleep.nights > 0) {
        lines.push(`Sommeil : ${fmtMin((_a = t.sleep.avgMin) !== null && _a !== void 0 ? _a : 0)} en moyenne · dette ${fmtMin(t.sleep.debtMin)} sur 7 nuits · ${t.sleep.shortNights} nuit${t.sleep.shortNights > 1 ? "s" : ""} courte${t.sleep.shortNights > 1 ? "s" : ""}`);
        if (s.sleep.avgBed != null) {
            lines.push(`  coucher ${clockOf(s.sleep.avgBed)}${s.sleep.plannedBed != null ? ` (bloc ${clockOf(s.sleep.plannedBed)})` : ""}${s.sleep.spreadMin != null ? ` · ± ${s.sleep.spreadMin} min` : ""}`);
        }
        if (s.sleep.impact)
            lines.push(`  après une nuit courte : ${s.sleep.impact.shortLowPct} % du temps en Flemme (contre ${s.sleep.impact.longLowPct} %)`);
    }
    if (t.parole && t.parole.given > 0)
        lines.push(`Parole tenue : ${t.parole.held} jour${t.parole.held > 1 ? "s" : ""} sur ${t.parole.given} donné${t.parole.given > 1 ? "s" : ""}`);
    if (t.watch && t.watch.measured > 0)
        lines.push(`Montre suisse : ${t.watch.won} / ${t.watch.measured}${t.watch.blocker ? ` · bloque : ${t.watch.blocker}` : ""}`);
    if (t.metronome && t.metronome.measured > 0)
        lines.push(`Métronome : ${t.metronome.won} / ${t.metronome.measured}`);
    if (t.cap)
        lines.push(`Posé la veille : ${t.cap.posed} / 7${t.cap.posed > 0 ? ` · tenus ${t.cap.held}` : ""}`);
    return lines;
}
/** « À aborder en séance » : 4 phrases au plus, les signaux qui bougent. */
function talkingPoints(s) {
    const t = signalTiles(s);
    const out = [];
    if (s.sleep && t.sleep && t.sleep.nights >= 3 && t.sleep.shortNights >= 3) {
        let p = `Nuits courtes ${t.sleep.shortNights} sur ${t.sleep.nights}`;
        if (s.sleep.avgBed != null && s.sleep.plannedBed != null && s.sleep.avgBed - s.sleep.plannedBed >= 20) {
            p += `, couché·e en moyenne à ${clockOf(s.sleep.avgBed)}, ${fmtMin(s.sleep.avgBed - s.sleep.plannedBed)} après son bloc Sommeil`;
        }
        if (s.sleep.impact && s.sleep.impact.shortLowPct > s.sleep.impact.longLowPct) {
            p += `. Après une nuit courte, son temps en Flemme passe de ${s.sleep.impact.longLowPct} % à ${s.sleep.impact.shortLowPct} %`;
        }
        out.push(p + ".");
    }
    if (t.parole && t.parole.given >= 2 && t.parole.held < t.parole.given) {
        let p = `Parole donnée ${t.parole.given} jours, tenue ${t.parole.held}.`;
        if (s.sleep && s.parole) {
            // Jours manqués qui suivent une nuit courte (`nightsBefore` aligné sur `days`).
            const before = s.sleep.nightsBefore;
            const missed = s.parole.days.map((d, i) => (d === false ? before[i] : undefined)).filter((n) => n !== undefined);
            const afterShort = missed.filter((n) => n != null && n < s.sleep.targetMin - 30).length;
            if (missed.length > 0 && afterShort === missed.length)
                p += missed.length > 1 ? " Les jours manqués suivent une nuit courte." : " Le jour manqué suit une nuit courte.";
        }
        out.push(p);
    }
    if (t.watch && t.watch.measured > 0 && t.watch.measured - t.watch.won >= 2) {
        const b = s.watch.blockers[0];
        out.push(`Montre suisse perdue ${t.watch.measured - t.watch.won} soirs${b ? `, surtout à cause de « ${b.name} » (minimum ${fmtMin(b.goalMin)}, en retard ${b.lostDays} soir${b.lostDays > 1 ? "s" : ""})` : ""}.`);
    }
    const good = [];
    if (t.metronome && t.metronome.measured >= 5 && t.metronome.won >= t.metronome.measured - 1)
        good.push(`routines tenues ${t.metronome.won} jours sur ${t.metronome.measured}`);
    if (t.cap && t.cap.held >= 3)
        good.push(`journée posée la veille et tenue ${t.cap.held} fois`);
    if (t.parole && t.parole.given >= 3 && t.parole.held === t.parole.given)
        good.push(`parole tenue tous les jours où elle a été donnée`);
    if (good.length)
        out.push(`Bon point : ${good.join(", ")}.`);
    return out.slice(0, 4);
}
/** Pastille « À SURVEILLER » (lot 3) : un signal de fond se dégrade. */
function watchFlag(s) {
    if (!s)
        return null;
    const t = signalTiles(s);
    if (t.sleep && t.sleep.nights >= 5 && t.sleep.shortNights >= 5)
        return "nuits courtes";
    if (t.parole && t.parole.given >= 4 && t.parole.held * 2 < t.parole.given)
        return "parole fragile";
    return null;
}
//# sourceMappingURL=coach_signals.js.map