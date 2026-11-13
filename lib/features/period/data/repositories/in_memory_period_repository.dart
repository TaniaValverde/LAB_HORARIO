import '../../domain/entities/academic_period.dart';
import '../../domain/repositories/period_repository.dart';

/// In-memory implementation of [PeriodRepository].
///
/// Stores academic periods in a local list for unit testing and domain
/// verification without requiring a persistent database. The production
/// application can use a repository implementation backed by Firestore.
class InMemoryPeriodRepository implements PeriodRepository {
  /// Creates an in-memory repository with an optional initial collection.
  ///
  /// Copies [periods] into an internal list so changes to the original list
  /// do not modify the repository's collection.
  InMemoryPeriodRepository([List<AcademicPeriod>? periods])
    : _periods = List<AcademicPeriod>.from(periods ?? <AcademicPeriod>[]);

  final List<AcademicPeriod> _periods;

  /// Returns all academic periods currently stored in memory.
  ///
  /// The returned list is unmodifiable, preventing callers from adding,
  /// removing or replacing elements in the returned collection.
  @override
  Future<List<AcademicPeriod>> getAll() async {
    return List<AcademicPeriod>.unmodifiable(_periods);
  }

  /// Saves a new academic period to the internal collection.
  ///
  /// Throws a [StateError] if a period with the same ID already exists.
  @override
  Future<void> save(AcademicPeriod period) async {
    final alreadyExists = _periods.any(
      (existingPeriod) => existingPeriod.id == period.id,
    );

    if (alreadyExists) {
      throw StateError(
        'An academic period with ID "${period.id}" already exists.',
      );
    }

    _periods.add(period);
  }

  /// Updates an existing academic period in the internal collection.
  ///
  /// Finds the period by its ID and replaces it with [period].
  /// Throws a [StateError] if no period with the specified ID exists.
  @override
  Future<void> update(AcademicPeriod period) async {
    final index = _periods.indexWhere(
      (existingPeriod) => existingPeriod.id == period.id,
    );

    if (index == -1) {
      throw StateError('Academic period with ID "${period.id}" was not found.');
    }

    _periods[index] = period;
  }
}
