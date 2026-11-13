import 'package:flutter/material.dart';

import '../domain/entities/declaration.dart';

class DeclarantSignatureSection extends StatefulWidget {
  const DeclarantSignatureSection({
    super.key,
    required this.declaration,
    required this.canSign,
    required this.busy,
    required this.onSign,
    this.message,
  });

  final Declaration declaration;
  final bool canSign;
  final bool busy;
  final Future<void> Function() onSign;
  final String? message;

  @override
  State<DeclarantSignatureSection> createState() =>
      _DeclarantSignatureSectionState();
}

class _DeclarantSignatureSectionState extends State<DeclarantSignatureSection> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final name = (widget.declaration.payload['profile'] as Map?)?['name'];
    final appointments = widget.declaration.payload['appointments'];
    final externalJobs = widget.declaration.payload['externalJobs'];
    final enabled = widget.canSign && _confirmed && !widget.busy;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Firma del declarante',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text('Resumen de la versión que va a firmar:'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text('Período ${widget.declaration.periodId}'),
              subtitle: Text(
                'Versión formal ${widget.declaration.version} · '
                'revisión ${widget.declaration.revision}',
              ),
            ),
            if (name is String && name.trim().isNotEmpty)
              Text('Persona declarante: ${name.trim()}'),
            Text(
              'Nombramientos: ${appointments is List ? appointments.length : 0} · '
              'otros empleos: ${externalJobs is List ? externalJobs.length : 0}',
            ),
            const SizedBox(height: 8),
            const Text(
              'La firma electrónica interna quedará vinculada a esta versión y revisión.',
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              onChanged: widget.canSign && !widget.busy
                  ? (value) => setState(() => _confirmed = value ?? false)
                  : null,
              title: const Text(
                'Confirmo que firmo esta versión de la declaración.',
              ),
            ),
            if (!widget.canSign)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'La versión no está disponible para firma. Recargue la declaración y verifique su estado.',
                ),
              ),
            if (widget.message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(widget.message!),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: enabled ? widget.onSign : null,
                icon: const Icon(Icons.draw_outlined),
                label: const Text('Firmar esta versión'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
