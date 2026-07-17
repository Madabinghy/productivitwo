import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/context_picker.dart';

// Création DÉTERMINISTE (pivot GTD) : plus d'appel LLM ici. L'endpoint
// structureProject reste déployé côté functions mais n'a plus d'appelant.

Future<void> showNewProjectSheet(
  BuildContext context, {
  required List<Domain> domains,
  required VoidCallback onCreated,
  required FirestoreSync sync,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _NewProjectSheet(domains: domains, onCreated: onCreated, sync: sync),
  );
}

class _NewProjectSheet extends StatefulWidget {
  final List<Domain> domains;
  final VoidCallback onCreated;
  final FirestoreSync sync;

  const _NewProjectSheet(
      {required this.domains, required this.onCreated, required this.sync});

  @override
  State<_NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends State<_NewProjectSheet> {
  final _titleCtrl = TextEditingController();
  final _firstActionCtrl = TextEditingController();
  final _titleFocus = FocusNode();
  List<String> _actionContexts = []; // contextes GTD de la première action
  String? _selectedDomainId;
  DateTime _endDate = DateTime.now().add(const Duration(days: 30));
  int? _presetDays = 30;
  bool _loading = false;
  String? _error;

  static const _accent = Color(0xFF7E57C2); // identité ORION (deepPurple 400)

  @override
  void initState() {
    super.initState();
    if (widget.domains.isNotEmpty) _selectedDomainId = widget.domains.first.id;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _firstActionCtrl.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
        _presetDays = null;
      });
    }
  }

  void _applyPreset(int days) {
    setState(() {
      _presetDays = days;
      _endDate = DateTime.now().add(Duration(days: days));
    });
  }

  /// Création DÉTERMINISTE : nom + domaine + échéance + première action GTD
  /// (optionnelle, avec son contexte). Pas de LLM — les actions suivantes sont
  /// définies par l'utilisateur au fil de l'eau (fiche tâche).
  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final firstAction = _firstActionCtrl.text.trim();
      final now = DateTime.now();

      final phases = <ProjectPhase>[];
      final tasks = <ProjectTask>[];
      if (firstAction.isNotEmpty) {
        phases.add(ProjectPhase(
          id: 'phase-1',
          label: 'Réalisation',
          startDate: now,
          endDate: _endDate,
        ));
        tasks.add(ProjectTask(
          title: firstAction,
          phaseId: 'phase-1',
          startDate: now,
          endDate: now.add(const Duration(days: 3)),
          actions: [
            TaskAction(
              title: firstAction,
              context:
                  _actionContexts.isEmpty ? null : _actionContexts.first,
              contexts: List.of(_actionContexts),
            ),
          ],
        ));
      }

      final project = Project(
        title: title,
        domainId: _selectedDomainId,
        startDate: now,
        endDate: _endDate,
        phases: phases,
        tasks: tasks,
        createdBy: uid,
        source: 'user',
        sourceType: 'manual',
        // 'active' direct : le flux est déterministe et saisi par le user —
        // 'draft' (héritage du flux LLM à valider) le rendrait invisible dans
        // les listes GTD (Actions / Prochaines actions filtrent sur active).
        status: 'active',
      );
      await widget.sync.saveProject(project);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onCreated();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(firstAction.isEmpty
            ? 'Projet créé — ajoute tes actions au fil de l\'eau.'
            : 'Projet créé — première action : « $firstAction »'),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  InputDecoration _fieldDecoration(BuildContext context,
      {required String label, String? hint}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle:
          TextStyle(color: cs.onSurface.withOpacity(.35), fontSize: 13),
      alignLabelWithHint: true,
      filled: true,
      fillColor: cs.surfaceVariant.withOpacity(.35),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _accent, width: 1.6),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .8,
          color: cs.onSurface.withOpacity(.45),
        ),
      ),
    );
  }

  Widget _domainChips(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.domains.map((d) {
        final selected = d.id == _selectedDomainId;
        final color = domainColor(d.id, widget.domains) ?? cs.primary;
        return ChoiceChip(
          selected: selected,
          onSelected: (_) => setState(() => _selectedDomainId = d.id),
          showCheckmark: false,
          avatar: CircleAvatar(radius: 5, backgroundColor: color),
          label: Text(d.name),
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? color : cs.onSurface.withOpacity(.7),
          ),
          selectedColor: color.withOpacity(.14),
          backgroundColor: cs.surfaceVariant.withOpacity(.35),
          side: BorderSide(
            color: selected ? color.withOpacity(.55) : Colors.transparent,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        );
      }).toList(),
    );
  }

  Widget _datePresets(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const presets = [(14, '2 sem'), (30, '1 mois'), (90, '3 mois'), (180, '6 mois')];
    final customSelected = _presetDays == null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (days, label) in presets)
          ChoiceChip(
            selected: _presetDays == days,
            onSelected: (_) => _applyPreset(days),
            showCheckmark: false,
            label: Text(label),
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight:
                  _presetDays == days ? FontWeight.w600 : FontWeight.w500,
              color: _presetDays == days
                  ? _accent
                  : cs.onSurface.withOpacity(.7),
            ),
            selectedColor: _accent.withOpacity(.14),
            backgroundColor: cs.surfaceVariant.withOpacity(.35),
            side: BorderSide(
              color: _presetDays == days
                  ? _accent.withOpacity(.55)
                  : Colors.transparent,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ActionChip(
          onPressed: _pickDate,
          avatar: Icon(Icons.edit_calendar_outlined,
              size: 15,
              color: customSelected ? _accent : cs.onSurface.withOpacity(.6)),
          label: Text(customSelected
              ? '${_endDate.day} ${_monthName(_endDate.month)} ${_endDate.year}'
              : 'Choisir…'),
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: customSelected ? FontWeight.w600 : FontWeight.w500,
            color:
                customSelected ? _accent : cs.onSurface.withOpacity(.7),
          ),
          backgroundColor: customSelected
              ? _accent.withOpacity(.14)
              : cs.surfaceVariant.withOpacity(.35),
          side: BorderSide(
            color:
                customSelected ? _accent.withOpacity(.55) : Colors.transparent,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canSubmit = _titleCtrl.text.trim().isNotEmpty;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.88,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scroll) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              // Poignée
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    // En-tête
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _accent,
                                Colors.deepPurple.shade300,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.auto_awesome,
                              size: 20, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Nouveau projet',
                                  style: TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(
                                'Nom, échéance, première action — tu complètes au fil de l\'eau.',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: cs.onSurface.withOpacity(.5)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    // Titre
                    TextField(
                      controller: _titleCtrl,
                      focusNode: _titleFocus,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _fieldDecoration(context,
                          label: 'Titre du projet'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 20),

                    // Domaine
                    if (widget.domains.isNotEmpty) ...[
                      _sectionLabel(context, 'Domaine'),
                      _domainChips(context),
                      const SizedBox(height: 20),
                    ],

                    // Échéance
                    _sectionLabel(context, 'Échéance'),
                    _datePresets(context),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Text(
                        'Objectif : ${_endDate.day} ${_monthName(_endDate.month)} ${_endDate.year}',
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withOpacity(.5)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Première action GTD (optionnelle)
                    _sectionLabel(context, 'Première action'),
                    TextField(
                      controller: _firstActionCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _fieldDecoration(
                        context,
                        label: 'La prochaine action concrète (optionnel)',
                        hint: 'Ex : Appeler la mairie pour les horaires',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    // Contextes GTD de la première action (multi)
                    ContextPicker(
                      values: _actionContexts,
                      sync: widget.sync,
                      onValuesChanged: (list) =>
                          setState(() => _actionContexts = list),
                    ),

                    // Erreur
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline,
                                size: 16, color: cs.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_error!,
                                  style: TextStyle(
                                      color: cs.onErrorContainer,
                                      fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),

                    // Bouton unique — création déterministe
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: (_loading || !canSubmit) ? null : _submit,
                        icon: _loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.flag, size: 18),
                        label: Text(
                          _loading ? 'Création…' : 'Créer le projet',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _monthName(int month) => const [
      '', 'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
      'juil', 'août', 'sep', 'oct', 'nov', 'déc'
    ][month];

String _friendlyError(Object e) {
  final s = e.toString();
  if (e is SocketException ||
      e is HandshakeException ||
      s.contains('SocketException') ||
      s.contains('Connection refused') ||
      s.contains('Failed host lookup')) {
    return 'Connexion impossible — vérifie ta connexion internet.';
  }
  if (s.contains('TimeoutException') || s.contains('timed out')) {
    return 'Délai dépassé — ORION met parfois quelques secondes, réessaie.';
  }
  if (s.contains('429') || s.contains('Limite journalière')) {
    return s.contains(':') ? s.split(':').last.trim() : 'Limite journalière atteinte.';
  }
  return 'Erreur : $s';
}
