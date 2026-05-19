#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const TOKEN = process.env.PRODUCTIVITWO_TOKEN;
const UID   = process.env.PRODUCTIVITWO_UID;
const API_URL = process.env.PRODUCTIVITWO_API_URL
  || "https://pushgantt-dzos75b65q-uc.a.run.app";

if (!TOKEN || !UID) {
  process.stderr.write(
    "Productivitwo MCP: PRODUCTIVITWO_TOKEN et PRODUCTIVITWO_UID sont requis.\n"
  );
  process.exit(1);
}

// ── Définition de l'outil ─────────────────────────────────────────────────────

const PUSH_GANTT_TOOL = {
  name: "push_gantt",
  description:
    "Crée ou met à jour un projet Gantt dans Productivitwo. " +
    "Utilise cet outil quand l'utilisateur veut planifier un projet, " +
    "une roadmap, une campagne ou tout travail avec des étapes dans le temps.",
  inputSchema: {
    type: "object",
    required: ["project"],
    properties: {
      project: {
        type: "object",
        required: ["title", "startDate"],
        description: "Le projet Gantt complet",
        properties: {
          title:       { type: "string" },
          description: { type: "string" },
          startDate:   { type: "string", description: "ISO date YYYY-MM-DD" },
          endDate:     { type: "string", description: "ISO date YYYY-MM-DD" },
          phases: {
            type: "array",
            description: "Phases du projet (Pré-lancement, Mois 1…)",
            items: {
              type: "object",
              required: ["label", "startDate", "endDate"],
              properties: {
                label:     { type: "string" },
                color:     { type: "string", description: "Couleur hex #RRGGBB" },
                startDate: { type: "string" },
                endDate:   { type: "string" },
              },
            },
          },
          tasks: {
            type: "array",
            items: {
              type: "object",
              required: ["title", "startDate"],
              properties: {
                title:        { type: "string" },
                groupLabel:   { type: "string", description: "Catégorie (ex: ASO, Réseaux, Acquisition)" },
                startDate:    { type: "string" },
                endDate:      { type: "string" },
                isMilestone:  { type: "boolean", description: "Jalon = startDate==endDate" },
                color:        { type: "string" },
                barLabel:     { type: "string", description: "Étiquette courte (≤3 mots)" },
                status:       { type: "string", enum: ["pending", "done", "skipped"] },
              },
            },
          },
        },
      },
      strategicObjective: {
        type: "object",
        description: "Objectif stratégique de haut niveau",
        properties: {
          title:        { type: "string" },
          kpiTarget:    { type: "string", description: "Ex: MRR 500€, 100 utilisateurs" },
          horizonLabel: { type: "string", description: "Ex: 3 mois, Q2 2026" },
        },
      },
    },
  },
};

// ── Serveur MCP ───────────────────────────────────────────────────────────────

const server = new Server(
  { name: "productivitwo", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [PUSH_GANTT_TOOL],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  if (request.params.name !== "push_gantt") {
    return { content: [{ type: "text", text: "Outil inconnu." }], isError: true };
  }

  const input = request.params.arguments;

  try {
    const body = {
      uid: UID,
      project: input.project,
      ...(input.strategicObjective ? { strategicObjective: input.strategicObjective } : {}),
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

    if (!res.ok) {
      return {
        content: [{ type: "text", text: `Erreur API (${res.status}): ${JSON.stringify(json)}` }],
        isError: true,
      };
    }

    return {
      content: [
        {
          type: "text",
          text:
            `✅ Projet Gantt créé dans Productivitwo !\n` +
            `• Titre : ${input.project.title}\n` +
            `• ${input.project.tasks?.length ?? 0} tâche(s) · ${input.project.phases?.length ?? 0} phase(s)\n` +
            `• Voir sur : https://productivitwo-app.web.app\n` +
            `• projectId : ${json.projectId}`,
        },
      ],
    };
  } catch (err) {
    return {
      content: [{ type: "text", text: `Erreur réseau : ${err.message}` }],
      isError: true,
    };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
