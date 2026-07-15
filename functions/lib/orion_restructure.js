"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.evaluateProjectRestructures = evaluateProjectRestructures;
const sdk_1 = require("@anthropic-ai/sdk");
const db_1 = require("./db");
const models_1 = require("./models");
const execute_1 = require("./execute");
const if_ = (cond, s) => (cond ? s : null);
const RESTRUCTURE_PROMPT = `Tu es ORION, l'assistant de Productivitwo. Un projet Gantt a dévié : propose une RESTRUCTURATION minimale pour que le plan colle à la réalité.

## Règles
1. N'archive une tâche QUE si elle est devenue hors-sujet ou irréaliste au vu des faits — jamais une tâche presque finie.
2. Reformule quand l'intention reste bonne mais le libellé est périmé.
3. Ajoute AU PLUS 3 tâches, uniquement si un chaînon manque vraiment (verbe d'action + 2-4 sous-actions concrètes + durationDays 1-15).
4. Les tâches "done" sont INTOUCHABLES — ne les mentionne pas.
5. Si le projet est simplement en retard mais toujours pertinent tel quel, réponds avec tous les tableaux vides et un rationale court — on ne dérange pas l'utilisateur pour rien.
6. rationale : 1-2 phrases FACTUELLES (cite les faits fournis, jamais de chiffres inventés).

## Projet
{{PROJECT}}

## Faits mesurés
{{FACTS}}

Réponds UNIQUEMENT avec ce JSON (rien d'autre) :
{
  "archiveTaskIds": ["..."],
  "reword": [ { "taskId": "...", "title": "..." } ],
  "addTasks": [ { "title": "...", "actions": ["...", "..."], "durationDays": 3 } ],
  "rationale": "..."
}`;
function todayYmdFor(tzOffsetMin, d = new Date()) {
    if (typeof tzOffsetMin === "number" && isFinite(tzOffsetMin)) {
        return new Date(d.getTime() + tzOffsetMin * 60000).toISOString().slice(0, 10);
    }
    return new Intl.DateTimeFormat("en-CA", {
        timeZone: "Europe/Paris", year: "numeric", month: "2-digit", day: "2-digit",
    }).format(d);
}
function addDays(ymd, n) {
    const d = new Date(`${ymd}T00:00:00Z`);
    d.setUTCDate(d.getUTCDate() + n);
    return d.toISOString().slice(0, 10);
}
async function evaluateProjectRestructures(uid, opts) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x, _y, _z;
    const metaSnap = await db_1.db.doc(`users/${uid}/data/meta`).get();
    const today = todayYmdFor((_a = metaSnap.data()) === null || _a === void 0 ? void 0 : _a.tzOffsetMin);
    const gateRef = db_1.db.doc(`users/${uid}/data/restructure_sweep`);
    const gate = await gateRef.get();
    if (!(opts === null || opts === void 0 ? void 0 : opts.force) && gate.exists && ((_b = gate.data()) === null || _b === void 0 ? void 0 : _b.lastYmd) === today)
        return null;
    const [projSnap, propSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
        db_1.db.collection(`users/${uid}/orion_proposals`)
            .where("kind", "==", "restructure_project").get(),
    ]);
    // Silences : proposition pending existante, ou refus < 30 jours.
    const pendingIds = new Set();
    const refusedIds = new Set();
    const cutoff30 = Date.now() - 30 * 86400000;
    for (const d of propSnap.docs) {
        const v = d.data();
        const pid = (_c = v.payload) === null || _c === void 0 ? void 0 : _c.projectId;
        if (!pid)
            continue;
        if (v.status === "pending")
            pendingIds.add(pid);
        if (v.status === "rejected") {
            const at = (_f = (_e = (_d = v.createdAt) === null || _d === void 0 ? void 0 : _d.toMillis) === null || _e === void 0 ? void 0 : _e.call(_d)) !== null && _f !== void 0 ? _f : 0;
            if (at > cutoff30)
                refusedIds.add(pid);
        }
    }
    // Blocs sautés/reportés des 14 derniers jours, comptés par projet.
    const skipped14 = {};
    const dayReads = await Promise.all(Array.from({ length: 14 }, (_, i) => db_1.db.doc(`users/${uid}/daily_schedules/${addDays(today, -i)}`).get()));
    for (const snap of dayReads) {
        for (const b of ((_h = (_g = snap.data()) === null || _g === void 0 ? void 0 : _g.blocks) !== null && _h !== void 0 ? _h : [])) {
            if (b.projectId && b.status === "skipped") {
                skipped14[b.projectId] = ((_j = skipped14[b.projectId]) !== null && _j !== void 0 ? _j : 0) + 1;
            }
        }
    }
    const now = Date.now();
    const cutoff48h = now - 48 * 3600000;
    const cutoff21d = now - 21 * 86400000;
    let proposed = 0;
    let checked = 0;
    for (const doc of projSnap.docs) {
        if (proposed >= 2)
            break; // jamais une avalanche de propositions
        const p = doc.data();
        const pid = p.id;
        checked++;
        if (pendingIds.has(pid) || refusedIds.has(pid))
            continue;
        // Touché récemment → l'utilisateur est déjà dessus, on ne s'en mêle pas.
        const updatedAt = (_l = (_k = p.updatedAt) === null || _k === void 0 ? void 0 : _k.toMillis) === null || _l === void 0 ? void 0 : _l.call(_k);
        if (updatedAt != null && updatedAt > cutoff48h)
            continue;
        const tasks = ((_m = p.tasks) !== null && _m !== void 0 ? _m : []);
        const pending = tasks.filter((t) => t.status !== "done" && t.status !== "skipped");
        if (pending.length === 0)
            continue;
        // Déclencheur 1 — dérive : ≥ 3 blocs du projet sautés sur 14 jours.
        const drift = ((_o = skipped14[pid]) !== null && _o !== void 0 ? _o : 0) >= 3;
        // Déclencheur 3 — stagnation : > 21 j, 0 action cochée en 21 j, retard.
        let lastDoneAt = 0;
        for (const t of tasks) {
            for (const a of ((_p = t.actions) !== null && _p !== void 0 ? _p : [])) {
                const at = Date.parse(String((_q = a.doneAt) !== null && _q !== void 0 ? _q : ""));
                if (isFinite(at) && at > lastDoneAt)
                    lastDoneAt = at;
            }
        }
        const createdParsed = Date.parse(String((_r = p.createdAt) !== null && _r !== void 0 ? _r : ""));
        const createdAtMs = (_u = (_t = (_s = p.createdAt) === null || _s === void 0 ? void 0 : _s.toMillis) === null || _t === void 0 ? void 0 : _t.call(_s)) !== null && _u !== void 0 ? _u : (isFinite(createdParsed) ? createdParsed : now);
        const hasLate = pending.some((t) => { var _a; return String((_a = t.endDate) !== null && _a !== void 0 ? _a : "") !== "" && String(t.endDate) < today; });
        const stagnant = createdAtMs < cutoff21d && lastDoneAt < cutoff21d && hasLate;
        if (!drift && !stagnant)
            continue;
        const facts = [
            if_(drift, `${skipped14[pid]} bloc(s) de ce projet sautés/reportés sur les 14 derniers jours`),
            if_(stagnant, `aucune action cochée depuis plus de 21 jours`),
            if_(hasLate, `${pending.filter((t) => { var _a; return String((_a = t.endDate) !== null && _a !== void 0 ? _a : "") !== "" && String(t.endDate) < today; }).length} tâche(s) pending en retard sur leur date de fin`),
        ].filter((s) => s !== null);
        const projectJson = {
            title: p.title,
            description: (_v = p.description) !== null && _v !== void 0 ? _v : "",
            tasks: tasks.map((t) => {
                var _a, _b, _c, _d, _e;
                return ({
                    id: t.id,
                    title: t.title,
                    status: (_a = t.status) !== null && _a !== void 0 ? _a : "pending",
                    startDate: (_b = t.startDate) !== null && _b !== void 0 ? _b : null,
                    endDate: (_c = t.endDate) !== null && _c !== void 0 ? _c : null,
                    actionsDone: ((_d = t.actions) !== null && _d !== void 0 ? _d : []).filter((a) => a.done === true).length,
                    actionsPending: ((_e = t.actions) !== null && _e !== void 0 ? _e : []).filter((a) => a.done !== true).length,
                });
            }),
        };
        let decision;
        try {
            const client = new sdk_1.default({ apiKey: process.env.ANTHROPIC_API_KEY });
            const msg = await client.messages.create({
                model: (0, models_1.getModel)("restructure_project"),
                max_tokens: 1500,
                messages: [{
                        role: "user",
                        content: RESTRUCTURE_PROMPT
                            .replace("{{PROJECT}}", JSON.stringify(projectJson, null, 2))
                            .replace("{{FACTS}}", facts.map((f) => `- ${f}`).join("\n")),
                    }],
            });
            (0, models_1.logTokenUsage)("restructure_project", (0, models_1.getModel)("restructure_project"), msg.usage);
            const raw = msg.content[0].text.trim();
            const m = raw.match(/\{[\s\S]*\}/);
            if (!m)
                continue;
            decision = JSON.parse(m[0]);
        }
        catch (e) {
            console.error("restructure LLM failed", e);
            continue;
        }
        // Validation déterministe du diff : ids réels, jamais une tâche done.
        const byId = new Map(tasks.map((t) => [t.id, t]));
        const archive = ((_w = decision.archiveTaskIds) !== null && _w !== void 0 ? _w : []).filter((id) => byId.has(id) && byId.get(id).status !== "done");
        const reword = ((_x = decision.reword) !== null && _x !== void 0 ? _x : []).filter((r) => {
            var _a;
            return byId.has(r.taskId) && byId.get(r.taskId).status !== "done" &&
                ((_a = r.title) !== null && _a !== void 0 ? _a : "").trim() !== "";
        });
        const addTasks = ((_y = decision.addTasks) !== null && _y !== void 0 ? _y : [])
            .filter((t) => { var _a; return ((_a = t.title) !== null && _a !== void 0 ? _a : "").trim() !== ""; })
            .slice(0, 3)
            .map((t) => {
            var _a, _b;
            return ({
                title: t.title.trim(),
                actions: ((_a = t.actions) !== null && _a !== void 0 ? _a : []).slice(0, 6),
                durationDays: Math.min(15, Math.max(1, Math.round((_b = t.durationDays) !== null && _b !== void 0 ? _b : 3))),
            });
        });
        if (archive.length + reword.length + addTasks.length === 0)
            continue;
        const parts = [
            archive.length > 0 ? `archiver ${archive.length} tâche(s)` : null,
            reword.length > 0 ? `reformuler ${reword.length}` : null,
            addTasks.length > 0 ? `ajouter ${addTasks.length}` : null,
        ].filter((s) => s !== null);
        await (0, execute_1.executeProposeChange)(uid, {
            kind: "restructure_project",
            title: `Recaler « ${p.title} » : ${parts.join(" · ")}`,
            rationale: `${facts.join(" · ")}. ${(_z = decision.rationale) !== null && _z !== void 0 ? _z : ""}`.trim(),
            payload: {
                projectId: pid,
                archiveTaskIds: archive,
                reword,
                addTasks,
            },
        });
        proposed++;
    }
    await gateRef.set({ lastYmd: today, lastResult: { checked, proposed }, at: db_1.FieldValue.serverTimestamp() }, { merge: true });
    return { checked, proposed };
}
//# sourceMappingURL=orion_restructure.js.map