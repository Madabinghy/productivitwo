import 'package:flutter/material.dart';

/// « Une liste, un seul bloc ouvert » (maquette validée 2026-10) : la ligne et
/// la carte du moment sont deux états du MÊME item. Tap = explorer (l'item
/// s'ouvre à sa place, l'autre se replie ; retoucher le bloc ouvert le
/// referme) ; aucun chrono, aucune écriture. Le bouton plein du bloc lance ;
/// les liens ouvrent une feuille. L'état ouvert / fermé est tenu par la page
/// (`OpenItem`), pour qu'un seul item soit ouvert.
class MomentItem extends StatelessWidget {
  final bool open;
  final Widget collapsed;
  final Widget expanded;
  final VoidCallback onToggle;
  final VoidCallback? onLongPress;
  const MomentItem({super.key, required this.open, required this.collapsed, required this.expanded, required this.onToggle, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        onLongPress: onLongPress,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open ? expanded : collapsed,
        ),
      ),
    );
  }
}

/// État « quel item est ouvert » d'une page : le premier du classement par
/// défaut tant que l'utilisateur n'a rien touché ; ensuite ce qu'il a choisi,
/// y compris rien. [toggle] garde la ligne touchée à la même hauteur à
/// l'écran quand un bloc au-dessus se replie.
class OpenItem {
  String? _id;
  bool _touched = false;
  final keys = <String, GlobalKey>{};

  String? current(String? defaultId) => _touched ? _id : defaultId;
  bool isOpen(String id, String? defaultId) => current(defaultId) == id;

  GlobalKey keyFor(String id) => keys.putIfAbsent(id, GlobalKey.new);

  /// À appeler dans un `setState` ; renvoie l'ajustement de défilement à
  /// appliquer après le frame (via [settle]).
  void toggle(String id, String? defaultId) {
    final now = current(defaultId);
    _touched = true;
    _id = now == id ? null : id;
  }

  double _top(String id) {
    final box = keys[id]?.currentContext?.findRenderObject() as RenderBox?;
    return box == null || !box.attached ? double.nan : box.localToGlobal(Offset.zero).dy;
  }

  /// Mesure la ligne avant le changement, puis recale le défilement après le
  /// frame pour qu'elle ne bouge pas.
  void settle(String id, ScrollController scroll, VoidCallback apply) {
    final before = _top(id);
    apply();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      final after = _top(id);
      if (before.isNaN || after.isNaN) return;
      final target = (scroll.offset + (after - before)).clamp(scroll.position.minScrollExtent, scroll.position.maxScrollExtent);
      if ((target - scroll.offset).abs() > .5) scroll.jumpTo(target);
    });
  }
}
