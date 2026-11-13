import '../../domain/entities/declaration.dart';
import '../../domain/repositories/declaration_repository.dart';

/// Temporary in-memory [DeclarationRepository] to run the prototype without
/// Firebase. Data is lost when the app closes.
///
/// It enforces a simplified subset of the rules of
/// `FirestoreDeclarationRepository`; the app uses that one.
class InMemoryDeclarationRepository implements DeclarationRepository {
  final List<Declaration> _items = [];

  /// Returns the declarations of [personId] as an unmodifiable copy, so the
  /// internal list is never exposed.
  @override
  Future<List<Declaration>> getForPerson(String personId) async =>
      List.unmodifiable(
        _items.where((item) => item.personId == personId).toList(),
      );

  @override
  Future<List<Declaration>> getAll() async => List.unmodifiable(_items);

  @override
  Future<Declaration?> getById(String id) async {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Stores [declaration]. Rejects duplicate ids, which keeps one declaration
  /// per person and period.
  @override
  Future<void> save(Declaration declaration) async {
    if (_items.any((item) => item.id == declaration.id)) {
      throw StateError('Ya existe una declaración para este período.');
    }
    _items.add(declaration);
  }

  /// Replaces a stored declaration and increments its `revision`.
  ///
  /// Rejects the update if the stored version is immutable (signed or in
  /// process), if an identity or versioning field changed, or if `revision`
  /// differs from the stored one (optimistic concurrency).
  @override
  Future<void> update(Declaration declaration) async {
    final index = _items.indexWhere((item) => item.id == declaration.id);
    if (index < 0) {
      throw StateError('No existe la declaración ${declaration.id}.');
    }
    final current = _items[index];
    if (current.isImmutable) {
      throw StateError(
        'Una versión firmada o en trámite no se puede modificar.',
      );
    }
    if (current.id != declaration.id ||
        current.personId != declaration.personId ||
        current.periodId != declaration.periodId ||
        current.version != declaration.version ||
        current.parentVersionId != declaration.parentVersionId ||
        current.createdAt != declaration.createdAt) {
      throw StateError(
        'Los datos de identidad y versionado no se pueden modificar.',
      );
    }
    if (current.revision != declaration.revision) {
      throw StateError(
        'La declaración cambió en otra sesión. Vuelva a abrirla.',
      );
    }
    _items[index] = declaration.copyWith(revision: declaration.revision + 1);
  }
}
