import 'package:flutter/material.dart';

import '../../period/data/repositories/firestore_period_repository.dart';
import '../data/repositories/in_memory_audit_repository.dart';
import '../data/repositories/in_memory_declaration_repository.dart';
import '../domain/entities/audit_event.dart';
import '../domain/entities/declaration.dart';
import '../domain/usecases/advance_declaration.dart';
import '../domain/usecases/create_declaration.dart';
import '../domain/usecases/create_declaration_version.dart';
import '../domain/usecases/get_declaration_timeline.dart';
import '../../pdf/domain/final_declaration_pdf_generator.dart';
import '../../roles/domain/entities/app_role.dart';

/// Prototype screen demonstrating a declaration lifecycle.
///
/// Academic periods are read from Cloud Firestore.
/// Declarations, audit records and PDF generation use
/// in-memory implementations in this retained prototype.
class DeclarationPage extends StatefulWidget {
  const DeclarationPage({super.key});

  @override
  State<DeclarationPage> createState() => _DeclarationPageState();
}

class _DeclarationPageState extends State<DeclarationPage> {
  static const _personId = 'usuario_demo';

  final _personController = TextEditingController(text: _personId);
  final _signatureController = TextEditingController(text: 'Firma demo');
  final _observationController = TextEditingController();

  AppRole _selectedRole = AppRole.declarant;

  /// In-memory declaration repository for the prototype.
  final _declarations = InMemoryDeclarationRepository();

  /// In-memory audit repository for the prototype.
  final _audit = InMemoryAuditRepository();

  /// Simulated PDF generator for the prototype.
  final _pdf = InMemoryFinalDeclarationPdfGenerator();

  /// Use case for creating declarations.
  ///
  /// Academic periods are loaded from Cloud Firestore.
  late final CreateDeclaration _createDeclaration = CreateDeclaration(
    periods: FirestorePeriodRepository(),
    declarations: _declarations,
    audit: _audit,
  );

  /// Use case for advancing a declaration through the prototype workflow.
  late final AdvanceDeclaration _advance = AdvanceDeclaration(
    declarations: _declarations,
    audit: _audit,
  );

  /// Use case for creating a new declaration version.
  late final CreateDeclarationVersion _createVersion = CreateDeclarationVersion(
    declarations: _declarations,
    audit: _audit,
  );

  /// Use case for reading a declaration timeline.
  late final GetDeclarationTimeline _timeline = GetDeclarationTimeline(
    declarations: _declarations,
    audit: _audit,
  );

  List<Declaration> _items = [];

  Map<String, List<AuditEvent>> _events = {};

  bool _busy = false;

  String? _message;

  bool _success = false;

  @override
  void dispose() {
    _personController.dispose();
    _signatureController.dispose();
    _observationController.dispose();
    super.dispose();
  }

  /// Reloads declarations and their audit events.
  Future<void> _refresh() async {
    final items = await _declarations.getAll();

    final events = <String, List<AuditEvent>>{};

    for (final item in items) {
      events[item.id] = await _timeline(item.id);
    }

    if (mounted) {
      setState(() {
        _items = items;
        _events = events;
      });
    }
  }

