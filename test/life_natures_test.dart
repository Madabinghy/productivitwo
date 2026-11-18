import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/life_natures.dart';

void main() {
  test('natures devinées', () {
    Domain d(String id, String n) => Domain(id: id, name: n);
    final cuis = Activity(id: 'c', domainId: 'sante', name: 'Cuisiner', role: ActivityRole.generic, type: 'time', goalMin: 1, createdAt: DateTime(2026));
    expect(guessNature(d('s', 'Sommeil'), const []), DomainNature.night);
    expect(guessNature(d('m', 'Musculation'), const []), DomainNature.sessions);
    expect(guessNature(d('sante', 'Santé'), [cuis]), DomainNature.meals);
    expect(guessNature(d('b', 'Business'), const []), DomainNature.work);
    expect(guessNature(d('f', 'Finances'), const []), DomainNature.money);
    expect(guessNature(d('i', 'Intendance'), const []), DomainNature.upkeep);
    expect(guessNature(d('sp', 'Spiritualité'), const []), DomainNature.practice);
    expect(parseNatures({'x': 'meals', 'y': 'zzz'}), {'x': DomainNature.meals});
  });

  test('détente : devinée par le nom, ses activités sont à part', () {
    Domain d(String id, String n) => Domain(id: id, name: n);
    for (final n in ['Chill', 'Détente', 'Loisirs', 'Jeux vidéo', 'Temps libre', 'Fun']) {
      expect(guessNature(d('x', n), const []), DomainNature.leisure, reason: n);
    }
    // Pas de faux amis : « jeunesse », « Jeudi » ne sont pas des jeux.
    expect(guessNature(d('x', 'Jeunesse'), const []), DomainNature.practice);
    Activity a(String id, String dom, {bool habit = false}) =>
        Activity(id: id, domainId: dom, name: id, role: ActivityRole.generic, type: habit ? 'habit' : 'time', createdAt: DateTime(2026));
    final domains = [d('chill', 'Chill'), d('biz', 'Business'), d('spi', 'Spiritualité')];
    final acts = [a('jeu', 'chill'), a('lire', 'chill', habit: true), a('code', 'biz'), a('prier', 'spi')];
    expect(leisureIdsOf(domains, acts, const {}), {'jeu', 'lire'});
    // La nature choisie à la main prime sur le nom, dans les deux sens.
    expect(leisureIdsOf(domains, acts, {'chill': DomainNature.practice, 'spi': DomainNature.leisure}), {'prier'});
    expect(leisureIdsOf([d('biz', 'Business')], acts, const {}), isEmpty);
  });

  test('ta semaine en une phrase', () {
    expect(lifeSentence(kept: 5, engagements: 7, sleepAvgMin: 380, sportSessions: 3, behindDomains: ['Business']),
        '5 / 7 engagements au rythme · nuits courtes · 3 séances de sport · Business en retard');
    expect(lifeSentence(kept: 7, engagements: 7), 'Semaine au rythme');
    expect(lifeSentence(kept: 0, engagements: 0), 'Rien à mesurer encore cette semaine.');
  });
}
