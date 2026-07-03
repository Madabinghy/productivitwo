// Rendu web du jeu Manoir : webview_flutter ne supporte pas le web, donc pour
// l'app web et surtout le mode `?mobilepreview` on embarque le jeu dans une
// iframe via HtmlElementView (même mécanisme que le viewer Gantt web).
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

int _manoirSeq = 0;

Widget manoirIframe(String url, {Key? key}) => _ManoirIframe(url: url, key: key);

class _ManoirIframe extends StatefulWidget {
  final String url;
  const _ManoirIframe({required this.url, super.key});

  @override
  State<_ManoirIframe> createState() => _ManoirIframeState();
}

class _ManoirIframeState extends State<_ManoirIframe> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'manoir-iframe-${_manoirSeq++}';
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (_) {
      return html.IFrameElement()
        ..src = widget.url
        ..allow = 'fullscreen; autoplay'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewId);
}
