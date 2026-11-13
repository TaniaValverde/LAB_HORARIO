import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/errors/user_error.dart';
import '../../../core/state/app_state.dart';
import '../data/services/supervisor_inbox_service.dart';
import '../domain/entities/declaration.dart';
import 'supervisor_review_screen.dart';
import '../../realtime/declaration_notices.dart';

typedef SupervisorDeclarationBuilder = Widget Function(
  BuildContext context,
  Declaration declaration,
);

class SupervisorInboxScreen extends StatefulWidget {
  const SupervisorInboxScreen({
    super.key,
    required this.name,
    this.inbox,
    this.detailBuilder,
  });

  final String name;
  final SupervisorInboxRepository? inbox;
  final SupervisorDeclarationBuilder? detailBuilder;

  @override
  State<SupervisorInboxScreen> createState() => _SupervisorInboxScreenState();
}

class _SupervisorInboxScreenState extends State<SupervisorInboxScreen> {
  late final SupervisorInboxRepository _inbox =
      widget.inbox ?? SupervisorInboxService();
  late Future<List<Declaration>> _items = _inbox.getInbox();
  late final SupervisorOutboxRepository? _outbox =
      widget.inbox is SupervisorOutboxRepository
      ? widget.inbox! as SupervisorOutboxRepository
      : widget.inbox == null
      ? _inbox as SupervisorOutboxRepository
      : null;
  late Future<List<Declaration>>? _outboxItems = _outbox?.getOutbox();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Callable queries are refreshed periodically; Firestore Rules continue to
    // deny direct reads by supervisors, including during assignment changes.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _items = _inbox.getInbox();
      _outboxItems = _outbox?.getOutbox();
    });
  }

  String _declarantName(Declaration declaration) {
    final profile = declaration.payload['profile'];
    if (profile is Map &&
        profile['name'] is String &&
        (profile['name'] as String).isNotEmpty) {
      return profile['name'] as String;
    }
    return declaration.personId;
  }

  Future<void> _open(Declaration summary) async {
    try {
      final declaration = await _inbox.getDeclaration(summary.id);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) =>
              (widget.detailBuilder ?? _buildDetail)(context, declaration),
        ),
      );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userError(error))));
      }
    }
  }

  Widget _buildDetail(BuildContext context, Declaration declaration) =>
      SupervisorReviewScreen(declaration: declaration);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Bandeja del superior'),
      actions: [
        const ThemeToggleAction(),
        IconButton(
          tooltip: 'Actualizar bandeja',
          onPressed: () => _reload(),
          icon: const Icon(Icons.refresh),
        ),
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
              'Superior: ${widget.name}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (DeclarationNotices.url.isNotEmpty && FirebaseAuth.instance.currentUser != null)
              DeclarationNotices(user: FirebaseAuth.instance.currentUser!, onChanged: _reload),
            const SizedBox(height: 16),
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
                        onPressed: () => _reload(),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  );
                }
                final declarations = snapshot.data ?? const <Declaration>[];
                if (declarations.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No hay declaraciones pendientes de revisión.',
                      ),
                    ),
                  );
                }
                return Column(
                  children: declarations.map((declaration) {
                    final form = declaration.payload['profile'];
                    final profile = form is Map
                        ? form
                        : const <String, Object?>{};
                    final name = profile['name'] is String
                        ? profile['name'] as String
                        : 'Persona declarante';
                    return Card(
                      child: ListTile(
                        title: Text(name),
                        subtitle: Text(
                          'Período ${declaration.periodId} · Versión ${declaration.version} · Revisión ${declaration.revision}\nPendiente de revisión del superior',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(declaration),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            if (_outboxItems != null) ...[
              const Divider(height: 40),
              Text(
                'Firmadas · pendientes de envío a RR. HH.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              FutureBuilder<List<Declaration>>(
                future: _outboxItems,
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
                  final rows = snapshot.data ?? const <Declaration>[];
                  if (rows.isEmpty) {
                    return const Text(
                      'No hay declaraciones firmadas pendientes de envío.',
                    );
                  }
                  return Column(
                    children: rows
                        .map(
                          (declaration) => Card(
                            child: ListTile(
                              title: Text(
                                'Declaración de ${_declarantName(declaration)}',
                              ),
                              subtitle: Text(
                                'Período ${declaration.periodId} · versión ${declaration.version} · revisión ${declaration.revision}',
                              ),
                              trailing: const Icon(Icons.send_outlined),
                              onTap: () => _open(declaration),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
