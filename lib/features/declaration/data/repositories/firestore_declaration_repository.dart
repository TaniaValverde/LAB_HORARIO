import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/audit_event.dart';
import '../../domain/entities/declaration.dart';
import '../../domain/entities/declaration_form.dart';
import '../../domain/repositories/audited_declaration_repository.dart';
import 'firestore_audit_repository.dart';
import '../../../validation/domain/validate_schedule.dart';

/// Serializes [Declaration] to Firestore and reads legacy documents
/// that do not yet include optional workflow fields.
class DeclarationFirestoreSerializer {
  const DeclarationFirestoreSerializer();

  /// Builds the document map for [declaration].
  ///
  /// `updatedAt` is always set by the server.
  Map<String, Object?> encode(Declaration declaration) => {
    'personId': declaration.personId,
    'periodId': declaration.periodId,
    'createdAt': Timestamp.fromDate(declaration.createdAt),
    'status': declaration.status.name,
    'version': declaration.version,
    'parentVersionId': declaration.parentVersionId,
    'revision': declaration.revision,
    'payload': declaration.payload,
    'oathAcceptedAt': _timestamp(declaration.oathAcceptedAt),
    'declarantSignedAt': _timestamp(declaration.declarantSignedAt),
    'declarantSignature': declaration.declarantSignature,
    'superiorSignedAt': _timestamp(declaration.superiorSignedAt),
    'superiorSignature': declaration.superiorSignature,
    'returnObservation': declaration.returnObservation,
    'hrReceivedAt': _timestamp(declaration.hrReceivedAt),
    'finalizedAt': _timestamp(declaration.finalizedAt),
    'finalPdfPath': declaration.finalPdfPath,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Rebuilds a [Declaration] from a stored document.
  ///
  /// A missing `revision` is read as 0 and a missing `payload` as an empty map.
  Declaration decode(String id, Map<String, dynamic> data) {
    DateTime? date(String key) => (data[key] as Timestamp?)?.toDate();
    return Declaration(
      id: id,
      personId: data['personId'] as String,
      periodId: data['periodId'] as String,
      createdAt: date('createdAt')!,
      status: DeclarationStatus.values.byName(data['status'] as String),
      version: (data['version'] as num).toInt(),
      revision: (data['revision'] as num?)?.toInt() ?? 0,
      parentVersionId: data['parentVersionId'] as String?,
      payload: Map<String, Object?>.from(data['payload'] as Map? ?? {}),
      oathAcceptedAt: date('oathAcceptedAt'),
      declarantSignedAt: date('declarantSignedAt'),
      declarantSignature: data['declarantSignature'] as String?,
      superiorSignedAt: date('superiorSignedAt'),
      superiorSignature: data['superiorSignature'] as String?,
      returnObservation: data['returnObservation'] as String?,
      hrReceivedAt: date('hrReceivedAt'),
      finalizedAt: date('finalizedAt'),
      finalPdfPath: data['finalPdfPath'] as String?,
    );
  }

  Timestamp? _timestamp(DateTime? value) =>
      value == null ? null : Timestamp.fromDate(value);
}

/// Preserves the formal version identity of each declaration document.
/// The versions/{version} mirror supplies consistent data for signatures and PDFs.
class FirestoreDeclarationRepository implements AuditedDeclarationRepository {
  static const _serializer = DeclarationFirestoreSerializer();
  static const _auditSerializer = AuditEventFirestoreSerializer();

  FirestoreDeclarationRepository({FirebaseFirestore? firestore})
    : db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore db;
  CollectionReference<Map<String, dynamic>> get collection =>
      db.collection('declarations');

  CollectionReference<Map<String, dynamic>> _events(String declarationId) =>
      collection.doc(declarationId).collection('events');

  /// Streams the declarations of [uid], newest first.
  Stream<List<Declaration>> watchForPerson(String uid) => collection
      .where('personId', isEqualTo: uid)
      .snapshots()
      .map((s) => _sort(s.docs.map(_read).toList()));
  List<Declaration> _sort(List<Declaration> items) =>
      items..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  @override
  Future<List<Declaration>> getForPerson(String personId) async => _sort(
    (await collection.where('personId', isEqualTo: personId).get()).docs
        .map(_read)
        .toList(),
  );

