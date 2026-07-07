import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

const _structureProjectUrl =
    'https://structureproject-dzos75b65q-uc.a.run.app';

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
  final _ideasCtrl = TextEditingController();
  final _titleFocus = FocusNode();
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
    _ideasCtrl.dispose();
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

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final ideas = _ideasCtrl.text.trim();
    if (title.isEmpty || ideas.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final idToken = await user?.getIdToken();
      if (idToken == null) throw Exception('Non authentifié');

      final domainName = widget.domains
          .firstWhereOrNull((d) => d.id == _selectedDomainId)
          ?.name;
      final endDateStr =
          '${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}';

      final resp = await http
          .post(
            Uri.parse(_structureProjectUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'title': title,
              if (domainName != null) 'domainName': domainName,
              if (_selectedDomainId != null) 'domainId': _selectedDomainId,
              'endDate': endDateStr,
              'ideas': ideas,
            }),
          )
          .timeout(const Duration(seconds: 40));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context);
          widget.onCreated();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '✨ ${data['phasesCount']} phases · ${data['tasksCount']} tâches — ORION a structuré ton projet'),
            duration: const Duration(seconds: 4),
          ));
        }
      } else {
        setState(() =>
            _error = (data['error'] as String?) ?? 'Erreur inconnue');
      }
    } catch (e) {
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Création MANUELLE (sans IA) : un projet vide avec titre/domaine/dates.
  /// L'utilisateur ajoute ensuite ses tâches à la main.
  Future<void> _createManual() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final project = Project(
        title: title,
        domainId: _selectedDomainId,
        startDate: DateTime.now(),
        endDate: _endDate,
        createdBy: uid,
        source: 'user',
        sourceType: 'manual',
        status: 'draft',
      );
      await widget.sync.saveProject(project);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onCreated();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Brouillon créé — ajoute tes tâches puis valide le plan.'),
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
    final canSubmit =
        _titleCtrl.text.trim().isNotEmpty && _ideasCtrl.text.trim().isNotEmpty;

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
                                'Décris tes idées, ORION structure le plan.',
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

                    // Idées libres
                    _sectionLabel(context, 'Tes idées'),
                    TextField(
                      controller: _ideasCtrl,
                      minLines: 5,
                      maxLines: 10,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _fieldDecoration(
                        context,
                        label: 'Décris librement ton projet',
                        hint:
                            'Objectifs, contraintes, livrables, personnes '
                            'impliquées, étapes importantes…\n\n'
                            'ORION s\'occupe du reste.',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),

                    // Info action stratégique
                    Row(
                      children: [
                        Icon(Icons.bolt, size: 14, color: _accent),
                        const SizedBox(width: 4),
                        Text(
                          'Consomme 1 action stratégique ORION',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withOpacity(.4)),
                        ),
                      ],
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

                    // Bouton IA
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
                            : const Icon(Icons.auto_awesome, size: 18),
                        label: Text(
                          _loading
                              ? 'ORION structure le projet…'
                              : 'Structurer avec ORION',
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
                    const SizedBox(height: 8),
                    // Création manuelle (sans IA) — ne nécessite qu'un titre
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: (_loading ||
                                _titleCtrl.text.trim().isEmpty)
                            ? null
                            : _createManual,
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        label:
                            const Text('Créer un projet vide (sans IA)'),
                        style: TextButton.styleFrom(
                          foregroundColor: cs.onSurface.withOpacity(.6),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
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
