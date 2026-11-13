import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/declaration.dart';
import 'callable_function_client.dart';

class DeclarantSignatureResult {
  const DeclarantSignatureResult({
    required this.declarationId,
    required this.version,
    required this.revision,
    required this.signatureId,
    required this.eventId,
    required this.signedAt,
    required this.alreadySigned,
  });

  final String declarationId;
  final int version;
  final int revision;
  final String signatureId;
  final String eventId;
  final DateTime signedAt;
  final bool alreadySigned;
}

abstract interface class DeclarantSignatureRepository {
  Future<DeclarantSignatureResult> sign({
    required Declaration declaration,
    required bool explicitlyConfirmed,
  });
}

/// Delegates identity, authorization, validation, and writes to signDeclaration.
class DeclarantSignatureService implements DeclarantSignatureRepository {
  DeclarantSignatureService({CallableFunctionClient? functions})
    : _functions = functions ?? FirebaseCallableFunctionClient();

  final CallableFunctionClient _functions;

  @override
  Future<DeclarantSignatureResult> sign({
    required Declaration declaration,
    required bool explicitlyConfirmed,
  }) async {
    if (!explicitlyConfirmed) throw ArgumentError('Confirme la firma.');
    final raw = await _functions.call('signDeclaration', {
      'declarationId': declaration.id,
      'expectedVersion': declaration.version,
      'expectedRevision': declaration.revision,
      'confirmed': true,
    });
    if (raw is! Map) {
      throw FirebaseFunctionsException(
        code: 'internal',
        message:
            'La respuesta de firma del servidor tiene un formato inválido.',
      );
    }
    final response = Map<String, Object?>.from(raw);
    final signedAtValue = response['signedAt'];
    final signedAt = signedAtValue is String
        ? DateTime.tryParse(signedAtValue)
        : null;
    final signedRevision = declaration.revision + 1;
    final expectedSignatureId =
        'declarantSignature_v${declaration.version}_r$signedRevision';
    final expectedEventId =
        'declarantSigned_v${declaration.version}_r$signedRevision';
    if (response['declarationId'] != declaration.id ||
        response['version'] != declaration.version ||
        response['revision'] != signedRevision ||
        response['signatureId'] != expectedSignatureId ||
        response['eventId'] != expectedEventId ||
        response['alreadySigned'] is! bool ||
        signedAt == null) {
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'La respuesta de firma no coincide con la versión solicitada.',
      );
    }
    return DeclarantSignatureResult(
      declarationId: declaration.id,
      version: declaration.version,
      revision: signedRevision,
      signatureId: expectedSignatureId,
      eventId: expectedEventId,
      signedAt: signedAt,
      alreadySigned: response['alreadySigned'] as bool,
    );
  }
}
