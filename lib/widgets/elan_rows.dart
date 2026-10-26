import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/models.dart';

/// Les trois pointages de l'état (design « Badges Productivitwo », section
/// Élan) : un tap, jamais bloquant, « × » toujours là. Couleurs de la rampe
/// d'élan : une seule teinte, lue à la clarté (jamais de rouge sur la flemme).
const kElanColors = [
  Color(0xFF35453C), // 1 Flemme (index 0 inutilisé → décalage ci-dessous)
  Color(0xFF35453C),
  Color(0xFF4C6555),
  Color(0xFF5E8A6F),
  Color(0xFF27C48F),
  Color(0xFF8FE3C3),
];

Color elanColor(int value) => kElanColors[value.clamp(1, 5)];

class ElanRow extends StatelessWidget {
  final int value; // 0 = rien
  final ValueChanged<int> onPick;
  final VoidCallback? onSkip;
  final String question;
  final String? context;
  final bool compact;
  final Color text, text2, text3, surface, raised;

  const ElanRow({
    super.key,
    required this.value,
    required this.onPick,
    this.onSkip,
    this.question = 'Ton élan, là ?',
    this.context,
    this.compact = false,
    required this.text,
    required this.text2,
    required this.text3,
    required this.surface,
    required this.raised,
  });

  @override
  Widget build(BuildContext ctx) {
    final pips = Row(children: [
      for (var i = 1; i <= 5; i++)
        Expanded(
          child: Semantics(
            button: true,
            selected: value == i,
            label: kElanLabels[i],
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                HapticFeedback.selectionClick();
                onPick(i);
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: compact ? 2 : 6),
                decoration: BoxDecoration(
                  color: value == i ? raised : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: compact ? 22 : 26,
                    height: compact ? 22 : 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: elanColor(i).withValues(alpha: value == i ? 1 : .55),
                      border: value == i ? Border.all(color: text2, width: 2) : null,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 5),
                    Text(kElanLabels[i], style: TextStyle(fontSize: 11, color: value == i ? text : text3)),
                  ],
                ]),
              ),
            ),
          ),
        ),
    ]);
    if (compact) return pips;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(question, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: text)),
          if (context != null) ...[
            const SizedBox(width: 8),
            Expanded(child: Text(context!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: text3))),
          ] else
            const Spacer(),
          if (onSkip != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Passer',
              onPressed: onSkip,
              icon: Icon(Icons.close, size: 18, color: text3),
            ),
        ]),
        const SizedBox(height: 4),
        pips,
      ]),
    );
  }
}

/// « C'était ? Facile · Juste · Dur » ou « Ton humeur aujourd'hui ? Bas ·
/// Neutre · Bon » : trois puces, une sélection.
class ChipRow extends StatelessWidget {
  final String question;
  final List<String> labels;
  final int value; // -1 = rien
  final ValueChanged<int> onPick;
  final Color text, text2, text3, surface, raised, accent;
  final String? context;

  const ChipRow({
    super.key,
    required this.question,
    required this.labels,
    required this.value,
    required this.onPick,
    this.context,
    required this.text,
    required this.text2,
    required this.text3,
    required this.surface,
    required this.raised,
    required this.accent,
  });

  @override
  Widget build(BuildContext ctx) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: question, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: text)),
            if (context != null) TextSpan(text: '  ${context!}', style: TextStyle(fontSize: 13, color: text3)),
          ])),
        ),
        const SizedBox(width: 8),
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () {
                HapticFeedback.selectionClick();
                onPick(i);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: value == i ? raised : null,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: value == i ? accent : text3.withValues(alpha: .45)),
                ),
                child: Text(labels[i], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: value == i ? text : text2)),
              ),
            ),
          ),
      ]),
    );
  }
}
