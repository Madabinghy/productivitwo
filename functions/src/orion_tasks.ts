import { db, FieldValue } from "./db";
import { executePushAssistantMessage, executeProposeChange, todayInParis, nowInParis } from "./execute";

// ── Helpers préparation la veille ─────────────────────────────────────────────
type SchedBlock = {
  id: string; startTime: string; durationMin: number; title: string;
  category: string; status: string; activityId?: string | null;
  kind?: string; prepForDate?: string | null; prepForBlockId?: string | null;
};

function loadBlocks(snap: FirebaseFirestore.DocumentSnapshot): SchedBlock[] {
  if (!snap.exists) return [];
  return ((snap.data()?.blocks as SchedBlock[]) ?? []).filter((b) => b && b.status !== "deleted");
}

// "07:15" → "7h15" ; "07:00" → "7h"
function hhmmToFr(hm: string): string {
  const [h, m] = hm.split(":");
  const hh = String(parseInt(h, 10));
  return m === "00" ? `${hh}h` : `${hh}h${m}`;
}

function hmToMinutes(hm: string): number {
  const [h, m] = hm.split(":").map((n) => parseInt(n, 10));
  return (h || 0) * 60 + (m || 0);
}

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
  const today = todayInParis();

  // NB : l'ancienne lecture de users/{uid}/dayPlan a été retirée — la
  // collection n'est plus écrite depuis la suppression de DayPlanItem
  // (le scheduling passe par daily_schedules). Seul le retard Gantt compte.
  const projectsSnap = await db.collection(`users/${uid}/projects`)
    .where("status", "==", "active")
    .get();

  const overdueGantt: Array<{ projectTitle: string; projectId: string; taskTitle: string; taskId: string; endDate: string }> = [];
  for (const doc of projectsSnap.docs) {
    const p = doc.data();
    for (const t of (p.tasks || []) as Array<{ id: string; title: string; status: string; endDate?: string }>) {
      if (t.status !== "done" && t.status !== "skipped" && t.endDate && t.endDate < today) {
        overdueGantt.push({ projectTitle: p.title, projectId: p.id, taskTitle: t.title, taskId: t.id, endDate: t.endDate });
      }
    }
  }

  if (overdueGantt.length === 0) {
    await executePushAssistantMessage(uid, {
      targetDate: today, text: "Aucun retard détecté — continue sur cette lancée !",
      condition: { type: "always" }, expiresAfterDays: 1, priority: 3,
    });
    pushed++;
    actions.push("ℹ️ Aucun retard détecté");
  } else {
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

  return { actions, pushed, skipped: false };
}

