import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/launcher_tab_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('le dernier onglet choisi est gardé, Focus la première fois', () async {
    SharedPreferences.setMockInitialValues({});
    LauncherTabStore.resetForTest();
    expect(await LauncherTabStore.load(LauncherTabStore.kRoutines), isTrue);
    await LauncherTabStore.save(LauncherTabStore.kRoutines, false);
    expect(LauncherTabStore.peek(LauncherTabStore.kRoutines), isFalse);
    LauncherTabStore.resetForTest();
    expect(await LauncherTabStore.load(LauncherTabStore.kRoutines), isFalse);
    expect(await LauncherTabStore.load(LauncherTabStore.kActivities), isTrue);
  });
}
