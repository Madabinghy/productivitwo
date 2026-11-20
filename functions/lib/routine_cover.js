"use strict";
/**
 * Routines « sur 7 jours » et « le chrono coche » (2026-11-19) — miroir serveur
 * de `lib/utils/routine_cover.dart` (**garder alignés**).
 *
 * Une routine QUOTIDIENNE réglée `rolling` se compte sur les 7 derniers jours :
 * ce qui est fait en plus couvre les jours suivants ; le retard ne s'accumule
 * pas (un jour sans avance demande la cible normale, jamais plus).
 * `minPerHit` = minutes de chrono sur l'activité liée (`linkedActivityId`) qui
 * valent une coche ; c'est l'APP qui pose ces coches.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.ROUTINE_WINDOW_DAYS = void 0;
exports.rollingDayTarget = rollingDayTarget;
exports.shiftYmd = shiftYmd;
exports.livedYmdOfTs = livedYmdOfTs;
exports.routineCover = routineCover;
exports.isRollingRoutine = isRollingRoutine;
exports.isCatchUpRoutine = isCatchUpRoutine;
exports.catchUpOf = catchUpOf;
exports.catchUpNote = catchUpNote;
exports.coverNote = coverNote;
exports.normalizeMinPerHit = normalizeMinPerHit;
exports.rhythmPatch = rhythmPatch;
exports.ROUTINE_WINDOW_DAYS = 7;
/** Ce qu'un jour demande d'après les 6 jours d'avant. */
function rollingDayTarget(target, pastSum) {
    const need = exports.ROUTINE_WINDOW_DAYS * target - pastSum;
    if (need <= 0)
        return 0;
    return need > target ? target : need;
}
/** `YYYY-MM-DD` décalé de `days` jours. */
function shiftYmd(ymd, days) {
    const [y, m, d] = ymd.split("-").map((x) => parseInt(x, 10));
    const t = new Date(Date.UTC(y, (m || 1) - 1, (d || 1) + days));
    return t.toISOString().slice(0, 10);
}
/**
 * Jour VÉCU d'une coche d'après son horodatage ISO lu tel quel (heure locale de
 * l'app) : avant la bascule (5 h par défaut), elle appartient à la veille.
 * Chaîne illisible = "".
 */
function livedYmdOfTs(ts, dayStartMin = 300) {
    if (typeof ts !== "string" || ts.length < 16)
        return "";
    const ymd = ts.slice(0, 10);
    const min = parseInt(ts.slice(11, 13), 10) * 60 + parseInt(ts.slice(14, 16), 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(ymd) || isNaN(min))
        return "";
    return min < dayStartMin ? shiftYmd(ymd, -1) : ymd;
}
/** Où en est une routine « sur 7 jours » le jour `ymd` (coches par jour vécu). */
function routineCover(target, counts, ymd) {
    const t = target > 0 ? Math.round(target) : 1;
    const on = (back) => { var _a; return (_a = counts[shiftYmd(ymd, -back)]) !== null && _a !== void 0 ? _a : 0; };
    const window = [];
    for (let i = exports.ROUTINE_WINDOW_DAYS - 1; i >= 1; i--)
        window.push(on(i));
    const pastDone = window.reduce((s, v) => s + v, 0);
    const todayDone = on(0);
    const dayTarget = rollingDayTarget(t, pastDone);
    const future = [...window, todayDone];
    const next = () => rollingDayTarget(t, future.slice(-(exports.ROUTINE_WINDOW_DAYS - 1)).reduce((s, v) => s + v, 0));
    const tomorrowTarget = next();
    const held = todayDone >= dayTarget;
    let aheadDays = 0;
    if (held) {
        while (aheadDays < exports.ROUTINE_WINDOW_DAYS - 1 && next() === 0) {
            aheadDays++;
            future.push(0);
        }
    }
    return { target: t, todayDone, pastDone, dayTarget, aheadDays, tomorrowTarget, held };
}
/** Routine quotidienne réglée « sur 7 jours ». */
function isRollingRoutine(a) {
    return a.type === "habit" && (a.habitFreq === 0 || a.habitFreq === "daily") && a.rolling === true;
}
/**
 * Un jour raté se rattrape (2026-11-19, « Routines rattrapables ») : rythme « Rattrapable » (`catchUp`, sans avance)
 * ou « Sur 7 jours » (`rolling`, rattrapage et avance).
 */
