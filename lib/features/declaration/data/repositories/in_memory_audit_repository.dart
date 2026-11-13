import '../../domain/entities/audit_event.dart';
import '../../domain/repositories/audit_repository.dart';

/// Temporary [AuditRepository] that keeps events in memory and loses them when
/// the app closes.
///
/// Meant for tests and local development; the app uses
/// `FirestoreAuditRepository`.
class InMemoryAuditRepository implements AuditRepository {
  final List<AuditEvent> _events = [];

  /// Returns an unmodifiable, chronologically sorted view of the history of
  /// [declarationId].
  @override
  Future<List<AuditEvent>> getForDeclaration(String declarationId) async {
    final events =
        _events.where((event) => event.declarationId == declarationId).toList()
          ..sort((a, b) {
            final byTime = a.occurredAt.compareTo(b.occurredAt);
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          });
    return List.unmodifiable(events);
  }

  /// Adds an event. The class offers no way to edit or delete history.
  @override
  Future<void> append(AuditEvent event) async => _events.add(event);
}
