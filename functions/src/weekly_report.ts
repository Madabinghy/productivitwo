import Anthropic from "@anthropic-ai/sdk";
import { db } from "./db";
import { getModel, logTokenUsage } from "./models";

// ─── RAPPORT HEBDO (phase 2, maquettes 16a/16b/16c) ──────────────────────────
//
// La semaine jugée sur les FAITS : agrégats 100 % déterministes (vital par
// domaine, engagements tenus/sautés, motifs de skipReason avec leurs heures),
// puis UN SEUL appel LLM (classe quotidienne) pour rédiger le narratif et LA
// question de fond (une seule, max) à partir de ces faits. Le rapport peut
// proposer UNE décision structurée {field, from, to, reason} — appliquée aux
// modalités du domaine seulement si l'utilisateur valide (« Oui — on
// réorganise »), lue par la proposition dès lundi.

type SchedBlock = {
  id: string; startTime: string; title: string; category: string;
  status: string; kind?: string; skipReason?: string | null;
  activityId?: string | null;
};

export type WeeklyFacts = {
  weekStart: string; // lundi YYYY-MM-DD
  weekEnd: string;
  isoWeek: number;
  engagements: { held: number; total: number };
  domains: Array<{
    domainId: string; name: string; intention: string;
    vitals: Array<{ label: string; done: number; target: number }>;
  }>;
  motifs: Array<{
    cause: string; count: number; brokenTotal: number;
    hours: string[]; // heures des blocs concernés ("14:00", …)
    samples: Array<{ weekday: string; time: string; held: boolean }>;
  }>;
  checkinsDone: number; // jours avec skipReason/dayReason posés (rendre des comptes)
  minutesLogged: number; // heures réelles de la semaine (« ce qui a tenu »)
  renegotiations: number; // renégociations de la semaine = sacrifices en connaissance
};

const WEEKDAY_FR = ["lun", "mar", "mer", "jeu", "ven", "sam", "dim"];

