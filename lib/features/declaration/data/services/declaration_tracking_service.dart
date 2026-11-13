import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/audit_event.dart';
import '../../domain/repositories/audit_repository.dart';
import '../../domain/entities/declaration.dart';
import 'callable_function_client.dart';

class DeclarationTrackingService {
  DeclarationTrackingService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<Map<String, Object?>> status(String declarationId) async {
    final response = await _functions
        .httpsCallable('getDeclarationStatus')
        .call({'declarationId': declarationId});
    final value = response.data;
    if (value is! Map) {
      throw const FormatException('El estado recibido tiene formato inválido.');
    }
    return Map<String, Object?>.from(value);
  }
}

/// Callable-backed timeline. Reads are authorized by the server for owners,
/// current assigned supervisors, HR and administrators. Writes stay in the
/// audited declaration repository/callables.
class CallableAuditRepository implements AuditRepository {
  CallableAuditRepository({
    FirebaseFunctions? functions,
    CallableFunctionClient? client,
  }) : _client = client ?? FirebaseCallableFunctionClient(functions: functions);

  final CallableFunctionClient _client;

  @override
  Future<void> append(AuditEvent event) => throw UnsupportedError(
    'El historial canónico solo se agrega mediante operaciones auditadas del servidor.',
  );

  @override
  Future<List<AuditEvent>> getForDeclaration(String declarationId) async {
    final value = await _client.call('getDeclarationTimeline', {
      'declarationId': declarationId,
    });
    if (value is! Map || value['events'] is! List) {
      throw const FormatException(
        'El historial recibido tiene formato inválido.',
      );
    }
    return (value['events'] as List)
        .map((raw) {
          if (raw is! Map) {
            throw const FormatException(
              'El evento recibido tiene formato inválido.',
            );
          }
          final event = Map<String, dynamic>.from(raw);
          final occurredAt = event['occurredAt'];
          if (occurredAt is! String) {
            throw const FormatException('El evento no tiene fecha válida.');
          }
          return AuditEvent(
            id: event['id'] as String,
            declarationId: event['declarationId'] as String,
            actorId: event['actorId'] as String,
            action: event['action'] as String,
            occurredAt: DateTime.parse(occurredAt),
            details: event['details'] as String?,
            version: event['version'] as int?,
            estadoAnterior: event['estadoAnterior'] as String?,
            estadoNuevo: event['estadoNuevo'] as String?,
          );
        })
        .toList(growable: false);
  }
}

class DeclarationVersionService {
  DeclarationVersionService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<String> create(Declaration declaration) async {
    final response = await _functions
        .httpsCallable('createDeclarationVersion')
        .call({
          'declarationId': declaration.id,
          'expectedVersion': declaration.version,
          'expectedRevision': declaration.revision,
        });
    final result = response.data;
    if (result is! Map || result['declarationId'] is! String) {
      throw const FormatException(
        'El servidor no devolvió el identificador de la nueva versión.',
      );
    }
    return result['declarationId'] as String;
  }
}
