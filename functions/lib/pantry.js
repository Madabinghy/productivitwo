"use strict";
// Mes placards (2026-11-03) — logique pure côté serveur, alignée sur
// `lib/utils/pantry.dart` (**garder alignés** : mêmes rayons, mêmes mots-clés,
// même ordre). Stockage `users/{uid}/data/meta.groceries` :
// `pantry: {<mot>: {label, aisle, state: have|low|out, staple?, boughtAt?}}`,
// `aisles: [..]`, `memory.<mot>.aisle`, `items.<id>.aisle`.
Object.defineProperty(exports, "__esModule", { value: true });
exports.STATE_LABEL = exports.AISLE_KEYWORDS = exports.OTHER_AISLE = exports.DEFAULT_AISLES = void 0;
exports.foldWords = foldWords;
exports.guessAisle = guessAisle;
exports.resolveAisle = resolveAisle;
exports.aisleFor = aisleFor;
exports.parseState = parseState;
exports.pantryText = pantryText;
exports.addAisle = addAisle;
exports.renameAisle = renameAisle;
exports.removeAisle = removeAisle;
exports.aisleSplit = aisleSplit;
const groceries_1 = require("./groceries");
exports.DEFAULT_AISLES = ["Épicerie", "Frais", "Fruits et légumes", "Surgelés", "Boissons", "Ménager", "Hygiène", "Autre"];
exports.OTHER_AISLE = "Autre";
exports.AISLE_KEYWORDS = [
    ["Ménager", [
            "lessive", "vaisselle", "eponge", "essuie tout", "sopalin", "papier toilette", "sac poubelle", "poubelle", "javel",
            "nettoyant", "detergent", "adoucissant", "lave vaisselle", "desinfectant", "serpillere", "allumette", "ampoule", "pile",
            "aluminium", "film alimentaire", "sac congelation",
        ]],
    ["Hygiène", [
            "dentifrice", "brosse a dents", "shampoing", "shampooing", "apres shampoing", "gel douche", "savon", "deodorant", "coton",
            "rasoir", "mouchoir", "serviette hygienique", "tampon", "creme hydratante", "creme solaire", "couche", "lingette", "parfum",
            "fil dentaire", "bain de bouche",
        ]],
    ["Surgelés", ["surgele", "surgeles", "glace", "glacon", "pizza surgelee", "frites"]],
    ["Boissons", ["eau", "jus", "soda", "coca", "limonade", "biere", "vin", "sirop", "cidre", "champagne", "tisane"]],
    ["Épicerie", [
            "sauce", "conserve", "boite", "compote", "lait de coco", "concentre de tomate", "puree", "soupe", "bouillon",
        ]],
    ["Frais", [
            "lait", "yaourt", "yogourt", "beurre", "creme", "creme fraiche", "fromage", "oeuf", "jambon", "lardon", "poulet", "boeuf",
            "steak", "viande", "hache", "poisson", "saumon", "dinde", "porc", "saucisse", "emmental", "mozzarella", "skyr", "feta",
            "chevre", "comte", "gruyere", "parmesan", "ricotta", "tofu", "pate feuilletee", "pate brisee", "cabillaud", "crevette",
            "escalope", "merguez", "chorizo",
            "ribs", "travers", "cote", "bacon", "filet", "roti", "cuisse", "aiguillette", "nugget", "cordon bleu",
            "veau", "agneau", "canard", "gigot", "blanc de poulet", "escargot",
        ]],
    ["Fruits et légumes", [
            "banane", "pomme", "poire", "orange", "citron", "tomate", "salade", "carotte", "oignon", "ail", "pomme de terre", "patate",
            "courgette", "poivron", "champignon", "avocat", "fraise", "raisin", "legume", "fruit", "echalote", "concombre", "poireau",
            "epinard", "brocoli", "chou", "kiwi", "melon", "persil", "basilic", "coriandre", "aubergine", "clementine", "mandarine",
            "peche", "abricot", "ananas", "mangue", "radis", "navet", "betterave", "haricot vert", "petit pois", "mache", "roquette",
            "gingembre", "menthe", "framboise", "myrtille", "cerise", "prune",
        ]],
    ["Épicerie", [
            "pate", "pates", "riz", "farine", "sucre", "sel", "poivre", "huile", "vinaigre", "thon", "sardine", "cafe", "the",
            "cereale", "biscuit", "chocolat", "confiture", "miel", "pain", "lentille", "semoule", "epice", "moutarde", "ketchup",
            "mayonnaise", "gateau", "chips", "quinoa", "boulgour", "pois chiche", "haricot", "flocon", "avoine", "muesli", "levure",
            "cacao", "noix", "amande", "noisette", "olive", "cornichon", "bonbon", "nouille", "spaghetti", "tagliatelle", "farfalle",
            "penne", "coquillette", "vermicelle", "couscous", "galette", "cracker", "tortilla", "brioche", "madeleine", "croquette",
        ]],
];
/** Minuscules, sans accents, « œ » → « oe », mots séparés par un espace. */
function foldWords(s) {
    return s
        .toLowerCase()
        .replace(/œ/g, "oe")
        .replace(/æ/g, "ae")
        .normalize("NFD")
        .replace(/[̀-ͯ]/g, "")
        .replace(/[^a-z0-9]+/g, " ")
        .trim();
}
const sameWord = (t, kw) => t === kw || t === `${kw}s` || t === `${kw}x`;
function hasPhrase(tokens, kw) {
    for (let i = 0; i + kw.length <= tokens.length; i++) {
        if (kw.every((w, j) => sameWord(tokens[i + j], w)))
            return true;
    }
    return false;
}
/** Le rayon deviné d'un produit par ses mots ; null si rien ne le reconnaît. */
function guessAisle(label) {
    const tokens = foldWords(label).split(" ").filter(Boolean);
    if (!tokens.length)
        return null;
    for (const [aisle, words] of exports.AISLE_KEYWORDS) {
        for (const w of words)
            if (hasPhrase(tokens, w.split(" ")))
                return aisle;
    }
    return null;
}
/** Un rayon connu par son nom (sans accents ni casse) ; null sinon. */
function resolveAisle(input, aisles) {
    var _a;
    if (!input)
        return null;
    const f = foldWords(input);
    return (_a = aisles.find((a) => foldWords(a) === f)) !== null && _a !== void 0 ? _a : null;
}
/** Le rayon d'un produit : retenu pour le mot, sinon placard, sinon deviné, sinon Autre. */
function aisleFor(label, memory, pantry) {
    var _a, _b, _c, _d, _e;
    const k = (0, groceries_1.groceryKey)(label);
    return (_e = (_d = (_b = (_a = memory[k]) === null || _a === void 0 ? void 0 : _a.aisle) !== null && _b !== void 0 ? _b : (_c = pantry[k]) === null || _c === void 0 ? void 0 : _c.aisle) !== null && _d !== void 0 ? _d : guessAisle(label)) !== null && _e !== void 0 ? _e : exports.OTHER_AISLE;
}
exports.STATE_LABEL = { have: "j'en ai", low: "bientôt fini", out: "plus rien" };
function parseState(s) {
    const f = typeof s === "string" ? foldWords(s) : "";
    if (["have", "j en ai", "en stock", "ok", "plein"].includes(f))
        return "have";
    if (["low", "bientot fini", "presque fini", "peu"].includes(f))
        return "low";
    if (["out", "plus rien", "fini", "vide", "epuise"].includes(f))
        return "out";
    return null;
}
/** Le placard en texte, par rayon, avec l'état et ce qui est habituel. */
function pantryText(pantry, aisles, opts = {}) {
    const all = Object.values(pantry).filter((p) => (!opts.aisle || p.aisle === opts.aisle) && (!opts.state || p.state === opts.state));
    if (!all.length) {
        return Object.keys(pantry).length
            ? "Rien ne correspond dans les placards."
            : "Placards vides. Ils se remplissent avec les tickets de caisse (record_receipt) ou update_pantry.";
    }
    const by = new Map();
    for (const p of all) {
        if (!by.has(p.aisle))
            by.set(p.aisle, []);
        by.get(p.aisle).push(p);
    }
    const order = [...aisles.filter((a) => by.has(a)), ...[...by.keys()].filter((a) => !aisles.includes(a))];
    const n = (s) => all.filter((p) => p.state === s).length;
    const out = [`Mes placards : ${all.length} produit(s) · ${n("have")} en stock · ${n("low")} bientôt fini · ${n("out")} plus rien.`];
    for (const a of order) {
        out.push(`\n${a.toUpperCase()}`);
        for (const p of by.get(a).sort((x, y) => x.label.localeCompare(y.label, "fr"))) {
            const mark = p.state === "have" ? "✓" : p.state === "low" ? "!" : "✕";
            out.push(`${mark} ${p.label} — ${exports.STATE_LABEL[p.state]}${p.staple ? " · habituel" : ""}${p.boughtAt ? ` · acheté le ${p.boughtAt}` : ""}`);
        }
    }
    out.push("\n(« Bientôt fini » et « Plus rien » sont proposés sur la liste de courses dans l'app.)");
    return out.join("\n");
}
function moveAisle(st, from, to) {
    const mapVals = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, v.aisle === from ? Object.assign(Object.assign({}, v), { aisle: to }) : v]));
    return { aisles: st.aisles, pantry: mapVals(st.pantry), items: mapVals(st.items), memory: mapVals(st.memory) };
}
/** Ajoute un rayon (avant « Autre ») ; inchangé s'il existe déjà. */
function addAisle(aisles, name) {
    const n = name.trim();
    if (!n || aisles.some((a) => foldWords(a) === foldWords(n)))
        return aisles;
    const list = [...aisles];
    const i = list.indexOf(exports.OTHER_AISLE);
    if (i < 0)
        list.push(n);
    else
        list.splice(i, 0, n);
    return list;
}
/** Renomme un rayon partout ; le nom existant = fusion. */
function renameAisle(st, from, to) {
    const n = to.trim();
    if (!n || from === n || !st.aisles.includes(from))
        return st;
    const aisles = st.aisles.includes(n) ? st.aisles.filter((a) => a !== from) : st.aisles.map((a) => (a === from ? n : a));
    return moveAisle(Object.assign(Object.assign({}, st), { aisles }), from, n);
}
/** Retire un rayon : ses produits passent dans « Autre ». */
function removeAisle(st, name) {
    if (name === exports.OTHER_AISLE || !st.aisles.includes(name))
        return st;
    const aisles = st.aisles.filter((a) => a !== name);
    if (!aisles.includes(exports.OTHER_AISLE))
        aisles.push(exports.OTHER_AISLE);
    return moveAisle(Object.assign(Object.assign({}, st), { aisles }), name, exports.OTHER_AISLE);
}
/** Répartit un montant entre les rayons de ses lignes, au poids des prix ; somme juste. */
function aisleSplit(lines) {
    var _a;
    const out = {};
    for (const l of lines)
        out[l.aisle] = ((_a = out[l.aisle]) !== null && _a !== void 0 ? _a : 0) + l.cents;
    return out;
}
//# sourceMappingURL=pantry.js.map