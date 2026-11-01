import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

Future<bool> shareImage(Uint8List png, String fileName, {String? text, Rect? origin}) async {
  final blob = html.Blob([png], 'image/png');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = fileName
    ..click();
  html.Url.revokeObjectUrl(url);
  return true;
}
