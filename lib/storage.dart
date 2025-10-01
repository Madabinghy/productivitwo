import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

class FileStore {
  static const _fileName = 'productivitwo.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  // NEW: supprime le fichier de données
  Future<void> wipe() async {
    final f = await _file();
    if (await f.exists()) {
      await f.delete();
    }
  }

  Future<AppState> loadOrInit() async {
    final f = await _file();
    if (await f.exists()) {
      final s = await f.readAsString();
      return AppState.decode(s); // decode gère habitProgress null -> []
    }

    // Seed minimal
    final d = Domain(name: 'Production', autoGoal: true);
    final a = Activity(
        domainId: d.id, name: 'Focus deep work', type: 'time', goalMin: 1, habitTarget: 1);

    final st = AppState(
      domains: [d],
      activities: [a],
      sessions: [],
      habitProgress: [],
      lastGoalsReview: null,
      snoozedUntil: {},
      goals: [],
      inbox: [],
      dayPlan: [],
    );

    await save(st);
    return st;
  }

  Future<void> save(AppState state) async {
    final f = await _file();
    await f.writeAsString(state.encode());
  }
}
