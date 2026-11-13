import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../realtime/declaration_notices.dart';

import '../../../core/errors/user_error.dart';
import '../../declaration/data/services/supervisor_inbox_service.dart';
import '../../declaration/domain/entities/declaration.dart';
import '../../declaration/domain/entities/declaration_form.dart';
import '../../schedule/domain/schedule.dart';
import '../../pdf/data/final_declaration_service.dart';

/// Inbox where human resources handles declarations signed by both parties.
///
/// Each declaration moves through three steps, and the actions shown in the
/// list depend on its status:
///
/// 1. [DeclarationStatus.sentToHr]: the reception can be registered.
/// 2. [DeclarationStatus.receivedByHr] without a final PDF: the PDF can be
///    generated.
/// 3. [DeclarationStatus.receivedByHr] with a final PDF: it can be downloaded
///    and the declaration can be finalized.
///
/// The list refreshes itself every 30 seconds. [service] allows injecting a
/// fake implementation in tests.
class HumanResourcesInboxScreen extends StatefulWidget {
  const HumanResourcesInboxScreen({super.key, this.service});

  final HumanResourcesInboxService? service;

  @override
  State<HumanResourcesInboxScreen> createState() =>
      _HumanResourcesInboxScreenState();
}

class _HumanResourcesInboxScreenState extends State<HumanResourcesInboxScreen> {
  late final HumanResourcesInboxService _service =
      widget.service ?? HumanResourcesInboxService();
  final _pdf = FinalDeclarationService();
  late Future<List<Declaration>> _items = _service.getInbox();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        _reload();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reload() {
    final items = _service.getInbox();
    setState(() {
      _items = items;
    });
  }

  /// Returns the declarant's name from the stored profile snapshot, falling
  /// back to the user id when the snapshot has no usable name.
  String _declarantName(Declaration declaration) {
    final profile = declaration.payload['profile'];
    if (profile is Map && profile['name'] is String) {
      final name = (profile['name'] as String).trim();
      if (name.isNotEmpty) {
        return name;
      }
    }
    return declaration.personId;
  }

  /// Builds the read-only detail of the signed version stored in the payload.
  List<Widget> _formDetails(Declaration declaration) {
    final form = DeclarationForm.fromMap(declaration.payload);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
    Widget field(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text('$label: ${value.trim().isEmpty ? "No indicado" : value}'),
    );
    List<Widget> jobs(String title, List<Appointment> items) => [
      heading(title),
      if (items.isEmpty) const Text('Ninguno registrado.'),
      for (final job in items) ...[
        field('Lugar de trabajo', job.workplace),
        if (job.institution.isNotEmpty) field('Institución', job.institution),
        field('Puesto', job.position),
        if (job.courseCode != null) field('Sigla del curso', job.courseCode!),
        field('Horas semanales', (job.weeklyMinutes / 60).toStringAsFixed(2)),
        if (job.workloadType != null) ...[
          field('Tipo de jornada', job.workloadType!.label),
          field(
            'Clases',
            durationText(job.minutesFor(ScheduleActivity.teaching)),
          ),
          field(
            'Consultas',
            durationText(job.minutesFor(ScheduleActivity.consultation)),
          ),
        ],
        field(
          'Vigencia',
          '${dateText(job.startsOn)} al ${dateText(job.endsOn)}',
        ),
        for (final block in job.blocks)
          Text(
            '${block.day >= 1 && block.day <= dayNames.length ? dayNames[block.day - 1] : "Día ${block.day}"}: ${timeText(block.start)} – ${timeText(block.end)}${block.activity == null ? '' : ' · ${block.activity!.label}'}',
          ),
        const Divider(),
      ],
    ];
    return [
      heading('Persona declarante'),
      field('Nombre', form.profile.name),
      field('Identificación', form.profile.identification),
      field('Teléfono', form.profile.phone),
      field('Correo', form.profile.email),
      field('Unidad', form.profile.unit),
      ...jobs('Nombramientos', form.appointments),
      ...jobs('Empleos externos', form.externalJobs),
      heading('Observaciones'),
      Text(
        form.observations.trim().isEmpty
            ? 'Sin observaciones.'
            : form.observations,
      ),
      heading('Firmas registradas'),
      field(
        'Declarante',
        declaration.declarantSignedAt?.toLocal().toString() ?? 'No registrada',
      ),
      field(
        'Superior',
        declaration.superiorSignedAt?.toLocal().toString() ?? 'No registrada',
      ),
    ];
  }

