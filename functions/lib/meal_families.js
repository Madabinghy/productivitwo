"use strict";
// Repas en 3 familles (2026-11-04) — logique pure côté serveur, alignée sur
// `lib/utils/meal_families.dart` (**garder alignés** : mêmes mots-clés, même
// ordre, même règle — le mot-clé le plus long gagne, à égalité la première
// famille de la liste). Stockage `users/{uid}/data/meta.groceries.families`
// `{<mot>: "proteines" | "feculents,proteines" | …}`.
Object.defineProperty(exports, "__esModule", { value: true });
exports.FAMILY_KEYWORDS = exports.NON_FOOD_AISLES = exports.FAMILY_LABEL = exports.MEAL_FAMILIES = exports.ACC = exports.FIB = exports.FEC = exports.PRO = void 0;
exports.guessFamilies = guessFamilies;
exports.parseFamilies = parseFamilies;
exports.familiesFor = familiesFor;
exports.familiesText = familiesText;
const groceries_1 = require("./groceries");
const pantry_1 = require("./pantry");
exports.PRO = "proteines";
exports.FEC = "feculents";
exports.FIB = "fibres";
exports.ACC = "accompagnement";
exports.MEAL_FAMILIES = [exports.PRO, exports.FEC, exports.FIB];
exports.FAMILY_LABEL = { [exports.PRO]: "Protéines", [exports.FEC]: "Féculents", [exports.FIB]: "Fibres", [exports.ACC]: "Accompagnements" };
exports.NON_FOOD_AISLES = new Set(["Ménager", "Hygiène", "Boissons"]);
exports.FAMILY_KEYWORDS = [
    [[exports.ACC], [
            "sauce", "concentre de tomate", "coulis", "moutarde", "ketchup", "mayonnaise", "vinaigrette", "pesto", "epice", "curry",
            "colombo", "paprika", "sel", "poivre", "huile", "vinaigre", "bouillon", "ail", "oignon", "echalote", "cive", "persil",
            "basilic", "coriandre", "menthe", "thym", "laurier", "gingembre", "piment", "herbe", "beurre", "creme", "creme fraiche",
            "lait de coco", "sucre", "farine", "levure", "confiture", "miel", "pate a tartiner", "cornichon", "olive", "capre", "chocolat",
            "cacao", "cafe", "the", "gateau", "tartelette", "biscuit", "madeleine", "bonbon", "chips", "glace", "dessert",
        ]],
    [[exports.FEC, exports.PRO], [
            "lentille", "pois chiche", "haricot rouge", "haricot blanc", "pois rouge", "pois d angole", "feve", "flageolet",
        ]],
    [[exports.FEC], [
            "pomme de terre", "patate", "patate douce", "igname", "dachine", "madere", "manioc", "banane plantain", "plantain",
            "fruit a pain", "riz", "pate", "pates", "spaghetti", "tagliatelle", "farfalle", "penne", "coquillette",
            "fusilli", "macaroni", "lasagne", "nouille", "vermicelle", "gnocchi", "semoule", "couscous", "quinoa", "boulgour", "ble",
            "polenta", "pain", "baguette", "biscotte", "brioche", "tortilla", "wrap", "galette", "cracker", "cereale", "flocon",
            "avoine", "muesli", "frites", "puree", "farine de manioc", "cassave", "dombre",
        ]],
    [[exports.PRO], [
            "oeuf", "jambon", "lardon", "bacon", "poulet", "blanc de poulet", "dinde", "canard", "boeuf", "veau", "agneau", "gigot",
            "porc", "cote", "cote de porc", "ribs", "travers", "roti", "filet", "cuisse", "aiguillette", "escalope", "steak", "viande",
            "hache", "saucisse", "merguez", "chorizo", "boudin", "nugget", "cordon bleu", "poisson", "saumon", "thon", "sardine",
            "maquereau", "cabillaud", "morue", "colin", "merlu", "crevette", "calamar", "escargot", "lambi", "chatrou", "ouassou",
            "tofu", "tempeh", "seitan", "fromage", "emmental", "mozzarella", "feta", "chevre", "comte", "gruyere", "parmesan", "ricotta",
            "yaourt", "yogourt", "skyr", "fromage blanc", "lait",
        ]],
    [[exports.FIB], [
            "legume", "haricot vert", "petit pois", "salade", "mache", "roquette", "carotte", "tomate", "courgette", "poivron",
            "champignon", "brocoli", "chou", "chou fleur", "epinard", "concombre", "aubergine", "poireau", "radis", "navet",
            "betterave", "christophine", "giraumon", "potiron", "citrouille", "gombo", "avocat", "crudite", "ratatouille", "soupe",
            "fruit", "banane", "pomme", "poire", "orange", "citron", "clementine", "mandarine", "kiwi", "fraise", "framboise",
            "myrtille", "cerise", "raisin", "melon", "pasteque", "ananas", "mangue", "papaye", "goyave", "peche", "abricot", "prune",
            "compote",
        ]],
];
const sameWord = (t, kw) => t === kw || t === `${kw}s` || t === `${kw}x`;
function hasPhrase(tokens, kw) {
    for (let i = 0; i + kw.length <= tokens.length; i++) {
        if (kw.every((w, j) => sameWord(tokens[i + j], w)))
            return true;
    }
    return false;
}
/** Les familles devinées par les mots ; [] si rien ne le reconnaît. */
function guessFamilies(label) {
    const tokens = (0, pantry_1.foldWords)(label).split(" ").filter(Boolean);
    if (!tokens.length)
        return [];
    let best = [];
    let bestLen = 0;
    for (const [fams, words] of exports.FAMILY_KEYWORDS) {
        for (const w of words) {
            const kw = w.split(" ");
            if (kw.length > bestLen && hasPhrase(tokens, kw)) {
                best = fams;
                bestLen = kw.length;
            }
        }
    }
    return best;
}
/** `"feculents,proteines"` / liste / noms en clair → familles propres ; accompagnement exclusif. */
function parseFamilies(raw) {
    const parts = Array.isArray(raw) ? raw.map(String) : String(raw !== null && raw !== void 0 ? raw : "").split(",");
    const alias = {
        proteine: exports.PRO, proteines: exports.PRO, feculent: exports.FEC, feculents: exports.FEC, fibre: exports.FIB, fibres: exports.FIB, legumes: exports.FIB, legume: exports.FIB,
        accompagnement: exports.ACC, accompagnements: exports.ACC, condiment: exports.ACC, aucune: exports.ACC,
    };
    const out = [];
    for (const p of parts) {
        const f = alias[(0, pantry_1.foldWords)(p).replace(/ /g, "")];
        if (f && !out.includes(f))
            out.push(f);
    }
    if (out.includes(exports.ACC) && out.length > 1)
        out.splice(out.indexOf(exports.ACC), 1);
    return out;
}
/** Les familles d'un produit : retenues pour le mot, sinon devinées ; hors alimentaire = [] ; inconnu = accompagnement. */
function familiesFor(label, families, memory, pantry, aisle) {
    var _a, _b;
    const k = (0, groceries_1.groceryKey)(label);
    const set = parseFamilies(families[k]);
    if (set.length)
        return set;
    const a = (_b = aisle !== null && aisle !== void 0 ? aisle : (_a = pantry[k]) === null || _a === void 0 ? void 0 : _a.aisle) !== null && _b !== void 0 ? _b : (0, pantry_1.aisleFor)(label, memory, pantry);
    if (exports.NON_FOOD_AISLES.has(a))
        return [];
    const g = guessFamilies(label);
    return g.length ? g : [exports.ACC];
}
/** Ce qu'on a (j'en ai · bientôt fini) par famille, en texte. */
function familiesText(pantry, families, memory) {
    var _a;
    const by = { [exports.PRO]: [], [exports.FEC]: [], [exports.FIB]: [], [exports.ACC]: [] };
    for (const p of Object.values(pantry)) {
        if (p.state === "out")
            continue;
        for (const f of familiesFor(p.label, families, memory, pantry, p.aisle))
            (_a = by[f]) === null || _a === void 0 ? void 0 : _a.push(p.state === "low" ? `${p.label} (bientôt fini)` : p.label);
    }
    const lines = [exports.PRO, exports.FEC, exports.FIB, exports.ACC].map((f) => `${exports.FAMILY_LABEL[f]} : ${by[f].length ? by[f].sort((a, b) => a.localeCompare(b, "fr")).join(", ") : "—"}`);
    return ["PAR FAMILLE (repas : 2 familles sur 3 suffisent ; les accompagnements ne comptent pas)", ...lines].join("\n");
}
//# sourceMappingURL=meal_families.js.map