  /// Exports must revalidate access and state rather than use an offline cache.
  Future<List<Declaration>> getForPersonFromServer(String personId) async =>
      _sort(
        (await collection
                .where('personId', isEqualTo: personId)
                .get(const GetOptions(source: Source.server)))
            .docs
            .map(_read)
            .toList(),
      );
  @override
  Future<List<Declaration>> getAll() async =>
      (await collection.get()).docs.map(_read).toList();
  @override
  Future<Declaration?> getById(String id) async {
    final doc = await collection.doc(id).get();
    return doc.exists ? _read(doc) : null;
  }

  /// Creates a declaration without an audit event.
  ///
  /// Prefer [saveWithAudit]. Fails if the declaration already exists, does not
  /// start as a draft, or its period is not enabled.
  @override
  Future<void> save(Declaration declaration) async {
    final ref = collection.doc(declaration.id);
    await db.runTransaction((tx) async {
      if ((await tx.get(ref)).exists) {
        throw StateError('Ya existe una declaración para este período.');
      }
      if (declaration.status != DeclarationStatus.draft) {
        throw StateError('La declaración debe comenzar en borrador.');
      }
      final period = await tx.get(
        db.collection('academic_periods').doc(declaration.periodId),
      );
      final data = period.data();
      final now = DateTime.now();
      if (data == null ||
          data['isActive'] != true ||
          now.isBefore((data['startsAt'] as Timestamp).toDate()) ||
          now.isAfter((data['endsAt'] as Timestamp).toDate())) {
        throw StateError(
          'El período no está habilitado para crear declaraciones.',
        );
      }
      tx.set(ref, _write(declaration));
      tx.set(
        ref.collection('versions').doc('${declaration.version}'),
        _write(declaration),
      );
    });
  }

  /// Creates the first version of a declaration together with its `created`
  /// audit event, atomically.
  ///
  /// The document id must be `{personId}_{periodId}`, which limits each person
  /// to one declaration per period. The period must be active and the current
  /// time must fall inside its validity window.
  @override
  Future<void> saveWithAudit(Declaration declaration, AuditEvent event) async {
    _validateAuditEvent(
      declaration,
      event,
      action: 'created',
      eventId: 'created_v1',
    );
    if (declaration.status != DeclarationStatus.draft ||
        declaration.version != 1 ||
        declaration.parentVersionId != null ||
        declaration.revision != 0 ||
        declaration.id != '${declaration.personId}_${declaration.periodId}') {
      throw StateError(
        'La declaración debe iniciar como versión 1 en borrador.',
      );
    }

    final ref = collection.doc(declaration.id);
    final versionRef = ref.collection('versions').doc('1');
    final eventRef = _events(declaration.id).doc(event.id);
    final periodRef = db
        .collection('academic_periods')
        .doc(declaration.periodId);
    await db.runTransaction((tx) async {
      final current = await tx.get(ref);
      final version = await tx.get(versionRef);
      final existingEvent = await tx.get(eventRef);
      final period = await tx.get(periodRef);
      if (current.exists || version.exists) {
        throw StateError('Ya existe una declaración para este período.');
      }
      if (existingEvent.exists) {
        throw StateError('El evento ${event.id} ya existe.');
      }
      final data = period.data();
      final now = DateTime.now();
      if (data == null ||
          data['isActive'] != true ||
          now.isBefore((data['startsAt'] as Timestamp).toDate()) ||
          now.isAfter((data['endsAt'] as Timestamp).toDate())) {
        throw StateError(
          'El período no está habilitado para crear declaraciones.',
        );
      }
      tx.set(ref, _write(declaration));
      tx.set(versionRef, _write(declaration));
      tx.set(eventRef, _auditSerializer.encode(event));
    });
  }

