import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/features/declaration/data/repositories/firestore_audit_repository.dart';
import 'package:declara_horario/features/declaration/data/repositories/in_memory_audit_repository.dart';
import 'package:declara_horario/features/declaration/data/repositories/in_memory_declaration_repository.dart';
import 'package:declara_horario/features/declaration/domain/entities/audit_event.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration.dart';
import 'package:declara_horario/features/declaration/domain/usecases/get_declaration_timeline.dart';

void main() {
  const serializer = AuditEventFirestoreSerializer();

  void expectSameInstant(DateTime actual, DateTime expected) {
    expect(actual.toUtc(), expected.toUtc());
  }

  test('serializa y deserializa todos los campos del AuditEvent', () {
    final event = AuditEvent(
      id: 'event-1',
      declarationId: 'declaration-1',
      actorId: 'actor-1',
      action: 'returnForCorrection',
      occurredAt: DateTime.utc(2026, 10, 8, 10, 30),
      details: 'Falta corregir el horario.',
      version: 2,
      estadoAnterior: 'pendingSuperiorSignature',
      estadoNuevo: 'returned',
    );

    final encoded = serializer.encode(event);
    final firestoreReadData = <String, dynamic>{
      ...encoded,
      'occurredAt': Timestamp.fromDate(event.occurredAt),
    };
    final decoded = serializer.decode(event.id, firestoreReadData);

    expect(encoded['id'], event.id);
    expect(encoded['declarationId'], event.declarationId);
    expect(encoded['actorId'], event.actorId);
    expect(encoded['action'], event.action);
    expect(encoded['occurredAt'], isA<FieldValue>());
    expect(encoded['details'], event.details);
    expect(encoded['version'], event.version);
    expect(encoded['estadoAnterior'], event.estadoAnterior);
    expect(encoded['estadoNuevo'], event.estadoNuevo);
    expect(decoded.id, event.id);
    expect(decoded.declarationId, event.declarationId);
    expect(decoded.actorId, event.actorId);
    expect(decoded.action, event.action);
    expectSameInstant(decoded.occurredAt, event.occurredAt);
    expect(decoded.details, event.details);
    expect(decoded.version, event.version);
    expect(decoded.estadoAnterior, event.estadoAnterior);
    expect(decoded.estadoNuevo, event.estadoNuevo);
  });

  test('lee detalles nulos y eventos históricos sin campo id', () {
    final decoded = serializer.decode('legacy-event', {
      'declarationId': 'declaration-1',
      'actorId': 'actor-1',
      'action': 'created',
      'occurredAt': Timestamp.fromDate(DateTime.utc(2026, 10, 8)),
      'details': null,
    });

    expect(decoded.id, 'legacy-event');
    expect(decoded.declarationId, 'declaration-1');
    expect(decoded.actorId, 'actor-1');
    expect(decoded.action, 'created');
    expectSameInstant(decoded.occurredAt, DateTime.utc(2026, 10, 8));
    expect(decoded.details, isNull);
  });

  test('ordena cronológicamente sin descartar eventos existentes', () {
    final later = AuditEvent(
      id: 'event-z',
      declarationId: 'declaration-1',
      actorId: 'actor-1',
      action: 'validated',
      occurredAt: DateTime.utc(2026, 10, 8, 11),
    );
    final earlier = AuditEvent(
      id: 'event-b',
      declarationId: 'declaration-1',
      actorId: 'actor-1',
      action: 'created',
      occurredAt: DateTime.utc(2026, 10, 8, 9),
    );
    final sameTimeFirst = AuditEvent(
      id: 'event-a',
      declarationId: 'declaration-1',
      actorId: 'actor-1',
      action: 'formUpdated',
      occurredAt: DateTime.utc(2026, 10, 8, 11),
      details: 'Datos conservados.',
    );

    final sorted = serializer.sort([later, earlier, sameTimeFirst]);

    expect(sorted.map((event) => event.id), ['event-b', 'event-a', 'event-z']);
    expect(sorted, hasLength(3));
    expect(sorted[1].details, 'Datos conservados.');
  });

  test('timeline consulta el historial a través de AuditRepository', () async {
    final declarationRepository = InMemoryDeclarationRepository();
    final declaration = Declaration(
      id: 'declaration-1',
      personId: 'actor-1',
      periodId: 'period-1',
      createdAt: DateTime.utc(2026, 10, 8),
    );
    await declarationRepository.save(declaration);
    final auditRepository = InMemoryAuditRepository();
    final event = AuditEvent(
      id: 'event-1',
      declarationId: declaration.id,
      actorId: declaration.personId,
      action: 'created',
      occurredAt: declaration.createdAt,
    );
    await auditRepository.append(event);

    final timeline = GetDeclarationTimeline(
      declarations: declarationRepository,
      audit: auditRepository,
    );

    expect(await timeline(declaration.id), [event]);
  });
}
