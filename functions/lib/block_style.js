"use strict";
// ── D : programme du jour moins haché (2026-10) ──────────────────────────────
// Diagnostic : les blocs copiaient la granularité des actions (15–25 min, une
// action = un bloc), et l'utilisateur retravaillait le programme à la main.
// Règle : un bloc de travail dure 30 min minimum ; les actions consécutives
// d'une même tâche tiennent dans UN bloc nommé par la tâche (actionId = la
// première action, les suivantes s'enchaînent dans l'écran bloc). Routines,
// pauses, préparations et rendez-vous ne sont pas concernés. Pure, pas d'I/O.
Object.defineProperty(exports, "__esModule", { value: true });
exports.MIN_WORK_BLOCK_MIN = exports.BLOCK_RULES = void 0;
exports.activityLoad = activityLoad;
exports.activityLoadLabel = activityLoadLabel;
exports.analyzeBlocks = analyzeBlocks;
exports.blockAdvice = blockAdvice;
exports.BLOCK_RULES = "BLOCS : par défaut, pose des blocs de TEMPS (timeBlock, sans source) — « Deep work » (deep, 1 h 30 à 2 h, le " +
    "matin de préférence), « Petites choses » (small, 45 min, mails / appels / petites actions) et « Tampon » " +
    "(buffer, 45 min, en fin de journée) : l'utilisateur choisit QUOI faire au moment de lancer le bloc (l'app lui " +
    "propose sa parole, ses retards, ses visées), car un programme détaillé est faux dès la première interruption. " +
    "Ne détaille par activité que si l'utilisateur le demande. " +
    "30 min minimum pour un bloc de travail. Pour un travail de fond détaillé, pose des blocs d'ACTIVITÉ " +
    "(activityId seul, sans projectId / taskId / actionId, titre = le nom de l'activité, ex. « Enseignement ») : " +
    "au lancement, l'app propose la prochaine action de chaque projet lié à l'activité (les en retard d'abord) et " +
    "le bloc ne retient que le temps — JAMAIS un bloc par action, jamais une action recopiée dans le programme. " +
    "Un bloc de tâche (projectId + taskId) est réservé au DATÉ : séance, jalon, rendez-vous, préparation. " +
    "Routines, pauses, prep (5 min) et rendez-vous gardent leur durée propre.";
function activityLoad(activityId, projects, today) {
    let count = 0;
    let overdue = 0;
    for (const p of projects) {
        if (p.status !== "active" || p.paused === true)
            continue;
        const whole = p.linkedActivityId === activityId;
        const tasks = Array.isArray(p.tasks) ? p.tasks : [];
        let serves = whole;
        let late = 0;
        for (const t of tasks) {
            if (t.status === "done" || t.status === "skipped")
                continue;
            const actions = Array.isArray(t.actions) ? t.actions : [];
            for (const raw of actions) {
                if (typeof raw !== "object" || raw === null)
                    continue;
                const a = raw;
                if (a.done === true)
                    continue;
                if (!(whole || a.linkedActivityId === activityId))
                    continue;
                serves = true;
                const due = typeof a.dueDate === "string" && a.dueDate
                    ? a.dueDate
                    : typeof t.endDate === "string" ? t.endDate.slice(0, 10) : "";
                if (due && due < today)
                    late++;
            }
        }
        if (serves) {
            count++;
            overdue += late;
        }
    }
    return { projects: count, overdue };
}
/** « 4 projets liés · 2 actions en retard » ; "" si rien n'est lié. */
function activityLoadLabel(l) {
    if (l.projects === 0)
        return "";
    const parts = [`${l.projects} projet${l.projects > 1 ? "s" : ""} lié${l.projects > 1 ? "s" : ""}`];
    if (l.overdue > 0)
        parts.push(`${l.overdue} action${l.overdue > 1 ? "s" : ""} en retard`);
    return parts.join(" · ");
}
exports.MIN_WORK_BLOCK_MIN = 30;
function toMin(hm) {
    const [h, m] = hm.split(":").map((x) => parseInt(x, 10));
    return (h || 0) * 60 + (m || 0);
}
function isWorkBlock(b) {
    if (b.gcalEventId)
        return false;
    if (b.kind && b.kind !== "normal")
        return false;
    if (b.category === "routine" || b.category === "break")
        return false;
    return !!(b.projectId || b.taskId || (b.activityId && b.category !== "personal"));
}
/** Blocs de travail trop courts, et suites de blocs consécutifs d'une même tâche. */
function analyzeBlocks(blocks) {
    const sorted = [...blocks].sort((a, b) => toMin(a.startTime) - toMin(b.startTime));
    const short = sorted.filter((b) => isWorkBlock(b) && b.durationMin < exports.MIN_WORK_BLOCK_MIN);
    const mergeable = [];
    let run = [];
    const flush = () => {
        if (run.length >= 2)
            mergeable.push({ taskId: String(run[0].taskId), blocks: run });
        run = [];
    };
    for (const b of sorted) {
        const prev = run[run.length - 1];
        const sameTask = prev && b.taskId && prev.taskId === b.taskId &&
            toMin(b.startTime) - (toMin(prev.startTime) + prev.durationMin) <= 15;
        if (sameTask)
            run.push(b);
        else {
            flush();
            run = isWorkBlock(b) && b.taskId ? [b] : [];
        }
    }
    flush();
    return { short, mergeable };
}
/** Ligne d'avis pour la réponse de schedule_day, "" si rien à dire. */
function blockAdvice(blocks) {
    const { short, mergeable } = analyzeBlocks(blocks);
    const rows = [];
    if (short.length) {
        rows.push(`• ${short.length} bloc(s) de travail < ${exports.MIN_WORK_BLOCK_MIN} min : ` +
            short.slice(0, 4).map((b) => `${b.startTime} « ${b.title} » (${b.durationMin} min)`).join(", ") +
            (short.length > 4 ? "…" : "") + " — regroupe-les ou allonge-les.");
    }
    for (const m of mergeable.slice(0, 3)) {
        const total = m.blocks.reduce((s, b) => s + b.durationMin, 0);
        rows.push(`• ${m.blocks.length} blocs consécutifs sur la même tâche (${m.blocks[0].startTime} → ` +
            `${m.blocks[m.blocks.length - 1].startTime}, ${total} min) : un seul bloc nommé par la tâche suffit, ` +
            `l'écran bloc enchaîne les actions.`);
    }
    if (!rows.length)
        return "";
    return `\n⏱ Programme haché (règle : ${exports.MIN_WORK_BLOCK_MIN} min minimum, une tâche = un bloc) :\n${rows.join("\n")}`;
}
//# sourceMappingURL=block_style.js.map