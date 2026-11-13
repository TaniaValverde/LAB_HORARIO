import '../entities/audit_event.dart';
import '../entities/declaration.dart';
import '../repositories/audit_repository.dart';
import '../repositories/declaration_repository.dart';

/// Creates an editable version derived from a returned declaration.
/// The previous version is preserved as a historical record.
class CreateDeclarationVersion {
  const CreateDeclarationVersion({
    required this.declarations,
    required this.audit,
  });

  final DeclarationRepository declarations;
  final AuditRepository audit;

  Future<Declaration> call({
    required String declarationId,
    required String actorId,
    DateTime? now,
  }) async {
    final original = await declarations.getById(declarationId);
    if (original == null) throw StateError('No existe la declaración.');
    if (original.status != DeclarationStatus.returned) {
      throw StateError(
        'Solo se puede crear una versión de una declaración devuelta.',
      );
    }
    final time = now ?? DateTime.now();
    // Copy the working payload so the declarant can correct it.
    final next = Declaration(
      id: '${original.id}_v${original.version + 1}',
      personId: original.personId,
      periodId: original.periodId,
      createdAt: time,
      status: DeclarationStatus.draft,
      version: original.version + 1,
      parentVersionId: original.id,
      payload: original.payload,
    );
    await declarations.save(next);
    await audit.append(
      AuditEvent(
        id: '${next.id}_created',
        declarationId: next.id,
        actorId: actorId,
        action: 'createVersion',
        occurredAt: time,
        details: 'Nueva versión derivada de ${original.id}',
      ),
    );
    return next;
  }
}
