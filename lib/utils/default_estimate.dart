/// Estimation par défaut d'une action à sa création (brief 2026-10, § 2.4),
/// miroir de `functions/src/default_estimates.ts` : quand l'utilisateur tape
/// juste un titre, on déduit une durée plausible du verbe / de l'objet
/// (imprimer 10, fiche de séquence 15, corriger 45…). Null = pas de règle
/// (l'app compte alors 45 min). Garder les deux listes alignées.

String _norm(String s) {
  const from = 'àâäéèêëîïôöùûüç';
  const to = 'aaaeeeeiioouuuc';
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

class _Rule {
  final RegExp test;
  final int min;
  const _Rule(this.test, this.min);
}

final List<_Rule> _rules = [
  _Rule(RegExp(r'\bderouler\b'), 0),
  _Rule(RegExp(r'\b(imprimer|impression|photocopi)'), 10),
  _Rule(RegExp(r'adapter au bilan|reprendre le non[- ]fait|reprendre le bilan'), 15),
  _Rule(RegExp(r'fiche de sequence'), 15),
  _Rule(RegExp(r'\b(corriger|correction)\b'), 45),
  _Rule(RegExp(r'\b(saisir|reporter|noter)\b.*\b(notes?|ligues?|resultats?)\b'), 10),
  _Rule(RegExp(r'\bnoter (le report|ce qui)'), 5),
  _Rule(RegExp(r'\b(deposer|envoyer|poster|publier|transmettre)\b'), 5),
  _Rule(RegExp(r'\b(relire|verifier|checker)\b'), 10),
  _Rule(RegExp(r'\bkahoot\b'), 20),
  _Rule(RegExp(r'\b(appeler|telephoner|rappeler|mail|courriel|message|ecrire a)\b'), 10),
  _Rule(RegExp(r'\b(rediger|creer|produire|concevoir|preparer|construire|elaborer|definir)\b'), 45),
  _Rule(RegExp(r'\b(ranger|classer|archiver|nettoyer)\b'), 15),
];

/// Minutes par défaut pour [title] (et ses contextes), ou null.
int? defaultEstimateFor(String title, {Iterable<String> contexts = const []}) {
  final t = _norm(title);
  if (t.trim().isEmpty) return null;
  if (contexts.any((c) => _norm(c) == '@impression')) return 10;
  for (final r in _rules) {
    if (r.test.hasMatch(t)) return r.min > 0 ? r.min : null;
  }
  return null;
}
