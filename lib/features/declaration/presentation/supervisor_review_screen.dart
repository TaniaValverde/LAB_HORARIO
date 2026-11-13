import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/errors/user_error.dart';
import '../../../core/state/app_state.dart';
import '../data/repositories/firestore_declaration_repository.dart';
import '../data/services/supervisor_inbox_service.dart';
import '../data/services/declaration_tracking_service.dart';
import '../domain/entities/declaration.dart';
import 'declaration_editor.dart';

class SupervisorReviewScreen extends StatefulWidget {
  const SupervisorReviewScreen({
    super.key,
    required this.declaration,
    this.actions,
  });

  final Declaration declaration;
  final SupervisorDeclarationActions? actions;

  @override
  State<SupervisorReviewScreen> createState() => _SupervisorReviewScreenState();
}

class _SupervisorReviewScreenState extends State<SupervisorReviewScreen> {
  late Declaration _declaration = widget.declaration;
  late final SupervisorDeclarationActions _actions =
      widget.actions ?? SupervisorDeclarationActionService();
  final ReviewState _reviewState = ReviewState();
  bool get _busy => _reviewState.busy;
  set _busy(bool value) => _reviewState.setBusy(value);

  @override
  void dispose() {
    _reviewState.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, String content, String confirm) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirm),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _sign() async {
    if (!await _confirm(
      'Confirmar firma',
      'Registrará una firma electrónica interna asociada a la versión ${_declaration.version}, revisión ${_declaration.revision}. No es una firma digital certificada.',
      'Firmar como superior',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _actions.sign(declaration: _declaration);
      if (mounted) {
        setState(
          () => _declaration = _declaration.copyWith(
            status: DeclarationStatus.signedBySuperior,
            revision: _declaration.revision + 1,
            superiorSignature:
                'superiorSignature_v${_declaration.version}_r${_declaration.revision + 1}',
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _return() async {
    final observation = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Devolver para correcciones'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Observación requerida',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );
    if (observation == null || observation.trim().isEmpty) return;
    _reviewState.setObservation(observation.trim());
    if (!await _confirm(
      'Confirmar devolución',
      'La versión se conservará y quedará de consulta. La corrección generará otra versión.',
      'Devolver',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _actions.returnForCorrection(
        declaration: _declaration,
        observation: observation.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Declaración devuelta para correcciones.'),
          ),
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendToHr() async {
    if (!await _confirm(
      'Enviar a Recursos Humanos',
      'Se remitirá la versión firmada a la bandeja de Recursos Humanos.',
      'Enviar',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _actions.sendToHr(declaration: _declaration);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Declaración enviada a Recursos Humanos.'),
          ),
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _reviewState,
    builder: (context, _) => Scaffold(
    appBar: AppBar(
      title: const Text('Revisión del superior'),
      actions: [
        const ThemeToggleAction(),
        TextButton.icon(
          onPressed: () => FirebaseAuth.instance.signOut(),
          icon: const Icon(Icons.logout),
          label: const Text('Salir'),
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: DeclarationEditor(
            key: ValueKey(
              'supervisor-${_declaration.status}-${_declaration.revision}',
            ),
            declaration: _declaration,
            repository: FirestoreDeclarationRepository(),
            audit: CallableAuditRepository(),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_declaration.status == DeclarationStatus.pendingSuperiorSignature)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _sign,
                  icon: const Icon(Icons.draw_outlined),
                  label: const Text('Firmar como superior'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _return,
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: const Text('Devolver para correcciones'),
                ),
              ],
            ),
          ),
        if (_declaration.status == DeclarationStatus.signedBySuperior)
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: _busy ? null : _sendToHr,
              icon: const Icon(Icons.send_outlined),
              label: const Text('Enviar a Recursos Humanos'),
            ),
          ),
      ],
    ),
    ),
  );
}
