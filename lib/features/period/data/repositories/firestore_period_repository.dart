import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/academic_period.dart';
import '../../domain/repositories/period_repository.dart';

/// Firestore implementation of [PeriodRepository].
///
/// Reads academic periods from Firestore and delegates create and update
/// operations to the trusted `saveAcademicPeriod` Cloud Function because
/// Firestore Security Rules deny direct client writes.
class FirestorePeriodRepository implements PeriodRepository {
  FirestorePeriodRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  /// Name of the Firestore collection containing academic periods.
  static const String _collectionName = 'academic_periods';

  /// Reference to the academic periods collection.
  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(_collectionName);

  /// Retrieves all academic periods from Firestore.
  ///
  /// Maps each document to an [AcademicPeriod], converting Firestore
  /// timestamps into Dart [DateTime] values and using the document ID
  /// as the period identifier.
  @override
  Future<List<AcademicPeriod>> getAll() async {
    final snapshot = await _collection.get();
    return snapshot.docs.map((document) {
      final data = document.data();
      return AcademicPeriod(
        id: document.id,
        name: data['name'] as String,
        startsAt: (data['startsAt'] as Timestamp).toDate(),
        endsAt: (data['endsAt'] as Timestamp).toDate(),
        isActive: data['isActive'] as bool,
      );
    }).toList();
  }

  /// Creates a new academic period through the server.
  ///
  /// Uses `createOnly: true` to indicate that the operation must create
  /// a period rather than update an existing one.
  @override
  Future<void> save(AcademicPeriod period) =>
      _saveThroughServer(period, createOnly: true);

  /// Updates an existing academic period through the server.
  ///
  /// Uses `createOnly: false` to distinguish the operation from creation.
  @override
  Future<void> update(AcademicPeriod period) =>
      _saveThroughServer(period, createOnly: false);

  /// Sends an academic period to the trusted `saveAcademicPeriod` function.
  ///
  /// Serializes the period fields into a request payload and converts the
  /// start and end dates to UTC ISO 8601 strings before sending them.
  /// The [createOnly] flag indicates whether the request is for creation
  /// or update. Server-side logic enforces the write operation.
  Future<void> _saveThroughServer(
    AcademicPeriod period, {
    required bool createOnly,
  }) async {
    await _functions.httpsCallable('saveAcademicPeriod').call({
      'id': period.id,
      'name': period.name,
      'startsAt': period.startsAt.toUtc().toIso8601String(),
      'endsAt': period.endsAt.toUtc().toIso8601String(),
      'isActive': period.isActive,
      'createOnly': createOnly,
    });
  }
}
