/// Represents the personal and organizational information of a declaration's
/// author.
///
/// Stores the declaring person's name, identification, phone, email and
/// organizational unit. The profile can be converted to a map for persistence
/// and reconstructed from a map retrieved from a data source.
class DeclaringProfile {
  /// Creates a declaring profile.
  ///
  /// All fields default to an empty string when no value is provided.
  const DeclaringProfile({
    this.name = '',
    this.identification = '',
    this.phone = '',
    this.email = '',
    this.unit = '',
  });

  final String name;
  final String identification;
  final String phone;
  final String email;
  final String unit;

  /// Converts this profile into a map using the field names expected by
  /// the data source.
  Map<String, Object?> toMap() => {
    'name': name,
    'identification': identification,
    'phone': phone,
    'email': email,
    'unit': unit,
  };

  /// Creates a [DeclaringProfile] from a map of stored profile data.
  ///
  /// Missing or null fields are replaced with empty strings.
  factory DeclaringProfile.fromMap(Map<String, dynamic> m) => DeclaringProfile(
    name: m['name'] as String? ?? '',
    identification: m['identification'] as String? ?? '',
    phone: m['phone'] as String? ?? '',
    email: m['email'] as String? ?? '',
    unit: m['unit'] as String? ?? '',
  );
}
