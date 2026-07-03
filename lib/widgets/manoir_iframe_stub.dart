// Stub non-web : sur mobile/desktop, webview_flutter gère l'embarquement du jeu ;
// cette iframe n'est jamais rendue (l'import conditionnel bascule sur la version
// web uniquement quand `dart:html` est disponible).
import 'package:flutter/material.dart';

Widget manoirIframe(String url, {Key? key}) => const SizedBox.shrink();
