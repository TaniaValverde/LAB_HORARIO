/// Activity labels are presentation only; enum names are persisted.
enum ScheduleActivity {
  teaching('Clase'),
  consultation('Consulta');

  const ScheduleActivity(this.label);
  final String label;
}

enum WorkloadType {
  fullTime('Tiempo completo', 2400),
  halfTime('Medio tiempo', 1200),
  quarterTime('¼ de tiempo', 600);

  const WorkloadType(this.label, this.minutes);
  final String label;
  final int minutes;
  int get consultationMinutes => minutes ~/ 3;
  int get teachingMinutes => minutes - consultationMinutes;
}

String durationText(int minutes) =>
    '${minutes ~/ 60} h${minutes % 60 == 0 ? '' : ' ${minutes % 60} min'}';

/// A recurring block in minutes from midnight, Monday (1) through Saturday (6).
/// A missing activity identifies legacy or external, unclassified work.
class ScheduleBlock {
  /// Creates a schedule block for the specified day and time range.
  const ScheduleBlock({
    required this.day,
    required this.start,
    required this.end,
    this.activity,
  });

  final int day;
  final int start;
  final int end;
  final ScheduleActivity? activity;

  /// Converts this schedule block into a map for data storage.
  Map<String, Object?> toMap() => {
    'day': day,
    'start': start,
    'end': end,
    if (activity != null) 'activity': activity!.name,
  };

  /// Creates a schedule block from a map of stored values.
  ///
  /// Converts numeric values to integers when reconstructing the block.
  factory ScheduleBlock.fromMap(Map<String, dynamic> m) => ScheduleBlock(
    day: (m['day'] as num).toInt(),
    start: (m['start'] as num).toInt(),
    end: (m['end'] as num).toInt(),
    activity: m['activity'] == null
        ? null
        : ScheduleActivity.values.byName(m['activity'] as String),
  );
}

/// Represents an employment appointment and its associated work schedule.
///
/// Stores the workplace, position, agreed weekly minutes, validity dates
/// and schedule blocks. An appointment can also identify an external
/// institution when [institution] is provided.
class Appointment {
  /// Creates an appointment with its employment details and schedule.
  ///
  /// Copies [blocks] into an unmodifiable list to prevent callers from
  /// adding, removing or replacing schedule blocks through this instance.
  Appointment({
    required this.id,
    required this.workplace,
    required this.position,
    required this.weeklyMinutes,
    required this.startsOn,
    required this.endsOn,
    required List<ScheduleBlock> blocks,
    this.institution = '',
    this.workloadType,
    this.courseCode,
  }) : blocks = List.unmodifiable(blocks);

  final String id;
  final String workplace;
  final String position;

  /// Agreed weekly time in minutes; matches [workloadType] when classified.
  final int weeklyMinutes;

  final DateTime startsOn;
  final DateTime endsOn;
  final String institution;
  final List<ScheduleBlock> blocks;
  final WorkloadType? workloadType;
  final String? courseCode;

  int minutesFor(ScheduleActivity activity) => blocks
      .where((b) => b.activity == activity && b.end > b.start)
      .fold(0, (total, b) => total + b.end - b.start);

  /// Indicates whether the appointment belongs to an external institution.
  ///
  /// Returns true when [institution] is not empty.
  bool get external => institution.isNotEmpty;

  /// Converts this appointment and its schedule blocks into a map.
  ///
  /// Dates are serialized using [dateText], and each schedule block is
  /// converted through [ScheduleBlock.toMap].
  Map<String, Object?> toMap() => {
    'id': id,
    'workplace': workplace,
    'position': position,
    'weeklyMinutes': weeklyMinutes,
    'startsOn': dateText(startsOn),
    'endsOn': dateText(endsOn),
    'institution': institution,
    'blocks': blocks.map((b) => b.toMap()).toList(),
    // Omit optional fields for legacy appointments to preserve their payload.
    if (workloadType != null) 'workloadType': workloadType!.name,
    if (courseCode != null) 'courseCode': courseCode,
  };

  /// Creates an appointment from a map of stored values.
  ///
  /// Reconstructs the schedule blocks and parses the start and end dates.
  /// The institution defaults to an empty string when the stored value
  /// is null or missing.
  factory Appointment.fromMap(Map<String, dynamic> m) => Appointment(
    id: m['id'] as String,
    workplace: m['workplace'] as String,
    position: m['position'] as String,
    courseCode: m['courseCode'] as String?,
    weeklyMinutes: (m['weeklyMinutes'] as num).toInt(),
    startsOn: parseDate(m['startsOn'] as String)!,
    endsOn: parseDate(m['endsOn'] as String)!,
    institution: m['institution'] as String? ?? '',
    workloadType: m['workloadType'] == null
        ? null
        : WorkloadType.values.byName(m['workloadType'] as String),
    blocks: (m['blocks'] as List)
        .map((b) => ScheduleBlock.fromMap(Map<String, dynamic>.from(b as Map)))
        .toList(),
  );
}

/// Spanish names of the supported weekdays, ordered from Monday to Saturday.
const dayNames = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
];

/// Formats minutes from midnight as a zero-padded `HH:mm` string.
String timeText(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// Formats a [DateTime] as a zero-padded `yyyy-MM-dd` date string.
String dateText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Parses a time string in `HH:mm` format into minutes from midnight.
///
/// Returns null if the value does not match the required format or
/// contains an hour outside 0–23 or a minute outside 0–59.
int? parseTime(String value) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  final h = int.parse(match[1]!);
  final m = int.parse(match[2]!);
  return h < 24 && m < 60 ? h * 60 + m : null;
}

/// Parses a date string in `yyyy-MM-dd` format.
///
/// Returns null if the format is invalid or the value does not represent
/// a valid calendar date matching the original input.
DateTime? parseDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  final d = DateTime.tryParse(value);
  return d != null && dateText(d) == value ? d : null;
}
