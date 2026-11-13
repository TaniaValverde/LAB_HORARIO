import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../../core/errors/user_error.dart';
import '../../../core/state/app_state.dart';
import '../../profile/domain/declaring_profile.dart';
import '../../profile/data/profile_repository.dart';
import '../../schedule/domain/schedule.dart';
import '../../validation/domain/validate_schedule.dart';
import '../data/services/declarant_oath_service.dart';
import '../data/services/declarant_signature_service.dart';
import '../data/services/declaration_submission_service.dart';
import '../data/services/declaration_tracking_service.dart';
import '../data/repositories/firestore_declaration_repository.dart';
import '../../pdf/data/final_declaration_service.dart';
import '../domain/entities/audit_event.dart';
import '../domain/entities/declaration.dart';
import '../domain/entities/declaration_form.dart';
import '../domain/repositories/audit_repository.dart';
import '../domain/repositories/declaration_repository.dart';
import '../domain/usecases/update_declaration_form.dart';
import 'appointment_dialog.dart';
import 'oath_acceptance_section.dart';
import 'declarant_signature_section.dart';
import 'weekly_schedule.dart';

class DeclarationEditor extends StatefulWidget {
  const DeclarationEditor({
    super.key,
    required this.declaration,
    required this.repository,
    required this.audit,
    this.oath,
    this.signature,
    this.submission,
    this.versionService,
    this.mobileLab = false,
  });
  final Declaration declaration;
  final DeclarationRepository repository;
  final AuditRepository audit;
  final DeclarantOathRepository? oath;
  final DeclarantSignatureRepository? signature;
  final DeclarationSubmissionService? submission;
  final DeclarationVersionService? versionService;
  final bool mobileLab;
  @override
  State<DeclarationEditor> createState() => _DeclarationEditorState();
}

class _DeclarationEditorState extends State<DeclarationEditor> {
  static const _mobileSteps = <({String title, IconData icon})>[
    (title: 'Datos', icon: Icons.person_outline),
    (title: 'Jornadas', icon: Icons.work_outline),
    (title: 'Horario', icon: Icons.calendar_month_outlined),
    (title: 'Revisar', icon: Icons.fact_check_outlined),
  ];
  late final DeclarationState _declarationState = DeclarationState(
    widget.declaration,
  );
  final SignatureFlowState _signatureFlow = SignatureFlowState();
  final ValidationState _validationState = ValidationState();
  Declaration get _current => _declarationState.declaration;
  set _current(Declaration value) => _declarationState.replace(value);
  bool get _busy => _signatureFlow.busy;
  bool get _mobileLabMode => widget.mobileLab;
  set _busy(bool value) =>
      value ? _signatureFlow.begin() : _signatureFlow.finish();
  String? get _message => _declarationState.error;
  set _message(String? value) => _declarationState.setError(value);
  late final DeclarationForm _initial = DeclarationForm.fromMap(
    _current.payload,
  );
  late final _name = TextEditingController(text: _initial.profile.name);
  late final _identification = TextEditingController(
    text: _initial.profile.identification,
  );
  late final _phone = TextEditingController(text: _initial.profile.phone);
  late final _email = TextEditingController(text: _initial.profile.email);
  late final _unit = TextEditingController(text: _initial.profile.unit);
  late final _observations = TextEditingController(text: _initial.observations);
  late final List<Appointment> _appointments = [..._initial.appointments];
  late final List<Appointment> _external = [..._initial.externalJobs];
  bool _dirty = false;
  int _mobileStep = 0;
  late final DeclarantOathRepository _oath =
      widget.oath ?? DeclarantOathService();
  late final DeclarantSignatureRepository _signature =
      widget.signature ?? DeclarantSignatureService();
  late final DeclarationSubmissionService _submission =
      widget.submission ?? DeclarationSubmissionService();
  ApprovedOath? _approvedOath;
  bool _loadingOath = false;
  String? _oathError;
  late Future<List<AuditEvent>> _timeline;
  Future<Map<String, Object?>>? _tracking;

  @override
  void initState() {
    super.initState();
    _timeline = _mobileLabMode
        ? Future.value(const <AuditEvent>[])
        : widget.audit.getForDeclaration(_current.id);
    if (!_mobileLabMode &&
        widget.repository is FirestoreDeclarationRepository) {
      _tracking = DeclarationTrackingService().status(_current.id);
    }
    if (!_mobileLabMode &&
        _current.status == DeclarationStatus.validated) {
      _loadOath();
    }
  }

