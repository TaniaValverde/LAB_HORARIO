import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/errors/user_error.dart';
import '../../../core/state/app_state.dart';
import '../../schedule/presentation/approved_schedule_document.dart';
import '../../schedule/presentation/schedule_export.dart';
import '../../schedule/data/schedule_download_unsupported.dart'
    if (dart.library.js_interop) '../../schedule/data/schedule_download_web.dart'
    as platform;
import '../domain/entities/declaration.dart';
import '../domain/usecases/approved_schedule.dart';

class ApprovedScheduleScreen extends StatefulWidget {
  const ApprovedScheduleScreen({
    super.key,
    required this.personId,
    required this.watch,
    required this.loadFresh,
    required this.identities,
    required this.isCurrentUser,
    this.encode,
    this.download,
  });

  final String personId;
  final Stream<List<Declaration>> Function() watch;
  final Future<List<Declaration>> Function() loadFresh;
  final Stream<String?> identities;
  final bool Function() isCurrentUser;
  final Future<Uint8List> Function(ApprovedScheduleDocument, bool pdf)? encode;
  final Future<void> Function(Uint8List, String, String)? download;

  @override
  State<ApprovedScheduleScreen> createState() => _ApprovedScheduleScreenState();
}

class _ApprovedScheduleScreenState extends State<ApprovedScheduleScreen> {
  StreamSubscription<List<Declaration>>? _subscription;
  StreamSubscription<String?>? _identitySubscription;
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  List<Declaration> _items = [];
  String? _period;
  String? _error;
  String? _exportMessage;
  bool _loading = true;
  bool _busy = false;
  bool _sessionValid = true;

  @override
  void initState() {
    super.initState();
    _identitySubscription = widget.identities.listen((uid) {
      if (uid != widget.personId && mounted) {
        setState(() {
          _sessionValid = false;
          _items = [];
        });
        _subscription?.cancel();
      }
    });
    _listen();
  }

  void _listen() {
    _subscription?.cancel();
    _subscription = widget.watch().listen(
      (items) {
        if (!mounted || !_sessionValid) return;
        setState(() {
          _items = approvedSchedules(items, widget.personId);
          if (!_items.any((d) => d.periodId == _period)) {
            _period = _items.isEmpty ? null : _items.first.periodId;
          }
          _loading = false;
          _error = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _items = [];
          _loading = false;
          _error = userError(error);
        });
      },
    );
  }

  Declaration? get _selected {
    for (final item in _items) {
      if (item.periodId == _period) return item;
    }
    return null;
  }

  Future<void> _export(bool pdf) async {
    final selected = _selected;
    if (selected == null ||
        _busy ||
        !_sessionValid ||
        !widget.isCurrentUser()) {
      return;
    }
    setState(() {
      _busy = true;
      _exportMessage = null;
    });
    try {
      // Re-read through the authorized server query before creating a local copy.
      final fresh = approvedSchedules(
        await widget.loadFresh(),
        widget.personId,
      );
      final matches = fresh.where(
        (d) =>
            d.id == selected.id &&
            d.version == selected.version &&
            d.revision == selected.revision,
      );
      if (matches.length != 1) {
        throw StateError(
          'La declaración cambió o ya no está aprobada. Actualice el horario antes de descargarlo.',
        );
      }
      if (!mounted || !_sessionValid || !widget.isCurrentUser()) return;
      final document = ApprovedScheduleDocument(matches.single);
      final encoder = ScheduleExport();
      final bytes =
          await (widget.encode?.call(document, pdf) ??
              (pdf ? encoder.pdf(document) : encoder.png(document)));
      // A stream update or account change during rendering invalidates this export.
      final current = _selected;
      if (!mounted ||
          !_sessionValid ||
          !widget.isCurrentUser() ||
          current?.id != selected.id ||
          current?.revision != selected.revision) {
        return;
      }
      final period = selected.periodId.replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]'),
        '_',
      );
      await (widget.download ?? platform.downloadSchedule)(
        bytes,
        'horario_${period}_v${selected.version}.${pdf ? 'pdf' : 'png'}',
        pdf ? 'application/pdf' : 'image/png',
      );
      if (mounted && _sessionValid) {
        setState(
          () => _exportMessage =
              'Descarga preparada. Revise las descargas de su navegador.',
        );
      }
    } catch (error) {
      if (mounted && _sessionValid) {
        setState(() => _exportMessage = userError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _identitySubscription?.cancel();
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi horario aprobado'),
        actions: const [ThemeToggleAction()],
      ),
      body: !_sessionValid
          ? const Center(
              child: Text(
                'La sesión cambió. Regrese al inicio e ingrese nuevamente.',
              ),
            )
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Consulte los nombramientos institucionales de la última versión aprobada por el superior en cada período. Incluye clases y consultas.',
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() => _loading = true);
                            _listen();
                          },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar horario'),
                  ),
                ),
                if (_error != null)
                  Text(_error!)
                else if (selected == null)
                  const Text(
                    'Todavía no tiene declaraciones aprobadas por el superior.',
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey(_period),
                    initialValue: _period,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Período aprobado',
                    ),
                    items: [
                      for (final item in _items)
                        DropdownMenuItem(
                          value: item.periodId,
                          child: Text(
                            '${item.periodId} · Versión ${item.version}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (period) => setState(() {
                            _period = period;
                            _exportMessage = null;
                          }),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _export(true),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Descargar PDF'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _export(false),
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Descargar PNG'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'La descarga incluye todo el horario del período, aunque no quepa en pantalla. Es una copia visual; no sustituye el PDF final de la declaración.',
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_exportMessage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_exportMessage!),
                    ),
                  const SizedBox(height: 16),
                  _preview(ApprovedScheduleDocument(selected)),
                ],
              ],
            ),
    );
  }

  Widget _preview(ApprovedScheduleDocument document) => SizedBox(
    height: 560,
    child: ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Scrollbar(
        controller: _vertical,
        thumbVisibility: true,
        trackVisibility: true,
        notificationPredicate: (notice) => notice.metrics.axis == Axis.vertical,
        child: Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          trackVisibility: true,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          notificationPredicate: (notice) =>
              notice.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _vertical,
            primary: false,
            child: SingleChildScrollView(
              controller: _horizontal,
              primary: false,
              scrollDirection: Axis.horizontal,
              child: Semantics(
                label:
                    'Horario semanal aprobado de ${document.form.profile.name}. Período ${document.declaration.periodId}.',
                child: CustomPaint(
                  size: document.size,
                  painter: ApprovedSchedulePainter(document),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
