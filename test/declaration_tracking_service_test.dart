import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/features/declaration/data/services/callable_function_client.dart';
import 'package:declara_horario/features/declaration/data/services/declaration_tracking_service.dart';

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
  test('el historial callable conserva eventos cronológicos de versiones relacionadas', () async {
    final client = _FakeCallableClient()
      ..response = {
        'events': [
          {
            'id': 'created_v1',
            'declarationId': 'decl-v1',
            'actorId': 'owner',
            'action': 'created',
            'occurredAt': '2026-10-01T10:00:00.000Z',
            'details': null,
            'version': 1,
            'estadoAnterior': null,
            'estadoNuevo': 'draft',
          },
          {
            'id': 'versionCreated_v2',
            'declarationId': 'decl-v2',
            'actorId': 'owner',
            'action': 'versionCreated',
            'occurredAt': '2026-10-02T10:00:00.000Z',
            'details': 'parentDeclarationId=decl-v1;version=2',
          },
        ],
      };
    final audit = CallableAuditRepository(client: client);

    final events = await audit.getForDeclaration('decl-v2');

    expect(client.name, 'getDeclarationTimeline');
    expect(client.data, {'declarationId': 'decl-v2'});
    expect(events.map((event) => event.id), ['created_v1', 'versionCreated_v2']);
    expect(events.map((event) => event.declarationId), ['decl-v1', 'decl-v2']);
    expect(events.first.version, 1);
    expect(events.first.estadoAnterior, isNull);
    expect(events.first.estadoNuevo, 'draft');
    expect(events.last.version, isNull);
    expect(events.map((event) => event.occurredAt.toUtc().toIso8601String()), [
      '2026-10-01T10:00:00.000Z',
      '2026-10-02T10:00:00.000Z',
    ]);
  });
}
