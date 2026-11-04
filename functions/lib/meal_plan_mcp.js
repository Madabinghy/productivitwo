"use strict";
// Repas en 3 familles — lot 3 (2026-11-04) : composer des repas avec Claude.
// Logique pure côté serveur ; même stockage que l'app (`lib/utils/meal_plan.dart`) :
// `users/{uid}/data/meta.meals.plans.<lundi>.<ymd|moment>` =
// `{title, portions, components: [{label, families}], ate?, ateWhat?, noted?, recipeId?, out?}`.
// Créneaux : petit-dej · midi · soir. Un repas composé est valide dès 2 familles sur 3.
Object.defineProperty(exports, "__esModule", { value: true });
exports.MOMENT_LABEL = exports.MEAL_MOMENTS = void 0;
exports.parseMoment = parseMoment;
exports.covered = covered;
exports.composedTitle = composedTitle;
exports.toComponent = toComponent;
exports.composedHistory = composedHistory;
exports.toFinish = toFinish;
exports.mealOptionsText = mealOptionsText;
exports.planMeals = planMeals;
const groceries_1 = require("./groceries");
const meal_families_1 = require("./meal_families");
exports.MEAL_MOMENTS = ["petit-dej", "midi", "soir"];
exports.MOMENT_LABEL = { "petit-dej": "petit-déj", midi: "midi", soir: "soir" };
/** « matin », « petit déj », « déjeuner »… → créneau ; null si inconnu. */
function parseMoment(s) {
    const f = String(s !== null && s !== void 0 ? s : "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z]/g, "");
    if (["petitdej", "petitdejeuner", "matin", "breakfast"].includes(f))
        return "petit-dej";
    if (["midi", "dejeuner", "lunch"].includes(f))
        return "midi";
    if (["soir", "diner", "dinner", "souper"].includes(f))
        return "soir";
    return null;
}
/** Les familles couvertes (accompagnements exclus). */
function covered(cs) {
    const s = new Set();
    for (const c of cs)
        for (const f of c.families)
            if (meal_families_1.MEAL_FAMILIES.includes(f))
                s.add(f);
    return meal_families_1.MEAL_FAMILIES.filter((f) => s.has(f));
}
/** Titre : protéines · féculents · fibres, comme l'app (`composedTitle`). */
function composedTitle(cs) {
    const rank = (c) => {
        const i = meal_families_1.MEAL_FAMILIES.findIndex((f) => c.families.includes(f));
        return i < 0 ? 9 : i;
    };
    return cs.filter((c) => rank(c) < 9).sort((a, b) => rank(a) - rank(b)).map((c) => c.label).join(" · ");
}
/** Une brique donnée par Claude : `"Riz"` ou `{label, family?}` → libellé + familles (données, sinon celles du mot). */
function toComponent(raw, f) {
    var _a;
    const label = (typeof raw === "string" ? raw : String((_a = raw === null || raw === void 0 ? void 0 : raw.label) !== null && _a !== void 0 ? _a : "")).trim();
    if (!label)
        return null;
    const given = typeof raw === "object" && raw ? (0, meal_families_1.parseFamilies)(raw.family) : [];
    const fams = given.length ? given : (0, meal_families_1.familiesFor)(label, f.families, f.memory, f.pantry);
    return { label, families: fams.length ? fams : [meal_families_1.ACC] };
}
/** Les repas composés connus, du plus récent au plus ancien. */
function composedHistory(meals) {
    var _a, _b, _c;
    const out = [];
    for (const week of Object.values((_a = meals.plans) !== null && _a !== void 0 ? _a : {})) {
        for (const [k, v] of Object.entries(week !== null && week !== void 0 ? week : {})) {
            if (!((_b = v === null || v === void 0 ? void 0 : v.components) === null || _b === void 0 ? void 0 : _b.length))
                continue;
            const [ymd, moment] = k.split("|");
            if (ymd && moment)
                out.push({ ymd, moment, title: (_c = v.title) !== null && _c !== void 0 ? _c : composedTitle(v.components), components: v.components });
        }
    }
    return out.sort((a, b) => b.ymd.localeCompare(a.ymd) || exports.MEAL_MOMENTS.indexOf(b.moment) - exports.MEAL_MOMENTS.indexOf(a.moment));
}
const daysBetween = (a, b) => Math.round((Date.parse(`${b}T12:00:00Z`) - Date.parse(`${a}T12:00:00Z`)) / 86400000);
/** Ce qui est « à finir » : bientôt fini, ou Frais / Fruits et légumes acheté il y a plus de 3 jours. */
function toFinish(pantry, ymd) {
    return Object.values(pantry)
        .filter((p) => p.state !== "out")
        .filter((p) => p.state === "low" || ((p.aisle === "Frais" || p.aisle === "Fruits et légumes") && p.boughtAt && daysBetween(p.boughtAt, ymd) > 3))
        .map((p) => p.label)
        .sort((a, b) => a.localeCompare(b, "fr"));
}
/** Le texte de get_meal_options : le créneau, ce qu'on a par famille, à finir, les derniers repas. */
function mealOptionsText(args) {
    var _a, _b, _c, _d, _e, _f, _g;
    const { ymd, moment, meals, f } = args;
    const week = (_b = (_a = meals.plans) === null || _a === void 0 ? void 0 : _a[(0, groceries_1.mondayOfYmd)(ymd)]) !== null && _b !== void 0 ? _b : {};
    const moments = moment ? [moment] : exports.MEAL_MOMENTS;
    const lines = [`Repas du ${ymd} :`];
    for (const m of moments) {
        const p = week[`${ymd}|${m}`];
        lines.push(`• ${exports.MOMENT_LABEL[m]} : ${p ? `${(_c = p.title) !== null && _c !== void 0 ? _c : "?"}${((_d = p.components) === null || _d === void 0 ? void 0 : _d.length) ? ` (composé : ${covered(p.components).map((x) => meal_families_1.FAMILY_LABEL[x]).join(" + ") || "—"})` : ""}${p.ate ? ` — mangé${p.ate === "ok" ? ", équilibré" : ""}` : ""}` : "rien de prévu"}`);
    }
    const by = { proteines: [], feculents: [], fibres: [], [meal_families_1.ACC]: [] };
    for (const p of Object.values(f.pantry)) {
        if (p.state === "out")
            continue;
        for (const fam of (0, meal_families_1.familiesFor)(p.label, f.families, f.memory, f.pantry, p.aisle))
            (_e = by[fam]) === null || _e === void 0 ? void 0 : _e.push(p.label);
    }
    lines.push("", "AU PLACARD, PAR FAMILLE");
    for (const fam of [...meal_families_1.MEAL_FAMILIES, meal_families_1.ACC]) {
        lines.push(`${meal_families_1.FAMILY_LABEL[fam]} : ${by[fam].length ? by[fam].sort((a, b) => a.localeCompare(b, "fr")).join(", ") : "—"}`);
    }
    const finish = toFinish(f.pantry, ymd);
    if (finish.length)
        lines.push("", `À FINIR : ${finish.join(", ")}`);
    const hist = composedHistory(meals).filter((h) => h.ymd <= ymd).slice(0, 6);
    if (hist.length) {
        lines.push("", "DERNIERS REPAS COMPOSÉS");
        for (const h of hist)
            lines.push(`${h.ymd} ${(_f = exports.MOMENT_LABEL[h.moment]) !== null && _f !== void 0 ? _f : h.moment} : ${h.title}`);
    }
    const lastMain = composedHistory(meals).find((h) => h.moment !== "petit-dej" && (h.ymd < ymd || (h.ymd === ymd && moment && exports.MEAL_MOMENTS.indexOf(h.moment) < exports.MEAL_MOMENTS.indexOf(moment))));
    const lastProt = (_g = lastMain === null || lastMain === void 0 ? void 0 : lastMain.components.filter((c) => c.families.includes(meal_families_1.PRO)).map((c) => c.label)) !== null && _g !== void 0 ? _g : [];
    lines.push("", "Règles : un repas = une brique par famille (protéines · féculents · fibres), 2 familles sur 3 suffisent ; les " +
        "accompagnements (ail, oignon, sauces…) ne comptent pas. Propose d'abord ce qu'il y a au placard, ce qui est à finir, " +
        (lastProt.length ? `pas la même protéine qu'au repas d'avant (${lastProt.join(", ")}), ` : "") +
        "puis montre ta proposition et appelle plan_meals (apply:false puis apply:true après accord).");
    return lines.join("\n");
}
/** Valide les repas demandés ; un repas composé qui couvre moins de 2 familles est refusé. */
function planMeals(inputs, meals, f, today) {
    var _a, _b, _c, _d, _e;
    const writes = [];
    const errors = [];
    for (const x of inputs) {
        const ymd = String((_a = x.date) !== null && _a !== void 0 ? _a : today);
        if (!/^\d{4}-\d{2}-\d{2}$/.test(ymd)) {
            errors.push(`date invalide « ${x.date} » (YYYY-MM-DD).`);
            continue;
        }
        const moment = parseMoment(x.moment);
        if (!moment) {
            errors.push(`${ymd} : créneau inconnu « ${(_b = x.moment) !== null && _b !== void 0 ? _b : ""} » (petit-dej · midi · soir).`);
            continue;
        }
        const monday = (0, groceries_1.mondayOfYmd)(ymd);
        const key = `${ymd}|${moment}`;
        const cur = (_d = (_c = meals.plans) === null || _c === void 0 ? void 0 : _c[monday]) === null || _d === void 0 ? void 0 : _d[key];
        if (x.clear === true) {
            writes.push({ monday, key, value: null, text: `🗑 ${ymd} ${exports.MOMENT_LABEL[moment]} vidé${(cur === null || cur === void 0 ? void 0 : cur.title) ? ` (était : ${cur.title})` : ""}` });
            continue;
        }
        const seen = new Set();
        const cs = ((_e = x.components) !== null && _e !== void 0 ? _e : [])
            .map((c) => toComponent(c, f))
            .filter((c) => !!c && !seen.has((0, groceries_1.groceryKey)(c.label)) && !!seen.add((0, groceries_1.groceryKey)(c.label)));
        const cov = covered(cs);
        if (cov.length < 2) {
            errors.push(`${ymd} ${exports.MOMENT_LABEL[moment]} : ${cs.map((c) => c.label).join(", ") || "rien"} ne couvre que ${cov.map((c) => meal_families_1.FAMILY_LABEL[c]).join(" + ") || "aucune famille"} — il en faut 2 sur 3 (précise family si une brique est mal classée).`);
            continue;
        }
        const value = Object.assign(Object.assign({ title: composedTitle(cs), portions: 1, components: cs }, ((cur === null || cur === void 0 ? void 0 : cur.ate) ? { ate: cur.ate } : {})), ((cur === null || cur === void 0 ? void 0 : cur.ateWhat) ? { ateWhat: cur.ateWhat } : {}));
        const sides = cs.filter((c) => !c.families.some((fam) => meal_families_1.MEAL_FAMILIES.includes(fam))).map((c) => c.label);
        writes.push({
            monday,
            key,
            value,
            text: `✓ ${ymd} ${exports.MOMENT_LABEL[moment]} : ${value.title}${sides.length ? ` · avec ${sides.join(", ").toLowerCase()}` : ""} (${cov.map((c) => meal_families_1.FAMILY_LABEL[c]).join(" + ")})${(cur === null || cur === void 0 ? void 0 : cur.title) && cur.title !== value.title ? ` — remplace « ${cur.title} »` : ""}`,
        });
    }
    return { writes, errors };
}
//# sourceMappingURL=meal_plan_mcp.js.map