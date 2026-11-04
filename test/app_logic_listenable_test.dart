import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';

void main() {
  test('AppLogic.listenable relaie chaque onChange, et se désabonne', () {
    final logic = AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {});
    var n = 0;
    void l() => n++;
    logic.listenable.addListener(l);
    logic.onChange();
    expect(n, 1);
    logic.listenable.removeListener(l);
    logic.onChange();
    expect(n, 1);
  });
}
