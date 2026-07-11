"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.mondayOf = mondayOf;
exports.buildWeeklyFacts = buildWeeklyFacts;
exports.isShortWeek = isShortWeek;
exports.generateWeeklyReport = generateWeeklyReport;
const sdk_1 = require("@anthropic-ai/sdk");
const db_1 = require("./db");
const models_1 = require("./models");
const WEEKDAY_FR = ["lun", "mar", "mer", "jeu", "ven", "sam", "dim"];
function ymd(d) {
    return d.toISOString().slice(0, 10);
}
function mondayOf(dateYmd) {
    const d = new Date(`${dateYmd}T12:00:00Z`);
    const wd = (d.getUTCDay() + 6) % 7; // 0 = lundi
    d.setUTCDate(d.getUTCDate() - wd);
    return ymd(d);
}
function isoWeekOf(dateYmd) {
    const d = new Date(`${dateYmd}T12:00:00Z`);
    const target = new Date(d.valueOf());
    target.setUTCDate(target.getUTCDate() + 3 - ((target.getUTCDay() + 6) % 7));
    const firstThursday = new Date(Date.UTC(target.getUTCFullYear(), 0, 4));
    firstThursday.setUTCDate(firstThursday.getUTCDate() + 3 - ((firstThursday.getUTCDay() + 6) % 7));
    return 1 + Math.round((target.valueOf() - firstThursday.valueOf()) / (7 * 24 * 3600 * 1000));
}
// ── Agrégats déterministes ────────────────────────────────────────────────────
async function buildWeeklyFacts(uid, weekStart) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u;
    const days = [];
    for (let i = 0; i < 7; i++) {
        const d = new Date(`${weekStart}T12:00:00Z`);
        d.setUTCDate(d.getUTCDate() + i);
        days.push(ymd(d));
    }
    const weekEnd = days[6];
    const [schedSnaps, domainsSnap, actsSnap, sessionsSnap] = await Promise.all([
        Promise.all(days.map((d) => db_1.db.doc(`users/${uid}/daily_schedules/${d}`).get())),
        db_1.db.collection(`users/${uid}/domains`).get(),
        db_1.db.collection(`users/${uid}/activities`).get(),
        db_1.db.collection(`users/${uid}/sessions`)
            .where("startAt", ">=", `${weekStart}T00:00:00`)
            .get(),
    ]);
    // Engagements de la semaine (hors preps, pauses, supprimés).
    let held = 0;
    const broken = [];
    let total = 0;
    let checkinsDone = 0;
    let reported = 0;
    let deletedBlocks = 0;
    schedSnaps.forEach((snap, i) => {
        var _a;
        if (!snap.exists)
            return;
        const data = snap.data();
        if (data.dayReason)
            checkinsDone++;
        let dayHasReason = !!data.dayReason;
        for (const b of ((_a = data.blocks) !== null && _a !== void 0 ? _a : [])) {
            if (!b || b.kind === "prep" || b.category === "break")
                continue;
            if (b.status === "deleted") {
                deletedBlocks++;
                continue;
            }
            total++;
            if (b.status === "done")
                held++;
            else
                broken.push(Object.assign(Object.assign({}, b), { day: days[i] }));
            if (b.skipReason === "reporte")
                reported++;
            if (b.skipReason)
                dayHasReason = true;
        }
        if (dayHasReason && !data.dayReason)
            checkinsDone++;
    });
    // Motifs : même cause ≥ 3× OU ≥ 60 % des sautés — avec les heures des blocs.
    const byCause = new Map();
    for (const b of broken) {
        const cause = ((_a = b.skipReason) !== null && _a !== void 0 ? _a : "").trim();
        if (!cause)
            continue;
        byCause.set(cause, [...((_b = byCause.get(cause)) !== null && _b !== void 0 ? _b : []), b]);
    }
    const motifs = [];
    byCause.forEach((blocksOfCause, cause) => {
        const isMotif = blocksOfCause.length >= 3 ||
            (broken.length > 0 && blocksOfCause.length / broken.length >= 0.6);
        if (!isMotif)
            return;
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
    const actDomain = new Map();
    for (const a of actsSnap.docs) {
        actDomain.set(a.id, (_c = a.get("domainId")) !== null && _c !== void 0 ? _c : "");
    }
    const sessionsByDomain = new Map();
    let minutesLogged = 0;
    for (const s of sessionsSnap.docs) {
        const startAt = String((_d = s.get("startAt")) !== null && _d !== void 0 ? _d : "");
        if (startAt.slice(0, 10) > weekEnd)
            continue;
        const endAt = s.get("endAt");
        const start = new Date(startAt).getTime();
        const end = endAt ? new Date(String(endAt)).getTime() : start;
        minutesLogged += Math.max(0, Math.round((end - start) / 60000));
        if (end - start < 10 * 60 * 1000)
            continue;
        const dom = (_f = actDomain.get(String((_e = s.get("activityId")) !== null && _e !== void 0 ? _e : ""))) !== null && _f !== void 0 ? _f : "";
        if (dom)
            sessionsByDomain.set(dom, ((_g = sessionsByDomain.get(dom)) !== null && _g !== void 0 ? _g : 0) + 1);
    }
    const domains = [];
    const declaredQuestions = [];
    let renegotiations = 0;
    for (const doc of domainsSnap.docs) {
        const d = doc.data();
        if (d.deleted === true || d.definitionStatus !== "active" || !d.intention)
            continue;
        // Renégociations de la semaine (history) — des sacrifices en connaissance.
        for (const h of ((_h = d.history) !== null && _h !== void 0 ? _h : [])) {
            const date = String((_j = h.date) !== null && _j !== void 0 ? _j : "").slice(0, 10);
            if (date >= weekStart && date <= weekEnd)
                renegotiations++;
        }
        // Suivi déclaré : pas de chrono, pas de score — le vital se DEMANDE
        // (2 questions binaires max, tous domaines déclarés confondus).
        if (d.tracking === "declared") {
            for (const v of ((_k = d.vitalMinimum) !== null && _k !== void 0 ? _k : [])) {
                if (declaredQuestions.length >= 2)
                    break;
                const label = String((_l = v.label) !== null && _l !== void 0 ? _l : "").trim();
                if (label) {
                    declaredQuestions.push({
                        domainId: doc.id, name: String((_m = d.name) !== null && _m !== void 0 ? _m : ""), label,
                    });
                }
            }
            continue;
        }
        const vitals = [];
        for (const v of ((_o = d.vitalMinimum) !== null && _o !== void 0 ? _o : [])) {
            const metric = String((_p = v.metric) !== null && _p !== void 0 ? _p : "");
            const target = Number((_q = v.target) !== null && _q !== void 0 ? _q : 0);
            if (!metric.startsWith("sessions") || target <= 0)
                continue; // pas mesurable ici → omis
            vitals.push({
                label: String((_r = v.label) !== null && _r !== void 0 ? _r : ""),
                done: (_s = sessionsByDomain.get(doc.id)) !== null && _s !== void 0 ? _s : 0,
                target,
            });
        }
        domains.push({
            domainId: doc.id,
            name: String((_t = d.name) !== null && _t !== void 0 ? _t : ""),
            intention: String((_u = d.intention) !== null && _u !== void 0 ? _u : ""),
            vitals,
        });
    }
    return {
        weekStart, weekEnd, isoWeek: isoWeekOf(weekStart),
        engagements: { held, total },
        domains, motifs, checkinsDone,
        minutesLogged, renegotiations,
        declaredQuestions,
        reported, deletedBlocks,
    };
}
/// Routage : vital < 50 % sur ≥ 2 domaines → rapport COURT (17b) — pas de
/// score, pas d'agrégat par bloc, les faits sans morale.
function isShortWeek(facts) {
    let under = 0;
    for (const d of facts.domains) {
        let done = 0;
        let target = 0;
        for (const v of d.vitals) {
            done += v.done;
            target += v.target;
        }
        if (target > 0 && done / target < 0.5)
            under++;
    }
    return under >= 2;
}
// ── Génération du rapport (faits + 1 appel narratif) ─────────────────────────
async function generateWeeklyReport(uid, apiKey, weekStartArg) {
    var _a, _b, _c, _d, _e;
    const today = ymd(new Date());
    const weekStart = weekStartArg !== null && weekStartArg !== void 0 ? weekStartArg : mondayOf(today);
    const facts = await buildWeeklyFacts(uid, weekStart);
    const short = isShortWeek(facts);
    // 2 semaines minimales d'affilée → on propose la renégociation structurelle,
    // jamais on ne requestionne l'intention à chaud.
    const prevMonday = (() => {
        const d = new Date(`${weekStart}T12:00:00Z`);
        d.setUTCDate(d.getUTCDate() - 7);
        return ymd(d);
    })();
    const prevSnap = await db_1.db.doc(`users/${uid}/weekly_reports/${prevMonday}`).get();
    const secondMinimal = short &&
        ["minimal", "vital"].includes(String((_b = (_a = prevSnap.data()) === null || _a === void 0 ? void 0 : _a.weekModeChosen) !== null && _b !== void 0 ? _b : ""));
    // Une phrase d'heures pour le motif principal (« toujours entre 14 h et 16 h »).
    const hoursLabel = (hours) => {
        if (hours.length === 0)
            return "";
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
        ...facts.domains.map((d) => `Domaine ${d.name} — intention « ${d.intention} » — vital : ` +
            (d.vitals.length > 0
                ? d.vitals.map((v) => `${v.done}/${v.target} ${v.label}`).join(" · ")
                : "aucune métrique mesurable")),
        ...facts.motifs.map((m) => `MOTIF : « ${m.cause} » a mangé ${m.count} blocs sur ${m.brokenTotal} sautés — ${hoursLabel(m.hours)}`),
        `Check-ins faits : ${facts.checkinsDone}/7 jours`,
        ...(facts.reported + facts.deletedBlocks > 0
            ? [`Hygiène du programme : ${facts.reported} bloc(s) reporté(s), ${facts.deletedBlocks} supprimé(s) sur ${facts.engagements.total + facts.deletedBlocks} posés${facts.engagements.total + facts.deletedBlocks >= 5 && (facts.reported + facts.deletedBlocks) / (facts.engagements.total + facts.deletedBlocks) >= 0.3 ? " — au-dessus de 30 % : le programme du matin ment peut-être (constat, pas morale)" : ""}`]
            : []),
        ...(facts.declaredQuestions.length > 0
            ? [`Domaines à suivi déclaré : ${[...new Set(facts.declaredQuestions.map((q) => q.name))].join(", ")} — leur vital est demandé directement dans l'app, tu n'as AUCUNE donnée dessus : n'en dis rien.`]
            : []),
    ];
    const client = new sdk_1.default({ apiKey });
    const model = (0, models_1.getModel)("weekly_report");
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
    (0, models_1.logTokenUsage)("weekly_report", model, response.usage);
    const raw = response.content
        .filter((b) => b.type === "text")
        .map((b) => b.text)
        .join("");
    const start = raw.indexOf("{");
    const end = raw.lastIndexOf("}");
    let narrative = "";
    let question = null;
    let proposedDecision = null;
    if (start >= 0 && end > start) {
        try {
            const parsed = JSON.parse(raw.slice(start, end + 1));
            narrative = (_c = parsed.narrative) !== null && _c !== void 0 ? _c : "";
            question = (_d = parsed.question) !== null && _d !== void 0 ? _d : null;
            proposedDecision = (_e = parsed.proposedDecision) !== null && _e !== void 0 ? _e : null;
        }
        catch ( /* narratif vide : les faits restent affichables */_f) { /* narratif vide : les faits restent affichables */ }
    }
    // Rattacher la décision proposée à un domainId réel (par nom).
    if (proposedDecision === null || proposedDecision === void 0 ? void 0 : proposedDecision.domainName) {
        const match = facts.domains.find((d) => d.name.toLowerCase() === String(proposedDecision.domainName).toLowerCase());
        if (match)
            proposedDecision.domainId = match.domainId;
        else
            proposedDecision = null; // domaine inconnu → pas de décision
    }
    await db_1.db.doc(`users/${uid}/weekly_reports/${weekStart}`).set({
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
//# sourceMappingURL=weekly_report.js.map