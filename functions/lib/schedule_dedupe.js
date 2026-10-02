"use strict";
// Doublons agenda ↔ programme (constaté 2026-10-02) : un rendez-vous Google
// arrive dans le programme comme bloc MIROIR (gcalEventId), puis Claude, qui
// le voit dans l'agenda, le recréait comme bloc ordinaire dans schedule_day
// → deux lignes identiques dans Aujourd'hui. Règle unique : même début +
// même titre (ou même durée) qu'un miroir vivant = le même rendez-vous.
Object.defineProperty(exports, "__esModule", { value: true });
exports.isLiveMirror = void 0;
exports.sameSlot = sameSlot;
exports.splitAgainstMirrors = splitAgainstMirrors;
exports.dropPlainDuplicates = dropPlainDuplicates;
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
//# sourceMappingURL=schedule_dedupe.js.map