  /// Runs an operation while displaying progress and any errors.
  Future<void> _run(Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      await operation();

      await _refresh();

      if (mounted) {
        setState(() {
          _success = true;
          _message ??= 'Acción completada.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _success = false;
          _message = _errorText(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Converts domain errors into user-facing messages.
  String _errorText(Object error) {
    if (error is DeclarationCreationException) {
      return switch (error.reason) {
        DeclarationCreationFailure.noActivePeriod =>
          'No hay un período activo.',
        DeclarationCreationFailure.outsidePeriodDates =>
          'El período está fuera de vigencia.',
        DeclarationCreationFailure.alreadyExists =>
          'Ya existe una declaración para este período.',
      };
    }

    if (error is DeclarationFlowException) {
      return switch (error.reason) {
        DeclarationFlowFailure.notFound => 'No se encontró la declaración.',
        DeclarationFlowFailure.validationFailed => 'Complete el formulario y corrija los errores de horario antes de validar.',
        DeclarationFlowFailure.invalidTransition =>
          'La acción no corresponde al estado actual.',
        DeclarationFlowFailure.oathRequired => 'Debe aceptar el juramento.',
        DeclarationFlowFailure.signatureRequired => 'La firma es obligatoria.',
        DeclarationFlowFailure.observationRequired =>
          'La observación de devolución es obligatoria.',
        DeclarationFlowFailure.pdfRequired =>
          'Debe generar y guardar el PDF final.',
        DeclarationFlowFailure.roleNotAllowed =>
          'El rol no tiene permiso para esta acción.',
      };
    }

    return error.toString();
  }

  /// Creates a declaration for the specified person.
  ///
  /// The active period is read from Cloud Firestore.
  Future<void> _create() => _run(() async {
    final id = _personController.text.trim();

    if (id.isEmpty) {
      throw ArgumentError('Ingresá el identificador de la persona.');
    }

    final declaration = await _createDeclaration(personId: id);

    _message = 'Declaración ${declaration.id} creada.';
  });

  /// Performs a prototype state transition for the selected role.
  Future<void> _action(Declaration item, DeclarationAction action) =>
      _run(() async {
        final actor = switch (action) {
          DeclarationAction.superiorSign ||
          DeclarationAction.returnForCorrection => 'supervisor_demo',

          DeclarationAction.sendToHr ||
          DeclarationAction.receiveAtHr ||
          DeclarationAction.finalize => 'rrhh_demo',

          _ => item.personId,
        };

        final actorRole = _selectedRole;

        final pdfPath = action == DeclarationAction.finalize
            ? await _pdf.generateAndStore(item)
            : null;

        await _advance(
          declarationId: item.id,
          actorId: actor,
          actorRole: actorRole,
          action: action,
          acceptOath: action == DeclarationAction.acceptOathAndSign,
          signature:
              action == DeclarationAction.acceptOathAndSign ||
                  action == DeclarationAction.superiorSign
              ? _signatureController.text
              : null,
          observation: action == DeclarationAction.returnForCorrection
              ? _observationController.text
              : null,
          pdfPath: pdfPath,
        );

        _message = 'Estado actualizado para ${item.id}.';
      });

  /// Creates an editable correction version from a returned declaration.
  Future<void> _newVersion(Declaration item) => _run(() async {
    final result = await _createVersion(
      declarationId: item.id,
      actorId: item.personId,
    );

    _message = 'Creada la versión ${result.version} (${result.id}).';
  });

  /// Maps internal states to display labels.
  String _statusName(DeclarationStatus status) => status.label;

  /// Returns the next available action for a declaration.
  Widget? _nextAction(Declaration item) {
    bool isAllowed(DeclarationAction action) => switch (action) {
      DeclarationAction.validate ||
      DeclarationAction.acceptOathAndSign ||
      DeclarationAction.submitToSuperior =>
        _selectedRole == AppRole.declarant ||
            _selectedRole == AppRole.administrator,

      DeclarationAction.superiorSign || DeclarationAction.returnForCorrection =>
        _selectedRole == AppRole.supervisor ||
            _selectedRole == AppRole.administrator,

      _ =>
        _selectedRole == AppRole.humanResources ||
            _selectedRole == AppRole.administrator,
    };

    final (String, DeclarationAction)? next = switch (item.status) {
      DeclarationStatus.draft => (
        'Marcar como validada',
        DeclarationAction.validate,
      ),

      DeclarationStatus.validated => (
        'Aceptar juramento y firmar',
        DeclarationAction.acceptOathAndSign,
      ),

      DeclarationStatus.signedByDeclarant => (
        'Enviar al superior',
        DeclarationAction.submitToSuperior,
      ),

      DeclarationStatus.pendingSuperiorSignature => null,

      DeclarationStatus.signedBySuperior => (
        'Enviar a RRHH',
        DeclarationAction.sendToHr,
      ),

      DeclarationStatus.returned => null,

      DeclarationStatus.sentToHr => (
        'Recibir en RRHH',
        DeclarationAction.receiveAtHr,
      ),

      DeclarationStatus.receivedByHr => (
        'Finalizar y generar PDF',
        DeclarationAction.finalize,
      ),

      DeclarationStatus.finalized => null,
      DeclarationStatus.annulled => null,

      DeclarationStatus.pendingDeclarantSignature => null,
    };

    if (next == null || !isAllowed(next.$2)) {
      return null;
    }

    return OutlinedButton(
      onPressed: _busy ? null : () => _action(item, next.$2),
      child: Text(next.$1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messageColor = _success ? Colors.green.shade700 : Colors.red.shade700;

    return Scaffold(
      appBar: AppBar(title: const Text('DeclaraHorario · Trámite')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Crear declaración',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),

                      const SizedBox(height: 12),

                      TextField(
                        controller: _personController,
                        decoration: const InputDecoration(
                          labelText: 'Identificador de persona',
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 12),

                      FilledButton.icon(
                        onPressed: _busy ? null : _create,
                        icon: const Icon(Icons.add),
                        label: const Text('Crear en período activo'),
                      ),
                    ],
                  ),
                ),
              ),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Acciones de firma',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),

                      const SizedBox(height: 12),

                      TextField(
                        controller: _signatureController,
                        decoration: const InputDecoration(
                          labelText: 'Identificador de firma demo',
                          helperText:
                              'Prototipo: no es una firma digital legal.',
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextField(
                        controller: _observationController,
                        decoration: const InputDecoration(
                          labelText: 'Observación si se devuelve',
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 12),

                      DropdownButtonFormField<AppRole>(
                        initialValue: _selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Rol activo en esta demostración',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: AppRole.declarant,
                            child: Text('Declarante'),
                          ),
                          DropdownMenuItem(
                            value: AppRole.supervisor,
                            child: Text('Superior'),
                          ),
                          DropdownMenuItem(
                            value: AppRole.humanResources,
                            child: Text('RRHH'),
                          ),
                          DropdownMenuItem(
                            value: AppRole.administrator,
                            child: Text('Administración'),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (role) {
                                if (role != null) {
                                  setState(() => _selectedRole = role);
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ),

              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_message!, style: TextStyle(color: messageColor)),
                ),

              Text(
                'Declaraciones y bandeja del superior',
                style: Theme.of(context).textTheme.titleLarge,
              ),

              const SizedBox(height: 8),

              if (_items.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Todavía no hay declaraciones.'),
                  ),
                ),

              ..._items.map((item) => _buildDeclarationCard(item)),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a card showing declaration state and available actions.
  Widget _buildDeclarationCard(Declaration item) {
    final isSuperiorInbox =
        item.status == DeclarationStatus.pendingSuperiorSignature &&
        (_selectedRole == AppRole.supervisor ||
            _selectedRole == AppRole.administrator);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.id} · v${item.version}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),

                Chip(label: Text(_statusName(item.status))),
              ],
            ),

            Text(
              'Persona: ${item.personId} · '
              'Período: ${item.periodId}',
            ),

            if (item.parentVersionId != null)
              Text(
                'Versión anterior: '
                '${item.parentVersionId}',
              ),

            if (item.returnObservation != null)
              Text(
                'Observación: '
                '${item.returnObservation}',
              ),

            if (item.finalPdfPath != null)
              SelectableText('PDF: ${item.finalPdfPath}'),

            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ?_nextAction(item),

                if (isSuperiorInbox) ...[
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _action(item, DeclarationAction.superiorSign),
                    child: const Text('Firmar como superior'),
                  ),

                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _action(
                            item,
                            DeclarationAction.returnForCorrection,
                          ),
                    child: const Text('Devolver'),
                  ),
                ],

                if (item.status == DeclarationStatus.returned &&
                    (_selectedRole == AppRole.declarant ||
                        _selectedRole == AppRole.administrator))
                  OutlinedButton(
                    onPressed: _busy ? null : () => _newVersion(item),
                    child: const Text('Crear nueva versión'),
                  ),
              ],
            ),

            if ((_events[item.id] ?? []).isNotEmpty) ...[
              const Divider(),

              const Text('Línea de tiempo'),

              ...(_events[item.id]!).map(
                (event) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${event.occurredAt.toLocal()} · '
                    '${event.action} · '
                    '${event.actorId}'
                    '${event.details == null ? '' : ' · ${event.details}'}',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
