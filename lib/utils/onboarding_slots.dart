// ─── CRÉNEAUX DES SESSIONS DE DÉFINITION (maquette 18b) ──────────────────────
//
// « On ne fait pas les trois ce soir — une définition à la va-vite ne vaut
// rien. » Les domaines nommés mais pas encore définis reçoivent une vraie
// session posée dans la semaine, sur des créneaux proposés intelligemment :
// soir de semaine après le travail, dimanche matin au calme. Fonctions pures,
// testables. 0 LLM.

/// [count] créneaux à partir de demain :
/// 1ᵉʳ = prochain soir de semaine (lun-ven) 18:30, 2ᵉ = prochain dimanche
/// 11:00, suivants = soirs de semaine 18:30 en cascade.
List<DateTime> definitionSessionSlots(DateTime now, int count) {
  final slots = <DateTime>[];
  if (count <= 0) return slots;

  DateTime nextWeekdayEvening(DateTime after) {
    var d = DateTime(after.year, after.month, after.day)
        .add(const Duration(days: 1));
    while (d.weekday > DateTime.friday) {
      d = d.add(const Duration(days: 1));
    }
    return DateTime(d.year, d.month, d.day, 18, 30);
  }

  final first = nextWeekdayEvening(now);
  slots.add(first);

  if (count >= 2) {
    var sunday = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    while (sunday.weekday != DateTime.sunday) {
      sunday = sunday.add(const Duration(days: 1));
    }
    slots.add(DateTime(sunday.year, sunday.month, sunday.day, 11, 0));
  }

  var prev = first;
  while (slots.length < count) {
    prev = nextWeekdayEvening(prev);
    slots.add(prev);
  }
  return slots;
}

/// Pourquoi ce créneau — la conséquence affichée sous chaque proposition.
String slotRationale(DateTime slot) => slot.weekday == DateTime.sunday
    ? 'au calme, avant le rapport hebdo du soir'
    : 'après ta journée — la tête encore dedans';

/// « mer 18:30 » / « dim 11:00 » — libellé court d'un créneau.
String slotShortLabel(DateTime slot) {
  const days = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
  final h = slot.hour.toString();
  final m = slot.minute.toString().padLeft(2, '0');
  return '${days[slot.weekday - 1]} $h:$m';
}
