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
