import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/notifications.dart';

/// Sélecteur de sonnerie d'alarme. Vérifie la présence réelle du fichier son
/// (assets/audio) et désactive les sonneries dont le fichier n'a pas encore été
/// ajouté — évite de choisir une alarme qui resterait muette.
Future<void> showAlarmRingtoneSheet(BuildContext context, AppLogic logic) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _AlarmRingtoneSheet(logic: logic),
  );
}

class _AlarmRingtoneSheet extends StatefulWidget {
  final AppLogic logic;
  const _AlarmRingtoneSheet({required this.logic});

  @override
  State<_AlarmRingtoneSheet> createState() => _AlarmRingtoneSheetState();
}

class _AlarmRingtoneSheetState extends State<_AlarmRingtoneSheet> {
  final Set<String> _available = {};
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    for (final r in kAlarmRingtones) {
      try {
        await rootBundle.load('assets/audio/${r.asset}');
        _available.add(r.key);
      } catch (_) {
        // fichier son pas encore ajouté → sonnerie indisponible
      }
    }
    if (mounted) setState(() => _checked = true);
  }

  Widget _tile(AlarmRingtone r, String selected) {
    final missing = _checked && !_available.contains(r.key);
    return RadioListTile<String>(
      contentPadding: EdgeInsets.zero,
      value: r.key,
      groupValue: selected,
      title: Text(r.label),
      subtitle: missing ? const Text('Fichier son à ajouter') : null,
      secondary: const Icon(Icons.notifications_active_outlined),
      onChanged: missing
          ? null
          : (v) {
              if (v == null) return;
              widget.logic.state.alarmSound = v;
              widget.logic.onChange();
              setState(() {});
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = widget.logic.state.alarmSound;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Sonnerie de l\'alarme',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface)),
            ),
            for (final r in kAlarmRingtones) _tile(r, selected),
            const SizedBox(height: 8),
            Text(
              'Le son choisi s\'applique au minuteur et aux défis programmés.',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5)),
            ),
          ],
        ),
      ),
    );
  }
}