  Future<void> _createCorrectedVersion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear nueva versión'),
        content: const Text(
          'La versión devuelta y sus firmas históricas se conservarán sin cambios. Se creará una nueva versión para corregir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crear versión'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final service = widget.versionService ?? DeclarationVersionService();
      final id = await service.create(_current);
      final next = await widget.repository.getById(id);
      if (next == null) {
        throw StateError(
          'El servidor creó la versión, pero no pudo recuperarse.',
        );
      }
      if (mounted) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => DeclarationEditor(
              declaration: next,
              repository: widget.repository,
              audit: widget.audit,
              oath: widget.oath,
              signature: widget.signature,
              versionService: widget.versionService,
              mobileLab: widget.mobileLab,
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = userError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadFinalPdf() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await FinalDeclarationService().download(_current);
      if (mounted) setState(() => _message = 'Descarga del PDF solicitada.');
    } catch (error) {
      if (mounted) setState(() => _message = userError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadOath() async {
    setState(() {
      _loadingOath = true;
      _approvedOath = null;
      _oathError = null;
    });
    try {
      final text = await _oath.loadApprovedText();
      if (mounted) setState(() => _approvedOath = text);
    } on OathConfigurationException catch (error) {
      if (mounted) setState(() => _oathError = error.message);
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(
          () => _oathError =
              'No se pudo consultar el juramento (${error.code}). ${userError(error)}',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _oathError = 'No se pudo consultar el juramento aprobado. Reintente; si persiste, revise su conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingOath = false);
    }
  }

  bool get _editable =>
      !_current.isImmutable &&
      (_current.status == DeclarationStatus.draft ||
          _current.status == DeclarationStatus.validated);
  DeclarationForm get _form => DeclarationForm(
    profile: DeclaringProfile(
      name: _name.text.trim(),
      identification: _identification.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      unit: _unit.text.trim(),
    ),
    appointments: _appointments,
    externalJobs: _external,
    observations: _observations.text.trim(),
  );
  @override
  void dispose() {
    _declarationState.dispose();
    _signatureFlow.dispose();
    _validationState.dispose();
    for (final c in [
      _name,
      _identification,
      _phone,
      _email,
      _unit,
      _observations,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(bool validate) async {
    final form = _form;
    final result = _validationState.validate(form);
    if (validate && !result.valid) {
      setState(() {
        _mobileStep = _mobileSteps.length - 1;
        _message =
            'Hay ${result.issues.length} errores. Corríjalos antes de validar. Puede guardar el borrador.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final next = _current.copyWith(
        payload: form.toMap(),
        status: validate
            ? DeclarationStatus.validated
            : DeclarationStatus.draft,
      );
      final updated =
          await UpdateDeclarationForm(
            declarations: widget.repository,
            audit: widget.audit,
          )(
            declaration: next,
            actorId: _current.personId,
            previousStatus: _current.status,
          );
      if (mounted) {
        setState(() {
          _current = updated;
          _timeline = _mobileLabMode
              ? Future.value(const <AuditEvent>[])
              : widget.audit.getForDeclaration(updated.id);
          if (_tracking != null) {
            _tracking = DeclarationTrackingService().status(updated.id);
          }
          _dirty = false;
          _message = validate
              ? _mobileLabMode
                    ? 'Declaración VALIDADA. Esta versión móvil no realiza firmas ni aprobaciones.'
                    : 'Declaración VALIDADA. Disponible para el flujo de firmas.'
              : 'Borrador guardado.';
        });
        if (validate && !_mobileLabMode) await _loadOath();
      }
    } catch (e) {
      if (mounted) setState(() => _message = userError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ProfileRepository().save(_current.personId, _form.profile);
      if (mounted) {
        setState(
          () => _message = 'Perfil actualizado para próximas declaraciones.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = userError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acceptOath() async {
    final approved = _approvedOath;
    if (approved == null || _dirty || _busy || _loadingOath) return;
    var acceptedOnServer = false;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await _oath.accept(
        declaration: _current,
        explicitlyConfirmed: true,
        expectedOathTextVersion: approved.version,
      );
      acceptedOnServer = true;
      // Use the persisted server timestamp rather than inventing a local one.
      final saved = await widget.repository.getById(_current.id);
      if (saved == null ||
          saved.version != result.version ||
          saved.revision < result.revision ||
          saved.oathAcceptedAt == null ||
          (saved.status != DeclarationStatus.pendingDeclarantSignature &&
              saved.status != DeclarationStatus.signedByDeclarant)) {
        throw StateError('No se pudo recuperar la aceptación registrada.');
      }
      if (mounted) {
        setState(() {
          _current = saved;
          _timeline = widget.audit.getForDeclaration(saved.id);
          if (_tracking != null) {
            _tracking = DeclarationTrackingService().status(saved.id);
          }
          _dirty = false;
          _message = result.alreadyAccepted
              ? 'El juramento ya estaba registrado. La declaración aún no está firmada.'
              : 'Juramento aceptado. La declaración aún no está firmada.';
        });
      }
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition' && mounted) await _loadOath();
      if (mounted) {
        setState(
          () => _message = switch (e.code) {
            'unauthenticated' => 'Su sesión expiró. Inicie sesión nuevamente.',
            'permission-denied' => 'Solo la persona declarante propietaria puede aceptar el juramento.',
            'failed-precondition' => 'La declaración o el texto del juramento cambió. Revise el texto actualizado; si persiste, vuelva a abrir la declaración.',
            'not-found' => 'La declaración ya no existe.',
            _ =>
              'No se pudo registrar la aceptación del juramento (${e.code}).',
          },
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _message = acceptedOnServer
              ? 'El juramento se registró, pero no se pudo actualizar la pantalla. Vuelva a abrir la declaración para recuperar su estado.'
              : userError(e),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signDeclaration() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await _signature.sign(
        declaration: _current,
        explicitlyConfirmed: true,
      );
      if (mounted) {
        setState(() {
          _current = _current.copyWith(
            status: DeclarationStatus.signedByDeclarant,
            revision: result.revision,
            declarantSignedAt: result.signedAt,
            declarantSignature: result.signatureId,
          );
          _timeline = widget.audit.getForDeclaration(_current.id);
          if (_tracking != null) {
            _tracking = DeclarationTrackingService().status(_current.id);
          }
          _dirty = false;
          _message = result.alreadySigned
              ? 'La firma de esta versión ya estaba registrada.'
              : 'Firma electrónica interna registrada para la versión ${result.version}, revisión ${result.revision}.';
        });
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(
          () => _message = switch (e.code) {
            'unauthenticated' => 'Su sesión expiró. Inicie sesión nuevamente.',
            'permission-denied' => 'El servidor rechazó la operación de firma. Compruebe que su perfil esté activo y que esta declaración le pertenezca.',
            'failed-precondition' => 'La versión cambió o ya no está pendiente de firma. Recargue la declaración.',
            'not-found' => 'La declaración ya no existe.',
            'invalid-argument' =>
              'Confirme la firma de la versión para continuar.',
            'already-exists' => 'Se encontró un evento de firma previo inconsistente. Contacte a soporte.',
            _ =>
              'No se pudo registrar la firma (${e.code}). Inténtelo de nuevo.',
          },
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = userError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitToSupervisor() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enviar al superior jerárquico'),
        content: Text(
          'Se enviará la versión ${_current.version}, revisión ${_current.revision}, '
          'a la revisión del superior asignado. La firma registrada no se modificará.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar envío'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await _submission.submit(
        declaration: _current,
        explicitlyConfirmed: true,
      );
      final saved = await widget.repository.getById(_current.id);
      if (saved == null ||
          saved.version != result.version ||
          saved.revision != result.revision ||
          saved.status != DeclarationStatus.pendingSuperiorSignature) {
        throw StateError('No se pudo recuperar el estado enviado al superior.');
      }
      if (mounted) {
        setState(() {
          _current = saved;
          _timeline = widget.audit.getForDeclaration(saved.id);
          if (_tracking != null) {
            _tracking = DeclarationTrackingService().status(saved.id);
          }
          _message = result.alreadySubmitted
              ? 'La declaración ya estaba enviada al superior asignado.'
              : 'La declaración fue enviada al superior asignado.';
        });
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(
          () => _message = switch (e.code) {
            'unauthenticated' => 'Su sesión expiró. Inicie sesión nuevamente.',
            'permission-denied' => 'Solo la persona declarante propietaria puede enviar esta declaración.',
            'failed-precondition' => 'La firma, la asignación o la versión ya no están vigentes. Vuelva a cargar la declaración.',
            'not-found' => 'La declaración ya no existe.',
            'invalid-argument' =>
              'Confirme el envío de la versión firmada para continuar.',
            _ =>
              'No se pudo enviar la declaración (${e.code}). Inténtelo de nuevo.',
          },
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = userError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editJob(bool external, [int? index]) async {
    final list = external ? _external : _appointments;
    final result = await showDialog<Appointment>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppointmentDialog(
        external: external,
        initial: index == null ? null : list[index],
      ),
    );
    if (result != null && mounted) {
      setState(() {
        if (index == null) {
          list.add(result);
        } else {
          list[index] = result;
        }
        _dirty = true;
        _message = null;
      });
    }
  }

  Future<bool> _confirmExit() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cambios sin guardar'),
            content: const Text(
              '¿Desea salir y descartar los cambios pendientes?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Continuar editando'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Descartar y salir'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final validation = _validationState.validate(_form, notify: false);
    return ListenableBuilder(
      listenable: Listenable.merge([
        _declarationState,
        _signatureFlow,
        _validationState,
      ]),
      builder: (context, _) => PopScope(
        canPop: !_dirty && !_busy,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop || _busy) return;
          if (await _confirmExit() && mounted) {
            setState(() => _dirty = false);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) Navigator.pop(context);
            });
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text('Declaración · versión ${_current.version}'),
            actions: const [ThemeToggleAction()],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 640;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 600 : 1000),
                  child: ListView(
                    padding: EdgeInsets.all(compact ? 16 : 20),
                    children: [
                      if (compact) _mobileProgress(validation),
                      Text(
                        'Período ${_current.periodId}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'Estado: ${_current.status.label}'
                        '${_dirty ? ' · Cambios sin guardar' : ''}',
                      ),
                      if (_mobileLabMode)
                        const Card(
                          child: ListTile(
                            leading: Icon(Icons.info_outline),
                            title: Text('Alcance de la versión móvil'),
                            subtitle: Text(
                              'Esta versión permite guardar y validar declaraciones. No realiza ni simula firmas, aprobaciones jerárquicas ni recepción de Recursos Humanos.',
                            ),
                          ),
                        ),
                      if (!_mobileLabMode) _returnObservationCard(),
                      if (_tracking != null)
                        FutureBuilder<Map<String, Object?>>(
                          future: _tracking,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                    ConnectionState.waiting &&
                                !snapshot.hasData) {
                              return const LinearProgressIndicator();
                            }
                            if (snapshot.hasError) {
                              return Text(
                                'No se pudo actualizar el seguimiento: ${userError(snapshot.error!)}',
                              );
                            }
                            final data = snapshot.data;
                            if (data == null) {
                              return const SizedBox.shrink();
                            }
                            final responsible = data['responsible'];
                            final status = data['status'];
                            final annulled =
                                status == DeclarationStatus.annulled.name;
                            final finalized =
                                status == DeclarationStatus.finalized.name ||
                                annulled;
                            final name =
                                responsible is Map &&
                                    responsible['name'] is String
                                ? responsible['name'] as String
                                : finalized
                                ? 'No hay acciones pendientes'
                                : 'Sin responsable activo registrado';
                            final updated = data['updatedAt'] is String
                                ? DateTime.tryParse(data['updatedAt'] as String)
                                          ?.toLocal()
                                          .toString() ??
                                      'No disponible'
                                : 'No disponible';
                            return Card(
                              child: ListTile(
                                leading: const Icon(
                                  Icons.track_changes_outlined,
                                ),
                                title: Text(
                                  annulled
                                      ? 'Declaración anulada · sin acciones pendientes'
                                      : finalized
                                      ? 'Trámite finalizado · sin acciones pendientes'
                                      : 'Responsable actual: $name',
                                ),
                                subtitle: Text(
                                  'Última actualización registrada: $updated',
                                ),
                              ),
                            );
                          },
                        ),
                      if (!_mobileLabMode &&
                          _current.status ==
                          DeclarationStatus.pendingDeclarantSignature)
                        const Text(
                          'Juramento aceptado. La firma del declarante aún no se ha realizado.',
                        ),
                      if (!_mobileLabMode &&
                          _current.status ==
                              DeclarationStatus.signedByDeclarant &&
                          _current.declarantSignedAt != null)
                        Text(
                          'Firma electrónica interna registrada el '
                          '${_current.declarantSignedAt!.toLocal()}.',
                        ),
                      if (!_editable && !_mobileLabMode)
                        const Text(
                          'Esta versión es de consulta. Para corregir una versión firmada se requiere una nueva versión.',
                        ),
                      if (_current.status == DeclarationStatus.validated &&
                          _editable)
                        const Text(
                          'Si guarda cambios, volverá a BORRADOR y deberá validar nuevamente.',
                        ),
                      const SizedBox(height: 20),
                      if (!compact || _mobileStep == 0)
                        _section('Datos de la persona declarante', [
                          _field(_name, 'Nombre completo'),
                          _field(_identification, 'Identificación'),
                          _field(
                            _phone,
                            'Teléfono',
                            keyboard: TextInputType.phone,
                          ),
                          _field(
                            _email,
                            'Correo de contacto',
                            keyboard: TextInputType.emailAddress,
                          ),
                          _field(_unit, 'Unidad académica o administrativa'),
                          if (_editable)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _busy ? null : _saveProfile,
                                icon: const Icon(Icons.person),
                                label: const Text(
                                  'Guardar estos datos en mi perfil',
                                ),
                              ),
                            ),
                        ]),
                      if (!compact || _mobileStep == 1) ...[
                        _jobSection(false),
                        _jobSection(true),
                      ],
                      if (!compact || _mobileStep == 2)
                        _section('Horario semanal', [
                          WeeklySchedule(
                            appointments: _appointments,
                            externalJobs: _external,
                          ),
                        ]),
                      if (!compact || _mobileStep == 3) ...[
                        _section('Resumen de la declaración', [
                          _summaryRow('Período', _current.periodId),
                          _summaryRow('Versión', '${_current.version}'),
                          _summaryRow(
                            'Nombramientos',
                            '${_appointments.length}',
                          ),
                          _summaryRow(
                            'Instituciones adicionales',
                            '${_external.length}',
                          ),
                          _summaryRow(
                            'Horas semanales registradas',
                            _hours(
                              validation.hours.fold<int>(
                                0,
                                (total, entry) => total + entry.declared,
                              ),
                            ),
                          ),
                          _summaryRow(
                            'Resultado',
                            validation.valid
                                ? 'Sin errores bloqueantes'
                                : '${validation.issues.length} observaciones por corregir',
                          ),
                        ]),
                        _section('Observaciones', [
                          _field(
                            _observations,
                            'Docencia, atención, proyectos u otras particularidades',
                            lines: 4,
                          ),
                        ]),
                        _section('Revisión de horarios y jornada', [
                          const Text(
                            'Lunes a sábado. De 12:00 a 13:00 no se admiten bloques. Máximo 10 horas por día, sumando nombramientos y empleos externos vigentes.',
                          ),
                          const SizedBox(height: 12),
                          ...validation.hours.map(
                            (h) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '${h.label}\nEsperadas: ${_hours(h.expected)} h · Declaradas: ${_hours(h.declared)} h · Diferencia: ${_hours(h.difference)} h',
                              ),
                            ),
                          ),
                          if (validation.valid)
                            ListTile(
                              leading: Icon(
                                Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              title: Text('Sin errores bloqueantes.'),
                            ),
                          ...validation.issues.map(
                            (i) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 20,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(i.message)),
                                ],
                              ),
                            ),
                          ),
                        ]),
                      ],
                      if (!_mobileLabMode &&
                          _current.status == DeclarationStatus.validated) ...[
                        if (_loadingOath) const LinearProgressIndicator(),
                        if (_oathError != null) Text(_oathError!),
                        if (!_loadingOath) ...[
                          if (_approvedOath != null)
                            Text(
                              'Texto del juramento · versión ${_approvedOath!.version}',
                            ),
                          if (_oathError == null)
                            OathAcceptanceSection(
                              key: ValueKey(
                                'oath_${_current.revision}_${_approvedOath?.version}',
                              ),
                              officialOathText: _approvedOath?.text,
                              canAccept: !_dirty && validation.valid,
                              busy: _busy,
                              onAccept: _acceptOath,
                            ),
                          TextButton(
                            onPressed: _busy ? null : _loadOath,
                            child: const Text('Actualizar texto del juramento'),
                          ),
                        ],
                      ],
                      if (!_mobileLabMode &&
                          _current.status ==
                          DeclarationStatus.pendingDeclarantSignature)
                        DeclarantSignatureSection(
                          declaration: _current,
                          canSign:
                              !_dirty &&
                              _current.oathAcceptedAt != null &&
                              _current.declarantSignedAt == null &&
                              _current.declarantSignature == null &&
                              validation.valid,
                          busy: _busy,
                          onSign: _signDeclaration,
                        ),
                      if (!_mobileLabMode &&
                          _current.status ==
                              DeclarationStatus.signedByDeclarant &&
                          widget.repository is FirestoreDeclarationRepository)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _submitToSupervisor,
                            icon: const Icon(Icons.send_outlined),
                            label: const Text('Enviar al superior'),
                          ),
                        ),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(_message!),
                          ),
                        ),
                      if (_busy) const LinearProgressIndicator(),
                      if (_editable)
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => _save(false),
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('Guardar borrador'),
                            ),
                            FilledButton.icon(
                              onPressed: _busy ? null : () => _save(true),
                              icon: const Icon(Icons.fact_check_outlined),
                              label: const Text('Validar declaración'),
                            ),
                          ],
                        ),
                      if (compact && _editable) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (_mobileStep > 0)
                              OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() => _mobileStep--),
                                icon: const Icon(Icons.arrow_back),
                                label: const Text('Atrás'),
                              ),
                            const Spacer(),
                            if (_mobileStep < _mobileSteps.length - 1)
                              FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() => _mobileStep++),
                                icon: const Icon(Icons.arrow_forward),
                                label: const Text('Continuar'),
                              ),
                          ],
                        ),
                      ],
                      if (!_mobileLabMode &&
                          _current.status == DeclarationStatus.returned &&
                          widget.repository is FirestoreDeclarationRepository)
                        FilledButton.icon(
                          onPressed: _busy ? null : _createCorrectedVersion,
                          icon: const Icon(Icons.add_task_outlined),
                          label: const Text(
                            'Crear nueva versión para corregir',
                          ),
                        ),
                      if (!_mobileLabMode &&
                          widget.repository is FirestoreDeclarationRepository &&
                          _current.finalPdfPath != null &&
                          (_current.status == DeclarationStatus.receivedByHr ||
                              _current.status == DeclarationStatus.finalized))
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _downloadFinalPdf,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Descargar PDF final'),
                        ),
                      if (!_mobileLabMode) _timelineSection(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _hours(int m) => (m / 60).toStringAsFixed(2);

  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );

  Widget _mobileProgress(ValidationResult validation) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Paso ${_mobileStep + 1} de ${_mobileSteps.length} · ${_mobileSteps[_mobileStep].title}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: (_mobileStep + 1) / _mobileSteps.length),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            validation.valid
                ? 'Los datos actuales no presentan errores bloqueantes.'
                : 'Hay ${validation.issues.length} observaciones. Revise el paso de validación antes de continuar.',
          ),
        ),
      ],
    ),
  );

  /// Displays the observation recorded when the supervisor returned the declaration.
  ///
  /// A returned version stores the observation on its own document. A correction
  /// version retrieves it from the historical `returnedForCorrection` event
  /// because the new version starts without a pending return observation.
  Widget _returnObservationCard() {
    final direct = _current.returnObservation;
    if (direct != null && direct.trim().isNotEmpty) {
      return _observationCard(direct.trim(), pending: true);
    }
    if (_current.parentVersionId == null) return const SizedBox.shrink();
    return FutureBuilder<List<AuditEvent>>(
      future: _timeline,
      builder: (context, snapshot) {
        final events = snapshot.data ?? const <AuditEvent>[];
        final returns = events
            .where(
              (event) =>
                  event.action == 'returnedForCorrection' &&
                  (event.details ?? '').trim().isNotEmpty,
            )
            .toList();
        if (returns.isEmpty) return const SizedBox.shrink();
        return _observationCard(returns.last.details!.trim(), pending: false);
      },
    );
  }

  Widget _observationCard(String observation, {required bool pending}) => Card(
    margin: const EdgeInsets.only(top: 12),
    color: pending
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                pending ? Icons.report_problem_outlined : Icons.history,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pending
                      ? 'Observación del superior (pendiente de corrección)'
                      : 'Observación registrada en la devolución anterior',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(observation),
        ],
      ),
    ),
  );

  Widget _timelineSection() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Historial de auditoría',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          FutureBuilder<List<AuditEvent>>(
            future: _timeline,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return Text(
                  'No se pudo cargar el historial: ${userError(snapshot.error!)}',
                );
              }
              final events = snapshot.data ?? const <AuditEvent>[];
              if (events.isEmpty) {
                return const Text('Todavía no hay eventos registrados.');
              }
              return Column(
                children: events
                    .map(
                      (event) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.history),
                        title: Text(_eventName(event.action)),
                        subtitle: Text(
                          '${event.occurredAt.toLocal()} · Actor ${event.actorId}'
                          '${event.version == null ? '' : ' · Versión ${event.version}'}'
                          '${event.estadoAnterior == null && event.estadoNuevo == null ? '' : '\n${_stateLabel(event.estadoAnterior) ?? 'Inicio'} → ${_stateLabel(event.estadoNuevo) ?? 'Sin cambio'}'}'
                          '${event.details == null ? '' : '\n${event.details}'}',
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    ),
  );

  /// Maps a persisted workflow state to its display label.
  String? _stateLabel(String? value) => DeclarationStatus.labelOf(value);

  String _eventName(String action) => switch (action) {
    'created' => 'Declaración creada',
    'formUpdated' => 'Formulario actualizado',
    'oathAccepted' => 'Juramento aceptado',
    'declarantSigned' => 'Firma del declarante',
    'submitToSuperior' => 'Enviada a revisión del superior',
    'superiorSigned' => 'Firma del superior',
    'returnedForCorrection' => 'Devuelta para correcciones',
    'versionCreated' => 'Nueva versión creada',
    'sentToHr' => 'Enviada a Recursos Humanos',
    'hrReceived' => 'Recibida en Recursos Humanos',
    'finalized' => 'Trámite finalizado',
    _ => action,
  };
  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
  Widget _field(
    TextEditingController c,
    String label, {
    TextInputType? keyboard,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: c,
      readOnly: !_editable || _busy,
      keyboardType: keyboard,
      maxLines: lines,
      onChanged: (_) => setState(() {
        _dirty = true;
        _message = null;
      }),
      decoration: InputDecoration(labelText: label),
    ),
  );
  Widget _jobSection(bool external) {
    final list = external ? _external : _appointments;
    return _section(
      external ? 'Otras instituciones' : 'Nombramientos institucionales',
      [
        if (list.isEmpty)
          Text(
            external
                ? 'No se han registrado empleos externos.'
                : 'Agregue al menos un nombramiento.',
          ),
        for (var i = 0; i < list.length; i++)
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${external ? list[i].institution : list[i].workplace} · ${list[i].position}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${dateText(list[i].startsOn)} a ${dateText(list[i].endsOn)} · Jornada: ${_hours(list[i].weeklyMinutes)} h/semana',
                  ),
                  if (list[i].courseCode != null)
                    Text('Sigla del curso: ${list[i].courseCode}'),
                  if (list[i].workloadType != null) ...[
                    Text('Tipo de jornada: ${list[i].workloadType!.label}'),
                    Text(
                      'Clases: ${durationText(list[i].minutesFor(ScheduleActivity.teaching))} de ${durationText(list[i].workloadType!.teachingMinutes)} · Consultas: ${durationText(list[i].minutesFor(ScheduleActivity.consultation))} de ${durationText(list[i].workloadType!.consultationMinutes)}',
                    ),
                  ],
                  ...list[i].blocks.map(
                    (b) => Text(
                      '${dayNames[b.day - 1]} ${timeText(b.start)}–${timeText(b.end)}${b.activity == null ? '' : ' · ${b.activity!.label}'}',
                    ),
                  ),
                  if (_editable)
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: _busy ? null : () => _editJob(external, i),
                          child: const Text('Editar'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  list.removeAt(i);
                                  _dirty = true;
                                }),
                          child: const Text('Eliminar'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        if (_editable)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _editJob(external),
              icon: const Icon(Icons.add),
              label: Text(
                external ? 'Agregar institución' : 'Agregar nombramiento',
              ),
            ),
          ),
      ],
    );
  }
}
