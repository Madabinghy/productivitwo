import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/modules.dart';

void main() {
  test('absent = tout allumé (compte d\'avant les modules)', () {
    final s = parseModules(null);
    expect(s.isEverything, isTrue);
    for (final i in kModules) {
      expect(s.isOn(i.module), isTrue);
    }
    expect(s.count, kModules.length);
  });

  test('liste explicite relue, clés inconnues ignorées', () {
    final s = parseModules({'v': 1, 'on': ['sleep', 'finances', 'inconnu']});
    expect(s.isOn(AppModule.sleep), isTrue);
    expect(s.isOn(AppModule.finances), isTrue);
    expect(s.isOn(AppModule.game), isFalse);
    expect(s.count, 2);
  });

  test('liste vide = le cœur seul', () {
    final s = parseModules({'on': []});
    expect(s.count, 0);
    expect(s.isOn(AppModule.modes), isFalse);
  });

  test('éteindre depuis « tout allumé » garde les autres', () {
    final s = withModule(ModuleSettings.everything, AppModule.game, false);
    expect(s.isOn(AppModule.game), isFalse);
    expect(s.count, kModules.length - 1);
    expect(parseModules(s.toJson()).sameAs(s), isTrue);
  });

  test('allumer un module', () {
    final s = withModule(const ModuleSettings.only({}), AppModule.planning, true);
    expect(s.isOn(AppModule.planning), isTrue);
    expect(s.toJson()['on'], ['planning']);
  });

  test('sameAs', () {
    expect(ModuleSettings.everything.sameAs(ModuleSettings.everything), isTrue);
    expect(ModuleSettings.everything.sameAs(const ModuleSettings.only({AppModule.sleep})), isFalse);
    expect(const ModuleSettings.only({AppModule.sleep}).sameAs(const ModuleSettings.only({AppModule.sleep})), isTrue);
  });

  test('chaque module a une clé unique', () {
    final keys = kModules.map((i) => i.key).toSet();
    expect(keys.length, kModules.length);
    expect(kModules.length, AppModule.values.length);
  });
}
