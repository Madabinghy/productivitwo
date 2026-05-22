import { db, FieldValue } from "./db";
import { executePushAssistantMessage } from "./execute";

export type TaskResult = {
  actions: string[];
  pushed: number;
  skipped: boolean;
  reason?: string;
};

// ── Résumé des retards ────────────────────────────────────────────────────────
export async function taskOverdueSummary(uid: string): Promise<TaskResult> {
  const actions: string[] = [];
  let pushed = 0;
  const today = new Date().toISOString().slice(0, 10);
  const todayYmd = today.replace(/-/g, "");

  const [dayPlanSnap, projectsSnap] = await Promise.all([
    db.collection(`users/${uid}/dayPlan`)
      .where("yyyymmdd", "<", todayYmd)
      .where("done", "==", false)
      .get(),
    db.collection(`users/${uid}/projects`)
      .where("status", "==", "active")
      .get(),
  ]);

  const planOverdue = dayPlanSnap.docs
    .map((d) => d.data())
    .filter((it) => it.status !== "archived" && it.status !== "done").length;

  const overdueGantt: Array<{ projectTitle: string; projectId: string; taskTitle: string; taskId: string; endDate: string }> = [];
  for (const doc of projectsSnap.docs) {
    const p = doc.data();
    for (const t of (p.tasks || []) as Array<{ id: string; title: string; status: string; endDate?: string }>) {
      if (t.status !== "done" && t.status !== "skipped" && t.endDate && t.endDate < today) {
        overdueGantt.push({ projectTitle: p.title, projectId: p.id, taskTitle: t.title, taskId: t.id, endDate: t.endDate });
      }
    }
  }

  if (planOverdue === 0 && overdueGantt.length === 0) {
    await executePushAssistantMessage(uid, {
      targetDate: today, text: "Aucun retard détecté — continue sur cette lancée !",
      condition: { type: "always" }, expiresAfterDays: 1, priority: 3,
    });
    pushed++;
    actions.push("ℹ️ Aucun retard détecté");
  } else {
    if (planOverdue > 0) {
      const text = `${planOverdue} action${planOverdue > 1 ? "s" : ""} en retard dans ton plan. Priorise tes 3 essentielles aujourd'hui.`;
      await executePushAssistantMessage(uid, {
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
      await executePushAssistantMessage(uid, {
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
export async function taskWeeklyDeadlines(uid: string): Promise<TaskResult> {
  const actions: string[] = [];
  let pushed = 0;
  const today = new Date().toISOString().slice(0, 10);
  const in7days = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);

  const snap = await db.collection(`users/${uid}/projects`).where("status", "==", "active").get();

  const upcoming: Array<{ projectTitle: string; projectId: string; taskTitle: string; taskId: string; endDate: string }> = [];
  for (const doc of snap.docs) {
    const p = doc.data();
    for (const t of (p.tasks || []) as Array<{ id: string; title: string; status: string; endDate?: string }>) {
      if (t.status !== "done" && t.status !== "skipped" && t.endDate && t.endDate >= today && t.endDate <= in7days)
        upcoming.push({ projectTitle: p.title, projectId: p.id, taskTitle: t.title, taskId: t.id, endDate: t.endDate });
    }
  }

  if (upcoming.length === 0) {
    await executePushAssistantMessage(uid, {
      targetDate: today, text: "Aucune deadline dans les 7 jours. Profites-en pour avancer sur tes tâches en attente.",
      condition: { type: "always" }, expiresAfterDays: 1, priority: 3,
    });
    pushed++;
    actions.push("ℹ️ Aucune deadline imminente");
  } else {
    upcoming.sort((a, b) => a.endDate.localeCompare(b.endDate));
    for (const item of upcoming.slice(0, 3)) {
      const daysLeft = Math.max(1, Math.ceil((new Date(item.endDate).getTime() - Date.now()) / 86400000));
      const text = `Deadline dans ${daysLeft}j : "${item.taskTitle}" (${item.projectTitle}).`;
      await executePushAssistantMessage(uid, {
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
export async function taskArchiveInactiveProjects(uid: string): Promise<TaskResult> {
  const actions: string[] = [];
  let pushed = 0;
  const today = new Date().toISOString().slice(0, 10);
  const cutoff = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000);

  const snap = await db.collection(`users/${uid}/projects`).where("status", "==", "active").get();

  const toArchive: Array<{ id: string; title: string }> = [];
  for (const doc of snap.docs) {
    const p = doc.data();
    const updated: Date = p.updatedAt?.toDate?.() ?? p.createdAt?.toDate?.() ?? new Date(0);
    const tasks = (p.tasks || []) as Array<{ status: string; endDate?: string }>;
    const hasUrgent = tasks.some((t) => t.status !== "done" && t.status !== "skipped" && t.endDate && t.endDate >= today);
    if (!hasUrgent && updated < cutoff) toArchive.push({ id: p.id, title: p.title });
  }

  if (toArchive.length === 0) {
    await executePushAssistantMessage(uid, {
      targetDate: today, text: "Aucun projet inactif à archiver — tous tes projets sont actifs.",
      condition: { type: "always" }, expiresAfterDays: 1, priority: 3,
    });
    pushed++;
    actions.push("ℹ️ Aucun projet inactif");
  } else {
    const batch = db.batch();
    for (const p of toArchive) {
      batch.update(db.collection(`users/${uid}/projects`).doc(p.id), {
        status: "archived", updatedAt: FieldValue.serverTimestamp(),
      });
      actions.push(`🗄 Projet archivé : ${p.title}`);
    }
    await batch.commit();
    const text = toArchive.length === 1
      ? `Projet "${toArchive[0].title}" archivé (inactif depuis 14j).`
      : `${toArchive.length} projets inactifs archivés.`;
    await executePushAssistantMessage(uid, {
      targetDate: today, text: text.slice(0, 179),
      condition: { type: "always" }, expiresAfterDays: 2, priority: 2,
    });
    pushed++;
  }

  return { actions, pushed, skipped: false };
}

// ── Nettoyer les messages expirés ─────────────────────────────────────────────
export async function taskCleanExpiredMessages(uid: string): Promise<TaskResult> {
  const actions: string[] = [];
  const today = new Date().toISOString().slice(0, 10);

  const snap = await db.collection(`users/${uid}/assistant_messages`)
    .where("status", "==", "pending").get();

  const batch = db.batch();
  let count = 0;
  for (const doc of snap.docs) {
    const m = doc.data();
    const expireDate = new Date(m.targetDate as string);
    expireDate.setDate(expireDate.getDate() + ((m.expiresAfterDays as number) ?? 2));
    if (expireDate.toISOString().slice(0, 10) < today) {
      batch.update(doc.ref, { status: "expired" });
      count++;
    }
  }
  if (count > 0) {
    await batch.commit();
    actions.push(`🧹 ${count} message${count > 1 ? "s" : ""} expiré${count > 1 ? "s" : ""} nettoyé${count > 1 ? "s" : ""}`);
  } else {
    actions.push("ℹ️ Aucun message expiré");
  }

  return { actions, pushed: 0, skipped: false };
}

// ── Rapport de progression (sans LLM) ────────────────────────────────────────
export async function taskProgressReport(uid: string): Promise<TaskResult> {
  const actions: string[] = [];
  let pushed = 0;
  const today = new Date().toISOString().slice(0, 10);

  const snap = await db.collection(`users/${uid}/projects`).where("status", "==", "active").get();
  if (snap.empty) {
    await executePushAssistantMessage(uid, {
      targetDate: today, text: "Aucun projet actif pour le moment.",
      condition: { type: "always" }, expiresAfterDays: 1, priority: 3,
    });
    pushed++;
    return { actions: ["ℹ️ Aucun projet actif"], pushed, skipped: false };
  }

  for (const doc of snap.docs.slice(0, 3)) {
    const p = doc.data();
    const tasks = (p.tasks || []) as Array<{ status: string }>;
    const done = tasks.filter((t) => t.status === "done").length;
    const total = tasks.length;
    const pct = total > 0 ? Math.round((done / total) * 100) : 0;
    const text = `${p.title} : ${pct}% (${done}/${total} tâches). ${pct >= 80 ? "Presque fini !" : pct >= 50 ? "Bonne progression." : "À accélérer."}`;
    await executePushAssistantMessage(uid, {
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
export async function runDeterministicTask(uid: string, taskId: string): Promise<TaskResult> {
  switch (taskId) {
    case "overdue_summary":        return taskOverdueSummary(uid);
    case "weekly_deadlines":       return taskWeeklyDeadlines(uid);
    case "archive_inactive":       return taskArchiveInactiveProjects(uid);
    case "clean_expired":          return taskCleanExpiredMessages(uid);
    case "progress_report":        return taskProgressReport(uid);
    default:
      return { actions: [`Tâche inconnue : ${taskId}`], pushed: 0, skipped: true, reason: `taskId inconnu : ${taskId}` };
  }
}
