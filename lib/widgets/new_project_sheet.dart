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
    showDragHandle: true,
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
  bool _loading = false;
  String? _error;

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
    if (picked != null) setState(() => _endDate = picked);
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canSubmit =
        _titleCtrl.text.trim().isNotEmpty && _ideasCtrl.text.trim().isNotEmpty;
    final dColor = domainColor(_selectedDomainId, widget.domains);

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            // En-tête
            Row(
              children: [
                Icon(Icons.auto_awesome,
                    size: 18, color: Colors.deepPurple.shade300),
                const SizedBox(width: 8),
                const Text('Nouveau projet',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'ORION structure le projet à partir de tes idées brutes.',
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(.45)),
            ),
            const SizedBox(height: 10),
            // Pastille info philosophie
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.deepPurple.withOpacity(.18)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 14,
                      color: Colors.deepPurple.shade300),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Productivitwo ne crée pas de projets manuellement — '
                      'ORION les structure pour toi en quelques secondes. '
                      'Tu passes ton temps à exécuter, pas à planifier.',
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: cs.onSurface.withOpacity(.55)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Titre
            TextField(
              controller: _titleCtrl,
              focusNode: _titleFocus,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Titre du projet *',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.folder_outlined),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),

            // Domaine
            if (widget.domains.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: _selectedDomainId,
                decoration: InputDecoration(
                  labelText: 'Domaine',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  prefixIcon: Icon(Icons.circle,
                      size: 12, color: dColor ?? cs.primary),
                ),
                items: widget.domains
                    .map((d) => DropdownMenuItem(
                          value: d.id,
                          child: Text(d.name),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedDomainId = v),
              ),
              const SizedBox(height: 14),
            ],

            // Date cible
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date cible',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  prefixIcon:
                      const Icon(Icons.calendar_today_outlined),
                  suffixIcon: const Icon(Icons.chevron_right, size: 18),
                ),
                child: Text(
                  '${_endDate.day} ${_monthName(_endDate.month)} ${_endDate.year}',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Idées libres
            TextField(
              controller: _ideasCtrl,
              minLines: 5,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Tes idées pour ce projet *',
                hintText:
                    'Décris librement : objectifs, contraintes, livrables, '
                    'personnes impliquées, étapes qui te semblent importantes…\n\n'
                    'ORION s\'occupe du reste.',
                hintStyle: TextStyle(
                    color: cs.onSurface.withOpacity(.35),
                    fontSize: 13),
                alignLabelWithHint: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),

            // Info action stratégique
            Row(
              children: [
                Icon(Icons.bolt,
                    size: 14,
                    color: Colors.deepPurple.shade300),
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
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!,
                    style: TextStyle(
                        color: cs.onErrorContainer, fontSize: 13)),
              ),
            ],
            const SizedBox(height: 20),

            // Bouton
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    (_loading || !canSubmit) ? null : _submit,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(Icons.auto_awesome,
                        size: 18,
                        color: Colors.deepPurple.shade100),
                label: Text(_loading
                    ? 'ORION structure le projet…'
                    : 'ORION structure ce projet →'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.deepPurple.shade500,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Création manuelle (sans IA) — ne nécessite qu'un titre
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (_loading || _titleCtrl.text.trim().isEmpty)
                    ? null
                    : _createManual,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Créer un projet vide (sans IA)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
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
