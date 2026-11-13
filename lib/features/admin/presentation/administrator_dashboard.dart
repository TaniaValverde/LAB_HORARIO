import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/errors/user_error.dart';
import '../../../core/state/app_state.dart';
import '../../period/data/repositories/firestore_period_repository.dart';
import '../../period/domain/entities/academic_period.dart';
import '../../period/domain/repositories/period_repository.dart';
import '../../roles/data/role_administration_service.dart';
import '../../roles/domain/entities/app_role.dart';
import 'supervisor_assignment_panel.dart';
import 'annulment_picker.dart';
import '../data/annulment_lookup_service.dart';

/// Landing screen for users with the administrator role.
///
/// Groups the administrative actions: academic period management, declaration
/// annulment, role assignment and supervisor assignment.
///
/// [periods] and [roles] allow injecting repositories (e.g. fakes in tests);
/// when omitted, the Firestore and Cloud Functions implementations are used.
class AdministratorDashboard extends StatefulWidget {
  const AdministratorDashboard({
    super.key,
    required this.operatorUid,
    required this.name,
    this.periods,
    this.roles,
    this.annulmentLookup = lookupAnnulments,
  });

  /// UID of the signed-in administrator. Used to block self role changes.
  final String operatorUid;
  final String name;
  final PeriodRepository? periods;
  final RoleAdministrationRepository? roles;
  final AnnulmentLookup annulmentLookup;

  @override
  State<AdministratorDashboard> createState() => _AdministratorDashboardState();
}

class _AdministratorDashboardState extends State<AdministratorDashboard> {
  late final PeriodRepository _periods =
      widget.periods ?? FirestorePeriodRepository();
  late final RoleAdministrationRepository _roles =
      widget.roles ?? RoleAdministrationService();
  late final TextEditingController _targetUid = TextEditingController();
  late final TextEditingController _annulmentId = TextEditingController();
  late final TextEditingController _annulmentVersion = TextEditingController();
  late final TextEditingController _annulmentRevision = TextEditingController();
  late final TextEditingController _annulmentReason = TextEditingController();
  late Future<List<AcademicPeriod>> _periodItems = _periods.getAll();
  AppRole _selectedRole = AppRole.declarant;
  bool _savingRole = false;
  AnnulmentCandidate? _annulment;
  bool _annulling = false;
  String? _annulmentMessage;
  bool _activePeriods = true;
  String _periodQuery = '';
  final _periodSearch = TextEditingController();
  final _periodScroll = ScrollController();

  /// Single feedback line shared by all actions on this screen.
  String? _message;

  @override
  void dispose() {
    _periodSearch.dispose();
    _periodScroll.dispose();
    _targetUid.dispose();
    _annulmentId.dispose();
    _annulmentVersion.dispose();
    _annulmentRevision.dispose();
    _annulmentReason.dispose();
    super.dispose();
  }

  void _filterPeriods({bool? active, String? query}) {
    if (_periodScroll.hasClients) _periodScroll.jumpTo(0);
    setState(() {
      if (active != null) _activePeriods = active;
      if (query != null) _periodQuery = query.trim().toLowerCase();
    });
  }

  void _reloadPeriods() {
    final items = _periods.getAll();
    setState(() {
      _periodItems = items;
    });
  }

  /// Opens the period dialog and persists the result.
  ///
  /// Creates a new period when [existing] is null, otherwise updates it.
  Future<void> _editPeriod([AcademicPeriod? existing]) async {
    final period = await showDialog<AcademicPeriod>(
      context: context,
      builder: (_) => _PeriodDialog(existing: existing),
    );
    if (period == null) return;
    try {
      if (existing == null) {
        await _periods.save(period);
      } else {
        await _periods.update(period);
      }
      if (!mounted) return;
      setState(() {
        _message = existing == null
            ? 'Período creado.'
            : 'Período actualizado.';
        _periodItems = _periods.getAll();
      });
    } catch (error) {
      if (mounted) setState(() => _message = userError(error));
    }
  }

