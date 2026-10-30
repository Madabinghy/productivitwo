"use strict";
/**
 * Règles des notifications push ORION / coach (2026-10-30). Pures.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.pushTitleFor = pushTitleFor;
exports.shouldPushNow = shouldPushNow;
exports.pushAllowed = pushAllowed;
exports.todayParis = todayParis;
/** Titre selon l'expéditeur : un coach signe de son nom, ORION reste ORION. */
function pushTitleFor(sender, characterName) {
    const name = (characterName !== null && characterName !== void 0 ? characterName : "").trim();
    if (sender === "coach")
        return `🎓 ${name || "Ton coach"}`;
    return `◉ ${name || "ORION"}`;
}
/** Un message daté d'un jour à venir ne part pas tout de suite (il s'affiche le jour venu dans l'app). */
function shouldPushNow(targetDate, todayYmd) {
    return targetDate <= todayYmd;
}
/** Interrupteur « Messages ORION / coach » : absent = activé. */
function pushAllowed(config) {
    return (config === null || config === void 0 ? void 0 : config.pushEnabled) !== false;
}
function todayParis(d = new Date()) {
    return new Intl.DateTimeFormat("en-CA", {
        timeZone: "Europe/Paris",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
    }).format(d);
}
//# sourceMappingURL=push_rules.js.map