function isCatchUpRoutine(a) {
    return a.type === "habit" && (a.habitFreq === 0 || a.habitFreq === "daily") && (a.catchUp === true || a.rolling === true);
}
/**
 * Rejoue les jours d'une routine rattrapable jusqu'à `ymd` : ce qu'un jour fait EN PLUS de ce qu'il demande comble
 * les jours ratés des 6 jours d'avant, le plus récent d'abord. Miroir de `catchUpOf` (app).
 */
function catchUpOf(target, counts, ymd, rolling) {
    var _a;
    const t = target > 0 ? Math.round(target) : 1;
    const days = Object.keys(counts).filter((k) => /^\d{4}-\d{2}-\d{2}$/.test(k) && k <= ymd).sort();
    if (!days.length)
        return { repaired: [], open: [] };
    const repaired = [];
    let holes = [];
    let open = [];
    const window = [];
    let past = 0;
    for (let d = days[0]; d <= ymd; d = shiftYmd(d, 1)) {
        const limit = shiftYmd(d, -(exports.ROUTINE_WINDOW_DAYS - 1));
        holes = holes.filter((h) => h.ymd >= limit);
        if (d === ymd)
            open = [...holes].reverse();
        const c = (_a = counts[d]) !== null && _a !== void 0 ? _a : 0;
        const need = rolling ? rollingDayTarget(t, past) : t;
        if (c > need) {
            let extra = c - need;
            for (let i = holes.length - 1; i >= 0 && extra > 0; i--) {
                const take = Math.min(extra, holes[i].deficit);
                extra -= take;
                if (take === holes[i].deficit) {
                    repaired.push(holes[i].ymd);
                    holes.splice(i, 1);
                }
                else {
                    holes[i] = { ymd: holes[i].ymd, deficit: holes[i].deficit - take };
                }
            }
        }
        else if (c < need && d !== ymd) {
            holes.push({ ymd: d, deficit: need - c });
        }
        window.push(c);
        past += c;
        if (window.length > exports.ROUTINE_WINDOW_DAYS - 1)
            past -= window.shift();
    }
    return { repaired, open };
}
/** Ce que Claude lit des jours à rattraper d'une routine, le jour visé ("" = rien à rattraper). */
function catchUpNote(c, minPerHit) {
    if (!c.open.length)
        return "";
    const total = c.open.reduce((s, h) => s + h.deficit, 0);
    const amount = minPerHit && minPerHit > 0 ? `${total * minPerHit} min` : `${total} coche${total > 1 ? "s" : ""}`;
    const n = c.open.length;
    return `${n} jour${n > 1 ? "s" : ""} raté${n > 1 ? "s" : ""} encore rattrapable${n > 1 ? "s" : ""} (${c.open.map((h) => h.ymd.slice(5)).join(", ")}) : ` +
        `${amount} en plus de la part du jour recollent la série`;
}
/** Ce que Claude lit d'une routine « sur 7 jours » pour le jour visé. */
function coverNote(c) {
    const window = `${c.pastDone + c.todayDone} / ${exports.ROUTINE_WINDOW_DAYS * c.target} sur 7 j`;
    if (c.dayTarget === 0) {
        const ahead = c.aheadDays > 0 ? `, encore ${c.aheadDays} j d'avance ensuite` : "";
        return `sur 7 jours · COUVERTE ce jour-là par son avance (${window}${ahead}) — ne pas la programmer`;
    }
    if (c.held)
        return `sur 7 jours · part du jour faite (${window})`;
    if (c.dayTarget < c.target) {
        return `sur 7 jours · l'avance réduit la part du jour à ${c.dayTarget} au lieu de ${c.target} (${window})`;
    }
    return `sur 7 jours · part du jour ${c.dayTarget} (${window}) · en faire plus couvre les jours suivants`;
}
const truthy = (v) => v === true || v === 1 || v === "true" || v === "1";
/** Minutes par coche : entier de 1 à 240 ; 0, vide ou illisible = pas de chrono qui coche. */
function normalizeMinPerHit(v) {
    if (v === null || v === undefined || v === "")
        return null;
    const n = Math.round(Number(v));
    if (!isFinite(n) || n <= 0)
        return null;
    return Math.min(240, n);
}
/**
 * Champs à écrire pour `rolling` / `catchUp` / `autoTarget` / `minPerHit`, et ce qu'on en dit. `current` =
 * la routine telle qu'elle sera après les autres modifications de l'appel.
 */
