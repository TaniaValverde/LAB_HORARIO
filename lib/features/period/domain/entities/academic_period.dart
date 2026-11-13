/// Represents an academic period in which declarations can be created.
///
/// Defines the date range during which declarations may be initiated.
/// The period must be active and the specified date must fall within
/// its inclusive start and end boundaries.
class AcademicPeriod {
  /// Creates an academic period with its identifier, name, date range
  /// and activation status.
  const AcademicPeriod({
    required this.id,
    required this.name,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
  });

  /// Unique identifier of the academic period.
  final String id;

  /// Human-readable name of the period.
  final String name;

  /// Date and time when the academic period starts.
  final DateTime startsAt;

  /// Date and time when the academic period ends.
  final DateTime endsAt;

  /// Indicates whether the academic period is enabled.
  final bool isActive;

  /// Checks whether [date] falls within this period and the period is active.
  ///
  /// Both [startsAt] and [endsAt] are inclusive. Returns false if the period
  /// is inactive or [date] falls outside the defined range.
  bool isOpenAt(DateTime date) {
    if (!isActive) {
      return false;
    }

    return !date.isBefore(startsAt) && !date.isAfter(endsAt);
  }
}
