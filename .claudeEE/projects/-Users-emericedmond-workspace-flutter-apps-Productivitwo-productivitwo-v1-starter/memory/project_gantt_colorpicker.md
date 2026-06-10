---
name: project-gantt-colorpicker
description: Color picker Gantt barres web — bug connu, fix à faire
metadata:
  type: project
---

Color picker sur les barres Gantt (web app) est implémenté mais ne fonctionne pas.

**Symptôme:** Clic sur une barre → popup s'ouvre mais les couleurs ne sont pas cliquables.

**Cause probable:** `PopupMenuItem(enabled: false)` bloque les `GestureDetector` enfants — les taps sur les swatches de couleur ne passent pas.

**Fix à faire:** Remplacer `showMenu` + `PopupMenuItem(enabled: false)` par un `OverlayEntry` ou `showDialog` positionné qui n'a pas cette limitation. Les couleurs doivent être des widgets cliquables indépendants, pas imbriqués dans un item désactivé.

**Fichier:** `lib/web/web_home_screen.dart` — méthode `_showColorPicker` dans `_FocusView`.

**How to apply:** Prochain session, refactoriser `_showColorPicker` pour utiliser un Overlay custom au lieu de `showMenu`.
