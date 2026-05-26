import { db, FieldValue } from "./db";
import { v4 as uuidv4 } from "uuid";
import * as admin from "firebase-admin";
import type { ProjectPhase, ProjectTask, PushGanttBody } from "./types";

function normalizePhases(phases?: ProjectPhase[]): ProjectPhase[] {
  if (!phases) return [];
  return phases.map((p) => ({ ...p, id: p.id || uuidv4() }));
}

function normalizeTasks(tasks?: ProjectTask[]): object[] {
  if (!tasks) return [];
  return tasks.map((t) => ({
    ...t,
    id: t.id || uuidv4(),
    isMilestone: t.isMilestone ?? false,
    status: t.status ?? "pending",
    actions: (t.actions ?? []).map((a: string) => ({
      id: uuidv4(),
      title: a,
      done: false,
      doneAt: null,
      createdAt: new Date().toISOString(),
    })),
  }));
}

async function executePushAssistantMessage(
  uid: string,
  args: {
    targetDate: string;
    text: string;
    condition: Record<string, unknown>;
    expiresAfterDays?: number;
    characterName?: string;
    priority?: number;
    action?: { type: string; label?: string; payload?: Record<string, unknown> };
  }
): Promise<string> {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(args.targetDate)) {
    return `Date invalide : ${args.targetDate}. Format attendu : YYYY-MM-DD`;
  }

  const validTypes = [
    "always", "overdue_count", "day_plan_empty", "project_inactive_days",
    "activity_behind_target", "goal_undone_actions", "habit_streak_broken",
    "inbox_overflow", "project_deadline_near", "no_now_focus",
    "routine_completion_low", "day_plan_overloaded", "no_activity_logged_today",
    "project_milestone_today", "week_start", "week_end",
    "activity_streak", "goal_near_deadline", "first_open_of_day", "custom_date",
  ];
  if (!validTypes.includes(args.condition.type as string)) {
    return `Type de condition inconnu : ${args.condition.type}`;
  }

  const id = uuidv4();
  await db.collection(`users/${uid}/assistant_messages`).doc(id).set({
    id,
    targetDate: args.targetDate,
    text: args.text,
    condition: args.condition,
    expiresAfterDays: args.expiresAfterDays ?? 2,
    characterName: args.characterName ?? "ORION",
    priority: args.priority ?? 1,
    action: args.action ?? null,
    status: "pending",
    createdAt: FieldValue.serverTimestamp(),
    createdBy: "claude",
    shownAt: null,
  });

  // Notification push FCM — fire and forget
  sendOrionPushNotification(uid, args.text).catch(() => {});

  return (
    `✅ Message assistant programmé pour le ${args.targetDate}.\n` +
    `• Condition : ${args.condition.type}\n` +
    `• Texte : "${args.text.slice(0, 60)}${args.text.length > 60 ? "…" : ""}"\n` +
    `• messageId : ${id}`
  );
}

async function sendOrionPushNotification(uid: string, text: string): Promise<void> {
  const configSnap = await db.collection(`users/${uid}/orion_config`).doc("main").get();
  if (!configSnap.exists) return;
  const fcmToken = configSnap.data()?.fcmToken as string | undefined;
  if (!fcmToken) return;

  const preview = text.length > 120 ? text.slice(0, 120) + "…" : text;

  await admin.messaging().send({
    token: fcmToken,
    notification: {
      title: "◉ ORION",
      body: preview,
    },
    data: {
      type: "orion_message",
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
          badge: 1,
        },
      },
    },
    android: {
      notification: {
        channelId: "orion_messages",
        priority: "high",
      },
    },
  });
}

async function validateToken(uid: string, rawToken: string): Promise<boolean> {
  const q = await db
    .collection(`users/${uid}/api_tokens`)
    .where("token", "==", rawToken)
    .where("active", "==", true)
    .limit(1)
    .get();
  if (!q.empty) {
    q.docs[0].ref.update({ lastUsedAt: FieldValue.serverTimestamp() });
    return true;
  }
  return false;
}

