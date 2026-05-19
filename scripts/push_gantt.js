#!/usr/bin/env node
/**
 * push_gantt.js
 *
 * Génère un Gantt Productivitwo depuis une description en langage naturel
 * en utilisant Claude, puis le pousse via l'API pushGantt.
 *
 * Usage :
 *   ANTHROPIC_API_KEY=sk-... \
 *   PRODUCTIVITWO_TOKEN=<token> \
 *   PRODUCTIVITWO_UID=<uid> \
 *   node push_gantt.js "Lance une campagne marketing de 3 mois pour Productivitwo"
 *
 * Variables d'environnement :
 *   ANTHROPIC_API_KEY       Clé API Anthropic
 *   PRODUCTIVITWO_TOKEN     Token généré dans l'app (section Tokens API)
 *   PRODUCTIVITWO_UID       Ton Firebase UID (visible dans l'app web)
 *   PRODUCTIVITWO_API_URL   (optionnel) URL de la Cloud Function
 */

import Anthropic from "@anthropic-ai/sdk";

const API_URL =
  process.env.PRODUCTIVITWO_API_URL ||
  "https://pushgantt-dzos75b65q-uc.a.run.app";

const TOKEN = process.env.PRODUCTIVITWO_TOKEN;
const UID = process.env.PRODUCTIVITWO_UID;

if (!TOKEN || !UID) {
  console.error(
    "❌  PRODUCTIVITWO_TOKEN et PRODUCTIVITWO_UID sont requis.\n" +
      "    Génère un token dans l'app web (icône clé 🔑) et récupère ton UID."
  );
  process.exit(1);
}

const userMessage = process.argv.slice(2).join(" ");
if (!userMessage) {
  console.error(
    '❌  Donne une description du projet. Ex:\n' +
      '    node push_gantt.js "Roadmap marketing pré-lancement + 3 mois"'
  );
  process.exit(1);
}

// ── Outil push_gantt ──────────────────────────────────────────────────────────

const PUSH_GANTT_TOOL = {
  name: "push_gantt",
  description:
    "Pousse un projet Gantt dans Productivitwo. Appelle cet outil une seule fois " +
    "avec le projet complet une fois que tu as fini de le construire.",
  input_schema: {
    type: "object",
    required: ["project"],
    properties: {
      project: {
        type: "object",
        required: ["title", "startDate"],
        properties: {
          title: { type: "string", description: "Titre du projet" },
          description: { type: "string" },
          startDate: { type: "string", description: "Date de début ISO (YYYY-MM-DD)" },
          endDate: { type: "string", description: "Date de fin ISO (YYYY-MM-DD)" },
          phases: {
            type: "array",
            description: "Phases du projet (ex: Pré-lancement, Mois 1…)",
            items: {
              type: "object",
              required: ["label", "startDate", "endDate"],
              properties: {
                id: { type: "string" },
                label: { type: "string" },
                color: { type: "string", description: "Couleur hex de fond (#RRGGBB)" },
                startDate: { type: "string" },
                endDate: { type: "string" },
              },
            },
          },
          tasks: {
            type: "array",
            items: {
              type: "object",
              required: ["title", "startDate"],
              properties: {
                id: { type: "string" },
                title: { type: "string" },
                groupLabel: {
                  type: "string",
                  description: "Groupe/catégorie affiché comme séparateur (ex: ASO, Réseaux sociaux)",
                },
                startDate: { type: "string" },
                endDate: { type: "string" },
                isMilestone: {
                  type: "boolean",
                  description: "true pour un jalon (diamant). Dans ce cas startDate == endDate.",
                },
                color: { type: "string", description: "Couleur hex de la barre (#RRGGBB)" },
                barLabel: {
                  type: "string",
                  description: "Étiquette courte affichée dans la barre (max 3 mots)",
                },
                status: { type: "string", enum: ["pending", "done", "skipped"] },
              },
            },
          },
        },
      },
      strategicObjective: {
        type: "object",
        description: "Objectif stratégique de haut niveau lié au projet",
        properties: {
          title: { type: "string" },
          kpiTarget: { type: "string", description: "KPI mesurable (ex: MRR 500€, 100 users)" },
          horizonLabel: { type: "string", description: "Horizon temporel (ex: 3 mois, Q2 2026)" },
        },
      },
    },
  },
};

// ── Prompt système ────────────────────────────────────────────────────────────

const today = new Date().toISOString().split("T")[0];

