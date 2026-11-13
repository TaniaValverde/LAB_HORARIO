import '../entities/audit_event.dart';
import '../entities/declaration.dart';
import '../repositories/audited_declaration_repository.dart';
import '../repositories/audit_repository.dart';
import '../repositories/declaration_repository.dart';

/// Saves a valid form and records the update in the audit history.
class UpdateDeclarationForm {
  const UpdateDeclarationForm({
    required this.declarations,
    required this.audit,
  });

  final DeclarationRepository declarations;
  final AuditRepository audit;

  Future<Declaration> call({
    required Declaration declaration,
    required String actorId,
    DeclarationStatus? previousStatus,
    DateTime? now,
  }) async {
    final time = now ?? DateTime.now();
    final nextRevision = declaration.revision + 1;
    final event = AuditEvent(
      id: 'formUpdated_v$nextRevision',
      declarationId: declaration.id,
      actorId: actorId,
      action: 'formUpdated',
      occurredAt: time,
      version: declaration.version,
      estadoAnterior: (previousStatus ?? declaration.status).name,
      estadoNuevo: declaration.status.name,
    );
    final repository = declarations;
    if (repository is AuditedDeclarationRepository) {
      await repository.updateWithAudit(declaration, event);
    } else {
      // El prototipo conserva sus repositorios en memoria independientes.
      await declarations.update(declaration);
      await audit.append(event);
    }
    return declaration.copyWith(revision: declaration.revision + 1);
  }
}