async function executeGetUserContext(uid: string): Promise<string> {
  // Fenêtre glissante : 7 derniers jours
  const now = new Date();
  const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  const ymdFrom = sevenDaysAgo.toISOString().slice(0, 10).replace(/-/g, "");

  const [domainsSnap, activitiesSnap, goalsSnap,
         dayPlanSnap, habitHitsSnap, sessionsSnap] = await Promise.all([
    db.collection(`users/${uid}/domains`).get(),
    db.collection(`users/${uid}/activities`).get(),
    db.collection(`users/${uid}/goals`).where("status", "==", "active").get(),
    // Actions planifiées et réalisées sur 7 jours
    db.collection(`users/${uid}/dayPlan`)
      .where("yyyymmdd", ">=", ymdFrom)
      .get(),
    // Incréments de routines/habitudes sur 7 jours
    db.collection(`users/${uid}/habitHits`)
      .where("ts", ">=", sevenDaysAgo)
      .get(),
    // Sessions de temps loggué sur 7 jours
    db.collection(`users/${uid}/sessions`)
      .where("startAt", ">=", sevenDaysAgo.toISOString())
      .get(),
  ]);

  const domains = domainsSnap.docs
    .map((d) => d.data())
    .filter((v) => !v.deleted)
    .map((v) => ({ id: v.id, name: v.name }));

  // activityMap inclut TOUTES les activités (y compris archivées) pour résoudre les noms dans timeLogged/habitCompletion
  const activityMap = new Map<string, string>();
  activitiesSnap.docs.forEach((d) => {
    const v = d.data();
    activityMap.set(v.id, v.deleted ? `${v.name} (archivé)` : v.name);
  });

  const activities = activitiesSnap.docs
    .map((d) => d.data())
    .filter((v) => !v.deleted)
    .map((v) => {
    return {
      id: v.id,
      name: v.name,
      type: v.type,
      domainId: v.domainId,
      goalMin: v.goalMin,
      habitFreq: v.habitFreq,
      habitTarget: v.habitTarget,
    };
  });

  const activeGoals = goalsSnap.docs.map((d) => {
    const v = d.data();
    const actions = (v.actions || []) as Array<{ done: boolean }>;
    return {
      id: v.id,
      title: v.title,
      domainId: v.domainId,
      dueDate: v.dueDate || null,
      progress: `${actions.filter((a) => a.done).length}/${actions.length}`,
    };
  });

  // ── Réalisé des 7 derniers jours ──────────────────────────────────────────

  // Actions complétées (dayPlan done)
  const completedActions = dayPlanSnap.docs
    .map((d) => d.data())
    .filter((it) => it.done)
    .map((it) => ({
      title: it.title,
      date: it.yyyymmdd,
      domainId: it.domainId || null,
    }));

  // Actions planifiées non faites (pour identifier les écarts)
  const pendingActions = dayPlanSnap.docs
    .map((d) => d.data())
    .filter((it) => !it.done && !it.archived && it.status !== "archived")
    .map((it) => ({ title: it.title, date: it.yyyymmdd }));

  // Taux de complétion des habitudes/routines (habitHits groupés par habitId)
  const hitsByHabit = new Map<string, number>();
  for (const doc of habitHitsSnap.docs) {
    const v = doc.data();
    hitsByHabit.set(v.habitId, (hitsByHabit.get(v.habitId) || 0) + 1);
  }
  const habitCompletion = Array.from(hitsByHabit.entries()).map(([id, count]) => ({
    activityId: id,
    name: activityMap.get(id) || id,
    hitsLast7Days: count,
  }));

  // Temps loggué par activité (sessions)
  const minByActivity = new Map<string, number>();
  for (const doc of sessionsSnap.docs) {
    const v = doc.data();
    if (!v.endAt) continue;
    const start = new Date(v.startAt);
    const end = new Date(v.endAt);
    const mins = Math.round((end.getTime() - start.getTime()) / 60000);
    if (mins > 0) {
      minByActivity.set(v.activityId,
        (minByActivity.get(v.activityId) || 0) + mins);
    }
  }
  const timeLogged = Array.from(minByActivity.entries()).map(([id, mins]) => ({
    activityId: id,
    name: activityMap.get(id) || id,
    minutesLast7Days: mins,
    hoursLast7Days: Math.round(mins / 6) / 10, // arrondi 1 décimale
  }));

  const recentActivity = {
    period: "7 derniers jours",
    completedActions,
    pendingActions,
    habitCompletion,
    timeLogged,
  };

  const coachingRules = {
    _instructions: [
      "AVANT de commencer tout travail long (programme, bilan, alignement Gantt) : annonce à l'utilisateur que ça prend ~1-2 min et que tu envoies une notification quand c'est prêt.",
      "QUAND l'utilisateur demande un programme (musculation, nutrition, formation, journée…) : demande-lui d'abord s'il veut que tu vérifies son agenda pour intégrer des créneaux concrets. Si oui : list_events → propose des créneaux → create_event après accord.",
      "APRÈS chaque save_document : envoie une push_notification pour informer l'utilisateur.",
      "QUAND tu modifies un projet Gantt (push_gantt, update_project, update_task_status) : appelle get_documents(projectId) et mets à jour le programme HTML associé via save_document en passant le documentId existant (évite les doublons).",
      "POUR créer un programme : appelle toujours get_document_template d'abord, génère le HTML, montre-le à l'utilisateur et attends sa validation avant de créer quoi que ce soit dans Productivitwo.",
      "CONVENTION CALENDRIER : quand tu crées un événement Google Calendar dans le cadre d'une session Productivitwo, ajoute ' - Productivitwo' à la fin du titre (ex: 'Séance musculation - Productivitwo'). Cela te permet d'identifier les events que tu peux modifier librement lors d'une réorganisation. Les events sans ' - Productivitwo' ont été créés par l'utilisateur ou hors contexte Productivitwo : ne les modifie pas sans demander confirmation explicite.",
      "FICHIERS DE TÂCHE : quand tu crées ou sauvegardes un document avec save_document, associe-le toujours à la tâche Gantt concernée via taskId (obtenu depuis get_project → tasks[].id). Choisis la category appropriée : 'programme' pour un plan structuré, 'brief' pour un cahier des charges, 'recherche' pour une analyse/veille, 'livrable' pour un output final, 'notes' pour des notes de travail. Avant de créer un nouveau document, vérifie via get_documents(taskId) si un document de même category existe déjà pour éviter les doublons — si oui, mets-le à jour via documentId.",
      "PROPOSITIONS DE FIN DE SESSION : après avoir terminé une action significative (programme créé, Gantt mis à jour, bilan fait, messages ORION programmés…), propose toujours 2 à 3 suites logiques sous forme de liste numérotée courte. " +
      "Adapte les options à ce qui vient d'être fait. Exemples pertinents selon le contexte : " +
      "• 'Programme ton plan du jour' (si pas encore fait aujourd'hui) " +
      "• 'Mettre à jour tes priorités Gantt' (si des tâches sont en retard) " +
      "• 'Faire le bilan de la semaine' (si c'est vendredi ou fin de sprint) " +
      "• 'Programmer des messages ORION pour la semaine' (si pas encore fait) " +
      "• 'Créer les routines liées à ce programme' (si un programme vient d'être créé) " +
      "• 'Aligner ton agenda Google Calendar' (si des créneaux sont à bloquer) " +
      "• 'Voir les projets en veille' (si tu as archivé quelque chose) " +
      "Formule-les en une ligne, sans description. Ne propose pas une option déjà réalisée dans la session.",
      "ASSISTANT ORION — RÈGLE PROACTIVE : après chaque appel get_user_context, appelle D'ABORD get_assistant_messages pour voir ce qui est déjà programmé — ne recrée jamais un message avec la même condition et la même période. Ensuite programme systématiquement 2 à 4 messages pour l'assistant via push_assistant_message, sans attendre que l'utilisateur le demande. " +
      "Choisis des dates et conditions pertinentes selon le contexte analysé. " +
      "Pour chaque message avec une tâche ou projet précis, ajoute TOUJOURS une action ciblée : " +
      "• open_gantt_task(projectId, taskId) pour une tâche Gantt urgente ou un jalon — c'est le plus utile, ça ouvre la fiche directement ; " +
      "• open_project(projectId) pour une deadline de projet ou un projet inactif ; " +
      "• open_day_plan pour les retards ou le plan vide ; " +
      "• open_goals pour les objectifs GTD en souffrance. " +
      "Pour obtenir les taskId, appelle get_project(projectId) — tasks[].id. " +
      "Exemples de messages pertinents à programmer : deadline dans 3 jours (condition: project_deadline_near), tâche en retard (overdue_count), jalon imminent (project_milestone_today), activité sous objectif (activity_behind_target), début de semaine (week_start). " +
      "Ne programme jamais deux messages avec la même condition pour la même période.",
    ],
  };

  return JSON.stringify(
    { ...coachingRules, domains, activities, activeGoals, recentActivity },
    null, 2
  );
}

async function executeUpdateActivityGoal(
  uid: string,
  activityId: string,
  updates: { goalMin?: number; habitTarget?: number; habitFreq?: number }
): Promise<string> {
  const ref = db.collection(`users/${uid}/activities`).doc(activityId);
  const snap = await ref.get();
  if (!snap.exists) return `Activité introuvable : ${activityId}`;

  const patch: Record<string, unknown> = {};
  if (updates.goalMin !== undefined) patch.goalMin = updates.goalMin;
  if (updates.habitTarget !== undefined) patch.habitTarget = updates.habitTarget;
  if (updates.habitFreq !== undefined) patch.habitFreq = updates.habitFreq;

  await ref.update(patch);
  const name = snap.data()?.name ?? activityId;
  return `✅ Objectif de "${name}" mis à jour. Visible dans Productivitwo à la prochaine synchronisation.`;
}

