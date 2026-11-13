/// Immutable record of an action performed on a declaration.
class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.declarationId,
    required this.actorId,
    required this.action,
    required this.occurredAt,
    this.details,
    this.version,
    this.estadoAnterior,
    this.estadoNuevo,
  });

  final String id;
  final String declarationId;
  final String actorId;
  final String action;
  final DateTime occurredAt;
  final String? details;
  final int? version;
  final String? estadoAnterior;
  final String? estadoNuevo;
}