// ── Deadlines de la semaine ───────────────────────────────────────────────────
export async function taskWeeklyDeadlines(uid: string): Promise<TaskResult> {
  const actions: string[] = [];
  let pushed = 0;
  const today = todayInParis();
  const in7days = todayInParis(new Date(Date.now() + 7 * 24 * 60 * 60 * 1000));

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
  const today = todayInParis();
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

// ── Revue hebdo : PROPOSE d'archiver les projets inactifs (Phase 3) ──────────
// Contrairement à taskArchiveInactiveProjects (archive direct), cette tâche
// respecte « ORION propose, l'utilisateur dispose » : elle écrit des propositions
// archive_project dans orion_proposals (file « À valider »). Idempotente : ne
// reproposera pas un projet ayant déjà une proposition d'archivage en attente.
export async function taskWeeklyReview(uid: string): Promise<TaskResult> {
  const actions: string[] = [];
  let pushed = 0;
  const today = todayInParis();
  const cutoff = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000);

  const [projectsSnap, pendingPropsSnap, captureSnap] = await Promise.all([
    db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
    db.collection(`users/${uid}/orion_proposals`)
      .where("status", "==", "pending").where("kind", "==", "archive_project").get(),
    db.collection(`users/${uid}/captures`).where("status", "==", "pending").get(),
  ]);

  // Projets déjà couverts par une proposition d'archivage en attente
  const alreadyProposed = new Set(
    pendingPropsSnap.docs
      .map((d) => (d.data().payload as { projectId?: string } | undefined)?.projectId)
      .filter((x): x is string => !!x)
  );

  let proposed = 0;
  for (const doc of projectsSnap.docs) {
    const p = doc.data();
    if (alreadyProposed.has(p.id as string)) continue;
    const updated: Date = p.updatedAt?.toDate?.() ?? p.createdAt?.toDate?.() ?? new Date(0);
    const tasks = (p.tasks || []) as Array<{ status: string; endDate?: string }>;
    const hasUrgent = tasks.some((t) => t.status !== "done" && t.status !== "skipped" && t.endDate && t.endDate >= today);
    if (!hasUrgent && updated < cutoff) {
      await executeProposeChange(uid, {
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
  const parts: string[] = [];
  if (proposed > 0) parts.push(`${proposed} projet${proposed > 1 ? "s" : ""} inactif${proposed > 1 ? "s" : ""} à trier`);
  if (orphanIdeas > 0) parts.push(`${orphanIdeas} idée${orphanIdeas > 1 ? "s" : ""} en attente`);

  const text = parts.length === 0
    ? "Revue de la semaine : tout est à jour, rien à trier. 👌"
    : `Revue de la semaine : ${parts.join(" · ")}. À valider dans « À valider ».`;
  await executePushAssistantMessage(uid, {
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
export async function taskGoldReview(uid: string): Promise<TaskResult> {
  const actions: string[] = [];
  let pushed = 0;
  const today = todayInParis();
  const todayYmd = today.replace(/-/g, "");

  const [actSnap, hpSnap, projSnap] = await Promise.all([
    db.collection(`users/${uid}/activities`).get(),
    db.collection(`users/${uid}/habitProgress`).get(),
    db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
  ]);

  // Cibles + noms des routines (habits non supprimées)
  const habitTarget = new Map<string, number>();
  const habitName = new Map<string, string>();
  for (const a of actSnap.docs) {
    if ((a.get("type") ?? "time") === "habit" && a.get("deleted") !== true) {
      habitTarget.set(a.id, (a.get("habitTarget") as number) ?? 1);
      habitName.set(a.id, (a.get("name") as string) ?? "routine");
    }
  }

  // Progrès par routine : valeur du jour + nb de jours atteints (or rapporté ≈ ×2)
  const todayVal = new Map<string, number>();
  const metDays = new Map<string, number>();
  for (const hp of hpSnap.docs) {
    const aid = hp.get("activityId") as string | undefined;
    if (!aid || !habitTarget.has(aid)) continue;
    const ymd = (hp.get("yyyymmdd") as string) ?? "";
    const val = (hp.get("value") as number) ?? 0;
    const tgt = habitTarget.get(aid)!;
    if (ymd === todayYmd) todayVal.set(aid, val);
    if (val >= tgt) metDays.set(aid, (metDays.get(aid) ?? 0) + 1);
  }

  // Routines lancées (déjà atteintes ≥1 fois) mais NON faites aujourd'hui → saignent
  const bleeding: Array<{ name: string; earned: number }> = [];
  for (const [aid, tgt] of habitTarget) {
    const launched = (metDays.get(aid) ?? 0) > 0;
    const doneToday = (todayVal.get(aid) ?? 0) >= tgt;
    if (launched && !doneToday) {
      bleeding.push({ name: habitName.get(aid) ?? "routine", earned: (metDays.get(aid) ?? 0) * 2 });
    }
  }
  bleeding.sort((a, b) => b.earned - a.earned);

  // Tâches Gantt en retard → −1 🪙/j chacune
  let lateCount = 0;
  for (const doc of projSnap.docs) {
    for (const t of (doc.data().tasks || []) as Array<{ status: string; endDate?: string }>) {
      if (t.status !== "done" && t.status !== "skipped" && t.endDate && t.endDate < today) lateCount++;
    }
  }

  if (bleeding.length === 0 && lateCount === 0) {
    return { actions: ["ℹ️ Aucune hémorragie d'or"], pushed: 0, skipped: false };
  }

  const parts: string[] = [];
  if (bleeding.length > 0) {
    const top = bleeding[0];
    parts.push(
      bleeding.length === 1
        ? `⚠️ Ta routine « ${top.name} » (${top.earned} 🪙) va casser — fais-la pour garder +2/j et stopper le −1/j.`
        : `⚠️ ${bleeding.length} routines vont casser (dont « ${top.name} », ${top.earned} 🪙) — fais-les pour stopper le −1/j.`
    );
  }
  if (lateCount > 0) {
    parts.push(`Tu perds ${lateCount} 🪙/j sur ${lateCount} tâche${lateCount > 1 ? "s" : ""} en retard.`);
  }

  await executePushAssistantMessage(uid, {
    targetDate: today, text: parts.join(" ").slice(0, 179),
    condition: { type: "always" }, expiresAfterDays: 1, priority: 1,
  });
  pushed++;
  actions.push(`🪙 Conseil d'or poussé (${bleeding.length} routine(s), ${lateCount} retard(s))`);

  return { actions, pushed, skipped: false };
}

// ── Nettoyer les messages expirés ─────────────────────────────────────────────
export async function taskCleanExpiredMessages(uid: string): Promise<TaskResult> {
  const actions: string[] = [];
  const today = todayInParis();

  const snap = await db.collection(`users/${uid}/assistant_messages`)
    .where("status", "==", "pending").get();

  const batch = db.batch();
  let count = 0;
  for (const doc of snap.docs) {
    const m = doc.data();
    const expireDate = new Date(m.targetDate as string);
    expireDate.setDate(expireDate.getDate() + ((m.expiresAfterDays as number) ?? 2));
    if (todayInParis(expireDate) < today) {
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
  const today = todayInParis();

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

// ── Défis du donjon (préparés EN AMONT par Orion, auto-validés côté app) ───────
// Objectifs réels (routine / tâche / temps) pioché dans les données de l'user
// pour le niveau VISÉ (unlockedLevel+1). Écrit dans meta.expeditionChallenges.
// Idempotent : ne régénère que si absent ou si le niveau visé a changé.
export async function taskGenerateExpeditionChallenges(uid: string): Promise<TaskResult> {
  const metaRef = db.doc(`users/${uid}/data/meta`);
  const metaSnap = await metaRef.get();
  const meta = metaSnap.data() || {};
  const unlocked = (meta.unlockedLevel as number) ?? 1;
  const target = Math.max(unlocked, 1) + 1;

  const existing = (meta.expeditionChallenges as string[]) || [];
  if (existing.length > 0) {
    try {
      if (((JSON.parse(existing[0]).level as number) ?? 0) === target) {
        return { actions: [`ℹ️ Défis déjà prêts (niveau ${target})`], pushed: 0, skipped: true };
      }
    } catch { /* malformé → on régénère */ }
  }

  const [actSnap, projSnap] = await Promise.all([
    db.collection(`users/${uid}/activities`).get(),
    db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
  ]);

  const challenges: string[] = [];

  // 1 routine (habit active)
  const habit = actSnap.docs.find(
    (a) => (a.get("type") ?? "time") === "habit" && a.get("deleted") !== true);
  if (habit) {
    challenges.push(JSON.stringify({
      level: target, type: "routine", refId: habit.id, target: 3,
      label: `Fais la routine « ${habit.get("name") ?? "routine"} » pendant 3 jours`,
    }));
  }

  // 1 tâche ouverte (1er projet actif qui en a une)
  let taskAdded = false;
  for (const doc of projSnap.docs) {
    if (taskAdded) break;
    for (const t of (doc.data().tasks || []) as Array<{ id: string; title: string; status: string }>) {
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
  const timeAct = actSnap.docs.find(
    (a) => (a.get("type") ?? "time") === "time" && a.get("deleted") !== true);
  if (timeAct) {
    challenges.push(JSON.stringify({
      level: target, type: "time", refId: timeAct.id, target: 60,
      label: `Logue 1h sur « ${timeAct.get("name") ?? "activité"} »`,
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

// ── Préparation la veille : rappel du soir (zéro LLM) ─────────────────────────
// Lit le programme de DEMAIN, repère le premier bloc matinal (< 9h30) qui exige
// du matériel/logistique (catégorie personal, domaine Santé/Sport, ou titre
// sport/déplacement/cuisine), et vérifie qu'un bloc de prep lié existe déjà dans
// le programme d'AUJOURD'HUI. S'il manque → pousse un message qui PROPOSE de
// préparer ce soir (il n'écrit pas le bloc : ORION propose, l'utilisateur dispose).
export async function taskPrepReminder(uid: string): Promise<TaskResult> {
  const today = todayInParis();
  const tomorrow = todayInParis(new Date(Date.now() + 24 * 60 * 60 * 1000));

  const [tomorrowSnap, todaySnap, actsSnap, domainsSnap] = await Promise.all([
    db.doc(`users/${uid}/daily_schedules/${tomorrow}`).get(),
    db.doc(`users/${uid}/daily_schedules/${today}`).get(),
    db.collection(`users/${uid}/activities`).get(),
    db.collection(`users/${uid}/domains`).get(),
  ]);

  const tomorrowBlocks = loadBlocks(tomorrowSnap);
  if (tomorrowBlocks.length === 0) {
    return { actions: ["ℹ️ Pas de programme demain — rien à préparer"], pushed: 0, skipped: true };
  }

  // Domaines « préparation-worthy » (santé, sport…) → set d'activityId concernés.
  const healthDomains = new Set(
    domainsSnap.docs
      .filter((d) => /sant|sport|forme|health|fit/i.test((d.get("name") as string) ?? ""))
      .map((d) => d.id)
  );
  const prepWorthyActivity = new Set(
    actsSnap.docs.filter((a) => healthDomains.has((a.get("domainId") as string) ?? "")).map((a) => a.id)
  );
  const titleNeedsPrep = (t: string) =>
    /s[eé]ance|sport|muscu|course|footing|run|piscine|natation|d[eé]placement|train|avion|rendez|cuisine|meal|repas/i.test(t);

  const morning = tomorrowBlocks
    .filter((b) => b.status === "pending" && b.startTime < "09:30")
    .sort((a, b) => a.startTime.localeCompare(b.startTime));

  const target = morning.find(
    (b) =>
      b.category === "personal" ||
      (b.activityId && prepWorthyActivity.has(b.activityId)) ||
      titleNeedsPrep(b.title)
  );

  if (!target) {
    return { actions: ["ℹ️ Aucun bloc matinal à préparer demain"], pushed: 0, skipped: true };
  }

  // Un bloc prep lié existe-t-il déjà (aujourd'hui OU demain) ?
  const alreadyPrepared = [...loadBlocks(todaySnap), ...tomorrowBlocks].some(
    (b) => b.kind === "prep" && b.prepForDate === tomorrow && b.prepForBlockId === target.id
  );
  if (alreadyPrepared) {
    return { actions: [`ℹ️ Prep déjà en place pour « ${target.title} »`], pushed: 0, skipped: true };
  }

  const text = `Demain ${hhmmToFr(target.startTime)} : ${target.title}. Prépare tes affaires ce soir — 3 min, et demain tu n'as plus qu'à sortir.`;
  await executePushAssistantMessage(uid, {
    targetDate: today, text: text.slice(0, 179),
    condition: { type: "always" }, expiresAfterDays: 1, priority: 1,
  });
  return { actions: [`🌙 Rappel prep poussé pour « ${target.title} » (demain ${target.startTime})`], pushed: 1, skipped: false };
}

// ── Préparation la veille : coup de pouce du matin (zéro LLM) ──────────────────
// Si un bloc prep d'HIER est `done` et que son bloc cible d'AUJOURD'HUI est
// encore `pending` → affirme le fait tracké « les affaires sont prêtes depuis
// hier » + compte à rebours vers le bloc.
export async function taskPrepMorningBoost(uid: string): Promise<TaskResult> {
  const today = todayInParis();
  const yesterday = todayInParis(new Date(Date.now() - 24 * 60 * 60 * 1000));

  const [yestSnap, todaySnap] = await Promise.all([
    db.doc(`users/${uid}/daily_schedules/${yesterday}`).get(),
    db.doc(`users/${uid}/daily_schedules/${today}`).get(),
  ]);

  const todayBlocks = loadBlocks(todaySnap);
  const donePreps = loadBlocks(yestSnap).filter(
    (b) => b.kind === "prep" && b.status === "done" && b.prepForDate === today
  );
  if (donePreps.length === 0) {
    return { actions: ["ℹ️ Aucune prep faite hier pour aujourd'hui"], pushed: 0, skipped: true };
  }

  const nowMin = nowInParis().hour * 60 + nowInParis().minute;
  let pushed = 0;
  const actions: string[] = [];
  for (const prep of donePreps) {
    const target = todayBlocks.find((b) => b.id === prep.prepForBlockId && b.status === "pending");
    if (!target) continue;
    const minsUntil = hmToMinutes(target.startTime) - nowMin;
    const whenStr = minsUntil > 0 ? `dans ${minsUntil} min` : "maintenant";
    const text = `Les affaires sont prêtes depuis hier — ${target.title} ${whenStr}. Plus qu'à sortir.`;
    await executePushAssistantMessage(uid, {
      targetDate: today, text: text.slice(0, 179),
      condition: { type: "always" }, expiresAfterDays: 1, priority: 1,
    });
    pushed++;
    actions.push(`☀️ Coup de pouce prep : « ${target.title} » (${whenStr})`);
  }

  if (pushed === 0) {
    return { actions: ["ℹ️ Prep faite mais bloc cible déjà validé"], pushed: 0, skipped: true };
  }
  return { actions, pushed, skipped: false };
}

// ── Router ────────────────────────────────────────────────────────────────────
export async function runDeterministicTask(uid: string, taskId: string): Promise<TaskResult> {
  switch (taskId) {
    case "overdue_summary":        return taskOverdueSummary(uid);
    case "weekly_deadlines":       return taskWeeklyDeadlines(uid);
    case "archive_inactive":       return taskArchiveInactiveProjects(uid);
    case "weekly_review":          return taskWeeklyReview(uid);
    case "gold_review":            return taskGoldReview(uid);
    case "clean_expired":          return taskCleanExpiredMessages(uid);
    case "progress_report":        return taskProgressReport(uid);
    case "expedition_challenges":  return taskGenerateExpeditionChallenges(uid);
    case "prep_reminder":          return taskPrepReminder(uid);
    case "prep_morning_boost":     return taskPrepMorningBoost(uid);
    default:
      return { actions: [`Tâche inconnue : ${taskId}`], pushed: 0, skipped: true, reason: `taskId inconnu : ${taskId}` };
  }
}