async function executeCreateRoutine(
  uid: string,
  args: { name: string; domainId: string; unit?: string; habitFreq?: number; habitTarget?: number }
): Promise<string> {
  const id = uuidv4();
  await db.collection(`users/${uid}/activities`).doc(id).set({
    id,
    name: args.name,
    domainId: args.domainId,
    type: "habit",
    role: "generic",
    goalMin: 1,
    unit: args.unit ?? null,
    habitFreq: args.habitFreq ?? 0,
    habitTarget: args.habitTarget ?? 1,
    manualTarget: false,
    autoTune: true,
    createdAt: FieldValue.serverTimestamp(),
    lastTuneAt: null,
    order: 0,
    iconCode: null,
    deleted: false,
  });
  return `✅ Routine "${args.name}" créée (tracking habitude). Elle apparaîtra dans Productivitwo à la prochaine synchronisation.`;
}


async function executeAddToDayPlan(
  uid: string,
  args: {
    title: string;
    date: string;
    domainId?: string;
    activityId?: string;
    projectId?: string;
    projectTaskId?: string;
  }
): Promise<string> {
  // Valider le format de date
  if (!/^\d{4}-\d{2}-\d{2}$/.test(args.date)) {
    return `Date invalide : ${args.date}. Format attendu : YYYY-MM-DD`;
  }
  const yyyymmdd = args.date.replace(/-/g, "");

  const id = uuidv4();
  await db.collection(`users/${uid}/dayPlan`).doc(id).set({
    id,
    kind: "action",
    title: args.title,
    yyyymmdd,
    done: false,
    doneCount: 0,
    allDay: false,
    isNowFocus: false,
    order: 9999,
    toPlan: false,
    archived: false,
    status: "active",
    createdAt: FieldValue.serverTimestamp(),
    domainId: args.domainId || null,
    activityId: args.activityId || null,
    projectId: args.projectId || null,
    projectTaskId: args.projectTaskId || null,
  });

  return `✅ "${args.title}" ajouté au plan du ${args.date}.`;
}

async function executeGetDayBlocks(uid: string): Promise<string> {
  const snap = await db.collection(`users/${uid}/blocks`).orderBy("order").get();
  if (snap.empty) return "Aucun bloc de journée configuré.";

  const blocks = snap.docs.map((d) => {
    const v = d.data();
    return {
      id: v.id,
      name: v.name,
      emoji: v.emoji || null,
      order: v.order,
      startHour: v.startHour ?? null,
      startMinute: v.startMinute ?? null,
      activityIds: v.activityIds || [],
    };
  });

  return JSON.stringify({ blocks }, null, 2);
}

async function executeGetDayPlan(uid: string, date: string): Promise<string> {
  const yyyymmdd = date.replace(/-/g, "");
  const snap = await db.collection(`users/${uid}/dayPlan`)
    .where("yyyymmdd", "==", yyyymmdd)
    .get();

  if (snap.empty) return `Aucune action planifiée le ${date}.`;

  const items = snap.docs
    .map((d) => d.data())
    .filter((v) => !v.archived && v.status !== "archived")
    .map((v) => ({
      id: v.id,
      title: v.title,
      done: v.done,
      blockId: v.blockId || null,
      domainId: v.domainId || null,
      activityId: v.activityId || null,
      status: v.status || "active",
      order: v.order || 0,
      checklist: (v.checklist || []).map((c: Record<string, unknown>) => ({
        id: c.id,
        title: c.title,
        done: c.done ?? false,
      })),
    }))
    .sort((a, b) => a.order - b.order);

  const done = items.filter((it) => it.done).length;
  return JSON.stringify({
    date,
    summary: `${done}/${items.length} actions faites`,
    items,
  }, null, 2);
}

async function executePlanDay(
  uid: string,
  date: string,
  items: Array<{
    title: string;
    blockId?: string;
    domainId?: string;
    activityId?: string;
    projectId?: string;
    projectTaskId?: string;
    durationNote?: string;
  }>,
  clearExisting: boolean
): Promise<string> {
  const yyyymmdd = date.replace(/-/g, "");

  if (clearExisting) {
    // Supprimer les items non-faits du jour
    const existing = await db.collection(`users/${uid}/dayPlan`)
      .where("yyyymmdd", "==", yyyymmdd)
      .where("done", "==", false)
      .get();
    const batch = db.batch();
    for (const doc of existing.docs) batch.delete(doc.ref);
    if (!existing.empty) await batch.commit();
  }

  const addBatch = db.batch();
  items.forEach((item, i) => {
    const id = uuidv4();
    const title = item.durationNote
      ? `${item.title} (${item.durationNote})`
      : item.title;
    addBatch.set(db.collection(`users/${uid}/dayPlan`).doc(id), {
      id,
      kind: "action",
      title,
      yyyymmdd,
      done: false,
      doneCount: 0,
      allDay: false,
      isNowFocus: false,
      order: 9000 + i,
      toPlan: false,
      archived: false,
      status: "active",
      createdAt: FieldValue.serverTimestamp(),
      blockId: item.blockId || null,
      domainId: item.domainId || null,
      activityId: item.activityId || null,
      projectId: item.projectId || null,
      projectTaskId: item.projectTaskId || null,
    });
  });
  await addBatch.commit();

  return (
    `✅ Programme du ${date} créé — ${items.length} action(s) planifiée(s).\n` +
    items.map((it, i) => `  ${i + 1}. ${it.title}${it.blockId ? ` → bloc ${it.blockId}` : ""}`).join("\n")
  );
}

async function executeCreateActivity(
  uid: string,
  args: { name: string; domainId: string; goalMin?: number }
): Promise<string> {
  const id = uuidv4();
  await db.collection(`users/${uid}/activities`).doc(id).set({
    id,
    name: args.name,
    domainId: args.domainId,
    type: "time",
    role: "generic",
    goalMin: args.goalMin ?? 1,
    unit: null,
    habitFreq: null,
    habitTarget: null,
    manualTarget: false,
    autoTune: true,
    createdAt: FieldValue.serverTimestamp(),
    lastTuneAt: null,
    order: 0,
    iconCode: null,
    deleted: false,
  });
  return `✅ Activité "${args.name}" créée (tracking temps). Elle apparaîtra dans Productivitwo à la prochaine synchronisation.`;
}

async function executeDeleteAction(uid: string, actionId: string): Promise<string> {
  const ref = db.collection(`users/${uid}/dayPlan`).doc(actionId);
  const snap = await ref.get();
  if (!snap.exists) return `Action introuvable : ${actionId}`;
  const title = snap.data()?.title ?? actionId;
  // Archiver plutôt que supprimer pour que le merge Flutter respecte la suppression
  await ref.update({ archived: true, status: "archived" });
  return `✅ Action "${title}" supprimée du plan.`;
}