function ymd(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export function mondayOf(dateYmd: string): string {
  const d = new Date(`${dateYmd}T12:00:00Z`);
  const wd = (d.getUTCDay() + 6) % 7; // 0 = lundi
  d.setUTCDate(d.getUTCDate() - wd);
  return ymd(d);
}

function isoWeekOf(dateYmd: string): number {
  const d = new Date(`${dateYmd}T12:00:00Z`);
  const target = new Date(d.valueOf());
  target.setUTCDate(target.getUTCDate() + 3 - ((target.getUTCDay() + 6) % 7));
  const firstThursday = new Date(Date.UTC(target.getUTCFullYear(), 0, 4));
  firstThursday.setUTCDate(
    firstThursday.getUTCDate() + 3 - ((firstThursday.getUTCDay() + 6) % 7));
  return 1 + Math.round((target.valueOf() - firstThursday.valueOf()) / (7 * 24 * 3600 * 1000));
}

// ── Agrégats déterministes ────────────────────────────────────────────────────

export async function buildWeeklyFacts(uid: string, weekStart: string): Promise<WeeklyFacts> {
  const days: string[] = [];
  for (let i = 0; i < 7; i++) {
    const d = new Date(`${weekStart}T12:00:00Z`);
    d.setUTCDate(d.getUTCDate() + i);
    days.push(ymd(d));
  }
  const weekEnd = days[6];

  const [schedSnaps, domainsSnap, actsSnap, sessionsSnap] = await Promise.all([
    Promise.all(days.map((d) => db.doc(`users/${uid}/daily_schedules/${d}`).get())),
    db.collection(`users/${uid}/domains`).get(),
    db.collection(`users/${uid}/activities`).get(),
    db.collection(`users/${uid}/sessions`)
      .where("startAt", ">=", `${weekStart}T00:00:00`)
      .get(),
  ]);

  // Engagements de la semaine (hors preps, pauses, supprimés).
  let held = 0;
  const broken: Array<SchedBlock & { day: string }> = [];
  let total = 0;
  let checkinsDone = 0;
  schedSnaps.forEach((snap, i) => {
    if (!snap.exists) return;
    const data = snap.data() as Record<string, unknown>;
    if (data.dayReason) checkinsDone++;
    let dayHasReason = !!data.dayReason;
    for (const b of ((data.blocks as SchedBlock[]) ?? [])) {
      if (!b || b.status === "deleted" || b.kind === "prep" || b.category === "break") continue;
      total++;
      if (b.status === "done") held++;
      else broken.push({ ...b, day: days[i] });
      if (b.skipReason) dayHasReason = true;
    }
    if (dayHasReason && !data.dayReason) checkinsDone++;
  });

  // Motifs : même cause ≥ 3× OU ≥ 60 % des sautés — avec les heures des blocs.
  const byCause = new Map<string, Array<SchedBlock & { day: string }>>();
  for (const b of broken) {
    const cause = (b.skipReason ?? "").trim();
    if (!cause) continue;
    byCause.set(cause, [...(byCause.get(cause) ?? []), b]);
  }
  const motifs: WeeklyFacts["motifs"] = [];
  byCause.forEach((blocksOfCause, cause) => {
    const isMotif = blocksOfCause.length >= 3 ||
      (broken.length > 0 && blocksOfCause.length / broken.length >= 0.6);
    if (!isMotif) return;
    motifs.push({
      cause,
      count: blocksOfCause.length,
      brokenTotal: broken.length,
      hours: blocksOfCause.map((b) => b.startTime).sort(),
      samples: blocksOfCause.slice(0, 4).map((b) => ({
        weekday: WEEKDAY_FR[(new Date(`${b.day}T12:00:00Z`).getUTCDay() + 6) % 7],
        time: b.startTime,
        held: false,
      })),
    });
  });
  motifs.sort((a, b) => b.count - a.count);

  // Vital par domaine défini : séances = sessions ≥ 10 min sur une activité du
  // domaine, cette semaine. Seules les métriques sessions* sont mesurées ici.
  const actDomain = new Map<string, string>();
  for (const a of actsSnap.docs) {
    actDomain.set(a.id, (a.get("domainId") as string) ?? "");
  }
  const sessionsByDomain = new Map<string, number>();
  let minutesLogged = 0;
  for (const s of sessionsSnap.docs) {
    const startAt = String(s.get("startAt") ?? "");
    if (startAt.slice(0, 10) > weekEnd) continue;
    const endAt = s.get("endAt");
    const start = new Date(startAt).getTime();
    const end = endAt ? new Date(String(endAt)).getTime() : start;
    minutesLogged += Math.max(0, Math.round((end - start) / 60000));
    if (end - start < 10 * 60 * 1000) continue;
    const dom = actDomain.get(String(s.get("activityId") ?? "")) ?? "";
    if (dom) sessionsByDomain.set(dom, (sessionsByDomain.get(dom) ?? 0) + 1);
  }

  const domains: WeeklyFacts["domains"] = [];
  let renegotiations = 0;
  for (const doc of domainsSnap.docs) {
    const d = doc.data() as Record<string, unknown>;
    if (d.deleted === true || d.definitionStatus !== "active" || !d.intention) continue;
    // Renégociations de la semaine (history) — des sacrifices en connaissance.
    for (const h of ((d.history as Array<Record<string, unknown>>) ?? [])) {
      const date = String(h.date ?? "").slice(0, 10);
      if (date >= weekStart && date <= weekEnd) renegotiations++;
    }
    const vitals: Array<{ label: string; done: number; target: number }> = [];
    for (const v of ((d.vitalMinimum as Array<Record<string, unknown>>) ?? [])) {
      const metric = String(v.metric ?? "");
      const target = Number(v.target ?? 0);
      if (!metric.startsWith("sessions") || target <= 0) continue; // pas mesurable ici → omis
      vitals.push({
        label: String(v.label ?? ""),
        done: sessionsByDomain.get(doc.id) ?? 0,
        target,
      });
    }
    domains.push({
      domainId: doc.id,
      name: String(d.name ?? ""),
      intention: String(d.intention ?? ""),
      vitals,
    });
  }

  return {
    weekStart, weekEnd, isoWeek: isoWeekOf(weekStart),
    engagements: { held, total },
    domains, motifs, checkinsDone,
    minutesLogged, renegotiations,
  };
}

/// Routage : vital < 50 % sur ≥ 2 domaines → rapport COURT (17b) — pas de
/// score, pas d'agrégat par bloc, les faits sans morale.
export function isShortWeek(facts: WeeklyFacts): boolean {
  let under = 0;
  for (const d of facts.domains) {
    let done = 0;
    let target = 0;
    for (const v of d.vitals) {
      done += v.done;
      target += v.target;
    }
    if (target > 0 && done / target < 0.5) under++;
  }
  return under >= 2;
}

// ── Génération du rapport (faits + 1 appel narratif) ─────────────────────────

export async function generateWeeklyReport(uid: string, apiKey: string, weekStartArg?: string): Promise<string> {
  const today = ymd(new Date());
  const weekStart = weekStartArg ?? mondayOf(today);
  const facts = await buildWeeklyFacts(uid, weekStart);
  const short = isShortWeek(facts);

  // 2 semaines minimales d'affilée → on propose la renégociation structurelle,
  // jamais on ne requestionne l'intention à chaud.
  const prevMonday = (() => {
    const d = new Date(`${weekStart}T12:00:00Z`);
    d.setUTCDate(d.getUTCDate() - 7);
    return ymd(d);
  })();
  const prevSnap = await db.doc(`users/${uid}/weekly_reports/${prevMonday}`).get();
  const secondMinimal = short &&
    ["minimal", "vital"].includes(String(prevSnap.data()?.weekModeChosen ?? ""));

  // Une phrase d'heures pour le motif principal (« toujours entre 14 h et 16 h »).
  const hoursLabel = (hours: string[]): string => {
    if (hours.length === 0) return "";
    const hs = hours.map((h) => parseInt(h.slice(0, 2), 10));
    const min = Math.min(...hs);
    const max = Math.max(...hs);
    return min === max ? `toujours vers ${min} h` : `toujours entre ${min} h et ${max} h`;
  };

  const hoursTotal = Math.round(facts.minutesLogged / 60);
  const factLines = [
    `Engagements tenus : ${facts.engagements.held}/${facts.engagements.total}`,
    `Heures logguées : ${hoursTotal} h`,
    ...(facts.renegotiations > 0
      ? [`Renégociations cette semaine : ${facts.renegotiations} (des sacrifices en connaissance, pas des oublis)`]
      : []),
    ...facts.domains.map((d) =>
      `Domaine ${d.name} — intention « ${d.intention} » — vital : ` +
      (d.vitals.length > 0
        ? d.vitals.map((v) => `${v.done}/${v.target} ${v.label}`).join(" · ")
        : "aucune métrique mesurable")),
    ...facts.motifs.map((m) =>
      `MOTIF : « ${m.cause} » a mangé ${m.count} blocs sur ${m.brokenTotal} sautés — ${hoursLabel(m.hours)}`),
    `Check-ins faits : ${facts.checkinsDone}/7 jours`,
  ];

  const client = new Anthropic({ apiKey });
  const model = getModel("weekly_report");
  const response = await client.messages.create({
    model,
    max_tokens: 900,
    system: [
      `Tu rédiges le RAPPORT HEBDO de Productivitwo à partir de FAITS déjà calculés (tu n'inventes AUCUN chiffre).`,
      `Ton : direct, factuel, jamais de culpabilité rétroactive. Ce qui a tenu compte autant que ce qui a sauté.`,
      ...(short
        ? [
            ``,
            `⚠️ SEMAINE RATÉE (vital < 50 % sur ≥ 2 domaines) → RAPPORT COURT : pas de score, pas de morale, pas d'interrogatoire.`,
            `narrative = les faits sans morale, EN COMMENÇANT par ce qui a tenu (heures logguées, check-ins faits, renégociations = sacrifices en connaissance).`,
            `question = null (la question binaire « le rush est-il fini ? » est posée par l'app, pas par toi). proposedDecision = null.`,
            `Termine par : une semaine comme ça n'annule rien — elle teste juste si le système survit au réel.`,
            ...(secondMinimal
              ? [`2ᵉ semaine minimale d'affilée : mentionne qu'on proposera de renégocier la structure (modalités) — sans JAMAIS requestionner l'intention à chaud.`]
              : []),
          ]
        : []),
      ``,
      `Tu réponds UNIQUEMENT en JSON valide :`,
      `{`,
      `  "narrative": "2-3 phrases : le constat de la semaine, chiffres repris des faits",`,
      `  "question": "LA question de fond — UNE SEULE, tirée du motif principal (ou null si aucun motif)",`,
      `  "proposedDecision": {"domainName": "…", "from": "modalité actuelle concernée", "to": "nouvelle modalité concrète", "reason": "le fait qui la justifie"} ou null`,
      `}`,
      ``,
      `RÈGLES : la question découle du motif chiffré (ex : blocs sautés toujours aux mêmes heures → déplacer le créneau ?). ` +
      `proposedDecision uniquement s'il y a un motif clair ET un domaine concerné — sinon null. Une décision par semaine suffit.`,
    ].join("\n"),
    messages: [{ role: "user", content: `FAITS DE LA SEMAINE ${facts.isoWeek} :\n${factLines.join("\n")}` }],
  });
  logTokenUsage("weekly_report", model, response.usage);

  const raw = response.content
    .filter((b) => b.type === "text")
    .map((b) => (b as { type: "text"; text: string }).text)
    .join("");
  const start = raw.indexOf("{");
  const end = raw.lastIndexOf("}");
  let narrative = "";
  let question: string | null = null;
  let proposedDecision: Record<string, unknown> | null = null;
  if (start >= 0 && end > start) {
    try {
      const parsed = JSON.parse(raw.slice(start, end + 1)) as {
        narrative?: string; question?: string | null;
        proposedDecision?: Record<string, unknown> | null;
      };
      narrative = parsed.narrative ?? "";
      question = parsed.question ?? null;
      proposedDecision = parsed.proposedDecision ?? null;
    } catch { /* narratif vide : les faits restent affichables */ }
  }

  // Rattacher la décision proposée à un domainId réel (par nom).
  if (proposedDecision?.domainName) {
    const match = facts.domains.find((d) =>
      d.name.toLowerCase() === String(proposedDecision!.domainName).toLowerCase());
    if (match) proposedDecision.domainId = match.domainId;
    else proposedDecision = null; // domaine inconnu → pas de décision
  }

  await db.doc(`users/${uid}/weekly_reports/${weekStart}`).set({
    id: weekStart,
    weekStart,
    weekEnd: facts.weekEnd,
    isoWeek: facts.isoWeek,
    kind: short ? "short" : "full",
    secondMinimal,
    generatedAt: new Date().toISOString(),
    facts,
    narrative,
    question: short ? null : question,
    proposedDecision: short ? null : proposedDecision,
    decisionStatus: !short && proposedDecision ? "pending" : "none",
  });

  return weekStart;
}
