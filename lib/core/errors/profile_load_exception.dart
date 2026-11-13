/// Stages of the profile loading flow at which a failure can occur.
enum ProfileLoadStep {
  /// Fetching the existing profile document.
  read,

  /// Creating a profile when none exists yet.
  create,

  /// Converting the stored data into a profile model.
  parse,
}

/// Thrown when the user profile cannot be loaded.
///
/// [step] identifies where the flow failed, and [code] carries the
/// machine-readable error code of the underlying failure, so callers can map
/// them to user-facing messages.
class ProfileLoadException implements Exception {
  const ProfileLoadException({required this.step, required this.code});

  final ProfileLoadStep step;
  final String code;
}
