import 'declaration_list.dart';
import '../../realtime/declaration_notices.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/errors/user_error.dart';
import '../../../core/state/app_state.dart';
import '../../admin/presentation/administrator_dashboard.dart';
import '../../admin/presentation/human_resources_dashboard.dart';
import '../../period/data/repositories/firestore_period_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../../roles/domain/entities/app_role.dart';
import '../data/repositories/firestore_declaration_repository.dart';
import '../data/services/declaration_tracking_service.dart';
import '../domain/entities/declaration.dart';
import '../domain/entities/declaration_form.dart';
import '../domain/usecases/create_declaration.dart';
import 'declaration_editor.dart';
import 'supervisor_inbox_screen.dart';
import 'approved_schedule_screen.dart';

class DeclarantDashboard extends StatefulWidget {
  const DeclarantDashboard({
    super.key,
    required this.user,
    required this.profile,
  });
  final User user;
  final UserProfile profile;
  @override
  State<DeclarantDashboard> createState() => _DeclarantDashboardState();
}

class _DeclarantDashboardState extends State<DeclarantDashboard> {
  final _repository = FirestoreDeclarationRepository();
  final _audit = CallableAuditRepository();
  bool _busy = false;
  String? _message;
  late final Future<String> _socketUrl = _mobileSocketUrl();
  bool get _mobileLabMode =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<String> _mobileSocketUrl() async {
    const configured = DeclarationNotices.url;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return configured;
    }
    final uri = Uri.tryParse(configured);
    if (uri == null ||
        (uri.host != 'localhost' && uri.host != '127.0.0.1')) {
      return configured;
    }
    try {
      const channel = MethodChannel('declara_horario/platform');
      final isEmulator =
          await channel.invokeMethod<bool>('isAndroidEmulator') ?? false;
      if (!isEmulator) return configured;
    } on MissingPluginException {
      return configured;
    }
    return uri.replace(host: '10.0.2.2').toString();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final profile = await ProfileRepository().load(widget.user);
      final declaration =
          await CreateDeclaration(
            periods: FirestorePeriodRepository(),
            declarations: _repository,
            audit: _audit,
          )(
            personId: widget.user.uid,
            payload: DeclarationForm(profile: profile.details).toMap(),
          );
      if (mounted) await _open(declaration);
    } on DeclarationCreationException catch (e) {
      if (mounted) {
        setState(
          () => _message = switch (e.reason) {
            DeclarationCreationFailure.noActivePeriod => 'No hay un período activo. Solicite su habilitación a administración.',
            DeclarationCreationFailure.outsidePeriodDates =>
              'No hay un período activo dentro de sus fechas de vigencia.',
            DeclarationCreationFailure.alreadyExists => 'Ya tiene una declaración para este período. Ábrala desde la lista.',
          },
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = userError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Declaration declaration) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DeclarationEditor(
        declaration: declaration,
        repository: _repository,
        audit: _audit,
        mobileLab: _mobileLabMode,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final role = widget.profile.role;
    if (!widget.profile.active) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('DeclaraHorario'),
          actions: [
            const ThemeToggleAction(),
            TextButton.icon(
              onPressed: () => FirebaseAuth.instance.signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Salir'),
            ),
          ],
        ),
        body: const Center(
          child: Text('El perfil está inactivo. Contacte a administración.'),
        ),
      );
    }
    if (role == AppRole.supervisor) {
      return SupervisorInboxScreen(
        name: widget.profile.details.name.isEmpty
            ? widget.user.email ?? ''
            : widget.profile.details.name,
      );
    }
    if (role == AppRole.administrator) {
      return AdministratorDashboard(
        operatorUid: widget.user.uid,
        name: widget.profile.details.name.isEmpty
            ? widget.user.email ?? ''
            : widget.profile.details.name,
      );
    }
    if (role == AppRole.humanResources) {
      return HumanResourcesDashboard(
        name: widget.profile.details.name.isEmpty
            ? widget.user.email ?? ''
            : widget.profile.details.name,
      );
    }
    final roleName = switch (role) {
      AppRole.declarant => 'Declarante',
      AppRole.supervisor => 'Superior jerárquico',
      AppRole.humanResources => 'Recursos Humanos',
      AppRole.administrator => 'Administración',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('DeclaraHorario'),
        actions: [
          const ThemeToggleAction(),
          TextButton.icon(
            onPressed: _busy ? null : () => FirebaseAuth.instance.signOut(),
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
                'Panel de $roleName',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(
                widget.profile.details.name.isEmpty
                    ? widget.user.email ?? ''
                    : widget.profile.details.name,
              ),
              const SizedBox(height: 20),
              if (role != AppRole.declarant)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Su sesión y rol están activos. Las acciones de revisión, firmas y administración corresponden al módulo de Persona 2, pendiente de conectar a la persistencia real.',
                    ),
                  ),
                ),
              if (role == AppRole.declarant) ...[
                FutureBuilder<String>(
                  future: _socketUrl,
                  builder: (context, snapshot) => DeclarationNotices(
                    user: widget.user,
                    urlOverride: snapshot.data ?? '',
                  ),
                ),
                const Text(
                  'Registre sus nombramientos y horarios. Guarde el borrador y corrija las observaciones antes de validar.',
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: const Icon(Icons.add),
                    label: const Text('Nueva declaración en período activo'),
                  ),
                ),
                if (_busy) const LinearProgressIndicator(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ApprovedScheduleScreen(
                                personId: widget.user.uid,
                                watch: () =>
                                    _repository.watchForPerson(widget.user.uid),
                                loadFresh: () => _repository
                                    .getForPersonFromServer(widget.user.uid),
                                identities: FirebaseAuth.instance
                                    .authStateChanges()
                                    .map((user) => user?.uid),
                                isCurrentUser: () =>
                                    FirebaseAuth.instance.currentUser?.uid ==
                                    widget.user.uid,
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('Mi horario aprobado'),
                  ),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_message!),
                  ),
                const SizedBox(height: 20),
                DeclarationList(
                  key: ValueKey('declarations-${widget.user.uid}'),
                  watch: () => _repository.watchForPerson(widget.user.uid),
                  busy: _busy,
                  onOpen: _open,
                  mobileLab: _mobileLabMode,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
