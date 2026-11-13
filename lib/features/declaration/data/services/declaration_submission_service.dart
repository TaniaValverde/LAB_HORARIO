import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/declaration.dart';
import 'callable_function_client.dart';

class DeclarationSubmissionResult {
  const DeclarationSubmissionResult({
    required this.declarationId,
    required this.version,
    required this.revision,
    required this.eventId,
    required this.alreadySubmitted,
  });

  final String declarationId;
  final int version;
  final int revision;
  final String eventId;
  final bool alreadySubmitted;
}

/// Sends a signed declaration to the currently assigned supervisor through the server.
class DeclarationSubmissionService {
  DeclarationSubmissionService({CallableFunctionClient? client})
    : _client = client ?? FirebaseCallableFunctionClient();

  final CallableFunctionClient _client;

  Future<DeclarationSubmissionResult> submit({
    required Declaration declaration,
    required bool explicitlyConfirmed,
  }) async {
    if (!explicitlyConfirmed) throw ArgumentError('Confirme el envío al superior.');
    final raw = await _client.call('submitDeclarationToSupervisor', {
      'declarationId': declaration.id,
      'expectedVersion': declaration.version,
      'expectedRevision': declaration.revision,
      'confirmed': true,
    });
    if (raw is! Map) {
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'La respuesta de envío del servidor tiene un formato inválido.',
      );
    }
    final response = Map<String, Object?>.from(raw);
    final nextRevision = declaration.revision + 1;
    final expectedEventId =
        'submitToSuperior_v${declaration.version}_r$nextRevision';
    if (response['declarationId'] != declaration.id ||
        response['version'] != declaration.version ||
        response['revision'] != nextRevision ||
        response['eventId'] != expectedEventId ||
        response['alreadySubmitted'] is! bool) {
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'La respuesta del servidor no corresponde a la declaración enviada.',
      );
    }
    return DeclarationSubmissionResult(
      declarationId: declaration.id,
      version: declaration.version,
      revision: nextRevision,
      eventId: expectedEventId,
      alreadySubmitted: response['alreadySubmitted'] as bool,
    );
  }
}
