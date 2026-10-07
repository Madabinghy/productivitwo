import test from "node:test";
import assert from "node:assert/strict";
import { defaultEstimateFor, defaultEstimateLabel } from "../lib/default_estimates.js";

test("règles par verbe / objet, insensibles aux accents", () => {
  assert.equal(defaultEstimateFor("Imprimer à l'école : contrôle CM1 + fiche de séquence"), 10);
  assert.equal(defaultEstimateFor("Fiche de séquence Pages du 9 nov"), 15);
  assert.equal(defaultEstimateFor("Remplir la fiche de séquence (réalisé + bilan)"), 15);
  assert.equal(defaultEstimateFor("Corriger les copies des CM1-CM2"), 45);
  assert.equal(defaultEstimateFor("Saisir notes et ligues dans le fichier de suivi"), 10);
  assert.equal(defaultEstimateFor("Déposer la fiche sur Teams"), 5);
  assert.equal(defaultEstimateFor("Importer les images dans le Kahoot « Bilan »"), 20);
  assert.equal(defaultEstimateFor("Adapter au bilan précédent"), 15);
  assert.equal(defaultEstimateFor("Rédiger le quiz d'évaluation Séq 1 + corrigé + barème"), 45);
  assert.equal(defaultEstimateFor("Voir avec Aurélie pour les codes Pix"), null);
  assert.equal(defaultEstimateFor(""), null);
});

test("contexte @impression → 10 ; « Dérouler » → pas de défaut (durée du créneau)", () => {
  assert.equal(defaultEstimateFor("Supports", ["@impression"]), 10);
  assert.equal(defaultEstimateFor("Dérouler la séance (13h15–15h00)"), null);
  assert.equal(defaultEstimateLabel("Dérouler la séance"), null);
  assert.equal(defaultEstimateLabel("Corriger les contrôles"), "correction");
});
