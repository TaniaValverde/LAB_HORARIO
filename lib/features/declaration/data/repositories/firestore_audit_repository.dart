import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/audit_event.dart';
import '../../domain/repositories/audit_repository.dart';

/// Converts [AuditEvent]s to and from their Firestore representation.
class AuditEventFirestoreSerializer {
  const AuditEventFirestoreSerializer();

  /// Builds the document map for [event].
  ///
  /// `occurredAt` is always set by the server: the value carried by [event]
  /// is ignored, so clients cannot forge the time of an audit entry.
  Map<String, Object?> encode(AuditEvent event) => {
    'id': event.id,
    'declarationId': event.declarationId,
    'actorId': event.actorId,
    'action': event.action,
    // Firestore replaces the sentinel with request.time when the write is committed.
    'occurredAt': FieldValue.serverTimestamp(),
    'details': event.details,
    'version': event.version,
    'estadoAnterior': event.estadoAnterior,
    'estadoNuevo': event.estadoNuevo,
  };

  /// Rebuilds an [AuditEvent] from a stored document.
  ///
  /// Throws a [FormatException] if `occurredAt` is not a [Timestamp]. This
  /// also happens when reading a document whose server timestamp has not been
  /// resolved yet. Falls back to [documentId] when the `id` field is missing.
  AuditEvent decode(String documentId, Map<String, dynamic> data) {
    final occurredAt = data['occurredAt'];
    if (occurredAt is! Timestamp) {
      throw FormatException(
        'El campo occurredAt del evento leído debe ser un Timestamp.',
      );
    }
    return AuditEvent(
      id: data['id'] as String? ?? documentId,
      declarationId: data['declarationId'] as String,
      actorId: data['actorId'] as String,
      action: data['action'] as String,
      occurredAt: occurredAt.toDate(),
      details: data['details'] as String?,
      version: data['version'] as int?,
      estadoAnterior: data['estadoAnterior'] as String?,
      estadoNuevo: data['estadoNuevo'] as String?,
    );
  }

  /// Returns [events] in chronological order as an unmodifiable list.
  ///
  /// Events with the same timestamp are ordered by id, so the result is
  /// deterministic.
  List<AuditEvent> sort(Iterable<AuditEvent> events) {
    final result = events.toList()
      ..sort((a, b) {
        final byTime = a.occurredAt.compareTo(b.occurredAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    return List.unmodifiable(result);
  }
}

/// Append-only storage of audit events in the `events` subcollection of each
/// declaration.
///
/// This class only ever creates documents. Guaranteeing that events cannot be
/// edited or deleted afterwards is the job of the Firestore security rules.
class FirestoreAuditRepository implements AuditRepository {
  FirestoreAuditRepository({FirebaseFirestore? firestore})
    : db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore db;
  static const _serializer = AuditEventFirestoreSerializer();

  CollectionReference<Map<String, dynamic>> _events(String declarationId) =>
      db.collection('declarations').doc(declarationId).collection('events');

  /// Stores [event] under its own id.
  ///
  /// Runs in a transaction so an existing event is never overwritten; throws a
  /// [StateError] if the id is already taken.
  @override
  Future<void> append(AuditEvent event) async {
    final ref = _events(event.declarationId).doc(event.id);
    await db.runTransaction((transaction) async {
      if ((await transaction.get(ref)).exists) {
        throw StateError('El evento ${event.id} ya existe.');
      }
      transaction.set(ref, _serializer.encode(event));
    });
  }

  /// Returns the full history of [declarationId] in chronological order.
  @override
  Future<List<AuditEvent>> getForDeclaration(String declarationId) async {
    final snapshot = await _events(declarationId).orderBy('occurredAt').get();
    return _serializer.sort(
      snapshot.docs.map((doc) => _serializer.decode(doc.id, doc.data())),
    );
  }
}