function executeGetDocumentTemplate(): string {
  return `<!DOCTYPE html>
<html lang="fr"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>{{TITRE}}</title>
<link href="https://fonts.googleapis.com/css2?family=Bebas+Neue&family=DM+Sans:ital,wght@0,300;0,400;0,600;1,400&display=swap" rel="stylesheet">
<style>
:root{--bg:#0f0f0f;--surf:#181818;--card:#1f1f1f;--gold:{{COULEUR_ACCENT}};--red:#ff5c35;--txt:#f0ece0;--muted:#747070;--border:#2a2a2a}
/* COULEUR_ACCENT = adapter au domaine : sport=#e8c94a | business=#4ae8b0 | santé=#e84a7a | mental=#7a8fe8 */
*{margin:0;padding:0;box-sizing:border-box}body{background:var(--bg);color:var(--txt);font-family:'DM Sans',sans-serif;font-size:15px;line-height:1.65}
.hero{background:var(--surf);border-bottom:1px solid var(--border);padding:52px 20px 40px;position:relative;overflow:hidden}
.hero::after{content:'';position:absolute;top:-60px;right:-60px;width:280px;height:280px;background:radial-gradient(circle,rgba(var(--gold-rgb),.13) 0%,transparent 70%);pointer-events:none}
.hero-tag{font-family:'Bebas Neue',sans-serif;font-size:11px;letter-spacing:4px;color:var(--gold);margin-bottom:10px}
.hero-title{font-family:'Bebas Neue',sans-serif;font-size:clamp(54px,14vw,96px);line-height:.9;margin-bottom:16px}
.hero-title em{color:var(--gold);font-style:normal}
.hero-sub{color:var(--muted);font-size:14px;max-width:420px}
.stats{display:flex;border-bottom:1px solid var(--border);overflow-x:auto;scrollbar-width:none}
.s{flex:1;min-width:90px;padding:18px 12px;border-right:1px solid var(--border);text-align:center}
.s:last-child{border-right:none}
.sv{font-family:'Bebas Neue',sans-serif;font-size:30px;color:var(--gold);display:block;line-height:1}
.sl{font-size:10px;letter-spacing:1.5px;text-transform:uppercase;color:var(--muted);margin-top:3px}
.wrap{max-width:660px;margin:0 auto;padding:28px 18px 60px}
.sec{margin-bottom:36px}
.sec-head{display:flex;align-items:center;gap:10px;margin-bottom:14px;padding-bottom:8px;border-bottom:1px solid var(--border)}
.sec-n{font-family:'Bebas Neue',sans-serif;font-size:11px;letter-spacing:3px;color:var(--gold)}
.sec-t{font-family:'Bebas Neue',sans-serif;font-size:20px;letter-spacing:1px}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:9px;margin-bottom:12px}
.ic{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:14px}
.ic.gold{border-color:rgba(232,201,74,.3);background:rgba(232,201,74,.05)}
.ic-tag{font-size:10px;letter-spacing:1.5px;text-transform:uppercase;color:var(--muted);margin-bottom:6px}
.ic-val{font-family:'Bebas Neue',sans-serif;font-size:28px;color:var(--gold);line-height:1}
.ic-sub{font-size:12px;color:var(--muted);margin-top:3px}
.note{background:rgba(232,201,74,.06);border:1px solid rgba(232,201,74,.2);border-radius:8px;padding:14px 16px;font-size:13px;color:var(--txt)}
.note strong{color:var(--gold)}
.phase{background:var(--card);border:1px solid var(--border);border-radius:10px;margin-bottom:10px;overflow:hidden}
.ph{display:flex;align-items:center;gap:12px;padding:15px 16px;cursor:pointer;user-select:none}
.pn{font-family:'Bebas Neue',sans-serif;font-size:12px;letter-spacing:2px;color:var(--gold);background:rgba(232,201,74,.1);border:1px solid rgba(232,201,74,.2);padding:2px 10px;border-radius:4px;white-space:nowrap}
.pt{font-weight:600;flex:1;font-size:14px}.pd{font-size:12px;color:var(--muted)}.pa{color:var(--muted);font-size:11px;transition:transform .2s}
.phase.open .pa{transform:rotate(180deg)}.pb{display:none;padding:0 16px 16px;border-top:1px solid var(--border)}.phase.open .pb{display:block}
.tabs{display:flex;gap:6px;margin:14px 0 10px;overflow-x:auto;scrollbar-width:none;padding-bottom:2px}.tabs::-webkit-scrollbar{display:none}
.tab{font-size:12px;font-weight:600;padding:5px 14px;border-radius:4px;border:1px solid var(--border);background:transparent;color:var(--muted);cursor:pointer;white-space:nowrap;font-family:'DM Sans',sans-serif;transition:all .15s}
.tab.on{background:var(--gold);color:#0f0f0f;border-color:var(--gold)}.wc{display:none}.wc.on{display:block}
.day{background:var(--surf);border:1px solid var(--border);border-radius:8px;margin-bottom:10px;overflow:hidden}
.dh{display:flex;align-items:center;gap:10px;padding:9px 14px;border-bottom:1px solid var(--border)}
.db{font-family:'Bebas Neue',sans-serif;font-size:11px;letter-spacing:1px;padding:2px 10px;border-radius:3px;background:var(--red);color:#fff}
.dn{font-weight:600;font-size:14px}.df{font-size:12px;color:var(--muted)}
table{width:100%;border-collapse:collapse;font-size:13px}
th{text-align:left;padding:6px 14px;font-size:10px;letter-spacing:1.5px;text-transform:uppercase;color:var(--muted);font-weight:500}
td{padding:8px 14px;border-top:1px solid var(--border);vertical-align:top}
tr:hover td{background:rgba(255,255,255,.02)}
.en{font-weight:500}.et{font-size:11px;color:var(--muted);margin-top:2px}
.sr{font-family:'Bebas Neue',sans-serif;font-size:16px;color:var(--gold);white-space:nowrap}.rt{font-size:12px;color:var(--muted);white-space:nowrap}
.tl{list-style:none}.tl li{display:flex;gap:10px;padding:8px 0;border-bottom:1px solid var(--border);font-size:14px}.tl li:last-child{border-bottom:none}
.ti{color:var(--gold);flex-shrink:0;font-size:16px}
.timeline{display:flex;flex-direction:column;gap:0}.trow{display:flex;align-items:stretch;gap:0}
.tline{display:flex;flex-direction:column;align-items:center;width:32px;flex-shrink:0}
.tdot{width:12px;height:12px;border-radius:50%;background:var(--gold);flex-shrink:0;margin-top:4px}.tbar{flex:1;width:2px;background:var(--border)}
.trow:last-child .tbar{display:none}.tcont{flex:1;padding:0 0 20px 14px}
.tmonth{font-family:'Bebas Neue',sans-serif;font-size:18px;letter-spacing:1px;color:var(--gold);line-height:1}
.tdesc{font-size:13px;color:var(--muted);margin-top:4px}.tkg{font-size:13px;color:var(--txt);margin-top:2px}
.footer{text-align:center;padding:28px 18px;color:var(--muted);font-size:12px;border-top:1px solid var(--border)}
</style></head><body>

<!-- HERO : adapter TITRE, SOUS-TITRE, TAG -->
<div class="hero">
  <div class="hero-tag">■ {{TAG}}</div>
  <h1 class="hero-title">{{TITRE_LIGNE1}}<br>{{TITRE_LIGNE2_EM}}</h1>
  <p class="hero-sub">{{SOUS_TITRE_PROFIL}}</p>
</div>

<!-- STATS : 5 métriques clés du programme -->
<div class="stats">
  <div class="s"><span class="sv">{{S1_VAL}}</span><div class="sl">{{S1_LABEL}}</div></div>
  <div class="s"><span class="sv">{{S2_VAL}}</span><div class="sl">{{S2_LABEL}}</div></div>
  <div class="s"><span class="sv">{{S3_VAL}}</span><div class="sl">{{S3_LABEL}}</div></div>
  <div class="s"><span class="sv">{{S4_VAL}}</span><div class="sl">{{S4_LABEL}}</div></div>
  <div class="s"><span class="sv">{{S5_VAL}}</span><div class="sl">{{S5_LABEL}}</div></div>
</div>

<div class="wrap">
<!-- SECTIONS : reproduire le pattern sec-head + contenu adapté au programme -->
<!-- Phases avec .phase.open + accordéons toggle() + onglets switchTab() -->
<!-- Timeline mois par mois + règles d'or en liste .tl -->
</div>

<div class="footer">{{FOOTER_TEXT}}</div>

<script>
function toggle(id){document.getElementById(id).classList.toggle('open')}
function switchTab(phase,key,btn){
  document.querySelectorAll('#'+phase+' .wc').forEach(w=>w.classList.remove('on'));
  btn.parentElement.querySelectorAll('.tab').forEach(t=>t.classList.remove('on'));
  btn.classList.add('on');
  var t=document.getElementById(phase+'-'+key);if(t)t.classList.add('on');
}
window.addEventListener('load',function(){
  var dots=document.querySelectorAll('.tdot');
  dots.forEach((d,i)=>{d.style.opacity='0';d.style.transform='scale(0)';d.style.transition='opacity .3s,transform .3s';setTimeout(()=>{d.style.opacity='1';d.style.transform='scale(1)'},200+i*120)});
});
</script></body></html>

INSTRUCTIONS D'ADAPTATION :
- Remplacer tous les {{PLACEHOLDER}} par le contenu réel
- {{COULEUR_ACCENT}} : sport=#e8c94a | business=#4ae8b0 | santé=#e84a7a | mental=#7a8fe8 | général=#e8c94a
- Reproduire la structure complète : hero + stats + sections numérotées + phases accordéon + timeline + règles
- Chaque phase doit avoir ses onglets avec les détails complets (exercices, séries, repos)
- NE PAS simplifier — le programme complet, pas un résumé`;
}

