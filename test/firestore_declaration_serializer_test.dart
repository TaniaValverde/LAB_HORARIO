import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/features/declaration/data/repositories/firestore_declaration_repository.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration.dart';

void main() {
  const serializer = DeclarationFirestoreSerializer();

  void expectSameInstant(DateTime? actual, DateTime? expected) {
    expect(actual?.toUtc(), expected?.toUtc());
  }

  test('serializa y recupera todos los campos del trámite', () {
    final declaration = Declaration(
      id: 'person_period',
      personId: 'person',
      periodId: 'period',
      createdAt: DateTime.utc(2026, 10, 8, 9),
      status: DeclarationStatus.finalized,
      version: 3,
      revision: 7,
      parentVersionId: 'person_period_v2',
      oathAcceptedAt: DateTime.utc(2026, 10, 8, 9, 1),
      declarantSignedAt: DateTime.utc(2026, 10, 8, 9, 2),
      declarantSignature: 'Firma declarante',
      superiorSignedAt: DateTime.utc(2026, 10, 8, 9, 3),
      superiorSignature: 'Firma superior',
      returnObservation: 'Observación registrada',
      hrReceivedAt: DateTime.utc(2026, 10, 8, 9, 4),
      finalizedAt: DateTime.utc(2026, 10, 8, 9, 5),
      finalPdfPath: 'declarations/person_period/final.pdf',
      payload: const {'schemaVersion': 1, 'observations': 'Payload intacto'},
    );

    final encoded = serializer.encode(declaration);
    final decoded = serializer.decode(declaration.id, encoded);

    expect(encoded['oathAcceptedAt'], isA<Timestamp>());
    expect(encoded['declarantSignedAt'], isA<Timestamp>());
    expect(encoded['declarantSignature'], declaration.declarantSignature);
    expect(encoded['superiorSignedAt'], isA<Timestamp>());
    expect(encoded['superiorSignature'], declaration.superiorSignature);
    expect(encoded['returnObservation'], declaration.returnObservation);
    expect(encoded['hrReceivedAt'], isA<Timestamp>());
    expect(encoded['finalizedAt'], isA<Timestamp>());
    expect(encoded['finalPdfPath'], declaration.finalPdfPath);
    expect(encoded['updatedAt'], isA<FieldValue>());
    expect(encoded['personId'], declaration.personId);
    expect(encoded['periodId'], declaration.periodId);
    expect(encoded['createdAt'], Timestamp.fromDate(declaration.createdAt));
    expect(encoded['status'], declaration.status.name);
    expect(encoded['version'], declaration.version);
    expect(encoded['revision'], declaration.revision);
    expect(encoded['parentVersionId'], declaration.parentVersionId);
    expect(encoded['payload'], declaration.payload);
    expect(decoded.status, declaration.status);
    expect(decoded.version, declaration.version);
    expect(decoded.revision, declaration.revision);
    expect(decoded.parentVersionId, declaration.parentVersionId);
    expectSameInstant(decoded.createdAt, declaration.createdAt);
    expectSameInstant(decoded.oathAcceptedAt, declaration.oathAcceptedAt);
    expectSameInstant(decoded.declarantSignedAt, declaration.declarantSignedAt);
    expect(decoded.declarantSignature, declaration.declarantSignature);
    expectSameInstant(decoded.superiorSignedAt, declaration.superiorSignedAt);
    expect(decoded.superiorSignature, declaration.superiorSignature);
    expect(decoded.returnObservation, declaration.returnObservation);
    expectSameInstant(decoded.hrReceivedAt, declaration.hrReceivedAt);
    expectSameInstant(decoded.finalizedAt, declaration.finalizedAt);
    expect(decoded.finalPdfPath, declaration.finalPdfPath);
    expect(decoded.payload, declaration.payload);
  });

  test('lee documentos anteriores sin campos opcionales del trámite', () {
    final decoded = serializer.decode('legacy_id', {
      'personId': 'person',
      'periodId': 'period',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 10, 8)),
      'status': DeclarationStatus.draft.name,
      'version': 1,
      'parentVersionId': null,
      'revision': 0,
      'payload': const {'schemaVersion': 1},
    });

    expect(decoded.id, 'legacy_id');
    expect(decoded.oathAcceptedAt, isNull);
    expect(decoded.declarantSignedAt, isNull);
    expect(decoded.declarantSignature, isNull);
    expect(decoded.superiorSignedAt, isNull);
    expect(decoded.superiorSignature, isNull);
    expect(decoded.returnObservation, isNull);
    expect(decoded.hrReceivedAt, isNull);
    expect(decoded.finalizedAt, isNull);
    expect(decoded.finalPdfPath, isNull);
  });
}
