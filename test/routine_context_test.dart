import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routine_context.dart';

Activity _r(String name, {String? timeContext}) => Activity(
    id: 'r1',
    name: name,
    domainId: 'd1',
    type: 'habit',
    habitFreq: HabitFreq.daily,
    timeContext: timeContext);

void main() {
  group('contextes alignés sur les moments réglés (2026-10)', () {
    test('timeContextsWith : bornes données, fenêtre qui passe minuit, ancre', () {
      final c = timeContextsWith({'evening': (19 * 60, 29 * 60), 'morning': (9 * 60, 12 * 60)});
      expect(c['evening']!.allows(30), isTrue); // 00:30 = encore le soir
      expect(c['evening']!.allows(4 * 60 + 59), isTrue);
      expect(c['evening']!.allows(5 * 60), isFalse);
      expect(c['evening']!.allows(18 * 60), isFalse);
      expect(c['evening']!.anchorMin, 21 * 60); // l'ancre par défaut reste dans la fenêtre
      expect(c['morning']!.allows(8 * 60), isFalse);
      expect(c['morning']!.anchorMin, 9 * 60 + 60); // 7 h 30 hors fenêtre → début + span/3 (60)
      expect(c['midday'], same(kTimeContexts['midday'])); // non réglé = défaut
      expect(c['meal'], same(kTimeContexts['meal']));
    });

    test('effTimeContextOf lit les contextes fournis', () {
      final c = timeContextsWith({'evening': (19 * 60, 29 * 60)});
      expect(effTimeContextOf(_r('Hygiène du soir'))!.allows(30), isFalse); // défauts : 23 h 30
      expect(effTimeContextOf(_r('Hygiène du soir'), contexts: c)!.allows(30), isTrue);
      expect(effTimeContextOf(_r('x', timeContext: 'evening'), contexts: c)!.allows(30), isTrue);
    });
  });

  group('catalogue d\'archétypes (accents/casse repliés)', () {
    test('les évidences matchent, le doute ne matche pas', () {
      expect(routineArchetype('Hygiène du soir')!.contextKey, 'evening');
      expect(routineArchetype('HYGIENE DU SOIR')!.contextKey, 'evening');
      expect(routineArchetype('Boire de l\'eau')!.contextKey, 'allday');
      expect(routineArchetype('Cuisiner')!.contextKey, 'meal');
      expect(routineArchetype('Musculation')!.contextKey, 'day');
      expect(routineArchetype('Vitamines')!.contextKey, 'morning');
      // Méditation à 15 h, lecture l'après-midi : légitimes — pas d'archétype
      // (le catalogue ne fixe que les évidences).
      expect(routineArchetype('Méditation'), isNull);
      expect(routineArchetype('Lecture'), isNull);
      // Pas d'évidence → pas d'archétype (jamais deviné dans le doute).
      expect(routineArchetype('Louanges'), isNull);
      expect(routineArchetype('Kingdom'), isNull);
    });

    test('méta-intention : celle de la ROUTINE, pas du domaine', () {
      expect(metaIntentionOf(_r('Hygiène du soir')),
          'clore la journée proprement');
      expect(metaIntentionOf(_r('Louanges')), isNull);
    });
  });

  group('contexte effectif et fenêtres', () {
    test('préséance : override user > archétype > rien', () {
      expect(effTimeContextOf(_r('Hygiène du soir'))!.key, 'evening');
      expect(
          effTimeContextOf(_r('Hygiène du soir', timeContext: 'morning'))!.key,
          'morning');
      expect(effTimeContextOf(_r('Louanges')), isNull);
    });

    test('allows : les fenêtres tiennent (soir, repas à deux fenêtres)', () {
      final soir = kTimeContexts['evening']!;
      expect(soir.allows(21 * 60), isTrue);
      expect(soir.allows(12 * 60), isFalse);
      final repas = kTimeContexts['meal']!;
      expect(repas.allows(12 * 60), isTrue);
      expect(repas.allows(19 * 60), isTrue);
      expect(repas.allows(16 * 60), isFalse);
      expect(kTimeContexts['any']!.allows(3 * 60), isTrue); // libre
    });

    test('tranches de renégociation : jamais « hygiène du soir à midi »', () {
      final soir = effTimeContextOf(_r('Hygiène du soir'));
      expect(contextAllowsBucket(soir, 'midi'), isFalse);
      expect(contextAllowsBucket(soir, 'apres_midi'), isFalse);
      expect(contextAllowsBucket(soir, 'soir'), isTrue);
      expect(contextAllowsBucket(null, 'midi'), isTrue); // routine libre
      expect(bucketOfContext(kTimeContexts['evening']!), 'soir');
      expect(bucketOfContext(kTimeContexts['meal']!), 'midi');
    });
  });
}
