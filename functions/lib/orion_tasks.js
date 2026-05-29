"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.taskOverdueSummary = taskOverdueSummary;
exports.taskWeeklyDeadlines = taskWeeklyDeadlines;
exports.taskArchiveInactiveProjects = taskArchiveInactiveProjects;
exports.taskCleanExpiredMessages = taskCleanExpiredMessages;
exports.taskProgressReport = taskProgressReport;
exports.runDeterministicTask = runDeterministicTask;
const db_1 = require("./db");
const execute_1 = require("./execute");
// ── Résumé des retards ────────────────────────────────────────────────────────
async function taskOverdueSummary(uid) {
    const actions = [];
    let pushed = 0;
    const today = (0, execute_1.todayInParis)();
    const todayYmd = today.replace(/-/g, "");
    const [dayPlanSnap, projectsSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/dayPlan`)
            .where("yyyymmdd", "<", todayYmd)
            .where("done", "==", false)
            .get(),
        db_1.db.collection(`users/${uid}/projects`)
            .where("status", "==", "active")
            .get(),
    ]);
    const planOverdue = dayPlanSnap.docs
        .map((d) => d.data())
        .filter((it) => it.status !== "archived" && it.status !== "done").length;
    const overdueGantt = [];
    for (const doc of projectsSnap.docs) {
        const p = doc.data();
        for (const t of (p.tasks || [])) {
            if (t.status !== "done" && t.status !== "skipped" && t.endDate && t.endDate < today) {
                overdueGantt.push({ projectTitle: p.title, projectId: p.id, taskTitle: t.title, taskId: t.id, endDate: t.endDate });
            }
        }
    }
    if (planOverdue === 0 && overdueGantt.length === 0) {
        await (0, execute_1.executePushAssistantMessage)(uid, {
            targetDate: today, text: "Aucun retard détecté — continue sur cette lancée !",
            condition: { type: "always" }, expiresAfterDays: 1, priority: 3,
        });
        pushed++;
        actions.push("ℹ️ Aucun retard détecté");
    }
    else {
        if (planOverdue > 0) {
            const text = `${planOverdue} action${planOverdue > 1 ? "s" : ""} en retard dans ton plan. Priorise tes 3 essentielles aujourd'hui.`;
            await (0, execute_1.executePushAssistantMessage)(uid, {
                targetDate: today, text: text.slice(0, 179),
                condition: { type: "overdue_count", min: 1 }, expiresAfterDays: 1, priority: 1,
                action: { type: "open_day_plan" },
            });
            pushed++;
            actions.push(`⚠️ ${planOverdue} actions en retard dans le plan`);
        }
        if (overdueGantt.length > 0) {
            overdueGantt.sort((a, b) => a.endDate.localeCompare(b.endDate));
            const most = overdueGantt[0];
            const text = overdueGantt.length === 1
                ? `Tâche Gantt en retard : "${most.taskTitle}" (${most.projectTitle}).`
                : `${overdueGantt.length} tâches Gantt en retard. Plus urgente : "${most.taskTitle}".`;
            await (0, execute_1.executePushAssistantMessage)(uid, {
                targetDate: today, text: text.slice(0, 179),
                condition: { type: "overdue_count", min: 1 }, expiresAfterDays: 1, priority: 1,
                action: { type: "open_gantt_task", payload: { projectId: most.projectId, taskId: most.taskId } },
            });
            pushed++;
            actions.push(`⚠️ ${overdueGantt.length} tâches Gantt en retard`);
        }
    }
    return { actions, pushed, skipped: false };
}
// ── Deadlines de la semaine ───────────────────────────────────────────────────
async function taskWeeklyDeadlines(uid) {
    const actions = [];
    let pushed = 0;
    const today = (0, execute_1.todayInParis)();
    const in7days = (0, execute_1.todayInParis)(new Date(Date.now() + 7 * 24 * 60 * 60 * 1000));
    const snap = await db_1.db.collection(`users/${uid}/projects`).where("status", "==", "active").get();
    const upcoming = [];
    for (const doc of snap.docs) {
        const p = doc.data();
        for (const t of (p.tasks || [])) {
            if (t.status !== "done" && t.status !== "skipped" && t.endDate && t.endDate >= today && t.endDate <= in7days)
                upcoming.push({ projectTitle: p.title, projectId: p.id, taskTitle: t.title, taskId: t.id, endDate: t.endDate });
        }
    }
    if (upcoming.length === 0) {
        await (0, execute_1.executePushAssistantMessage)(uid, {
            targetDate: today, text: "Aucune deadline dans les 7 jours. Profites-en pour avancer sur tes tâches en attente.",
            condition: { type: "always" }, expiresAfterDays: 1, priority: 3,
        });
        pushed++;
        actions.push("ℹ️ Aucune deadline imminente");
    }
    else {
        upcoming.sort((a, b) => a.endDate.localeCompare(b.endDate));
        for (const item of upcoming.slice(0, 3)) {
            const daysLeft = Math.max(1, Math.ceil((new Date(item.endDate).getTime() - Date.now()) / 86400000));
            const text = `Deadline dans ${daysLeft}j : "${item.taskTitle}" (${item.projectTitle}).`;
            await (0, execute_1.executePushAssistantMessage)(uid, {
                targetDate: today, text: text.slice(0, 179),
                condition: { type: "project_deadline_near", projectId: item.projectId, daysBefore: 7 },
                expiresAfterDays: daysLeft, priority: 1,
                action: { type: "open_gantt_task", payload: { projectId: item.projectId, taskId: item.taskId } },
            });
            pushed++;
            actions.push(`📅 Deadline : ${item.taskTitle} (J-${daysLeft})`);
        }
    }
    return { actions, pushed, skipped: false };
}
// ── Archiver les projets inactifs (>14j sans mise à jour) ─────────────────────
async function taskArchiveInactiveProjects(uid) {
    var _a, _b, _c, _d, _e, _f;
    const actions = [];
    let pushed = 0;
    const today = (0, execute_1.todayInParis)();
    const cutoff = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000);
    const snap = await db_1.db.collection(`users/${uid}/projects`).where("status", "==", "active").get();
    const toArchive = [];
    for (const doc of snap.docs) {
        const p = doc.data();
        const updated = (_f = (_c = (_b = (_a = p.updatedAt) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a)) !== null && _c !== void 0 ? _c : (_e = (_d = p.createdAt) === null || _d === void 0 ? void 0 : _d.toDate) === null || _e === void 0 ? void 0 : _e.call(_d)) !== null && _f !== void 0 ? _f : new Date(0);
        const tasks = (p.tasks || []);
        const hasUrgent = tasks.some((t) => t.status !== "done" && t.status !== "skipped" && t.endDate && t.endDate >= today);
        if (!hasUrgent && updated < cutoff)
            toArchive.push({ id: p.id, title: p.title });
    }
    if (toArchive.length === 0) {
        await (0, execute_1.executePushAssistantMessage)(uid, {
            targetDate: today, text: "Aucun projet inactif à archiver — tous tes projets sont actifs.",
            condition: { type: "always" }, expiresAfterDays: 1, priority: 3,
        });
        pushed++;
        actions.push("ℹ️ Aucun projet inactif");
    }
    else {
        const batch = db_1.db.batch();
        for (const p of toArchive) {
            batch.update(db_1.db.collection(`users/${uid}/projects`).doc(p.id), {
                status: "archived", updatedAt: db_1.FieldValue.serverTimestamp(),
            });
            actions.push(`🗄 Projet archivé : ${p.title}`);
        }
        await batch.commit();
        const text = toArchive.length === 1
            ? `Projet "${toArchive[0].title}" archivé (inactif depuis 14j).`
            : `${toArchive.length} projets inactifs archivés.`;
        await (0, execute_1.executePushAssistantMessage)(uid, {
            targetDate: today, text: text.slice(0, 179),
            condition: { type: "always" }, expiresAfterDays: 2, priority: 2,
        });
        pushed++;
    }
    return { actions, pushed, skipped: false };
}
// ── Nettoyer les messages expirés ─────────────────────────────────────────────
async function taskCleanExpiredMessages(uid) {
    var _a;
    const actions = [];
    const today = (0, execute_1.todayInParis)();
    const snap = await db_1.db.collection(`users/${uid}/assistant_messages`)
        .where("status", "==", "pending").get();
    const batch = db_1.db.batch();
    let count = 0;
    for (const doc of snap.docs) {
        const m = doc.data();
        const expireDate = new Date(m.targetDate);
        expireDate.setDate(expireDate.getDate() + ((_a = m.expiresAfterDays) !== null && _a !== void 0 ? _a : 2));
        if ((0, execute_1.todayInParis)(expireDate) < today) {
            batch.update(doc.ref, { status: "expired" });
            count++;
        }
    }
    if (count > 0) {
        await batch.commit();
        actions.push(`🧹 ${count} message${count > 1 ? "s" : ""} expiré${count > 1 ? "s" : ""} nettoyé${count > 1 ? "s" : ""}`);
    }
    else {
        actions.push("ℹ️ Aucun message expiré");
    }
    return { actions, pushed: 0, skipped: false };
}
// ── Rapport de progression (sans LLM) ────────────────────────────────────────
async function taskProgressReport(uid) {
    const actions = [];
    let pushed = 0;
    const today = (0, execute_1.todayInParis)();
    const snap = await db_1.db.collection(`users/${uid}/projects`).where("status", "==", "active").get();
    if (snap.empty) {
        await (0, execute_1.executePushAssistantMessage)(uid, {
            targetDate: today, text: "Aucun projet actif pour le moment.",
            condition: { type: "always" }, expiresAfterDays: 1, priority: 3,
        });
        pushed++;
        return { actions: ["ℹ️ Aucun projet actif"], pushed, skipped: false };
    }
    for (const doc of snap.docs.slice(0, 3)) {
        const p = doc.data();
        const tasks = (p.tasks || []);
        const done = tasks.filter((t) => t.status === "done").length;
        const total = tasks.length;
        const pct = total > 0 ? Math.round((done / total) * 100) : 0;
        const text = `${p.title} : ${pct}% (${done}/${total} tâches). ${pct >= 80 ? "Presque fini !" : pct >= 50 ? "Bonne progression." : "À accélérer."}`;
        await (0, execute_1.executePushAssistantMessage)(uid, {
            targetDate: today, text: text.slice(0, 179),
            condition: { type: "always" }, expiresAfterDays: 2, priority: 2,
            action: { type: "open_project", payload: { projectId: p.id } },
        });
        pushed++;
        actions.push(`📊 Rapport : ${p.title} (${pct}%)`);
    }
    return { actions, pushed, skipped: false };
}
// ── Router ────────────────────────────────────────────────────────────────────
async function runDeterministicTask(uid, taskId) {
    switch (taskId) {
        case "overdue_summary": return taskOverdueSummary(uid);
        case "weekly_deadlines": return taskWeeklyDeadlines(uid);
        case "archive_inactive": return taskArchiveInactiveProjects(uid);
        case "clean_expired": return taskCleanExpiredMessages(uid);
        case "progress_report": return taskProgressReport(uid);
        default:
            return { actions: [`Tâche inconnue : ${taskId}`], pushed: 0, skipped: true, reason: `taskId inconnu : ${taskId}` };
    }
}
//# sourceMappingURL=orion_tasks.js.map