async function executeSaveDocument(
  uid: string,
  args: { title: string; content: string; projectId?: string; taskId?: string; category?: string; documentId?: string; domainId?: string; subtitle?: string }
): Promise<string> {
  const id = args.documentId || uuidv4();
  const isUpdate = !!args.documentId;
  await db.collection(`users/${uid}/documents`).doc(id).set({
    id,
    title: args.title,
    content: args.content,
    projectId: args.projectId || null,
    taskId: args.taskId || null,
    category: args.category || "notes",
    domainId: args.domainId || null,
    subtitle: args.subtitle || null,
    type: "html",
    ...(isUpdate ? { updatedAt: FieldValue.serverTimestamp() } : { createdAt: FieldValue.serverTimestamp() }),
  }, { merge: true });
  return `✅ Document "${args.title}" ${isUpdate ? "mis à jour" : "sauvegardé"} (id: ${id}, category: ${args.category || "notes"}${args.taskId ? `, taskId: ${args.taskId}` : ""}).`;
}

async function executeGetDocuments(uid: string, projectId?: string, taskId?: string): Promise<string> {
  const snap = await db.collection(`users/${uid}/documents`).orderBy("createdAt", "desc").get();
  if (snap.empty) return "Aucun document sauvegardé.";

  const docs = snap.docs
    .map((d) => d.data())
    .filter((d) => !projectId || d.projectId === projectId)
    .filter((d) => !taskId || d.taskId === taskId)
    .map((d) => ({
      id: d.id,
      title: d.title,
      subtitle: d.subtitle || null,
      category: d.category || "notes",
      projectId: d.projectId || null,
      taskId: d.taskId || null,
      createdAt: d.createdAt?.toDate?.()?.toISOString?.() || null,
      updatedAt: d.updatedAt?.toDate?.()?.toISOString?.() || null,
      content: d.content,
    }));

  if (!docs.length) return taskId ? "Aucun document pour cette tâche." : "Aucun document pour ce projet.";
  return JSON.stringify(docs, null, 2);
}

async function executeGetArchives(uid: string): Promise<string> {
  const [domainsSnap, activitiesSnap] = await Promise.all([
    db.collection(`users/${uid}/domains`).where("deleted", "==", true).get(),
    db.collection(`users/${uid}/activities`).where("deleted", "==", true).get(),
  ]);

  const domains = domainsSnap.docs.map((d) => ({ id: d.id, name: d.data().name }));
  const activities = activitiesSnap.docs.map((d) => ({
    id: d.id, name: d.data().name, domainId: d.data().domainId ?? null,
  }));

  if (!domains.length && !activities.length)
    return "Aucun élément archivé — tout est propre.";

  return JSON.stringify({ domains, activities }, null, 2);
}

async function executeRestoreItem(
  uid: string,
  collection: string,
  itemId: string
): Promise<string> {
  const ref = db.collection(`users/${uid}/${collection}`).doc(itemId);
  const snap = await ref.get();
  if (!snap.exists) return `Élément introuvable : ${itemId}`;
  const label = snap.data()?.name ?? snap.data()?.title ?? itemId;
  await ref.update({ deleted: false });
  return `✅ "${label}" restauré dans ${collection}.`;
}


async function executeCreateDomain(
  uid: string,
  args: { name: string; goalMinDay?: number; autoGoal?: boolean; colorValue?: number }
): Promise<string> {
  const id = uuidv4();
  await db.collection(`users/${uid}/domains`).doc(id).set({
    id,
    name: args.name,
    goalMinDay: args.goalMinDay ?? null,
    autoGoal: args.autoGoal ?? true,
    colorValue: args.colorValue ?? null,
    createdAt: FieldValue.serverTimestamp(),
  });
  return `✅ Domaine "${args.name}" créé (id: ${id}). Il apparaîtra dans Productivitwo à la prochaine synchronisation.`;
}

async function executeDeleteDomain(uid: string, domainId: string): Promise<string> {
  const ref = db.collection(`users/${uid}/domains`).doc(domainId);
  const snap = await ref.get();
  if (!snap.exists) return `Domaine introuvable : ${domainId}`;
  const name = snap.data()?.name ?? domainId;

  await ref.update({ deleted: true });

  // Cascade : soft-delete toutes les activités du domaine
  const activitiesSnap = await db.collection(`users/${uid}/activities`)
    .where("domainId", "==", domainId)
    .get();

  let deletedActivities = 0;

  if (!activitiesSnap.empty) {
    const actBatch = db.batch();
    for (const doc of activitiesSnap.docs) actBatch.update(doc.ref, { deleted: true });
    await actBatch.commit();
    deletedActivities = activitiesSnap.size;

  }

  const details = [
    deletedActivities > 0 ? `${deletedActivities} activité(s)` : null,
  ].filter(Boolean).join(", ");

  return `✅ Domaine "${name}" supprimé${details ? ` (cascade : ${details})` : ""}.`;
}

