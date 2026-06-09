import 'package:flutter/material.dart';

/// Couleur or de la monnaie (pièces d'or) — partagée par toute l'UID gamifiée.
const kGoldColor = Color(0xFFD4A017);

/// Pièce d'or — remplace l'emoji 🪙 (qui rend « argent ») par une vraie pièce
/// dorée à la couleur contrôlée. À utiliser comme widget autonome.
class GoldIcon extends StatelessWidget {
  final double size;
  final Color? color;
  const GoldIcon({super.key, this.size = 14, this.color});

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.monetization_on, size: size, color: color ?? kGoldColor);
}

/// Pièce d'or à insérer DANS un `Text.rich`/`RichText` (contexte texte).
/// Ex : `Text.rich(TextSpan(children: [TextSpan(text: '−5'), goldIconSpan()]))`.
WidgetSpan goldIconSpan({double size = 14}) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Icon(Icons.monetization_on, size: size, color: kGoldColor),
      ),
    );

/// Montant + pièce d'or : « 1240 ◉ ». [color] colore le texte (la pièce reste or).
Widget goldAmount(String text,
    {double fontSize = 13, FontWeight? weight, Color? color}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(text,
          style:
              TextStyle(fontSize: fontSize, fontWeight: weight, color: color)),
      const SizedBox(width: 3),
      GoldIcon(size: fontSize + 1),
    ],
  );
}
