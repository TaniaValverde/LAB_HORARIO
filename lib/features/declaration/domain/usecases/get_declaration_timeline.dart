import '../entities/audit_event.dart';
import '../entities/declaration.dart';
import '../repositories/audit_repository.dart';
import '../repositories/declaration_repository.dart';

/// Reads the audit history of an existing declaration.
class GetDeclarationTimeline {
  const GetDeclarationTimeline({
    required this.declarations,
    required this.audit,
  });

  final DeclarationRepository declarations;
  final AuditRepository audit;

  Future<List<AuditEvent>> call(String declarationId) async {
    if (await declarations.getById(declarationId) == null) {
      throw StateError('No existe la declaración.');
    }
    return audit.getForDeclaration(declarationId);
  }
}

/// Prototype inbox for declarations awaiting supervisor review and signature.
class GetSuperiorInbox {
  const GetSuperiorInbox(this.declarations);
  final DeclarationRepository declarations;

  Future<List<Declaration>> call() async => (await declarations.getAll())
      .where(
        (item) => item.status == DeclarationStatus.pendingSuperiorSignature,
      )
      .toList(growable: false);
}

/// A person's declaration history, ordered newest first.
class GetDeclarationsForPerson {
  const GetDeclarationsForPerson(this.declarations);
  final DeclarationRepository declarations;

  Future<List<Declaration>> call(String personId) async {
    final items = await declarations.getForPerson(personId);
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(items);
  }
}
