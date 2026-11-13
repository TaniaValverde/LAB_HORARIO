/// Roles recognized by the declaration workflow and its access rules.
enum AppRole { declarant, supervisor, humanResources, administrator }

/// Converts a stored role value into its corresponding [AppRole].
///
/// Supports the legacy Firestore value `DECLARANTE` for compatibility
/// with existing user records. Other values must match an enum role name.
/// Returns null when the value is not recognized, without assigning a
/// default role or modifying the stored document.
AppRole? parseAppRole(Object? value) {
  if (value == 'DECLARANTE') return AppRole.declarant;
  for (final role in AppRole.values) {
    if (value == role.name) return role;
  }
  return null;
}
