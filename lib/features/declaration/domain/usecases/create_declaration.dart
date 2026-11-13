import '../../../period/domain/repositories/period_repository.dart';
import '../entities/audit_event.dart';
import '../entities/declaration.dart';
import '../repositories/audited_declaration_repository.dart';
import '../repositories/audit_repository.dart';
import '../repositories/declaration_repository.dart';

/// Reasons why a declaration cannot be created for the current period.
enum DeclarationCreationFailure {
  noActivePeriod,
  outsidePeriodDates,
  alreadyExists,
}

/// Business rule violation when starting a declaration.
class DeclarationCreationException implements Exception {
  const DeclarationCreationException(this.reason);
  final DeclarationCreationFailure reason;
}

/// Creates a draft when an enabled academic period is currently open.
class CreateDeclaration {
  const CreateDeclaration({
    required this.periods,
    required this.declarations,
    required this.audit,
  });

  final PeriodRepository periods;
  final DeclarationRepository declarations;
  final AuditRepository audit;

  Future<Declaration> call({
    required String personId,
    DateTime? now,
    Map<String, Object?> payload = const {},
  }) async {
    if (personId.trim().isEmpty) {
      throw ArgumentError('Se requiere un usuario autenticado.');
    }
    // Inject the current time to make date-dependent tests deterministic.
    final today = now ?? DateTime.now();
    final allPeriods = await periods.getAll();
    final active = allPeriods.where((period) => period.isActive).toList();
    if (active.isEmpty) {
      throw const DeclarationCreationException(
        DeclarationCreationFailure.noActivePeriod,
      );
    }
    final period = active.where((item) => item.isOpenAt(today)).firstOrNull;
    if (period == null) {
      throw const DeclarationCreationException(
        DeclarationCreationFailure.outsidePeriodDates,
      );
    }
    // Each person may have only one declaration chain per academic period.
    final existing = await declarations.getForPerson(personId);
    if (existing.any((item) => item.periodId == period.id)) {
      throw const DeclarationCreationException(
        DeclarationCreationFailure.alreadyExists,
      );
    }
    final declaration = Declaration(
      id: '${personId}_${period.id}',
      personId: personId,
      periodId: period.id,
      createdAt: today,
      payload: payload,
    );
    final event = AuditEvent(
      id: 'created_v1',
      declarationId: declaration.id,
      actorId: personId,
      action: 'created',
      occurredAt: today,
      version: declaration.version,
      estadoAnterior: null,
      estadoNuevo: declaration.status.name,
    );
    final repository = declarations;
    if (repository is AuditedDeclarationRepository) {
      await repository.saveWithAudit(declaration, event);
    } else {
      // The prototype keeps declaration and audit data in separate memory stores.
      await declarations.save(declaration);
      await audit.append(event);
    }
    return declaration;
  }
}

extension<T> on Iterable<T> {
  /// Returns the first element, or null when the collection is empty.
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
