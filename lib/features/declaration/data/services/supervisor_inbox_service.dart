import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/declaration.dart';

abstract interface class SupervisorInboxRepository {
  Future<List<Declaration>> getInbox();

  Future<Declaration> getDeclaration(String declarationId);
}

abstract interface class SupervisorOutboxRepository {
  Future<List<Declaration>> getOutbox();
}

/// Server-authorized, read-only access to the current supervisor inbox.
class SupervisorInboxService
    implements SupervisorInboxRepository, SupervisorOutboxRepository {
  SupervisorInboxService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<List<Declaration>> getInbox() async {
    final response = await _functions
        .httpsCallable('getSupervisorInbox')
        .call();
    final result = _map(response.data);
    final rows = result['declarations'];
    if (rows is! List) {
      throw const FormatException(
        'La bandeja recibida tiene un formato inválido.',
      );
    }
    return rows.map((row) => _declaration(_map(row))).toList(growable: false);
  }

  @override
  Future<List<Declaration>> getOutbox() async {
    final response = await _functions
        .httpsCallable('getSupervisorOutbox')
        .call();
    final result = _map(response.data);
    final rows = result['declarations'];
    if (rows is! List) {
      throw const FormatException(
        'La bandeja de envío tiene formato inválido.',
      );
    }
    return rows.map((row) => _declaration(_map(row))).toList(growable: false);
  }

  @override
  Future<Declaration> getDeclaration(String declarationId) async {
    final response = await _functions
        .httpsCallable('getSupervisorDeclaration')
        .call(<String, Object?>{'declarationId': declarationId});
    return _declaration(_map(response.data));
  }

  Declaration _declaration(Map<String, dynamic> data) {
    DateTime? date(String key) {
      final value = data[key];
      return value is String ? DateTime.tryParse(value) : null;
    }

    final statusName = data['status'];
    if (statusName is! String) {
      throw const FormatException('La declaración recibida no tiene estado.');
    }
    final payload = data['payload'];
    final parsedPayload = payload is Map
        ? Map<String, Object?>.from(payload)
        : <String, Object?>{};
    if (data['declarantName'] is String &&
        !parsedPayload.containsKey('profile')) {
      parsedPayload['profile'] = <String, Object?>{
        'name': data['declarantName'],
      };
    }
    return Declaration(
      id: data['declarationId'] as String? ?? data['id'] as String,
      personId: data['personId'] as String,
      periodId: data['periodId'] as String,
      createdAt: date('createdAt') ?? DateTime.fromMillisecondsSinceEpoch(0),
      status: DeclarationStatus.values.byName(statusName),
      version: (data['version'] as num).toInt(),
      revision: (data['revision'] as num).toInt(),
      parentVersionId: data['parentVersionId'] as String?,
      oathAcceptedAt: date('oathAcceptedAt'),
      declarantSignedAt: date('declarantSignedAt'),
      declarantSignature: data['declarantSignature'] as String?,
      superiorSignedAt: date('superiorSignedAt'),
      superiorSignature: data['superiorSignature'] as String?,
      returnObservation: data['returnObservation'] as String?,
      hrReceivedAt: date('hrReceivedAt'),
      finalizedAt: date('finalizedAt'),
      finalPdfPath: data['finalPdfPath'] as String?,
      payload: parsedPayload,
    );
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const FormatException(
        'La respuesta del servidor tiene un formato inválido.',
      );
    }
    return Map<String, dynamic>.from(value);
  }
}

abstract interface class SupervisorAssignmentRepository {
  Future<void> assign({
    required String declarantId,
    required String supervisorId,
  });
}

abstract interface class SupervisorDeclarationActions {
  Future<void> sign({required Declaration declaration});
  Future<void> returnForCorrection({
    required Declaration declaration,
    required String observation,
  });
  Future<void> sendToHr({required Declaration declaration});
}

class SupervisorDeclarationActionService
    implements SupervisorDeclarationActions {
  SupervisorDeclarationActionService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<void> sign({required Declaration declaration}) async {
    await _functions.httpsCallable('signAsSuperior').call(<String, Object?>{
      'declarationId': declaration.id,
      'expectedVersion': declaration.version,
      'expectedRevision': declaration.revision,
      'confirmed': true,
    });
  }

  @override
  Future<void> returnForCorrection({
    required Declaration declaration,
    required String observation,
  }) async {
    await _functions.httpsCallable('returnForCorrection').call(
      <String, Object?>{
        'declarationId': declaration.id,
        'expectedVersion': declaration.version,
        'expectedRevision': declaration.revision,
        'observation': observation,
        'confirmed': true,
      },
    );
  }

  @override
  Future<void> sendToHr({required Declaration declaration}) async {
    await _functions.httpsCallable('sendDeclarationToHr').call(
      <String, Object?>{
        'declarationId': declaration.id,
        'expectedVersion': declaration.version,
        'expectedRevision': declaration.revision,
        'confirmed': true,
      },
    );
  }
}

