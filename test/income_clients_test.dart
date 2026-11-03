import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/finances.dart';
import 'package:productivitwo_v1/utils/income_clients.dart';

ProjectTask _t(String id) => ProjectTask(id: id, title: id, startDate: DateTime(2026, 9, 1));

Project _p(String id, {String? parent, bool folder = false, String status = 'active'}) => Project(
    id: id, title: id, startDate: DateTime(2026, 9, 1), createdBy: 'u', tasks: folder ? [] : [_t('t$id')], parentProjectId: parent, status: status);

void main() {
  final orga = _p('Chérubins', folder: true);
  final cm = _p('CM', parent: 'Chérubins');
  final six = _p('6e', parent: 'Chérubins');
  final solo = _p('Perso');
  final all = [orga, cm, six, solo];

  test('les dossiers d’abord, puis les noms déjà tapés (récents d’abord, sans doublon)', () {
    final incomes = [
      const Income(id: 'a', ymd: '2026-10-01', amount: 100, from: 'Julie'),
      const Income(id: 'b', ymd: '2026-10-20', amount: 100, from: 'Marc'),
      const Income(id: 'c', ymd: '2026-10-21', amount: 100, from: 'chérubins'),
      const Income(id: 'd', ymd: '2026-10-22', amount: 100, from: 'julie'),
    ];
    final c = incomeClients(all, incomes);
    expect(c.map((x) => x.name), ['Chérubins', 'julie', 'Marc']);
    expect(c.first.id, 'Chérubins');
    expect(c[1].id, isNull);
  });

  test('un dossier archivé n’est plus proposé', () {
    final c = incomeClients([_p('Vieux', folder: true, status: 'archived'), _p('x', parent: 'Vieux')], const []);
    expect(c, isEmpty);
  });

  test('les projets d’un client = ceux sous son dossier', () {
    expect(projectsOfClient('Chérubins', all).map((p) => p.id), ['CM', '6e']);
  });

  test('ce que chaque client a versé', () {
    final m = incomeByClient([
      const Income(id: 'a', ymd: '2026-10-01', amount: 100, from: 'Chérubins', clientId: 'Chérubins'),
      const Income(id: 'b', ymd: '2026-10-02', amount: 50, from: 'Julie'),
      const Income(id: 'c', ymd: '2026-09-02', amount: 50, from: 'Julie'),
    ], '2026-10-01', '2026-10-31');
    expect(m, {'Chérubins': 100, 'nom:julie': 50});
  });

  test('clientId fait l’aller-retour JSON', () {
    const x = Income(id: 'a', ymd: '2026-10-01', amount: 100, clientId: 'Chérubins');
    expect(Income.fromJson('a', x.toJson())?.clientId, 'Chérubins');
  });
}
