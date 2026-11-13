import '../entities/audit_event.dart';
import '../entities/declaration.dart';
import 'declaration_repository.dart';

/// A declaration and its canonical event are written as one operation.
abstract interface class AuditedDeclarationRepository
    implements DeclarationRepository {
  Future<void> saveWithAudit(Declaration declaration, AuditEvent event);

  Future<void> updateWithAudit(Declaration declaration, AuditEvent event);
}
