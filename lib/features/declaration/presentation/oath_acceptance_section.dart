import 'package:flutter/material.dart';

class OathAcceptanceSection extends StatefulWidget {
  const OathAcceptanceSection({
    super.key,
    required this.officialOathText,
    required this.canAccept,
    required this.busy,
    required this.onAccept,
  });

  final String? officialOathText;
  final bool canAccept;
  final bool busy;
  final Future<void> Function() onAccept;

  @override
  State<OathAcceptanceSection> createState() => _OathAcceptanceSectionState();
}

class _OathAcceptanceSectionState extends State<OathAcceptanceSection> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final oathText = widget.officialOathText?.trim();
    final hasOfficialText = oathText != null && oathText.isNotEmpty;
    final enabled =
        hasOfficialText && widget.canAccept && _confirmed && !widget.busy;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Aceptación bajo juramento',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (hasOfficialText) ...[
              SelectableText(oathText),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _confirmed,
                onChanged: widget.canAccept && !widget.busy
                    ? (value) => setState(() => _confirmed = value ?? false)
                    : null,
                title: const Text('Confirmo expresamente mi aceptación.'),
              ),
            ] else
              const Text(
                'El texto oficial institucional del juramento está pendiente de aprobación. '
                'No se puede confirmar una aceptación real hasta que se incorpore.',
              ),
            if (hasOfficialText && !widget.canAccept)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Guarde los cambios pendientes y asegúrese de que la declaración siga VALIDADA antes de continuar.',
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: enabled ? widget.onAccept : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Aceptar juramento'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