async function executeDeleteActivity(uid: string, activityId: string): Promise<string> {
  const ref = db.collection(`users/${uid}/activities`).doc(activityId);
  const snap = await ref.get();
  if (!snap.exists) return `Activité introuvable : ${activityId}`;
  const name = snap.data()?.name ?? activityId;

  await ref.update({ deleted: true });

  // Délie les day plan items non faits
  const planSnap = await db.collection(`users/${uid}/dayPlan`)
    .where("activityId", "==", activityId)
    .where("done", "==", false)
    .get();
  if (!planSnap.empty) {
    const batch = db.batch();
    for (const doc of planSnap.docs) batch.update(doc.ref, { activityId: null });
    await batch.commit();
  }

  const details = planSnap.size > 0 ? `${planSnap.size} action(s) du plan déliée(s)` : null;

  return `✅ Activité "${name}" supprimée${details ? ` (cascade : ${details})` : ""}.`;
}

async function executeUpdateProject(
  uid: string,
  projectId: string,
  updates: { domainId?: string; title?: string; description?: string; status?: string }
): Promise<string> {
  const ref = db.collection(`users/${uid}/projects`).doc(projectId);
  const snap = await ref.get();
  if (!snap.exists) return `Projet introuvable : ${projectId}`;
  const title = updates.title ?? (snap.data()?.title ?? projectId);

  const patch: Record<string, unknown> = { updatedAt: FieldValue.serverTimestamp() };
  if (updates.domainId  !== undefined) patch.domainId    = updates.domainId;
  if (updates.title     !== undefined) patch.title       = updates.title;
  if (updates.description !== undefined) patch.description = updates.description;
  if (updates.status    !== undefined) patch.status      = updates.status;

  await ref.update(patch);
  return `✅ Projet "${title}" mis à jour.`;
}

async function executeUpdateTaskStatus(
  uid: string,
  projectId: string,
  taskId: string,
  status: string
): Promise<string> {
  const ref = db.collection(`users/${uid}/projects`).doc(projectId);
  const snap = await ref.get();
  if (!snap.exists) return `Projet introuvable : ${projectId}`;

  const data = snap.data() as Record<string, unknown>;
  const tasks = (data.tasks || []) as Array<Record<string, unknown>>;
  const idx = tasks.findIndex((t) => t.id === taskId);
  if (idx === -1) return `Tâche introuvable : ${taskId}`;

  tasks[idx] = { ...tasks[idx], status };
  await ref.update({ tasks, updatedAt: FieldValue.serverTimestamp() });

  const taskTitle = tasks[idx].title ?? taskId;
  const emoji = status === "done" ? "✅" : status === "skipped" ? "⏭️" : "🔄";
  return `${emoji} Tâche "${taskTitle}" → ${status}.`;
}

async function executeUpdateActivity(
  uid: string,
  activityId: string,
  updates: {
    name?: string;
    domainId?: string;
    goalMin?: number;
    unit?: string;
    habitFreq?: number;
    habitTarget?: number;
  }
): Promise<string> {
  const ref = db.collection(`users/${uid}/activities`).doc(activityId);
  const snap = await ref.get();
  if (!snap.exists) return `Activité introuvable : ${activityId}`;
  const currentName = snap.data()?.name ?? activityId;

  const patch: Record<string, unknown> = {};
  if (updates.name !== undefined) patch.name = updates.name;
  if (updates.domainId !== undefined) patch.domainId = updates.domainId;
  if (updates.goalMin !== undefined) patch.goalMin = updates.goalMin;
  if (updates.unit !== undefined) patch.unit = updates.unit;
  if (updates.habitFreq !== undefined) patch.habitFreq = updates.habitFreq;
  if (updates.habitTarget !== undefined) patch.habitTarget = updates.habitTarget;

  await ref.update(patch);
  return `✅ Activité "${currentName}" mise à jour.`;
}

async function executeLinkGoalToTask(
  uid: string,
  goalId: string,
  projectId: string | null,
  projectTaskId: string | null
): Promise<string> {
  const ref = db.collection(`users/${uid}/goals`).doc(goalId);
  const snap = await ref.get();
  if (!snap.exists) return `Objectif introuvable : ${goalId}`;
  const title = snap.data()?.title ?? goalId;

  await ref.update({ projectId: projectId ?? null, projectTaskId: projectTaskId ?? null });

  if (!projectTaskId) return `✅ Objectif "${title}" délié de tout projet Gantt.`;
  return `✅ Objectif "${title}" lié à la tâche Gantt ${projectTaskId}.`;
}

async function executeDeleteRoutine(uid: string, routineId: string): Promise<string> {
  const ref = db.collection(`users/${uid}/activities`).doc(routineId);
  const snap = await ref.get();
  if (!snap.exists) return `Routine introuvable : ${routineId}`;
  const title = snap.data()?.name ?? routineId;
  // Soft-delete pour que le merge Flutter respecte la suppression
  await ref.update({ deleted: true });
  return `✅ Routine "${title}" supprimée.`;
}

async function executeDeleteGoal(uid: string, goalId: string, action: string): Promise<string> {
  const ref = db.collection(`users/${uid}/goals`).doc(goalId);
  const snap = await ref.get();
  if (!snap.exists) return `Objectif introuvable : ${goalId}`;
  const title = snap.data()?.title ?? goalId;
  if (action === "delete") {
    await ref.delete();
    return `✅ Objectif "${title}" supprimé définitivement.`;
  }
  // Archive par défaut
  await ref.update({ status: "archived" });
  return `✅ Objectif "${title}" archivé.`;
}

async function executeClearDayPlan(uid: string, date: string): Promise<string> {
  const yyyymmdd = date.replace(/-/g, "");
  const snap = await db.collection(`users/${uid}/dayPlan`)
    .where("yyyymmdd", "==", yyyymmdd)
    .where("done", "==", false)
    .get();
  if (snap.empty) return `Aucune action non faite à supprimer le ${date}.`;
  // Archiver plutôt que supprimer pour que le merge Flutter respecte la suppression
  const batch = db.batch();
  for (const doc of snap.docs) batch.update(doc.ref, { archived: true, status: "archived" });
  await batch.commit();
  return `✅ ${snap.size} action(s) non faite(s) supprimée(s) du plan du ${date}.`;
}

async function executeArchiveProject(uid: string, projectId: string, restore: boolean): Promise<string> {
  const ref = db.collection(`users/${uid}/projects`).doc(projectId);
  const snap = await ref.get();
  if (!snap.exists) return `Projet introuvable : ${projectId}`;
  const title = snap.data()?.title ?? projectId;
  const newStatus = restore ? "active" : "archived";
  await ref.update({ status: newStatus, updatedAt: FieldValue.serverTimestamp() });
  return restore
    ? `✅ Projet "${title}" réactivé — il apparaît à nouveau dans le focus.`
    : `✅ Projet "${title}" mis en veille — visible dans la section Archives du web app.`;
}

