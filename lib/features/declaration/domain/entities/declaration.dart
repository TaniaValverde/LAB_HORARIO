/// States in the institutional declaration workflow.
enum DeclarationStatus {
  draft,
  validated,
  pendingDeclarantSignature,
  signedByDeclarant,
  pendingSuperiorSignature,
  signedBySuperior,
  returned,
  sentToHr,
  receivedByHr,
  finalized,
  annulled;

  /// User-facing state label used in the institutional workflow.
  String get label => switch (this) {
    DeclarationStatus.draft => 'BORRADOR',
    DeclarationStatus.validated => 'VALIDADA',
    DeclarationStatus.pendingDeclarantSignature => 'PENDIENTE_FIRMA_DECLARANTE',
    DeclarationStatus.signedByDeclarant => 'FIRMADA_POR_DECLARANTE',
    DeclarationStatus.pendingSuperiorSignature => 'PENDIENTE_FIRMA_SUPERIOR',
    DeclarationStatus.signedBySuperior => 'FIRMADA_POR_SUPERIOR',
    DeclarationStatus.returned => 'DEVUELTA',
    DeclarationStatus.sentToHr => 'ENVIADA_A_RRHH',
    DeclarationStatus.receivedByHr => 'RECIBIDA_RRHH',
    DeclarationStatus.finalized => 'FINALIZADA',
    DeclarationStatus.annulled => 'ANULADA',
  };

  /// Maps a persisted Firestore or audit-event state to its display label.
  ///
  /// Returns `null` for unknown states so the interface can display
  /// the raw value without inventing a label.
  static String? labelOf(String? value) {
    for (final status in DeclarationStatus.values) {
      if (status.name == value) return status.label;
    }
    return null;
  }
}

/// Declaration data and workflow state for an academic period.
///
/// [payload] contains form data such as appointments, schedules and
/// observations without coupling this entity to the concrete form schema.
class Declaration {
  const Declaration({
    required this.id,
    required this.personId,
    required this.periodId,
    required this.createdAt,
    this.status = DeclarationStatus.draft,
    this.version = 1,
    this.revision = 0,
    this.parentVersionId,
    this.oathAcceptedAt,
    this.declarantSignedAt,
    this.declarantSignature,
    this.superiorSignedAt,
    this.superiorSignature,
    this.returnObservation,
    this.hrReceivedAt,
    this.finalizedAt,
    this.finalPdfPath,
    this.payload = const {},
  });

  final String id;
  final String personId;
  final String periodId;
  final DateTime createdAt;
  final DeclarationStatus status;
  final int version;

  /// Optimistic concurrency counter for edits from multiple tabs.
  final int revision;
  final String? parentVersionId;
  final DateTime? oathAcceptedAt;
  final DateTime? declarantSignedAt;
  final String? declarantSignature;
  final DateTime? superiorSignedAt;
  final String? superiorSignature;
  final String? returnObservation;
  final DateTime? hrReceivedAt;
  final DateTime? finalizedAt;
  final String? finalPdfPath;

  /// Form data, including appointments, schedules and observations.
  final Map<String, Object?> payload;

  /// Whether the content belongs to a version already in the signature workflow.
  /// Content in these versions is preserved without edits.
  bool get isImmutable =>
      declarantSignedAt != null ||
      superiorSignedAt != null ||
      status == DeclarationStatus.returned ||
      status == DeclarationStatus.pendingDeclarantSignature ||
      status == DeclarationStatus.signedByDeclarant ||
      status == DeclarationStatus.pendingSuperiorSignature ||
      status == DeclarationStatus.signedBySuperior ||
      status == DeclarationStatus.sentToHr ||
      status == DeclarationStatus.receivedByHr ||
      status == DeclarationStatus.finalized ||
      status == DeclarationStatus.annulled;

  /// Creates a copy replacing only the specified fields.
  /// Null arguments preserve the current declaration values.
  Declaration copyWith({
    DeclarationStatus? status,
    int? version,
    int? revision,
    String? parentVersionId,
    DateTime? oathAcceptedAt,
    DateTime? declarantSignedAt,
    String? declarantSignature,
    DateTime? superiorSignedAt,
    String? superiorSignature,
    String? returnObservation,
    DateTime? hrReceivedAt,
    DateTime? finalizedAt,
    String? finalPdfPath,
    Map<String, Object?>? payload,
  }) => Declaration(
    id: id,
    personId: personId,
    periodId: periodId,
    createdAt: createdAt,
    status: status ?? this.status,
    version: version ?? this.version,
    revision: revision ?? this.revision,
    parentVersionId: parentVersionId ?? this.parentVersionId,
    oathAcceptedAt: oathAcceptedAt ?? this.oathAcceptedAt,
    declarantSignedAt: declarantSignedAt ?? this.declarantSignedAt,
    declarantSignature: declarantSignature ?? this.declarantSignature,
    superiorSignedAt: superiorSignedAt ?? this.superiorSignedAt,
    superiorSignature: superiorSignature ?? this.superiorSignature,
    returnObservation: returnObservation ?? this.returnObservation,
    hrReceivedAt: hrReceivedAt ?? this.hrReceivedAt,
    finalizedAt: finalizedAt ?? this.finalizedAt,
    finalPdfPath: finalPdfPath ?? this.finalPdfPath,
    payload: payload ?? this.payload,
  );
}