  /// Assigns [_selectedRole] to the profile identified by the entered UID.
  ///
  /// Administrators cannot change their own role. That check is a client-side
  /// convenience only; the server performs the authoritative validation. The
  /// new role is read from the user's token, so it is only visible after the
  /// target user starts a new session.
  Future<void> _assignRole() async {
    final targetUid = _targetUid.text.trim();
    if (targetUid.isEmpty) {
      setState(() => _message = 'Ingrese el UID del perfil existente.');
      return;
    }
    if (targetUid == widget.operatorUid) {
      setState(() => _message = 'No puede cambiar su propio rol.');
      return;
    }
    setState(() {
      _savingRole = true;
      _message = null;
    });
    try {
      final result = await _roles.assign(
        targetUid: targetUid,
        role: _selectedRole,
      );
      if (mounted) {
        setState(
          () => _message = result.alreadyAssigned
              ? 'El perfil ya tenía el rol ${_roleName(result.role)}.'
              : 'Rol ${_roleName(result.role)} asignado. El cambio se verá al iniciar una nueva sesión.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = userError(error));
    } finally {
      if (mounted) setState(() => _savingRole = false);
    }
  }

  /// Annuls a declaration through the `annulDeclaration` Cloud Function.
  ///
  /// Annulment is terminal: the declaration becomes read-only and cannot be
  /// reopened, hence the explicit confirmation dialog. `expectedVersion` and
  /// `expectedRevision` act as optimistic-concurrency guards so the server can
  /// reject the request if the declaration changed after the administrator
  /// looked at it. Input validation, including the mandatory reason, is
  /// enforced server-side.
  Future<void> _chooseAnnulment() async {
    try {
      final periods = await _periodItems;
      if (!mounted) return;
      final selected = await showDialog<AnnulmentCandidate>(
        context: context,
        builder: (_) =>
            AnnulmentPicker(periods: periods, lookup: widget.annulmentLookup),
      );
      if (!mounted || selected == null) return;
      setState(() {
        _annulment = selected;
        _annulmentId.text = selected.id;
        _annulmentVersion.text = '${selected.version}';
        _annulmentRevision.text = '${selected.revision}';
        _annulmentReason.clear();
        _annulmentMessage = null;
      });
    } catch (error) {
      if (mounted) setState(() => _annulmentMessage = userError(error));
    }
  }

  Future<void> _annulDeclaration() async {
    final selected = _annulment;
    final reason = _annulmentReason.text.trim();
    if (selected == null || _annulling) return;
    if (reason.isEmpty || reason.length > 2000) {
      setState(
        () => _annulmentMessage =
            'Indique un motivo de entre 1 y 2000 caracteres.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar anulación'),
        content: Text(
          '${selected.name} · Período ${selected.periodId}\nID: ${selected.id}\nVersión ${selected.version} · Revisión ${selected.revision}\nMotivo: $reason\n\nLa declaración quedará en modo de consulta y no podrá reabrirse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar anulación'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _annulling = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('annulDeclaration').call({
        'declarationId': selected.id,
        'reason': reason,
        'expectedVersion': selected.version,
        'expectedRevision': selected.revision,
        'confirmed': true,
      });
      if (mounted) setState(() => _annulmentMessage = 'Declaración anulada.');
    } catch (error) {
      if (mounted) {
        setState(
          () => _annulmentMessage =
              '${userError(error)} Consulte nuevamente la declaración antes de reintentar.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _annulling = false;
          _annulment = null;
          _annulmentId.clear();
          _annulmentVersion.clear();
          _annulmentRevision.clear();
        });
      }
    }
  }

  String _roleName(AppRole role) => switch (role) {
    AppRole.declarant => 'Declarante',
    AppRole.supervisor => 'Superior jerárquico',
    AppRole.humanResources => 'Recursos Humanos',
    AppRole.administrator => 'Administración',
  };

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Administración'),
      actions: [
        const ThemeToggleAction(),
        TextButton.icon(
          onPressed: () => FirebaseAuth.instance.signOut(),
          icon: const Icon(Icons.logout),
          label: const Text('Salir'),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Administración · ${widget.name}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            Text(
              'Períodos académicos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Solo los períodos activos y dentro de vigencia permiten iniciar declaraciones.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _editPeriod(),
                icon: const Icon(Icons.add),
                label: const Text('Crear período'),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                ChoiceChip(
                  label: const Text('Activos'),
                  selected: _activePeriods,
                  onSelected: (_) => _filterPeriods(active: true),
                ),
                ChoiceChip(
                  label: const Text('Inactivos'),
                  selected: !_activePeriods,
                  onSelected: (_) => _filterPeriods(active: false),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _periodSearch,
              onChanged: (value) => _filterPeriods(query: value),
              decoration: InputDecoration(
                labelText: 'Buscar por identificador',
                hintText: 'Escriba una parte del identificador',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _periodSearch.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _periodSearch.clear();
                          _filterPeriods(query: '');
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<AcademicPeriod>>(
              future: _periodItems,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userError(snapshot.error!)),
                      TextButton(
                        onPressed: _reloadPeriods,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  );
                }
                final periods =
                    [...?snapshot.data]
                        .where(
                          (p) =>
                              p.isActive == _activePeriods &&
                              p.id.toLowerCase().contains(_periodQuery),
                        )
                        .toList()
                      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
                if (periods.isEmpty) {
                  return Card(
                    child: ListTile(
                      title: Text(
                        (snapshot.data ?? []).isEmpty
                            ? 'No hay períodos configurados.'
                            : 'No hay períodos que coincidan con los filtros.',
                      ),
                    ),
                  );
                }
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(scrollbars: false),
                    child: Scrollbar(
                      controller: _periodScroll,
                      thumbVisibility: true,
                      child: ListView(
                        controller: _periodScroll,
                        primary: false,
                        shrinkWrap: true,
                        children: periods
                            .map(
                              (period) => Card(
                                child: ListTile(
                                  title: Text('${period.name} (${period.id})'),
                                  subtitle: Text(
                                    '${_date(period.startsAt.toLocal())} – ${_date(period.endsAt.toLocal())} · '
                                    '${period.isActive ? 'Activo' : 'Inactivo'}',
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Editar período',
                                    onPressed: () => _editPeriod(period),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
            const Divider(height: 40),
            Text(
              'Anular declaración',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Consulte y seleccione una declaración. La versión y revisión se completan automáticamente.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _annulling ? null : _chooseAnnulment,
                icon: const Icon(Icons.search),
                label: const Text('Consultar declaraciones'),
              ),
            ),
            if (_annulment != null)
              Text('${_annulment!.name} · ${_annulment!.periodId}'),
            TextField(
              controller: _annulmentId,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'ID de declaración'),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _annulmentVersion,
                    readOnly: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Versión esperada',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _annulmentRevision,
                    readOnly: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Revisión esperada',
                    ),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _annulmentReason,
              enabled: !_annulling,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo obligatorio',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _annulling || _annulment == null
                    ? null
                    : _annulDeclaration,
                icon: const Icon(Icons.block),
                label: const Text('Anular'),
              ),
            ),
            if (_annulmentMessage != null) Text(_annulmentMessage!),
            const Divider(height: 40),
            Text(
              'Asignación de roles',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Asigne un rol a un perfil existente. Los cambios se validan en el servidor y no se aplican al propio administrador.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('administrator-role-target-uid'),
              controller: _targetUid,
              enabled: !_savingRole,
              decoration: const InputDecoration(
                labelText: 'UID del usuario',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AppRole>(
              initialValue: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'Rol',
                border: OutlineInputBorder(),
              ),
              items: AppRole.values
                  .map(
                    (role) => DropdownMenuItem(
                      value: role,
                      child: Text(_roleName(role)),
                    ),
                  )
                  .toList(),
              onChanged: _savingRole
                  ? null
                  : (role) {
                      if (role != null) setState(() => _selectedRole = role);
                    },
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _savingRole ? null : _assignRole,
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('Asignar rol'),
              ),
            ),
            if (_savingRole) const LinearProgressIndicator(),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(liveRegion: true, child: Text(_message!)),
              ),
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Aprovisionamiento inicial'),
                subtitle: Text(
                  'La primera cuenta administradora debe ser habilitada por una persona con acceso confiable al proyecto Firebase. No existe una ruta de autoasignación desde el cliente.',
                ),
              ),
            ),
            const Divider(height: 40),
            const SupervisorAssignmentPanel(),
          ],
        ),
      ),
    ),
  );
}

