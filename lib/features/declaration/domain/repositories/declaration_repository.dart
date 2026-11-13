import '../entities/declaration.dart';

/// Persistence contract for reading and updating declarations.
/// The domain depends on this interface, not on a concrete database.
abstract interface class DeclarationRepository {
  /// Returns declarations owned by [personId].
  Future<List<Declaration>> getForPerson(String personId);

  /// Returns all declarations visible to the implementation.
  Future<List<Declaration>> getAll();

  /// Finds a declaration by ID, or returns null if it does not exist.
  Future<Declaration?> getById(String id);

  /// Saves a new declaration.
  Future<void> save(Declaration declaration);

  /// Updates an existing declaration while respecting immutability rules.
  Future<void> update(Declaration declaration);
}
