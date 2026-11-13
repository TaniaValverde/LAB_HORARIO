import '../../domain/entities/declaration.dart';
import 'callable_function_client.dart';

class OathConfigurationException implements Exception {
  const OathConfigurationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ApprovedOath {
  const ApprovedOath({required this.version, required this.text});
  final int version;
  final String text;
}

abstract interface class DeclarantOathRepository {
  Future<ApprovedOath?> loadApprovedText();
  Future<OathAcceptanceResult> accept({
    required Declaration declaration,
    required bool explicitlyConfirmed,
    required int expectedOathTextVersion,
  });
}

class OathAcceptanceResult {
  const OathAcceptanceResult({
    required this.declarationId,
    required this.version,
    required this.revision,
    required this.eventId,
    required this.oathTextVersion,
    required this.alreadyAccepted,
  });

  final String declarationId;
  final int version;
  final int revision;
  final String eventId;
  final int oathTextVersion;
  final bool alreadyAccepted;
}

/// Reads the approved wording and accepts it through trusted callable functions.
class DeclarantOathService implements DeclarantOathRepository {
  DeclarantOathService({CallableFunctionClient? functions})
    : _functions = functions ?? FirebaseCallableFunctionClient();

  final CallableFunctionClient _functions;

  Map<String, Object?> _response(Object? value, String operation) {
    if (value is Map) return Map<String, Object?>.from(value);
    throw OathConfigurationException(
      'La respuesta del servidor para $operation tiene un formato inválido.',
    );
  }

  @override
  Future<ApprovedOath?> loadApprovedText() async {
    final response = _response(
      await _functions.call('getApprovedDeclarantOath', const {}),
      'el juramento aprobado',
    );
    final version = response['version'];
    final text = response['text'];
    if (version is! int ||
        version < 1 ||
        text is! String ||
        text.trim().isEmpty) {
      throw const OathConfigurationException(
        'El servidor devolvió una versión de juramento incompleta.',
      );
    }
    return ApprovedOath(version: version, text: text);
  }

  @override
  Future<OathAcceptanceResult> accept({
    required Declaration declaration,
    required bool explicitlyConfirmed,
    required int expectedOathTextVersion,
  }) async {
    if (!explicitlyConfirmed) {
      throw ArgumentError('Debe confirmar expresamente la aceptación.');
    }
    final response = _response(
      await _functions.call('acceptOath', {
        'declarationId': declaration.id,
        'expectedVersion': declaration.version,
        'expectedRevision': declaration.revision,
        'accepted': true,
        'expectedOathTextVersion': expectedOathTextVersion,
      }),
      'la aceptación del juramento',
    );
    final alreadyAccepted = response['alreadyAccepted'];
    if (alreadyAccepted is! bool) {
      throw const OathConfigurationException(
        'La respuesta del servidor omitió el resultado de idempotencia.',
      );
    }
    final result = OathAcceptanceResult(
      declarationId: response['declarationId'] as String? ?? '',
      version: response['version'] as int? ?? 0,
      revision: response['revision'] as int? ?? 0,
      eventId: response['eventId'] as String? ?? '',
      oathTextVersion: response['oathTextVersion'] as int? ?? 0,
      alreadyAccepted: alreadyAccepted,
    );
    final expectedRevision = declaration.revision + 1;
    final expectedEventId =
        'oathAccepted_v${declaration.version}_r$expectedRevision';
    if (result.declarationId != declaration.id ||
        result.version != declaration.version ||
        result.revision != expectedRevision ||
        result.eventId != expectedEventId ||
        result.oathTextVersion != expectedOathTextVersion) {
      throw const OathConfigurationException(
        'La respuesta del servidor no corresponde a la declaración y versión confirmadas.',
      );
    }
    return result;
  }
}
