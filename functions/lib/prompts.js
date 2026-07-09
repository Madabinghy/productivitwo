"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MCP_PROMPTS = void 0;
exports.defineDomainSystemPrompt = defineDomainSystemPrompt;
exports.getPromptMessages = getPromptMessages;
exports.executeGetDocumentTemplate = executeGetDocumentTemplate;
const today = () => new Date().toISOString().split("T")[0];
exports.MCP_PROMPTS = [
    {
        name: "programme-du-jour",
        description: "Crée mon programme personnalisé pour aujourd'hui ou une date donnée",
        arguments: [
            { name: "date", description: "Date YYYY-MM-DD (défaut: aujourd'hui)", required: false },
        ],
    },
    {
        name: "bilan-semaine",
        description: "Bilan de la semaine : réalisé, écarts, ajustements suggérés",
        arguments: [],
    },
    {
        name: "aligner-gantt",
        description: "Aligne mon planning des prochains jours avec mes projets Gantt actifs",
        arguments: [],
    },
    {
        name: "definir-domaine",
        description: "Session de définition d'un domaine : intention, minimum vital, modalités (15-20 min, une fois)",
        arguments: [
            { name: "domaine", description: "Nom du domaine (ex: Santé)", required: false },
        ],
    },
];
// ── Prompt système de la session de définition (workflow define_domain) ──────
// Utilisé par la Cloud Function defineDomainChat ET par le prompt MCP
// definir-domaine. Moment fondateur : conversation, pas formulaire ; chaque
// élément validé est ÉCRIT via save_domain_definition (fait structuré, jamais
// un souvenir de chat).
function defineDomainSystemPrompt(domainName, dossier) {
    const base = [
        `Tu es Orion, coach de Productivitwo, en SESSION DE DÉFINITION du domaine « ${domainName} » (15-20 min, une fois).`,
        `Une vraie conversation, pas un formulaire. Tu creuses jusqu'à tenir une intention qui ressemble à l'utilisateur — puis tu la rends exécutable.`,
        ``,
        `LES 3 PHASES, DANS L'ORDRE (annonce la progression : « 2/3 · minimum vital ») :`,
        `1. L'INTENTION — creuse le concret (« qu'est-ce que ça changerait, un mardi soir de semaine chargée ? »). Quand tu tiens une formulation DANS SES MOTS, propose-la entre guillemets et demande validation (« On la garde ? »). Jamais du jargon de coach.`,
        `2. LE MINIMUM VITAL — le plancher sous lequel on ne descend pas. Chaque élément doit être MESURABLE et vérifiable par les données (séances/sem, repas cuisinés, heure de coucher). Ce qui n'est pas mesurable n'entre pas dans la fiche.`,
        `3. LES MODALITÉS & ARTEFACTS — créneaux et fréquences concrets (ex: « séances le matin 7h15, prep la veille »), puis la liste des artefacts à générer ensuite (plan, menu…). Tu n'écris PAS les artefacts eux-mêmes ici.`,
        ``,
        `RÈGLES STRICTES :`,
        `- À CHAQUE élément validé par l'utilisateur, appelle save_domain_definition (name: "${domainName}", + le champ validé). La fiche doit refléter l'état réel à tout moment — « reprendre plus tard » doit être gratuit. N'attends JAMAIS la fin pour écrire.`,
        `- L'intention est citée telle quelle, dans SES mots — tu ne la reformules jamais après validation.`,
        `- Chiffres réels uniquement ; ne pré-remplis rien, tout vient de la conversation.`,
        `- En fin de session (3 éléments validés), rappelle save_domain_definition avec finalize:true, puis conclus en une phrase : ce que tu en feras chaque jour.`,
        `- Messages courts (2-4 phrases), une question à la fois, en français, tutoiement.`,
    ];
    // ── Domaine VIVANT (19) : tu ne pars pas de zéro — le dossier fait foi ──────
    if ((dossier === null || dossier === void 0 ? void 0 : dossier.mode) === "vivant" && dossier.text) {
        base.push(``, `── LE DOSSIER — LES FAITS (6 dernières semaines, agrégats réels) ──`, dossier.text, ``, `RÈGLES DOMAINE VIVANT :`, `- Ouvre en montrant que tu connais le dossier : « ici je ne pars pas de zéro — je te regarde travailler ». Cite 1-2 chiffres du dossier, pas plus.`, `- En phase intention, si l'écart entre ce qu'il déclare et les heures réelles est massif (ex: beaucoup d'heures sur un axe, 0 sur celui qu'il dit vouloir), tu DOIS confronter : cite les deux chiffres, puis propose DEUX lectures possibles — les deux valables — et laisse-le choisir laquelle est vraie. Celle qu'il choisit, tu la défendras.`, `- Les artefacts existants du dossier sont ADOPTÉS : référence-les dans le vital/les modalités (« ses blocs comptent désormais dans… »), ne propose JAMAIS de les régénérer.`, `- Clos la session sur un changement CONCRET dès demain (un bloc, une règle) — pas une résolution.`);
    }
    // ── Domaine SANS DONNÉES (20) : le vide est le point de départ ──────────────
    if ((dossier === null || dossier === void 0 ? void 0 : dossier.mode) === "vide") {
        base.push(``, ...(dossier.text
            ? [`── CE QU'ON VOIT EN CREUX (le domaine est vide, mais autour :) ──`, dossier.text, ``]
            : []), `RÈGLES DOMAINE SANS DONNÉES :`, `- Ouvre sur le vide lui-même : « pas une heure, pas un bloc — ce vide ne veut pas dire que ce domaine va bien, c'est la première chose à regarder ». Utilise les faits en creux s'il y en a.`, `- REFUSE le vœu pieux : un vœu ne survit pas à un mardi chargé. Pousse vers un plancher MINUSCULE (« en dessous de quoi, dans un mois, tu te diras "j'ai raté quelque chose" ? »).`, `- DÉCIDE AUSSI CE QU'ON NE MESURE PAS : propose tracking:"declared" — pas de chrono, pas de blocs, pas de score ; le vital sera demandé en 1-2 questions binaires au rapport du dimanche, c'est tout. Écris-le via save_domain_definition (tracking:"declared") si l'utilisateur valide.`, `- Propose un TERRITOIRE DÉFENDU : protectedSlots (codes "{mon|tue|wed|thu|fri|sat|sun}_{morning|afternoon|evening|day}", ex: ["fri_evening","sat_evening","sun_day"]) — contrainte DURE : la proposition n'y posera jamais un bloc, quel que soit le retard ailleurs ; y travailler devient une renégociation explicite, plus jamais silencieuse.`, `- Une seule promesse : on n'instrumente pas sa vie privée — on décide ce qui est non négociable, et tu le défendras contre les autres domaines.`);
    }
    return base.join("\n");
}
function getPromptMessages(name, args) {
    const date = args.date || today();
    if (name === "programme-du-jour") {
        return [
            {
                role: "user",
                content: {
                    type: "text",
                    text: `Crée mon programme pour le ${date}.\n\n` +
                        `Annonce-moi d'abord : "Je prépare ton programme — ça prend environ 1-2 min. Je t'envoie une notification dès que c'est prêt."\n\n` +
                        `Étapes à suivre dans l'ordre :\n` +
                        `1. Appelle get_user_context pour connaître mes objectifs et ce que j'ai fait cette semaine.\n` +
                        `2. Appelle get_day_blocks pour connaître mes blocs de journée.\n` +
                        `3. Appelle get_day_schedule(${date}) pour voir ce qui est déjà prévu.\n` +
                        `4. Appelle list_events (Google Calendar) pour voir mes rendez-vous existants.\n` +
                        `5. Crée un programme cohérent avec schedule_day :\n` +
                        `   - Respecte mes blocs\n` +
                        `   - Priorise les tâches Gantt en retard\n` +
                        `   - Commente les actions non faites de la semaine si pertinent\n` +
                        `6. Demande-moi : "Veux-tu que j'intègre des créneaux dans ton agenda Google Calendar ?"\n` +
                        `   - Si oui : identifie les créneaux libres, propose-les clairement, puis appelle create_event après validation.\n` +
                        `   - Si non : passe à l'étape suivante.\n` +
                        `7. Génère le document HTML du programme avec save_document (utilise get_document_template si besoin).\n` +
                        `8. Envoie-moi une notification push_notification : "Programme du ${date} prêt ✅"`,
                },
            },
        ];
    }
    if (name === "bilan-semaine") {
        return [
            {
                role: "user",
                content: {
                    type: "text",
                    text: `Fais mon bilan de la semaine.\n\n` +
                        `1. Appelle get_user_context — analyse recentActivity en détail :\n` +
                        `   - Qu'est-ce que j'ai accompli (completedActions) ?\n` +
                        `   - Qu'est-ce que j'avais prévu mais pas fait (pendingActions) ?\n` +
                        `   - Quelles habitudes sont en dessous de leur cible (habitCompletion) ?\n` +
                        `   - Quelles activités manquent de temps loggué vs objectif (timeLogged) ?\n` +
                        `2. Appelle list_projects pour voir l'état des Gantts actifs.\n` +
                        `3. Présente un bilan structuré : ce qui va bien, ce qui bloque, 3 actions prioritaires pour la semaine prochaine.\n` +
                        `4. Propose des ajustements concrets (update_activity_goal si un objectif est irréaliste).`,
                },
            },
        ];
    }
    if (name === "aligner-gantt") {
        return [
            {
                role: "user",
                content: {
                    type: "text",
                    text: `Aligne mon planning des prochains jours avec mes projets Gantt.\n\n` +
                        `Annonce-moi d'abord : "Je fais le point sur tes Gantts — ça prend environ 1-2 min. Je t'envoie une notification dès que c'est prêt."\n\n` +
                        `1. Appelle get_user_context.\n` +
                        `2. Appelle list_projects puis get_project pour chaque projet actif.\n` +
                        `3. Identifie les tâches Gantt :\n` +
                        `   - En retard (endDate dépassée, status != done)\n` +
                        `   - À venir dans les 7 prochains jours\n` +
                        `   - Des jalons proches\n` +
                        `4. Pour chaque tâche urgente, propose de la planifier via plan_day sur les prochains jours.\n` +
                        `5. Si une tâche Gantt devrait générer des routines régulières, propose create_routine.\n` +
                        `6. Pour chaque projet modifié (push_gantt, update_project, update_task_status) :\n` +
                        `   - Appelle get_documents(projectId) pour voir si un programme HTML existe.\n` +
                        `   - Si oui, mets-le à jour avec save_document en passant son documentId (évite les doublons).\n` +
                        `   - Si non, propose-moi de le créer.\n` +
                        `7. Envoie-moi une notification push_notification : "Gantts alignés ✅"`,
                },
            },
        ];
    }
    if (name === "definir-domaine") {
        const domain = args.domaine || "à choisir ensemble";
        return [
            {
                role: "user",
                content: {
                    type: "text",
                    text: `Session de définition du domaine « ${domain} ».\n\n` +
                        defineDomainSystemPrompt(domain) +
                        `\n\nCommence par le contrat : « Une vraie conversation, pas un formulaire. Je vais creuser ` +
                        `jusqu'à ce qu'on tienne une intention qui te ressemble — puis on la rendra exécutable. ` +
                        `Tout ce qu'on décide est écrit et me servira chaque jour. » Puis lance la phase 1.`,
                },
            },
        ];
    }
    return [];
}
function executeGetDocumentTemplate() {
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
//# sourceMappingURL=prompts.js.map