/// Dialog to create or edit an [AcademicPeriod].
///
/// Pops with the resulting period, or with null if cancelled. When [existing]
/// is provided the identifier is locked, since it is the document key.
class _PeriodDialog extends StatefulWidget {
  const _PeriodDialog({this.existing});
  final AcademicPeriod? existing;

  @override
  State<_PeriodDialog> createState() => _PeriodDialogState();
}

class _PeriodDialogState extends State<_PeriodDialog> {
  late final TextEditingController _id = TextEditingController(
    text: widget.existing?.id ?? '',
  );
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late DateTime _startsAt = _dateOnly(
    widget.existing?.startsAt.toLocal() ?? DateTime.now(),
  );
  late DateTime _endsAt = _dateOnly(
    widget.existing?.endsAt.toLocal() ??
        DateTime.now().add(const Duration(days: 90)),
  );
  late bool _active = widget.existing?.isActive ?? true;
  String? _error;

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String _format(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool starts}) async {
    final current = starts ? _startsAt : _endsAt;
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() {
      if (starts) {
        _startsAt = selected;
      } else {
        _endsAt = selected;
      }
    });
  }

  /// Validates the form and pops the dialog with the resulting period.
  ///
  /// The period is stored with day granularity: it starts at 00:00 on the
  /// start date and ends at 23:59:59.999 on the end date, so the whole last
  /// day is still inside the validity window.
  void _submit() {
    final id = _id.text.trim();
    final name = _name.text.trim();
    if (id.isEmpty || name.isEmpty) {
      setState(() => _error = 'Complete el identificador y el nombre.');
      return;
    }
    if (_endsAt.isBefore(_startsAt)) {
      setState(
        () => _error = 'La fecha final debe ser posterior a la inicial.',
      );
      return;
    }
    final start = DateTime(_startsAt.year, _startsAt.month, _startsAt.day);
    final end = DateTime(
      _endsAt.year,
      _endsAt.month,
      _endsAt.day,
      23,
      59,
      59,
      999,
    );
    Navigator.of(context).pop(
      AcademicPeriod(
        id: id,
        name: name,
        startsAt: start,
        endsAt: end,
        isActive: _active,
      ),
    );
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Crear período' : 'Editar período'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _id,
            enabled: widget.existing == null,
            decoration: const InputDecoration(labelText: 'Identificador'),
          ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Inicio'),
            subtitle: Text(_format(_startsAt)),
            onTap: () => _pickDate(starts: true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fin'),
            subtitle: Text(_format(_endsAt)),
            onTap: () => _pickDate(starts: false),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            title: const Text('Período activo'),
            onChanged: (value) => setState(() => _active = value),
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Guardar')),
    ],
  );
}
