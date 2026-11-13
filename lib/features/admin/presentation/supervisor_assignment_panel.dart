import 'package:flutter/material.dart';

import '../../../core/errors/user_error.dart';
import '../../declaration/data/services/supervisor_inbox_service.dart';

/// Panel to assign a supervisor to a declarant.
///
/// Shared by the administrator and human resources dashboards. The assignment
/// determines which declarations show up in the supervisor's inbox.
///
/// UID inputs intentionally avoid exposing a profile directory to operators.
/// The callable verifies both profiles and the operator's current role, so
/// the checks in this widget are only a convenience, not a security boundary.
///
/// [service] allows injecting a fake implementation in tests.
class SupervisorAssignmentPanel extends StatefulWidget {
  const SupervisorAssignmentPanel({super.key, this.service});

  final SupervisorAssignmentRepository? service;

  @override
  State<SupervisorAssignmentPanel> createState() =>
      _SupervisorAssignmentPanelState();
}

class _SupervisorAssignmentPanelState extends State<SupervisorAssignmentPanel> {
  late final SupervisorAssignmentRepository _service =
      widget.service ?? SupervisorAssignmentService();
  final _declarant = TextEditingController();
  final _supervisor = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _declarant.dispose();
    _supervisor.dispose();
    super.dispose();
  }

  Future<void> _assign() async {
    final declarantId = _declarant.text.trim();
    final supervisorId = _supervisor.text.trim();
    if (declarantId.isEmpty || supervisorId.isEmpty) {
      setState(
        () => _message = 'Ingrese el UID del declarante y del superior.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _service.assign(
        declarantId: declarantId,
        supervisorId: supervisorId,
      );
      if (mounted) setState(() => _message = 'Asignación guardada.');
    } catch (error) {
      if (mounted) setState(() => _message = userError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Asignación de superior',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Administración o Recursos Humanos pueden asignar un superior activo a un declarante activo. La operación se valida y registra en el servidor.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _declarant,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'UID del declarante'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _supervisor,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'UID del superior'),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _busy ? null : _assign,
              child: const Text('Asignar superior'),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(liveRegion: true, child: Text(_message!)),
            ),
        ],
      ),
    ),
  );
}