  /// Saves edits to a declaration without an audit event.
  ///
  /// Prefer [updateWithAudit]. Applies the same rules and increments
  /// `revision`.
  @override
  Future<void> update(Declaration declaration) async {
    final ref = collection.doc(declaration.id);
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      if (!snapshot.exists) throw StateError('La declaración ya no existe.');
      final current = _read(snapshot);
      _validateUpdate(current, declaration);
      final updated = declaration.copyWith(revision: declaration.revision + 1);
      tx.set(ref, _write(updated));
      tx.set(
        ref.collection('versions').doc('${declaration.version}'),
        _write(updated),
      );
    });
  }

  /// Saves edits to a declaration together with its `formUpdated` audit event,
  /// atomically, and increments `revision`.
  ///
  /// [declaration] must carry the revision that was read; if the stored one
  /// differs, the write is rejected. The event id is derived from the new
  /// revision, so replaying the same save cannot create a duplicate entry.
  @override
  Future<void> updateWithAudit(
    Declaration declaration,
    AuditEvent event,
  ) async {
    final expectedRevision = declaration.revision + 1;
    _validateAuditEvent(
      declaration,
      event,
      action: 'formUpdated',
      eventId: 'formUpdated_v$expectedRevision',
    );
    final ref = collection.doc(declaration.id);
    final versionRef = ref.collection('versions').doc('${declaration.version}');
    final eventRef = _events(declaration.id).doc(event.id);
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      final existingEvent = await tx.get(eventRef);
      if (!snapshot.exists) throw StateError('La declaración ya no existe.');
      if (existingEvent.exists) {
        throw StateError('El evento ${event.id} ya existe.');
      }
      final current = _read(snapshot);
      _validateUpdate(current, declaration);
      final updated = declaration.copyWith(revision: expectedRevision);
      tx.set(ref, _write(updated));
      tx.set(versionRef, _write(updated));
      tx.set(eventRef, _auditSerializer.encode(event));
    });
  }

  /// Checks that [event] describes exactly the operation being persisted.
  ///
  /// The event id is fixed per operation (`created_v1`, `formUpdated_v{n}`)
  /// and the actor must be the declaration owner.
  void _validateAuditEvent(
    Declaration declaration,
    AuditEvent event, {
    required String action,
    required String eventId,
  }) {
    if (event.id != eventId ||
        event.declarationId != declaration.id ||
        event.actorId != declaration.personId ||
        event.action != action ||
        event.version != declaration.version ||
        event.estadoNuevo != declaration.status.name ||
        (action == 'created' && event.estadoAnterior != null) ||
        (action == 'formUpdated' && event.estadoAnterior == null)) {
      throw StateError('El evento no corresponde a esta operación.');
    }
  }

  /// Enforces the rules for editing a declaration, comparing the stored
  /// [current] state with the incoming [declaration].
  ///
  /// - The revision must match, otherwise another session changed it first.
  /// - Signed (immutable) or returned versions cannot be edited; corrections
  ///   require a new version.
  /// - Identity fields (owner, period, version, parent, creation date) cannot
  ///   change.
  /// - Only the `draft` and `validated` statuses are allowed here; any other
  ///   transition goes through the signature service.
  /// - Moving to `validated` requires the schedule to pass validation.
  void _validateUpdate(Declaration current, Declaration declaration) {
    if (current.revision != declaration.revision) {
      throw StateError(
        'Esta declaración cambió en otra sesión. Regrese a la lista y vuelva a abrirla antes de guardar.',
      );
    }
    if (current.isImmutable || current.status == DeclarationStatus.returned) {
      throw StateError(
        'La versión está bloqueada; las correcciones requieren una nueva versión.',
      );
    }
    if (current.personId != declaration.personId ||
        current.periodId != declaration.periodId ||
        current.version != declaration.version ||
        current.parentVersionId != declaration.parentVersionId ||
        current.createdAt != declaration.createdAt) {
      throw StateError('No se puede cambiar la identidad de una versión.');
    }
    if (declaration.status != DeclarationStatus.draft &&
        declaration.status != DeclarationStatus.validated) {
      throw StateError('Esta operación corresponde al servicio de firmas.');
    }
    if (declaration.status == DeclarationStatus.validated &&
        !const ValidateSchedule()(DeclarationForm.fromMap(declaration.payload))
            .valid) {
      throw StateError('Corrija los errores del formulario antes de validar.');
    }
  }

  Map<String, Object?> _write(Declaration d) => _serializer.encode(d);

  Declaration _read(DocumentSnapshot<Map<String, dynamic>> doc) =>
      _serializer.decode(doc.id, doc.data()!);
}
