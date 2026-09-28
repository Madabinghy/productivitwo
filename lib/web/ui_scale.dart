import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Taille de l'interface web : zoom interne à l'app (100 · 90 · 80 %), mémorisé
// par appareil. Tout rétrécit d'un bloc (textes, hauteurs, marges), comme le
// zoom du navigateur, sans toucher aux mises en page.

const kWebUiScales = [1.0, .9, .8];
const _kPref = 'web_ui_scale';

final ValueNotifier<double> webUiScale = ValueNotifier(1.0);

Future<void> loadWebUiScale() async {
  try {
    final p = await SharedPreferences.getInstance();
    final v = p.getDouble(_kPref);
    if (v != null && kWebUiScales.contains(v)) webUiScale.value = v;
  } catch (_) {}
}

Future<void> saveWebUiScale(double v) async {
  webUiScale.value = v;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kPref, v);
  } catch (_) {}
}

/// Réduit tout l'arbre [child] à [scale] : surface logique agrandie, puis
/// remise à l'échelle. Les dialogs et menus vivent dedans (Navigator) et
/// suivent ; la `MediaQuery` annonce la taille logique agrandie.
class ScaledUi extends StatelessWidget {
  final double scale;
  final Widget child;
  const ScaledUi({super.key, required this.scale, required this.child});

  @override
  Widget build(BuildContext context) {
    if (scale == 1.0) return child;
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth / scale, h = c.maxHeight / scale;
      final mq = MediaQuery.of(ctx);
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: w,
          maxWidth: w,
          minHeight: h,
          maxHeight: h,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: MediaQuery(
              data: mq.copyWith(size: Size(w, h)),
              child: SizedBox(width: w, height: h, child: child),
            ),
          ),
        ),
      );
    });
  }
}

/// Position globale (écran) → repère de l'overlay (échelle appliquée), pour
/// ancrer popovers et menus.
Offset overlayLocal(BuildContext context, Offset global) {
  final box = Overlay.of(context).context.findRenderObject() as RenderBox?;
  return box == null ? global : box.globalToLocal(global);
}

/// Dialog « Taille de l'interface ».
Future<void> showUiScaleDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Taille de l'interface"),
      content: ValueListenableBuilder<double>(
        valueListenable: webUiScale,
        builder: (_, current, __) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Réduit toute l'interface d'un bloc, comme le zoom du navigateur : plus d'informations à l'écran sans changer les mises en page.",
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, children: [
              for (final s in kWebUiScales)
                ChoiceChip(
                  label: Text(
                      '${(s * 100).round()} %${s == .9 ? ' · compact' : s == 1.0 ? ' · confort' : ''}'),
                  selected: current == s,
                  onSelected: (_) => saveWebUiScale(s),
                ),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer')),
      ],
    ),
  );
}
