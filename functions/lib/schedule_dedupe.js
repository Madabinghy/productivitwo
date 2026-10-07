"use strict";
// Doublons agenda ↔ programme (constaté 2026-10-02) : un rendez-vous Google
// arrive dans le programme comme bloc MIROIR (gcalEventId), puis Claude, qui
// le voit dans l'agenda, le recréait comme bloc ordinaire dans schedule_day
// → deux lignes identiques dans Aujourd'hui. Règle unique : même début +
// même titre (ou même durée) qu'un miroir vivant = le même rendez-vous.
Object.defineProperty(exports, "__esModule", { value: true });
exports.isOccupying = exports.toMin = exports.isLiveMirror = void 0;
exports.sameSlot = sameSlot;
exports.splitAgainstMirrors = splitAgainstMirrors;
exports.dropPlainDuplicates = dropPlainDuplicates;
exports.fillAgainstExisting = fillAgainstExisting;
exports.nearestFreeSlot = nearestFreeSlot;
const norm = (s) => String(s !== null && s !== void 0 ? s : "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/\s+/g, " ")
    .trim();
/** Même créneau qu'un miroir : même heure de début ET (même titre OU même durée). */
function sameSlot(a, mirror) {
    if (String(a.startTime) !== String(mirror.startTime))
        return false;
    return norm(a.title) === norm(mirror.title) || Number(a.durationMin) === Number(mirror.durationMin);
}
const isLiveMirror = (b) => b.gcalEventId != null && b.status !== "deleted";
exports.isLiveMirror = isLiveMirror;
/** Sépare les blocs entrants : ceux à garder, ceux qui doublonnent un miroir. */
function splitAgainstMirrors(incoming, existing) {
    const mirrors = existing.filter(exports.isLiveMirror);
    const kept = [];
    const dropped = [];
    for (const b of incoming) {
        (mirrors.some((m) => sameSlot(b, m)) ? dropped : kept).push(b);
    }
    return { kept, dropped };
}
/**
 * Nettoyage d'un programme existant : un bloc ORDINAIRE (sans gcalEventId)
 * qui doublonne un miroir vivant est retiré. Retourne le tableau nettoyé et
 * le nombre de retraits (0 = rien à écrire).
 */
function dropPlainDuplicates(blocks) {
    const mirrors = blocks.filter(exports.isLiveMirror);
    if (mirrors.length === 0)
        return { blocks, removed: 0 };
    const out = [];
    let removed = 0;
    for (const b of blocks) {
        const plain = b.gcalEventId == null && b.status !== "done";
        if (plain && mirrors.some((m) => sameSlot(b, m))) {
            removed++;
            continue;
        }
        out.push(b);
    }
    return { blocks: out, removed };
}
/** "HH:mm" → minutes depuis minuit (format invalide → 0). */
const toMin = (hm) => {
    const m = /^(\d{1,2}):(\d{2})$/.exec(String(hm !== null && hm !== void 0 ? hm : ""));
    return m ? Number(m[1]) * 60 + Number(m[2]) : 0;
};
exports.toMin = toMin;
/** Bloc qui OCCUPE son créneau : ni supprimé, ni sauté. */
const isOccupying = (b) => b.status !== "deleted" && b.status !== "skipped";
exports.isOccupying = isOccupying;
const overlaps = (a, b) => {
    var _a, _b;
    const aS = (0, exports.toMin)(a.startTime), aE = aS + Number((_a = a.durationMin) !== null && _a !== void 0 ? _a : 0);
    const bS = (0, exports.toMin)(b.startTime), bE = bS + Number((_b = b.durationMin) !== null && _b !== void 0 ? _b : 0);
    return aS < bE && bS < aE;
};
/**
 * Mode « compléter » de schedule_day (programmation automatique, 2026-10) :
 * le programme existant est conservé TEL QUEL (blocs faits, manuels, reports,
 * tombstones) et un bloc entrant n'est posé que s'il ne chevauche aucun bloc
 * existant qui occupe son créneau. Les entrants qui se chevauchent entre eux
 * sont posés dans l'ordre : le second est écarté.
 */
function fillAgainstExisting(incoming, existing) {
    const busy = existing.filter(exports.isOccupying);
    const kept = [];
    const dropped = [];
    for (const b of incoming) {
        if (busy.some((e) => overlaps(b, e))) {
            dropped.push(b);
        }
        else {
            kept.push(b);
            busy.push(b);
        }
    }
    return { kept, dropped };
}
const fromMin = (m) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
/**
 * Créneau libre le plus proche de l'heure demandée (B9) : on cherche, par pas
 * de 15 min, le début le plus proche (avant ou après) dans la fenêtre
 * [startMin, endMin[ où le bloc tient sans chevaucher un bloc occupant.
 * Null si aucun. Retourne "HH:mm".
 */
function nearestFreeSlot(block, existing, window, step = 15) {
    var _a;
    const dur = Number((_a = block.durationMin) !== null && _a !== void 0 ? _a : 0);
    if (dur <= 0)
        return null;
    const busy = existing.filter(exports.isOccupying);
    const want = (0, exports.toMin)(block.startTime);
    const fits = (start) => start >= window.startMin &&
        start + dur <= window.endMin &&
        !busy.some((e) => overlaps({ startTime: fromMin(start), durationMin: dur }, e));
    const base = Math.round(want / step) * step;
    for (let delta = 0; delta <= 24 * 60; delta += step) {
        for (const start of delta === 0 ? [base] : [base + delta, base - delta]) {
            if (fits(start))
                return fromMin(start);
        }
    }
    return null;
}
//# sourceMappingURL=schedule_dedupe.js.map