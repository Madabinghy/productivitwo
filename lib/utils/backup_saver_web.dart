import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/widgets.dart';

/// Téléchargement direct côté web — même fichier que sur mobile.
Future<bool> saveBackupFile(String fileName, String content,
    {Rect? origin}) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = fileName
    ..click();
  html.Url.revokeObjectUrl(url);
  return true;
}
