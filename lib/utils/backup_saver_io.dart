import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Écrit le JSON dans un fichier temporaire puis ouvre la feuille de partage
/// (Fichiers, AirDrop, mail…). [origin] : ancrage du popover iPad.
Future<bool> saveBackupFile(String fileName, String content,
    {Rect? origin}) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$fileName');
  await f.writeAsString(content, flush: true);
  final result = await Share.shareXFiles(
    [XFile(f.path, mimeType: 'application/json')],
    sharePositionOrigin: origin,
  );
  return result.status == ShareResultStatus.success ||
      // iOS renvoie parfois unavailable après un enregistrement dans
      // Fichiers réussi — on ne compte que le dismiss explicite comme échec.
      result.status == ShareResultStatus.unavailable;
}
