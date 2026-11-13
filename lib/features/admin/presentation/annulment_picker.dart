import 'package:flutter/material.dart';

import '../../../core/errors/user_error.dart';
import '../../declaration/domain/entities/declaration.dart';
import '../../period/domain/entities/academic_period.dart';
import '../data/annulment_lookup_service.dart';

class AnnulmentPicker extends StatefulWidget {
  const AnnulmentPicker({
    super.key,
    required this.periods,
    required this.lookup,
  });
  final List<AcademicPeriod> periods;
  final AnnulmentLookup lookup;
  @override
  State<AnnulmentPicker> createState() => _AnnulmentPickerState();
}

class _AnnulmentPickerState extends State<AnnulmentPicker> {
  String? _period, _next, _error;
  String _query = '';
  bool _busy = false;
  List<AnnulmentCandidate> _items = [];

  Future<void> _load({bool more = false}) async {
    if (_period == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      if (!more) _items = [];
    });
    try {
      final page = await widget.lookup(_period!, more ? _next : null);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _next = page.next;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _items = [];
          _next = null;
          _error = userError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _items
        .where(
          (d) =>
              '${d.name} ${d.personId} ${d.id}'.toLowerCase().contains(_query),
        )
        .toList();
    return AlertDialog(
      title: const Text('Consultar declaraciones'),
      content: SizedBox(
        width: 680,
        height: 480,
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Período'),
              items: widget.periods
                  .map(
                    (p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(
                        '${p.name} (${p.id})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (value) {
                      _period = value;
                      _load();
                    },
            ),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar docente o ID en resultados cargados',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            Expanded(
              child: ListView(
                children: [
                  if (!_busy && visible.isEmpty)
                    Text(
                      _period == null
                          ? 'Seleccione un período para consultar.'
                          : 'No hay resultados con este filtro.',
                    ),
                  for (final d in visible)
                    Card(
                      child: ListTile(
                        title: Text(d.name.isEmpty ? d.personId : d.name),
                        subtitle: Text(
                          '${d.periodId} · ${DeclarationStatus.labelOf(d.status) ?? d.status}\nVersión ${d.version} · Revisión ${d.revision}\nID: ${d.id}',
                        ),
                        isThreeLine: true,
                        trailing: d.canAnnul
                            ? const Icon(Icons.chevron_right)
                            : const Icon(Icons.lock_outline),
                        enabled: d.canAnnul && !_busy,
                        onTap: () => Navigator.pop(context, d),
                      ),
                    ),
                ],
              ),
            ),
            if (_next != null)
              TextButton(
                onPressed: _busy ? null : () => _load(more: true),
                child: const Text('Cargar más'),
              ),
            TextButton(
              onPressed: _busy || _period == null ? null : () => _load(),
              child: const Text('Actualizar resultados'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
