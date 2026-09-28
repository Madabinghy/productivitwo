import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/pro_manager.dart';

void main() {
  test('ouverture : Pro dès le démarrage, sans init ni réseau', () {
    expect(kFreeForAll, isTrue);
    expect(ProManager.isPro, isTrue);
    expect(ProManager.notifier.value, isTrue);
  });

  test('deactivate ne retire pas le Pro tant que kFreeForAll', () async {
    await ProManager.deactivate();
    expect(ProManager.isPro, isTrue);
  });
}
