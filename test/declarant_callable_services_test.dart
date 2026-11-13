import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/features/declaration/data/services/callable_function_client.dart';
import 'package:declara_horario/features/declaration/data/services/declarant_oath_service.dart';
import 'package:declara_horario/features/declaration/data/services/declarant_signature_service.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration.dart';

class _FakeCallableClient implements CallableFunctionClient {
  String? name;
  Map<String, Object?>? data;
  Object? response;

  @override
  Future<Object?> call(String name, Map<String, Object?> data) async {
    this.name = name;
    this.data = data;
    return response;
  }
}

void main() {
  final declaration = Declaration(
    id: 'decl-1',
    personId: 'uid-1',
    periodId: '2026-II',
    createdAt: DateTime.utc(2026),
    version: 1,
    revision: 4,
    status: DeclarationStatus.validated,
  );

  test(
    'el servicio de juramento consulta el texto aprobado por callable',
    () async {
      final client = _FakeCallableClient()
        ..response = {'version': 3, 'text': 'Texto aprobado'};
      final oath = DeclarantOathService(functions: client);

      final approved = await oath.loadApprovedText();

      expect(client.name, 'getApprovedDeclarantOath');
      expect(client.data, isEmpty);
      expect(approved?.version, 3);
      expect(approved?.text, 'Texto aprobado');
    },
  );

  test(
    'aceptar juramento invoca acceptOath con versión y revisión esperadas',
    () async {
      final client = _FakeCallableClient()
        ..response = {
          'declarationId': 'decl-1',
          'version': 1,
          'revision': 5,
          'eventId': 'oathAccepted_v1_r5',
          'oathTextVersion': 3,
          'alreadyAccepted': false,
        };
      final oath = DeclarantOathService(functions: client);

      final result = await oath.accept(
        declaration: declaration,
        explicitlyConfirmed: true,
        expectedOathTextVersion: 3,
      );

      expect(client.name, 'acceptOath');
      expect(client.data, {
        'declarationId': 'decl-1',
        'expectedVersion': 1,
        'expectedRevision': 4,
        'accepted': true,
        'expectedOathTextVersion': 3,
      });
      expect(result.alreadyAccepted, isFalse);
      expect(result.eventId, 'oathAccepted_v1_r5');
    },
  );

  test(
    'aceptar juramento rechaza respuesta callable sin alreadyAccepted',
    () async {
      final client = _FakeCallableClient()
        ..response = {
          'declarationId': 'decl-1',
          'version': 1,
          'revision': 5,
          'eventId': 'oathAccepted_v1_r5',
          'oathTextVersion': 3,
        };
      final oath = DeclarantOathService(functions: client);

      await expectLater(
        oath.accept(
          declaration: declaration,
          explicitlyConfirmed: true,
          expectedOathTextVersion: 3,
        ),
        throwsA(isA<OathConfigurationException>()),
      );
      expect(client.name, 'acceptOath');
    },
  );

  test(
    'aceptar juramento conserva el resultado de un reintento idempotente',
    () async {
      final client = _FakeCallableClient()
        ..response = {
          'declarationId': 'decl-1',
          'version': 1,
          'revision': 5,
          'eventId': 'oathAccepted_v1_r5',
          'oathTextVersion': 3,
          'alreadyAccepted': true,
        };
      final oath = DeclarantOathService(functions: client);

      final result = await oath.accept(
        declaration: declaration,
        explicitlyConfirmed: true,
        expectedOathTextVersion: 3,
      );

      expect(result.alreadyAccepted, isTrue);
    },
  );

  test(
    'firma invoca signDeclaration y conserva la identidad de la versión',
    () async {
      final client = _FakeCallableClient()
        ..response = {
          'declarationId': 'decl-1',
          'version': 1,
          'revision': 5,
          'signatureId': 'declarantSignature_v1_r5',
          'eventId': 'declarantSigned_v1_r5',
          'alreadySigned': true,
          'signedAt': '2026-10-19T12:00:00.000Z',
        };
      final signature = DeclarantSignatureService(functions: client);

      final result = await signature.sign(
        declaration: declaration,
        explicitlyConfirmed: true,
      );

      expect(client.name, 'signDeclaration');
      expect(client.data, {
        'declarationId': 'decl-1',
        'expectedVersion': 1,
        'expectedRevision': 4,
        'confirmed': true,
      });
      expect(result.signatureId, 'declarantSignature_v1_r5');
      expect(result.alreadySigned, isTrue);
      expect(result.signedAt.toUtc(), DateTime.utc(2026, 10, 19, 12));
    },
  );

  test(
    'los servicios no llaman al servidor sin confirmación explícita',
    () async {
      final client = _FakeCallableClient();
      final oath = DeclarantOathService(functions: client);
      final signature = DeclarantSignatureService(functions: client);

      await expectLater(
        oath.accept(
          declaration: declaration,
          explicitlyConfirmed: false,
          expectedOathTextVersion: 3,
        ),
        throwsArgumentError,
      );
      await expectLater(
        signature.sign(declaration: declaration, explicitlyConfirmed: false),
        throwsArgumentError,
      );
      expect(client.name, isNull);
    },
  );
}
