import '../entities/academic_period.dart';

/// Defines the contract for accessing academic period data.
///
/// Allows the domain layer to retrieve and manage academic periods without
/// depending on a specific storage implementation. Concrete repositories
/// can use Firestore, in-memory storage or another data source.
abstract interface class PeriodRepository {
  /// Retrieves all configured academic periods.
  Future<List<AcademicPeriod>> getAll();

  /// Saves a new [AcademicPeriod].
  Future<void> save(AcademicPeriod period);

  /// Updates an existing [AcademicPeriod].
  Future<void> update(AcademicPeriod period);
}
