import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/features/declaration/data/services/supervisor_inbox_service.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration.dart';
import 'package:declara_horario/features/declaration/domain/entities/audit_event.dart';
import 'package:declara_horario/features/declaration/domain/repositories/audit_repository.dart';
import 'package:declara_horario/features/declaration/domain/repositories/declaration_repository.dart';
import 'package:declara_horario/features/declaration/presentation/supervisor_inbox_screen.dart';
import 'package:declara_horario/features/declaration/presentation/declaration_editor.dart';

class _Inbox implements SupervisorInboxRepository {
  _Inbox(this.items);

  final List<Declaration> items;
  int detailReads = 0;

  @override
  Future<List<Declaration>> getInbox() async => items;

  @override
  Future<Declaration> getDeclaration(String declarationId) async {
    detailReads++;
    return items.singleWhere((item) => item.id == declarationId);
  }
}

Declaration _declaration({String id = 'decl1'}) => Declaration(
  id: id,
  personId: 'person1',
  periodId: '2026-II',
  createdAt: DateTime.utc(2026, 10, 1),
  status: DeclarationStatus.pendingSuperiorSignature,
  version: 1,
  revision: 2,
  declarantSignedAt: DateTime.utc(2026, 10, 2),
  declarantSignature: 'signature-id',
  payload: const {
    'schemaVersion': 1,
    'profile': {'name': 'Declarante de prueba'},
    'appointments': <Object?>[],
    'externalJobs': <Object?>[],
    'observations': '',
  },
);

void main() {
  testWidgets('muestra declaraciones pendientes y abre detalle de consulta', (
    tester,
  ) async {
    final inbox = _Inbox([_declaration()]);
    await tester.pumpWidget(
      MaterialApp(
        home: SupervisorInboxScreen(
          name: 'Superior de prueba',
          inbox: inbox,
          detailBuilder: (context, declaration) => DeclarationEditor(
            declaration: declaration,
            repository: _Declarations(),
            audit: _Audit(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bandeja del superior'), findsOneWidget);
    expect(find.text('Declarante de prueba'), findsOneWidget);
    expect(
      find.textContaining('Período 2026-II · Versión 1 · Revisión 2'),
      findsOneWidget,
    );
    await tester.tap(find.text('Declarante de prueba'));
    await tester.pumpAndSettle();
    expect(inbox.detailReads, 1);
    expect(
      find.text(
        'Esta versión es de consulta. Para corregir una versión firmada se requiere una nueva versión.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('muestra una bandeja vacía', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SupervisorInboxScreen(name: 'Superior', inbox: _Inbox([])),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No hay declaraciones pendientes de revisión.'),
      findsOneWidget,
    );
  });

  testWidgets('muestra error de carga y permite reintentar', (tester) async {
    final inbox = _FailingInbox();
    await tester.pumpWidget(
      MaterialApp(
        home: SupervisorInboxScreen(name: 'Superior', inbox: inbox),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No se pudo cargar la bandeja.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });
}

class _FailingInbox implements SupervisorInboxRepository {
  @override
  Future<List<Declaration>> getInbox() async =>
      throw StateError('No se pudo cargar la bandeja.');

  @override
  Future<Declaration> getDeclaration(String declarationId) async =>
      throw StateError('No se pudo cargar la declaración.');
}

class _Declarations implements DeclarationRepository {
  @override
  Future<List<Declaration>> getForPerson(String personId) async => [];
  @override
  Future<List<Declaration>> getAll() async => [];
  @override
  Future<Declaration?> getById(String id) async => null;
  @override
  Future<void> save(Declaration declaration) async {}
  @override
  Future<void> update(Declaration declaration) async {}
}

class _Audit implements AuditRepository {
  @override
  Future<List<AuditEvent>> getForDeclaration(String declarationId) async => [];
  @override
  Future<void> append(AuditEvent event) async {}
}
