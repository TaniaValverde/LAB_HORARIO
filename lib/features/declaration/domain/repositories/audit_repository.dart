import '../entities/audit_event.dart';

/// Contract for appending and reading audit events.
abstract interface class AuditRepository {
  /// Returns events for [declarationId] in recorded order.
  Future<List<AuditEvent>> getForDeclaration(String declarationId);

  /// Appends an event; existing history entries are never edited.
  Future<void> append(AuditEvent event);
}
