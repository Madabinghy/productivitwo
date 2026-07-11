import 'package:productivitwo_v1/models.dart';

// ─── VERDICT DU CHECK-IN DU SOIR ─────────────────────────────────────────────
//
// Template déterministe v1 — 0 appel LLM. Même esprit que computeCoachMoment :
// fonction pure, chiffres réels uniquement (une donnée absente = phrase omise).
// Squelette : constat sur le(s) rompu(s) avec la récurrence de la semaine
// + ce qui a tenu (« c'est la base qui compte »).

/// Libellé humain d'une skipReason (enum ouvert : texte libre passé tel quel).
String skipReasonLabel(String reason) => switch (reason) {
      'imprevu' => 'imprévu client',
      'energie' => 'pas d\'énergie',
      'sous_estime' => 'sous-estimé',
      'evite' => 'évité',
      'reporte' => 'reporté',
      'renegocie' => 'renégocié — modalité changée',
      'pas_sur_place' => 'pas sur place',
      'pas_le_moment' => 'pas le bon moment',
      'imprevu_global' => 'un imprévu a mangé la journée',
      'irrealiste' => 'programme irréaliste',
      _ => reason,
    };

/// Parade déterministe v1 associée à une cause (pour le « Demain je le pose… »).
String _parade(String? cause) => switch (cause) {
      'imprevu' => 'avant que la journée s\'emballe',
      'energie' => 'sur un créneau du matin, quand l\'énergie est là',
      'sous_estime' => 'avec plus de marge',
      'evite' => '25 minutes pour l\'enclencher, pas plus',
      _ => 'tôt, tant que la journée t\'appartient',
    };

/// [todayBlocks] : blocs du jour (hors `deleted`). [weekBlocks] : blocs des
/// 7 derniers jours (aujourd'hui exclu), pour compter les récurrences.
/// [dayReason] : cause globale posée à l'étape 2 quand 3+ blocs ont sauté.
String buildEveningVerdict({
  required List<ScheduleBlock> todayBlocks,
  required List<ScheduleBlock> weekBlocks,
  String? dayReason,
}) {
  final engagements = todayBlocks
      .where((b) =>
          !b.isPrep && b.category != 'break' && b.status != 'deleted')
      .toList();
  if (engagements.isEmpty) {
    return 'Pas d\'engagement posé aujourd\'hui. Demain se gagne ce soir — '
        'pose demain et la journée aura une colonne vertébrale.';
  }

  final broken = engagements.where((b) => b.status != 'done').toList();
  final held = engagements.where((b) => b.status == 'done').toList();

  // ── Tout est tenu ───────────────────────────────────────────────────────────
  if (broken.isEmpty) {
    return '${engagements.length}/${engagements.length} engagements tenus — '
        'rien à reprendre. C\'est ça qu\'on voulait.';
  }

  final parts = <String>[];

  // ── 3+ rompus : cause globale (dayReason), pas de détail par bloc ───────────
  if (broken.length >= 3) {
    parts.add(
        'La journée a déraillé — ${broken.length} engagements sur ${engagements.length} ont sauté.');
    if (dayReason != null && dayReason.isNotEmpty) {
      parts.add('Cause notée : « ${skipReasonLabel(dayReason)} ».');
      if (dayReason == 'irrealiste') {
        parts.add('Demain sera plus court, volontairement.');
      } else {
        parts.add('Demain, on repart proprement.');
      }
    }
  } else {
    // ── 1-2 rompus : constat avec récurrence de la semaine ────────────────────
    for (final b in broken) {
      final history = _sameEngagement(b, weekBlocks)
          .where((w) => w.status != 'done' && w.status != 'deleted')
          .toList();
      final skipCount = history.length + 1; // + aujourd'hui
      final causes = <String, int>{};
      for (final w in history) {
        final r = w.skipReason;
        if (r != null && r.isNotEmpty) causes[r] = (causes[r] ?? 0) + 1;
      }
      final today = b.skipReason;
      if (today != null && today.isNotEmpty) {
        causes[today] = (causes[today] ?? 0) + 1;
      }
      String? topCause;
      var topCount = 0;
      causes.forEach((c, n) {
        if (n > topCount) {
          topCause = c;
          topCount = n;
        }
      });

      if (skipCount > 1) {
        final causeStr = topCause != null
            ? ', $topCount fois « ${skipReasonLabel(topCause!)} »'
            : '';
        parts.add(
            '${b.title} a sauté $skipCount fois cette semaine$causeStr.');
      } else {
        final causeStr = topCause != null
            ? ' — « ${skipReasonLabel(topCause!)} »'
            : '';
        parts.add('${b.title} a sauté aujourd\'hui$causeStr.');
      }
    }
    // Une seule parade, sur le premier rompu (garder le verdict court).
    final first = broken.first;
    final hour = first.startTime.compareTo('12:00') < 0
        ? _hhmmToFr(first.startTime)
        : '9 h';
    parts.add(
        'Demain je le pose à $hour — ${_parade(first.skipReason)}.');
  }

  // ── Ce qui a tenu ───────────────────────────────────────────────────────────
  if (held.isNotEmpty) {
    final names = held.take(2).map((b) => b.title).join(' et ');
    final suffix = held.length > 2 ? ' (+${held.length - 2})' : '';
    parts.add(
        '$names$suffix : ${held.length > 1 ? 'tenus' : 'tenu'}, c\'est la base qui compte.');
  }

  return parts.join(' ');
}

/// Nombre de fois où CET engagement a sauté sur les 7 derniers jours
/// (aujourd'hui exclu) — pour le « 2ᵉ fois cette semaine » du check-in.
int weeklySkipCount(ScheduleBlock b, List<ScheduleBlock> weekBlocks) =>
    _sameEngagement(b, weekBlocks)
        .where((w) => w.status != 'done' && w.status != 'deleted')
        .length;

/// La skipReason la plus fréquente des 7 derniers jours (tous blocs confondus)
/// — heuristique v1 du raccourci « Même cause pour les deux ». Null sans
/// historique.
String? topWeeklyCause(List<ScheduleBlock> weekBlocks) {
  final counts = <String, int>{};
  for (final w in weekBlocks) {
    final r = w.skipReason;
    if (r != null && r.isNotEmpty) counts[r] = (counts[r] ?? 0) + 1;
  }
  String? top;
  var topN = 0;
  counts.forEach((c, n) {
    if (n > topN) {
      top = c;
      topN = n;
    }
  });
  return top;
}

/// Même engagement qu'un bloc : même source liée (tâche/activité), sinon même
/// titre (blocs libres régénérés chaque jour).
List<ScheduleBlock> _sameEngagement(
    ScheduleBlock b, List<ScheduleBlock> pool) {
  return pool.where((w) {
    if (w.isPrep || w.category == 'break') return false;
    if (b.taskId != null) return w.taskId == b.taskId;
    if (b.activityId != null) return w.activityId == b.activityId;
    return w.title.trim().toLowerCase() == b.title.trim().toLowerCase();
  }).toList();
}

String _hhmmToFr(String hm) {
  final parts = hm.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? parts[1] : '00';
  return m == '00' ? '$h h' : '$h h $m';
}
