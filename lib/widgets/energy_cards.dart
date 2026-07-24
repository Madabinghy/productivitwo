import 'package:flutter/material.dart';

/// Violet du Maintenant adaptatif (24b) — mappé sur la luminosité du thème,
/// même pattern que l'ambre du mode soirée (jamais les hex web en dur ailleurs).
Color energyViolet(ColorScheme cs) => cs.brightness == Brightness.dark
    ? const Color(0xFF9F8AFF)
    : const Color(0xFF6C55D8);

/// Carte « question d'état » (maquette 24a) — remplace la carte coach.
/// 3 chips avec leur conséquence en sous-texte + note libre optionnelle.
/// 1 tap, pas de morale : la question ne bascule rien toute seule — la
/// réponse, si. Le tap écrit le fait et se suffit (pas de bouton Valider).
class EnergyQuestionCard extends StatefulWidget {
  final String message;
  final void Function(String level, String? note) onPick;
  const EnergyQuestionCard(
      {super.key, required this.message, required this.onPick});

  @override
  State<EnergyQuestionCard> createState() => _EnergyQuestionCardState();
}

class _EnergyQuestionCardState extends State<EnergyQuestionCard> {
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  void _pick(String level) {
    final note = _noteCtrl.text.trim();
    widget.onPick(level, note.isEmpty ? null : note);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final violet = energyViolet(cs);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withOpacity(.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('ORION · ÉTAT',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: cs.primary)),
            const Spacer(),
            Text('1 TAP · PAS DE MORALE',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: cs.onSurface.withOpacity(.4))),
          ]),
          const SizedBox(height: 8),
          Text(widget.message,
              style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: cs.onSurface.withOpacity(.9))),
          const SizedBox(height: 14),
          Row(children: [
            _chip(cs, 'À fond', 'on protège 2 h', cs.primary,
                () => _pick('full')),
            const SizedBox(width: 8),
            _chip(cs, 'Correct', 'on continue', cs.onSurface.withOpacity(.6),
                () => _pick('ok')),
            const SizedBox(width: 8),
            _chip(cs, 'À plat', 'une chose à la fois', violet,
                () => _pick('low')),
          ]),
          const SizedBox(height: 12),
          // Note libre : optionnelle, stockée telle quelle, ressortie au
          // check-in — aucun appel LLM à la saisie.
          TextField(
            controller: _noteCtrl,
            minLines: 1,
            maxLines: 2,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText:
                  'Qu\'est-ce que tu as en tête ? — optionnel, un mot suffit. Je le ressors au check-in.',
              hintStyle: TextStyle(
                  fontSize: 12.5, color: cs.onSurface.withOpacity(.4)),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.onSurface.withOpacity(.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.primary.withOpacity(.5)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
              'Ta réponse est un fait, pas une conversation. Je ne redemande pas avant 3 h.',
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  fontStyle: FontStyle.italic,
                  color: cs.onSurface.withOpacity(.5))),
        ],
      ),
    );
  }

  /// Cible tactile ≥ 44 px, label + conséquence en sous-texte.
  Widget _chip(ColorScheme cs, String label, String sub, Color accent,
      VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withOpacity(.5)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: accent)),
              const SizedBox(height: 2),
              Text(sub,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10.5,
                      height: 1.2,
                      color: cs.onSurface.withOpacity(.55))),
            ],
          ),
        ),
      ),
    );
  }
}
