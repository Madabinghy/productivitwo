"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.taskOverdueSummary = taskOverdueSummary;
exports.taskWeeklyDeadlines = taskWeeklyDeadlines;
exports.taskArchiveInactiveProjects = taskArchiveInactiveProjects;
exports.taskWeeklyReview = taskWeeklyReview;
exports.taskGoldReview = taskGoldReview;
exports.taskCleanExpiredMessages = taskCleanExpiredMessages;
exports.taskProgressReport = taskProgressReport;
exports.taskGenerateExpeditionChallenges = taskGenerateExpeditionChallenges;
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
// ── Revue hebdo : PROPOSE d'archiver les projets inactifs (Phase 3) ──────────
// Contrairement à taskArchiveInactiveProjects (archive direct), cette tâche
// respecte « ORION propose, l'utilisateur dispose » : elle écrit des propositions
// archive_project dans orion_proposals (file « À valider »). Idempotente : ne
// reproposera pas un projet ayant déjà une proposition d'archivage en attente.
async function taskWeeklyReview(uid) {
    var _a, _b, _c, _d, _e, _f;
    const actions = [];
    let pushed = 0;
    const today = (0, execute_1.todayInParis)();
    const cutoff = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000);
    const [projectsSnap, pendingPropsSnap, captureSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
        db_1.db.collection(`users/${uid}/orion_proposals`)
            .where("status", "==", "pending").where("kind", "==", "archive_project").get(),
        db_1.db.collection(`users/${uid}/captures`).where("status", "==", "pending").get(),
    ]);
    // Projets déjà couverts par une proposition d'archivage en attente
    const alreadyProposed = new Set(pendingPropsSnap.docs
        .map((d) => { var _a; return (_a = d.data().payload) === null || _a === void 0 ? void 0 : _a.projectId; })
        .filter((x) => !!x));
    let proposed = 0;
    for (const doc of projectsSnap.docs) {
        const p = doc.data();
        if (alreadyProposed.has(p.id))
            continue;
        const updated = (_f = (_c = (_b = (_a = p.updatedAt) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a)) !== null && _c !== void 0 ? _c : (_e = (_d = p.createdAt) === null || _d === void 0 ? void 0 : _d.toDate) === null || _e === void 0 ? void 0 : _e.call(_d)) !== null && _f !== void 0 ? _f : new Date(0);
        const tasks = (p.tasks || []);
        const hasUrgent = tasks.some((t) => t.status !== "done" && t.status !== "skipped" && t.endDate && t.endDate >= today);
        if (!hasUrgent && updated < cutoff) {
            await (0, execute_1.executeProposeChange)(uid, {
                kind: "archive_project",
                title: `Archiver « ${p.title} »`,
                rationale: "Aucune tâche urgente et pas de mise à jour depuis 14 jours.",
                payload: { projectId: p.id },
            });
            proposed++;
            actions.push(`📋 Proposition d'archivage : ${p.title}`);
        }
    }
    const orphanIdeas = captureSnap.size;
    const parts = [];
    if (proposed > 0)
        parts.push(`${proposed} projet${proposed > 1 ? "s" : ""} inactif${proposed > 1 ? "s" : ""} à trier`);
    if (orphanIdeas > 0)
        parts.push(`${orphanIdeas} idée${orphanIdeas > 1 ? "s" : ""} en attente`);
    const text = parts.length === 0
        ? "Revue de la semaine : tout est à jour, rien à trier. 👌"
        : `Revue de la semaine : ${parts.join(" · ")}. À valider dans « À valider ».`;
    await (0, execute_1.executePushAssistantMessage)(uid, {
        targetDate: today, text: text.slice(0, 179),
        condition: { type: "always" }, expiresAfterDays: 2, priority: 2,
    });
    pushed++;
    return { actions, pushed, skipped: false };
}
// ── Conseil d'Or (Phase E) : alerte sur l'or qui fond ────────────────────────
// Lit l'état d'or + routines + tâches en retard, et pousse 1 message chiffré :
// routines « lancées » non faites aujourd'hui (saignent −1 🪙/j) et tâches Gantt
// en retard (−1 🪙/j). Déterministe, sans LLM.
async function taskGoldReview(uid) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k;
    const actions = [];
    let pushed = 0;
    const today = (0, execute_1.todayInParis)();
    const todayYmd = today.replace(/-/g, "");
    const [actSnap, hpSnap, projSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/activities`).get(),
        db_1.db.collection(`users/${uid}/habitProgress`).get(),
        db_1.db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
    ]);
    // Cibles + noms des routines (habits non supprimées)
    const habitTarget = new Map();
    const habitName = new Map();
    for (const a of actSnap.docs) {
        if (((_a = a.get("type")) !== null && _a !== void 0 ? _a : "time") === "habit" && a.get("deleted") !== true) {
            habitTarget.set(a.id, (_b = a.get("habitTarget")) !== null && _b !== void 0 ? _b : 1);
            habitName.set(a.id, (_c = a.get("name")) !== null && _c !== void 0 ? _c : "routine");
        }
    }
    // Progrès par routine : valeur du jour + nb de jours atteints (or rapporté ≈ ×2)
    const todayVal = new Map();
    const metDays = new Map();
    for (const hp of hpSnap.docs) {
        const aid = hp.get("activityId");
        if (!aid || !habitTarget.has(aid))
            continue;
        const ymd = (_d = hp.get("yyyymmdd")) !== null && _d !== void 0 ? _d : "";
        const val = (_e = hp.get("value")) !== null && _e !== void 0 ? _e : 0;
        const tgt = habitTarget.get(aid);
        if (ymd === todayYmd)
            todayVal.set(aid, val);
        if (val >= tgt)
            metDays.set(aid, ((_f = metDays.get(aid)) !== null && _f !== void 0 ? _f : 0) + 1);
    }
    // Routines lancées (déjà atteintes ≥1 fois) mais NON faites aujourd'hui → saignent
    const bleeding = [];
    for (const [aid, tgt] of habitTarget) {
        const launched = ((_g = metDays.get(aid)) !== null && _g !== void 0 ? _g : 0) > 0;
        const doneToday = ((_h = todayVal.get(aid)) !== null && _h !== void 0 ? _h : 0) >= tgt;
        if (launched && !doneToday) {
            bleeding.push({ name: (_j = habitName.get(aid)) !== null && _j !== void 0 ? _j : "routine", earned: ((_k = metDays.get(aid)) !== null && _k !== void 0 ? _k : 0) * 2 });
        }
    }
    bleeding.sort((a, b) => b.earned - a.earned);
    // Tâches Gantt en retard → −1 🪙/j chacune
    let lateCount = 0;
    for (const doc of projSnap.docs) {
        for (const t of (doc.data().tasks || [])) {
            if (t.status !== "done" && t.status !== "skipped" && t.endDate && t.endDate < today)
                lateCount++;
        }
    }
    if (bleeding.length === 0 && lateCount === 0) {
        return { actions: ["ℹ️ Aucune hémorragie d'or"], pushed: 0, skipped: false };
    }
    const parts = [];
    if (bleeding.length > 0) {
        const top = bleeding[0];
        parts.push(bleeding.length === 1
            ? `⚠️ Ta routine « ${top.name} » (${top.earned} 🪙) va casser — fais-la pour garder +2/j et stopper le −1/j.`
            : `⚠️ ${bleeding.length} routines vont casser (dont « ${top.name} », ${top.earned} 🪙) — fais-les pour stopper le −1/j.`);
    }
    if (lateCount > 0) {
        parts.push(`Tu perds ${lateCount} 🪙/j sur ${lateCount} tâche${lateCount > 1 ? "s" : ""} en retard.`);
    }
    await (0, execute_1.executePushAssistantMessage)(uid, {
        targetDate: today, text: parts.join(" ").slice(0, 179),
        condition: { type: "always" }, expiresAfterDays: 1, priority: 1,
    });
    pushed++;
    actions.push(`🪙 Conseil d'or poussé (${bleeding.length} routine(s), ${lateCount} retard(s))`);
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
// ── Défis du donjon (préparés EN AMONT par Orion, auto-validés côté app) ───────
// Objectifs réels (routine / tâche / temps) pioché dans les données de l'user
// pour le niveau VISÉ (unlockedLevel+1). Écrit dans meta.expeditionChallenges.
// Idempotent : ne régénère que si absent ou si le niveau visé a changé.
async function taskGenerateExpeditionChallenges(uid) {
    var _a, _b, _c, _d;
    const metaRef = db_1.db.doc(`users/${uid}/data/meta`);
    const metaSnap = await metaRef.get();
    const meta = metaSnap.data() || {};
    const unlocked = (_a = meta.unlockedLevel) !== null && _a !== void 0 ? _a : 1;
    const target = Math.max(unlocked, 1) + 1;
    const existing = meta.expeditionChallenges || [];
    if (existing.length > 0) {
        try {
            if (((_b = JSON.parse(existing[0]).level) !== null && _b !== void 0 ? _b : 0) === target) {
                return { actions: [`ℹ️ Défis déjà prêts (niveau ${target})`], pushed: 0, skipped: true };
            }
        }
        catch ( /* malformé → on régénère */_e) { /* malformé → on régénère */ }
    }
    const [actSnap, projSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/activities`).get(),
        db_1.db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
    ]);
    const challenges = [];
    // 1 routine (habit active)
    const habit = actSnap.docs.find((a) => { var _a; return ((_a = a.get("type")) !== null && _a !== void 0 ? _a : "time") === "habit" && a.get("deleted") !== true; });
    if (habit) {
        challenges.push(JSON.stringify({
            level: target, type: "routine", refId: habit.id, target: 3,
            label: `Fais la routine « ${(_c = habit.get("name")) !== null && _c !== void 0 ? _c : "routine"} » pendant 3 jours`,
        }));
    }
    // 1 tâche ouverte (1er projet actif qui en a une)
    let taskAdded = false;
    for (const doc of projSnap.docs) {
        if (taskAdded)
            break;
        for (const t of (doc.data().tasks || [])) {
            if (t.status !== "done" && t.status !== "skipped") {
                challenges.push(JSON.stringify({
                    level: target, type: "task", refId: t.id, target: 1,
                    label: `Termine la tâche « ${t.title} »`,
                }));
                taskAdded = true;
                break;
            }
        }
    }
    // 1 activité temps
    const timeAct = actSnap.docs.find((a) => { var _a; return ((_a = a.get("type")) !== null && _a !== void 0 ? _a : "time") === "time" && a.get("deleted") !== true; });
    if (timeAct) {
        challenges.push(JSON.stringify({
            level: target, type: "time", refId: timeAct.id, target: 60,
            label: `Logue 1h sur « ${(_d = timeAct.get("name")) !== null && _d !== void 0 ? _d : "activité"} »`,
        }));
    }
    if (challenges.length === 0) {
        return { actions: ["ℹ️ Aucune donnée pour générer des défis de donjon"], pushed: 0, skipped: true };
    }
    await metaRef.set({ expeditionChallenges: challenges }, { merge: true });
    return {
        actions: [`🏰 ${challenges.length} défi(s) de donjon préparés (niveau ${target})`],
        pushed: 0, skipped: false,
    };
}
// ── Router ────────────────────────────────────────────────────────────────────
async function runDeterministicTask(uid, taskId) {
    switch (taskId) {
        case "overdue_summary": return taskOverdueSummary(uid);
        case "weekly_deadlines": return taskWeeklyDeadlines(uid);
        case "archive_inactive": return taskArchiveInactiveProjects(uid);
        case "weekly_review": return taskWeeklyReview(uid);
        case "gold_review": return taskGoldReview(uid);
        case "clean_expired": return taskCleanExpiredMessages(uid);
        case "progress_report": return taskProgressReport(uid);
        case "expedition_challenges": return taskGenerateExpeditionChallenges(uid);
        default:
            return { actions: [`Tâche inconnue : ${taskId}`], pushed: 0, skipped: true, reason: `taskId inconnu : ${taskId}` };
    }
}
//# sourceMappingURL=orion_tasks.js.map