async function executeDeleteProject(
  uid: string,
  projectId: string,
  deleteObjective: boolean
): Promise<string> {
  const projectRef = db.collection(`users/${uid}/projects`).doc(projectId);
  const projectSnap = await projectRef.get();

  if (!projectSnap.exists) {
    return `Projet introuvable : ${projectId}`;
  }

  const projectData = projectSnap.data() as Record<string, unknown>;
  const title = projectData.title ?? projectId;
  const objId = projectData.strategicObjectiveId as string | undefined;

  await projectRef.delete();

  if (deleteObjective && objId) {
    await db.collection(`users/${uid}/strategic_objectives`).doc(objId).delete();
    return `✅ Projet "${title}" et son objectif stratégique supprimés.`;
  }

  return `✅ Projet "${title}" supprimé.`;
}

async function executeListProjects(uid: string): Promise<string> {
  const snap = await db.collection(`users/${uid}/projects`).get();
  if (snap.empty) return "Aucun projet trouvé dans Productivitwo.";

  const lines = snap.docs.map((doc) => {
    const d = doc.data();
    const taskCount = (d.tasks || []).length;
    const start = d.startDate || "?";
    const end   = d.endDate   || "?";
    const domain = d.domainId ? ` · domaine:${d.domainId}` : '';
    return `• [${d.id}] ${d.title} (${start} → ${end}, ${taskCount} tâche(s)${domain})`;
  });

  return `Projets Productivitwo (${snap.size}) :\n${lines.join("\n")}`;
}

async function executeGetProject(uid: string, projectId: string): Promise<string> {
  const doc = await db.collection(`users/${uid}/projects`).doc(projectId).get();
  if (!doc.exists) return `Projet introuvable : ${projectId}`;

  const d = doc.data() as Record<string, unknown>;
  // Retourner le JSON complet pour que Claude puisse le modifier
  return JSON.stringify(d, null, 2);
}

