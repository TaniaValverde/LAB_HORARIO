import '../entities/declaration.dart';

/// Selects the latest version per period before checking approval, so a newer
/// returned or annulled version cannot expose an obsolete approved schedule.
List<Declaration> approvedSchedules(List<Declaration> items, String personId) {
  final latest = <String, Declaration>{};
  for (final item in items.where((d) => d.personId == personId)) {
    final previous = latest[item.periodId];
    if (previous == null ||
        item.version > previous.version ||
        (item.version == previous.version &&
            item.revision > previous.revision)) {
      latest[item.periodId] = item;
    }
  }
  const approved = {
    DeclarationStatus.signedBySuperior,
    DeclarationStatus.sentToHr,
    DeclarationStatus.receivedByHr,
    DeclarationStatus.finalized,
  };
  return latest.values
      .where(
        (d) =>
            approved.contains(d.status) &&
            d.superiorSignedAt != null &&
            (d.superiorSignature ?? '').isNotEmpty,
      )
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}
