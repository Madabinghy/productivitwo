// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

class TinyBar extends StatelessWidget {
  final double ratio;     // 0..1
  final String labelLeft; // ex: "Mois 220/900m" ou "Semaine 12/35"
  final EdgeInsets padding;
  const TinyBar({
    super.key,
    required this.ratio,
    required this.labelLeft,
    this.padding = const EdgeInsets.only(top: 4),
  });

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.onSurface.withOpacity(.12);
    Color color;
    if (ratio >= 1) color = Colors.green;
    else if (ratio >= .5) color = const Color(0xFFFFA000);
    else color = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: padding,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 15,
              color: color,
              backgroundColor: track,
            ),
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              labelLeft,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}