function rhythmPatch(updates, current) {
    var _a;
    const patch = {};
    const notes = [];
    const isHabit = current.type === "habit";
    const daily = current.habitFreq === 0 || current.habitFreq === "daily";
    if (updates.rolling !== undefined) {
        const on = truthy(updates.rolling);
        if (on && !(isHabit && daily)) {
            notes.push("⚠️ « Sur 7 jours » ne s'applique qu'aux routines quotidiennes : rien n'a été changé (une hebdomadaire compte déjà sur 7 jours glissants).");
        }
        else if (isHabit) {
            patch.rolling = on;
            // Un seul rythme à la fois : « sur 7 jours » rattrape déjà.
            if (on)
                patch.catchUp = false;
            notes.push(on
                ? "Rythme : sur 7 jours — ce qui est fait en plus rattrape d'abord un jour raté des 7 derniers jours, puis couvre les jours suivants."
                : "Rythme : chaque jour.");
        }
        else {
            notes.push("⚠️ « Sur 7 jours » concerne les routines, pas les activités de temps.");
        }
    }
    if (updates.catchUp !== undefined) {
        const on = truthy(updates.catchUp);
        if (on && !(isHabit && daily)) {
            notes.push("⚠️ « Rattrapable » ne s'applique qu'aux routines quotidiennes : rien n'a été changé.");
        }
        else if (isHabit && on && patch.rolling === true) {
            notes.push("« Sur 7 jours » rattrape déjà : le rythme reste sur 7 jours.");
        }
        else if (isHabit) {
            patch.catchUp = on;
            if (on)
                patch.rolling = false;
            notes.push(on
                ? "Rythme : rattrapable — un jour raté se rattrape dans les 7 jours en faisant plus un autre jour (la série recolle), sans avance sur demain."
                : (patch.rolling === undefined ? "Rythme : plus de rattrapage." : ""));
        }
        else {
            notes.push("⚠️ « Rattrapable » concerne les routines, pas les activités de temps.");
        }
    }
    // Cible automatique (2026-11-20) : la règle est appliquée par l'app (`lib/utils/auto_target.dart`), au lancement.
    if (updates.autoTarget !== undefined) {
        const on = truthy(updates.autoTarget);
        const capped = Number((_a = current.finalTarget) !== null && _a !== void 0 ? _a : 0) > 0;
        if (!isHabit) {
            notes.push("⚠️ La cible automatique concerne les routines, pas les activités de temps (leur minimum suit déjà le réel).");
        }
        else if (on && !daily) {
            notes.push("⚠️ La cible automatique ne s'applique qu'aux routines quotidiennes : rien n'a été changé.");
        }
        else if (on && capped) {
            notes.push("⚠️ Cette routine a un cap (progression par paliers) : c'est lui qui pilote la cible, la cible automatique n'a pas été allumée.");
        }
        else {
            patch.autoTarget = on;
            notes.push(on
                ? "Cible automatique : à 120 % sur 7 jours clos elle monte d'un cran, sous 50 % elle descend d'un cran, une fois par semaine au plus (appliqué par l'app à son lancement ; une hausse ne casse pas la série)."
                : "Cible automatique éteinte : la cible ne bouge plus toute seule.");
        }
    }
    if (updates.minPerHit !== undefined) {
        const n = normalizeMinPerHit(updates.minPerHit);
        if (!isHabit) {
            notes.push("⚠️ « Le chrono coche » concerne les routines, pas les activités de temps.");
        }
        else {
            patch.minPerHit = n;
            // Une seule durée par routine : celle du chrono qui coche est aussi celle du minuteur.
            if (n !== null)
                patch.timerMin = n;
            if (n === null) {
                notes.push("Le chrono ne coche plus cette routine.");
            }
            else {
                const linked = typeof current.linkedActivityId === "string" && current.linkedActivityId.trim() !== "";
                notes.push(`Le chrono coche : 1 coche = ${n} min sur l'activité liée (les coches sont posées par l'app, chrono en cours ou à l'arrêt).`);
                if (!linked)
                    notes.push("⚠️ Aucune activité liée : rien ne sera coché tant que linkedActivityId n'est pas posé.");
            }
        }
    }
    return { patch, notes: notes.filter((x) => x) };
}
//# sourceMappingURL=routine_cover.js.map