  /// Fetches the full declaration for [summary] and shows it in a read-only
  /// dialog. The inbox list may hold only summary data, so the document is
  /// re-read before displaying it.
  Future<void> _open(Declaration summary) async {
    try {
      final declaration = await _service.getDeclaration(summary.id);
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Declaración · ${declaration.periodId}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Estado: ${declaration.status.label}'),
                Text(
                  'Versión ${declaration.version} · revisión ${declaration.revision}',
                ),
                Text('UID declarante: ${declaration.personId}'),
                const SizedBox(height: 12),
                ..._formDetails(declaration),
                const SizedBox(height: 12),
                const Text(
                  'Vista de consulta. No se modifica el documento desde esta pantalla.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userError(error))));
      }
    }
  }

  /// Registers the administrative reception after explicit confirmation.
  Future<void> _receive(Declaration declaration) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar recepción'),
        content: const Text(
          '¿Registrar la recepción de esta declaración en Recursos Humanos?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar recepción'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await _service.receive(declaration);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Recepción registrada.')));
        _reload();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userError(error))));
      }
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  /// Requests the final PDF for the signed version of [declaration].
  ///
  /// The PDF is produced server-side and stored in Firebase Storage. The list
  /// is reloaded on failure too, since the server may have linked the file
  /// before the error surfaced.
  Future<void> _generatePdf(Declaration declaration) async {
    if (!await _confirm(
      'Generar PDF final',
      'El documento se generará en el servidor para la versión firmada y se almacenará en Firebase Storage.',
      'Generar PDF',
    )) {
      return;
    }
    try {
      await _pdf.generate(declaration);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF generado y vinculado a la versión.'),
          ),
        );
        _reload();
      }
    } catch (error, stack) {
      debugPrint('Generar PDF: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        _reload();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userError(error))));
      }
    }
  }

  /// Closes the process. Only offered once the final PDF exists.
  Future<void> _finalize(Declaration declaration) async {
    if (!await _confirm(
      'Finalizar declaración',
      'La declaración recibida y su PDF final quedarán en estado FINALIZADO.',
      'Finalizar',
    )) {
      return;
    }
    try {
      await _pdf.finalize(declaration);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Declaración finalizada.')),
        );
        _reload();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userError(error))));
      }
    }
  }

  Future<void> _download(Declaration declaration) async {
    try {
      await _pdf.download(declaration);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (DeclarationNotices.url.isNotEmpty &&
              FirebaseAuth.instance.currentUser?.uid != null)
            DeclarationNotices(
              user: FirebaseAuth.instance.currentUser!,
              onChanged: _reload,
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Bandeja de Recursos Humanos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          FutureBuilder<List<Declaration>>(
            future: _items,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Column(
                  children: [
                    Text(userError(snapshot.error!)),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('Reintentar'),
                    ),
                  ],
                );
              }
              final declarations = snapshot.data ?? const <Declaration>[];
              if (declarations.isEmpty) {
                return const Text(
                  'No hay declaraciones enviadas a Recursos Humanos.',
                );
              }
              return Column(
                children: declarations
                    .map(
                      (declaration) => Card(
                        child: ListTile(
                          title: Text(
                            'Declaración de ${_declarantName(declaration)}',
                          ),
                          subtitle: Text(
                            'Período ${declaration.periodId} · versión ${declaration.version} · revisión ${declaration.revision}',
                          ),
                          onTap: () => _open(declaration),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: 'Consultar',
                                onPressed: () => _open(declaration),
                                icon: const Icon(Icons.visibility_outlined),
                              ),
                              if (declaration.status ==
                                  DeclarationStatus.sentToHr)
                                IconButton(
                                  tooltip: 'Registrar recepción',
                                  onPressed: () => _receive(declaration),
                                  icon: const Icon(
                                    Icons.move_to_inbox_outlined,
                                  ),
                                ),
                              if (declaration.status ==
                                  DeclarationStatus.receivedByHr)
                                if (declaration.finalPdfPath == null)
                                  IconButton(
                                    tooltip: 'Generar PDF final',
                                    onPressed: () => _generatePdf(declaration),
                                    icon: const Icon(
                                      Icons.picture_as_pdf_outlined,
                                    ),
                                  )
                                else ...[
                                  IconButton(
                                    tooltip: 'Descargar PDF final',
                                    onPressed: () => _download(declaration),
                                    icon: const Icon(Icons.download_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Finalizar declaración',
                                    onPressed: () => _finalize(declaration),
                                    icon: const Icon(Icons.task_alt_outlined),
                                  ),
                                ],
                            ],
                          ),
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
}