async function executePushGantt(uid: string, input: PushGanttBody): Promise<string> {
  const { project, strategicObjective } = input;

  let strategicObjectiveId: string | undefined;
  if (strategicObjective) {
    const objId = strategicObjective.id || uuidv4();
    strategicObjectiveId = objId;
    await db.collection(`users/${uid}/strategic_objectives`).doc(objId).set(
      { ...strategicObjective, id: objId, status: "active", updatedAt: FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
  }

  const projectId = project.id || uuidv4();
  await db.collection(`users/${uid}/projects`).doc(projectId).set(
    {
      ...project,
      id: projectId,
      phases: (project.phases || []).map((p: ProjectPhase) => ({ ...p, id: p.id || uuidv4() })),
      tasks: normalizeTasks(project.tasks),
      createdBy: uid,
      sourceType: "claude_mcp",
      status: "active",
      ...(strategicObjectiveId ? { strategicObjectiveId } : {}),
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  if (strategicObjectiveId) {
    await db.collection(`users/${uid}/strategic_objectives`).doc(strategicObjectiveId)
      .update({ projectIds: FieldValue.arrayUnion(projectId) });
  }

  const isUpdate = !!project.id;
  return (
    `✅ Projet "${project.title}" ${isUpdate ? "mis à jour" : "créé"} dans Productivitwo !\n` +
    `• ${(project.tasks || []).length} tâche(s) · ${(project.phases || []).length} phase(s)\n` +
    `• Voir sur : https://productivitwo-app.web.app\n` +
    `• projectId : ${projectId}`
  );
}


async function executeGetAssistantMessages(uid: string): Promise<string> {
  const [pendingSnap, shownSnap] = await Promise.all([
    db.collection(`users/${uid}/assistant_messages`)
      .where("status", "==", "pending")
      .get(),
    db.collection(`users/${uid}/assistant_messages`)
      .where("status", "==", "shown")
      .limit(10)
      .get(),
  ]);

  const pending = pendingSnap.docs
    .map((d) => {
      const v = d.data();
      return {
        id: v.id,
        targetDate: v.targetDate as string,
        condition: v.condition,
        text: v.text,
        characterName: v.characterName ?? "ORION",
        action: v.action ?? null,
        expiresAfterDays: v.expiresAfterDays ?? 2,
        createdAt: v.createdAt?.toDate?.()?.toISOString?.() ?? null,
      };
    })
    .sort((a, b) => a.targetDate.localeCompare(b.targetDate));

  const recentShown = shownSnap.docs
    .map((d) => {
      const v = d.data();
      return {
        id: v.id,
        targetDate: v.targetDate as string,
        text: v.text,
        shownAt: v.shownAt?.toDate?.()?.toISOString?.() ?? null,
      };
    })
    .sort((a, b) => (b.shownAt ?? "").localeCompare(a.shownAt ?? ""))
    .slice(0, 10);

  if (!pending.length && !recentShown.length) {
    return "Aucun message ORION programmé ou récent.";
  }

  return JSON.stringify({ pending, recentShown }, null, 2);
}

async function executeDeleteAssistantMessage(uid: string, messageId: string): Promise<string> {
  const ref = db.collection(`users/${uid}/assistant_messages`).doc(messageId);
  const snap = await ref.get();
  if (!snap.exists) return `Message introuvable : ${messageId}`;
  const text = (snap.data()?.text as string ?? "").slice(0, 50);
  await ref.update({ status: "expired" });
  return `✅ Message ORION supprimé : "${text}${text.length >= 50 ? "…" : ""}".`;
}

// ── Contexte allégé pour ORION (sans coachingRules, sans détails sessions) ────

async function executeGetOrionContext(uid: string): Promise<string> {
  const now = new Date();
  const today = now.toISOString().slice(0, 10);
  const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  const ymdFrom = sevenDaysAgo.toISOString().slice(0, 10).replace(/-/g, "");
  const ymdToday = today.replace(/-/g, "");

  const [domainsSnap, activitiesSnap, goalsSnap,
         dayPlanSnap, habitHitsSnap, sessionsSnap, projectsSnap] = await Promise.all([
    db.collection(`users/${uid}/domains`).get(),
    db.collection(`users/${uid}/activities`).get(),
    db.collection(`users/${uid}/goals`).where("status", "==", "active").get(),
    db.collection(`users/${uid}/dayPlan`).where("yyyymmdd", ">=", ymdFrom).get(),
    db.collection(`users/${uid}/habitHits`).where("ts", ">=", sevenDaysAgo).get(),
    db.collection(`users/${uid}/sessions`).where("startAt", ">=", sevenDaysAgo.toISOString()).get(),
    db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
  ]);

  const domains = domainsSnap.docs
    .map((d) => d.data()).filter((v) => !v.deleted)
    .map((v) => ({ id: v.id, name: v.name }));

  const activityMap = new Map<string, string>();
  activitiesSnap.docs.forEach((d) => { const v = d.data(); activityMap.set(v.id, v.name); });

  const activities = activitiesSnap.docs.map((d) => d.data()).filter((v) => !v.deleted)
    .map((v) => ({ id: v.id, name: v.name, type: v.type, domainId: v.domainId, goalMin: v.goalMin ?? null }));

  const goals = goalsSnap.docs.map((d) => {
    const v = d.data();
    const actions = (v.actions || []) as Array<{ done: boolean }>;
    return { id: v.id, title: v.title, domainId: v.domainId, dueDate: v.dueDate ?? null,
             progress: `${actions.filter((a) => a.done).length}/${actions.length}` };
  });

  // Plan du jour — seulement aujourd'hui, résumé
  const todayPlan = dayPlanSnap.docs.map((d) => d.data()).filter((it) => it.yyyymmdd === ymdToday);
  const planSummary = {
    done: todayPlan.filter((it) => it.done).length,
    pending: todayPlan.filter((it) => !it.done && it.status !== "archived").length,
    overdue: dayPlanSnap.docs.map((d) => d.data())
      .filter((it) => !it.done && it.status !== "archived" && it.yyyymmdd < ymdToday).length,
  };

  // Habitudes : hits 7j par activité
  const hitsByHabit = new Map<string, number>();
  habitHitsSnap.docs.forEach((d) => { const v = d.data(); hitsByHabit.set(v.habitId, (hitsByHabit.get(v.habitId) || 0) + 1); });
  const habitStats = Array.from(hitsByHabit.entries())
    .map(([id, count]) => ({ name: activityMap.get(id) ?? id, hits7d: count }));

  // Sessions : temps 7j par activité
  const minByActivity = new Map<string, number>();
  sessionsSnap.docs.forEach((d) => {
    const v = d.data();
    if (!v.endAt) return;
    const mins = Math.round((new Date(v.endAt).getTime() - new Date(v.startAt).getTime()) / 60000);
    if (mins > 0) minByActivity.set(v.activityId, (minByActivity.get(v.activityId) || 0) + mins);
  });
  const timeStats = Array.from(minByActivity.entries())
    .map(([id, mins]) => ({ name: activityMap.get(id) ?? id, hours7d: Math.round(mins / 6) / 10 }));

  // Projets actifs — résumé + tâches urgentes seulement
  const in30days = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
  const projects = projectsSnap.docs.map((d) => {
    const p = d.data();
    const tasks = (p.tasks || []) as Array<{ id: string; title: string; status: string; startDate: string; endDate?: string }>;
    const activeTasks = tasks.filter((t) => t.status !== "done" && t.status !== "skipped");
    const urgentTasks = activeTasks.filter((t) => t.endDate && t.endDate <= in30days)
      .map((t) => ({ id: t.id, title: t.title, endDate: t.endDate, overdue: t.endDate! < today }));
    return {
      id: p.id, title: p.title, domainId: p.domainId ?? null,
      endDate: p.endDate ?? null,
      activeTasks: activeTasks.length,
      urgentTasks,
    };
  });

  return JSON.stringify({ today, domains, activities, goals, planSummary, habitStats, timeStats, projects }, null, 2);
}

async function executeGetInbox(uid: string): Promise<string> {
  const snap = await db.collection(`users/${uid}/captures`)
    .where("status", "==", "pending")
    .orderBy("createdAt", "asc")
    .get();
  if (snap.empty) return "Aucune idée en attente dans l'inbox.";
  const items = snap.docs.map((d) => {
    const v = d.data();
    return { id: v.id, text: v.text, createdAt: v.createdAt?.toDate?.()?.toISOString?.() ?? null };
  });
  return JSON.stringify(items, null, 2);
}

async function executeProcessInboxItem(uid: string, itemId: string, note: string): Promise<string> {
  const ref = db.collection(`users/${uid}/captures`).doc(itemId);
  const snap = await ref.get();
  if (!snap.exists) return `Item inbox introuvable : ${itemId}`;
  await ref.update({
    status: "processed",
    orionNote: note,
    processedAt: FieldValue.serverTimestamp(),
  });
  return `✅ Idée traitée : "${snap.data()?.text}" → ${note}`;
}

// ── Programme horaire journalier ─────────────────────────────────────────────

async function executeGetDaySchedule(uid: string, date: string): Promise<string> {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return `Date invalide : ${date}. Format attendu : YYYY-MM-DD`;
  const snap = await db.doc(`users/${uid}/daily_schedules/${date}`).get();
  if (!snap.exists) return `Aucun programme pour le ${date}.`;
  const data = snap.data() as Record<string, unknown>;
  const blocks = (data.blocks as Array<Record<string, unknown>>) ?? [];
  const statusIcon = (s: string) =>
    s === "done" ? "✅" : s === "skipped" ? "⏭" : s === "deleted" ? "❌" : "⬜";
  const lines = blocks.map((b) => {
    const icon = statusIcon(b.status as string);
    const deletedNote = b.status === "deleted" ? " [supprimé par l'utilisateur — ne pas recréer]" : "";
    return `${icon} ${b.startTime} (${b.durationMin}min) — ${b.title} [${b.category}]${deletedNote}`;
  });
  return `Programme du ${date} (généré par ${data.generatedBy}) :\n${lines.join("\n")}`;
}

async function executeScheduleDay(
  uid: string,
  date: string,
  blocks: Array<{
    startTime: string;
    durationMin: number;
    title: string;
    category: string;
    projectId?: string;
    taskId?: string;
    activityId?: string;
  }>
): Promise<string> {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return `Date invalide : ${date}. Format attendu : YYYY-MM-DD`;
  if (!blocks?.length) return `Aucun bloc fourni — le programme n'a pas été enregistré.`;

  const normalizedBlocks = blocks.map((b) => ({
    id: uuidv4(),
    startTime: b.startTime,
    durationMin: b.durationMin,
    title: b.title,
    category: b.category,
    projectId: b.projectId ?? null,
    taskId: b.taskId ?? null,
    activityId: b.activityId ?? null,
    status: "pending",
    doneAt: null,
  }));

  await db.doc(`users/${uid}/daily_schedules/${date}`).set({
    date,
    generatedBy: "claude",
    generatedAt: FieldValue.serverTimestamp(),
    blocks: normalizedBlocks,
  });

  const lines = normalizedBlocks.map((b) => `• ${b.startTime} (${b.durationMin}min) — ${b.title}`);
  return `✅ Programme du ${date} enregistré — ${normalizedBlocks.length} bloc(s)\n${lines.join("\n")}`;
}

export {
executePushAssistantMessage,
validateToken,
executeGetUserContext,
executeGetOrionContext,
executeUpdateActivityGoal,
executeCreateRoutine,
executeAddToDayPlan,
executeGetDayBlocks,
executeGetDayPlan,
executePlanDay,
executeCreateActivity,
executeDeleteAction,
executeGetDocumentTemplate,
executeSaveDocument,
executeGetDocuments,
executeGetArchives,
executeRestoreItem,
executeCreateDomain,
executeDeleteDomain,
executeDeleteActivity,
executeUpdateProject,
executeUpdateTaskStatus,
executeUpdateActivity,
executeLinkGoalToTask,
executeDeleteRoutine,
executeDeleteGoal,
executeClearDayPlan,
executeArchiveProject,
executeDeleteProject,
executeListProjects,
executeGetProject,
executePushGantt,
executeGetAssistantMessages,
executeDeleteAssistantMessage,
executeGetInbox,
executeProcessInboxItem,
executeGetDaySchedule,
executeScheduleDay,
  normalizePhases,
  normalizeTasks,
};