class HumanResourcesInboxService {
  HumanResourcesInboxService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<List<Declaration>> getInbox() async {
    final response = await _functions
        .httpsCallable('getHumanResourcesInbox')
        .call();
    final result = _map(response.data);
    final rows = result['declarations'];
    if (rows is! List) {
      throw const FormatException(
        'La bandeja recibida tiene formato inválido.',
      );
    }
    return rows.map((row) => _declaration(_map(row))).toList(growable: false);
  }

  Future<Declaration> getDeclaration(String id) async {
    final response = await _functions
        .httpsCallable('getHumanResourcesDeclaration')
        .call({'declarationId': id});
    final data = _map(response.data);
    final payload = data['payload'] is Map
        ? Map<String, Object?>.from(data['payload'] as Map)
        : <String, Object?>{};
    if (data['declarantName'] is String && !payload.containsKey('profile')) {
      payload['profile'] = <String, Object?>{'name': data['declarantName']};
    }
    DateTime? date(String key) =>
        data[key] is String ? DateTime.tryParse(data[key] as String) : null;
    return Declaration(
      id: data['id'] as String,
      personId: data['personId'] as String,
      periodId: data['periodId'] as String,
      createdAt: date('createdAt') ?? DateTime.fromMillisecondsSinceEpoch(0),
      status: DeclarationStatus.values.byName(data['status'] as String),
      version: (data['version'] as num).toInt(),
      revision: (data['revision'] as num).toInt(),
      declarantSignedAt: date('declarantSignedAt'),
      declarantSignature: data['declarantSignature'] as String?,
      superiorSignedAt: date('superiorSignedAt'),
      superiorSignature: data['superiorSignature'] as String?,
      payload: payload,
    );
  }

  Future<void> receive(Declaration declaration) async {
    await _functions.httpsCallable('receiveDeclarationAtHr').call(
      <String, Object?>{
        'declarationId': declaration.id,
        'expectedVersion': declaration.version,
        'expectedRevision': declaration.revision,
        'confirmed': true,
      },
    );
  }

  Future<void> finalize(Declaration declaration) async {
    await _functions.httpsCallable('finalizeDeclaration').call(
      <String, Object?>{
        'declarationId': declaration.id,
        'expectedVersion': declaration.version,
        'expectedRevision': declaration.revision,
        'confirmed': true,
      },
    );
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const FormatException('Respuesta inválida del servidor.');
    }
    return Map<String, dynamic>.from(value);
  }

  Declaration _declaration(Map<String, dynamic> data) {
    DateTime? date(String key) =>
        data[key] is String ? DateTime.tryParse(data[key] as String) : null;
    final payload = <String, Object?>{};
    if (data['declarantName'] is String) {
      payload['profile'] = <String, Object?>{'name': data['declarantName']};
    }
    return Declaration(
      id: data['declarationId'] as String,
      personId: data['personId'] as String,
      periodId: data['periodId'] as String,
      createdAt: date('updatedAt') ?? DateTime.fromMillisecondsSinceEpoch(0),
      status: DeclarationStatus.values.byName(data['status'] as String),
      version: (data['version'] as num).toInt(),
      revision: (data['revision'] as num).toInt(),
      hrReceivedAt: date('hrReceivedAt'),
      finalizedAt: date('finalizedAt'),
      finalPdfPath: data['finalPdfPath'] as String?,
      payload: payload,
    );
  }
}

/// Invokes the privileged assignment endpoint; role and target validation are
/// performed by the server using the authenticated token and current profiles.
class SupervisorAssignmentService implements SupervisorAssignmentRepository {
  SupervisorAssignmentService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<void> assign({
    required String declarantId,
    required String supervisorId,
  }) async {
    await _functions.httpsCallable('assignDeclarantSupervisor').call(
      <String, Object?>{
        'declarantId': declarantId,
        'supervisorId': supervisorId,
      },
    );
  }
}