const SYSTEM_PROMPT = `Tu es un assistant de gestion de projet pour Productivitwo, une app de productivité iOS et web.
Ta mission : convertir une description en langage naturel en un diagramme de Gantt structuré, puis le pousser via l'outil push_gantt.

## Date d'aujourd'hui
${today}

## Règles de construction du Gantt

### Phases
- Découpe le projet en phases logiques (Pré-lancement, Mois 1, Mois 2…)
- Assigne une couleur pastel harmonieuse à chaque phase :
  - Violet clair : #EEEDFE  |  Vert clair : #E1F5EE
  - Orange clair : #FAEEDA  |  Rose clair : #FAECE7
  - Bleu clair   : #E3F2FD

### Tâches
- Groupe les tâches avec groupLabel (ex: "ASO", "Réseaux sociaux", "Acquisition", "Contenu", "Jalons")
- Utilise un barLabel court (≤3 mots) visible dans la barre
- Couleurs suggérées selon le type :
  - Pré-lancement / setup : #AFA9EC
  - Canaux sociaux actifs  : #1D9E75
  - Canaux sociaux légers  : #9FE1CB
  - Contenu & SEO          : #EF9F27
  - Partenariats           : #F0997B
  - Actions ponctuelles    : #5DCAA5

### Jalons (isMilestone: true)
- Crée des jalons pour les objectifs clés mesurables (ex: "50 payants", "Lancement Product Hunt")
- startDate == endDate pour un jalon
- Place-les dans le groupe "Jalons"

### Objectif stratégique
- Synthétise en un kpiTarget mesurable (ex: "MRR 500€", "100 utilisateurs actifs")

## Important
- Appelle push_gantt une seule fois avec le projet complet.
- Ne génère pas de JSON brut dans le texte, utilise directement l'outil.
- Adapte la granularité au contexte (semaines pour <1 mois, mois pour >3 mois).`;

// ── Exécution ─────────────────────────────────────────────────────────────────

async function callPushGanttAPI(input) {
  const body = {
    uid: UID,
    project: input.project,
    ...(input.strategicObjective
      ? { strategicObjective: input.strategicObjective }
      : {}),
  };

  const res = await fetch(API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${TOKEN}`,
    },
    body: JSON.stringify(body),
  });

  const json = await res.json();
  if (!res.ok) throw new Error(JSON.stringify(json));
  return json;
}

async function main() {
  const client = new Anthropic();

  console.log(`\n🎯  Génération du Gantt pour : "${userMessage}"\n`);

  const messages = [{ role: "user", content: userMessage }];

  // Boucle agentique (tool use loop)
  while (true) {
    const response = await client.messages.create({
      model: "claude-opus-4-7",
      max_tokens: 4096,
      system: SYSTEM_PROMPT,
      tools: [PUSH_GANTT_TOOL],
      messages,
    });

    // Afficher le texte de réflexion de Claude si présent
    for (const block of response.content) {
      if (block.type === "text" && block.text.trim()) {
        console.log("💭 ", block.text.trim(), "\n");
      }
    }

    if (response.stop_reason === "end_turn") break;

    if (response.stop_reason === "tool_use") {
      const toolUse = response.content.find((b) => b.type === "tool_use");
      if (!toolUse || toolUse.name !== "push_gantt") break;

      console.log(`🔧  Appel push_gantt…`);

      messages.push({ role: "assistant", content: response.content });

      let result;
      try {
        result = await callPushGanttAPI(toolUse.input);
        console.log(`✅  Gantt créé ! projectId = ${result.projectId}`);
        console.log(`    👉  https://productivitwo-app.web.app\n`);
      } catch (err) {
        console.error("❌  Erreur API :", err.message);
        result = { error: err.message };
      }

      messages.push({
        role: "user",
        content: [{ type: "tool_result", tool_use_id: toolUse.id, content: JSON.stringify(result) }],
      });

      // Récupérer la réponse finale de Claude
      const finalResponse = await client.messages.create({
        model: "claude-opus-4-7",
        max_tokens: 1024,
        system: SYSTEM_PROMPT,
        tools: [PUSH_GANTT_TOOL],
        messages,
      });

      for (const block of finalResponse.content) {
        if (block.type === "text" && block.text.trim()) {
          console.log("🤖 ", block.text.trim());
        }
      }
      break;
    }
  }
}

main().catch((err) => {
  console.error("❌ ", err.message);
  process.exit(1);
});
