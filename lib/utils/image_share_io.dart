import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<bool> shareImage(Uint8List png, String fileName, {String? text, Rect? origin}) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$fileName');
  await f.writeAsBytes(png, flush: true);
  final r = await Share.shareXFiles([XFile(f.path, mimeType: 'image/png')], text: text, sharePositionOrigin: origin);
  return r.status != ShareResultStatus.dismissed;
}
