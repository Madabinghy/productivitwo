import 'package:flutter/material.dart';

/// Dialog desktop centrée (lot 1b) : remplace les bottom sheets mobiles sur
/// le web — largeur bornée, hauteur ≤ 85 % de l'écran, coins arrondis.
Future<T?> showDesktopDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 680,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) {
      final size = MediaQuery.of(ctx).size;
      return Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: (size.height * .85).clamp(320.0, 760.0),
          ),
          child: builder(ctx),
        ),
      );
    },
  );
}
