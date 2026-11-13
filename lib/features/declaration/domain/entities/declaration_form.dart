import '../../../profile/domain/declaring_profile.dart';
import '../../../schedule/domain/schedule.dart';

/// Version-one payload, including optional teaching fields on appointments.
/// Legacy appointments omit those fields to preserve their signed content.
class DeclarationForm {
  DeclarationForm({
    required this.profile,
    List<Appointment> appointments = const [],
    List<Appointment> externalJobs = const [],
    this.observations = '',
  }) : appointments = List.unmodifiable(appointments),
       externalJobs = List.unmodifiable(externalJobs);
  final DeclaringProfile profile;
  final List<Appointment> appointments;
  final List<Appointment> externalJobs;
  final String observations;
  Map<String, Object?> toMap() => {
    'schemaVersion': 1,
    'profile': profile.toMap(),
    'appointments': appointments.map((a) => a.toMap()).toList(),
    'externalJobs': externalJobs.map((a) => a.toMap()).toList(),
    'observations': observations,
  };
  factory DeclarationForm.fromMap(Map<String, Object?> m) => DeclarationForm(
    profile: DeclaringProfile.fromMap(
      Map<String, dynamic>.from(m['profile'] as Map? ?? {}),
    ),
    appointments: _jobs(m['appointments']),
    externalJobs: _jobs(m['externalJobs']),
    observations: m['observations'] as String? ?? '',
  );
  static List<Appointment> _jobs(Object? v) => (v as List? ?? [])
      .map((a) => Appointment.fromMap(Map<String, dynamic>.from(a as Map)))
      .toList();
}
