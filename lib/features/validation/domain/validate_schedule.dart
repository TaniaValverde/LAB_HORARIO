import 'dart:math';

import '../../declaration/domain/entities/declaration_form.dart';
import '../../schedule/domain/schedule.dart';

/// Represents a validation issue found in a declaration form.
///
/// Contains a machine-readable code and a descriptive message explaining
/// the validation rule that was not satisfied.
class ValidationIssue {
  const ValidationIssue(this.code, this.message);

  final String code;
  final String message;
}

/// Summarizes the expected and declared working time for an appointment.
///
/// Provides the appointment label, the expected weekly minutes and the total
/// minutes calculated from its schedule blocks.
class HourSummary {
  const HourSummary(this.label, this.expected, this.declared);

  final String label;
  final int expected;
  final int declared;

  /// Returns the difference between declared and expected working minutes.
  ///
  /// A positive value indicates excess declared time, while a negative
  /// value indicates a shortage.
  int get difference => declared - expected;
}

/// Contains the validation issues and working-hour summaries for a form.
///
/// The supplied collections are copied into unmodifiable lists so callers
/// cannot add, remove or replace their elements through this result.
class ValidationResult {
  ValidationResult(List<ValidationIssue> issues, List<HourSummary> hours)
    : issues = List.unmodifiable(issues),
      hours = List.unmodifiable(hours);

  final List<ValidationIssue> issues;
  final List<HourSummary> hours;

  /// Indicates whether validation completed without issues.
  bool get valid => issues.isEmpty;
}

/// Validates declaration profile data, appointments and work schedules.
///
/// This validation engine does not perform external operations. It checks
/// required profile fields, email format, appointment data, schedule blocks,
/// weekly working time, overlapping schedules and the daily working-time limit.
///
/// Schedule conflicts and daily limits are evaluated only across periods
/// when the corresponding appointments are simultaneously valid.
class ValidateSchedule {
  const ValidateSchedule();

  /// Validates the supplied [form] and returns its issues and hour summaries.
  ///
  /// Checks profile completeness, contact email format, appointment details,
  /// date ranges, schedule blocks, declared weekly minutes, overlapping time
  /// blocks and the maximum daily working time during overlapping validity
  /// periods. Each detected issue is returned with a code and message.
  ValidationResult call(DeclarationForm form) {
    final errors = <ValidationIssue>[];
    final hours = <HourSummary>[];

    // Adds a validation issue with its corresponding code and message.
    void issue(String code, String text) =>
        errors.add(ValidationIssue(code, text));

    final p = form.profile;
    if ([
      p.name,
      p.identification,
      p.phone,
      p.email,
      p.unit,
    ].any((s) => s.trim().isEmpty)) {
      issue(
        'profile',
        'Complete nombre, identificación, teléfono, correo y unidad.',
      );
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(p.email)) {
      issue('email', 'El correo de contacto no es válido.');
    }
    if (form.appointments.isEmpty) {
      issue('appointments', 'Agregue al menos un nombramiento institucional.');
    }

    // Combines institutional appointments and external jobs for validation.
    final jobs = [...form.appointments, ...form.externalJobs];
    final entries = <({Appointment job, ScheduleBlock block, String label})>[];

    for (var i = 0; i < jobs.length; i++) {
      final a = jobs[i];
      final external = i >= form.appointments.length;
      if (a.courseCode != null &&
          (external ||
              a.courseCode!.trim().isEmpty ||
              a.courseCode!.length > 40)) {
        issue(
          'courseCode',
          'La sigla debe tener de 1 a 40 caracteres y pertenecer a un nombramiento institucional.',
        );
      }
      final label =
          '${external ? 'Externo' : 'Nombramiento'} ${i + 1}: ${external ? a.institution : a.workplace}';

      if (a.workplace.trim().isEmpty ||
          a.position.trim().isEmpty ||
          (external && a.institution.trim().isEmpty)) {
        issue('job', '$label: complete institución/lugar y cargo.');
      }
      if (a.weeklyMinutes <= 0 || a.weeklyMinutes > 3600) {
        issue(
          'expected',
          '$label: la jornada debe ser mayor a 0 y como máximo 60 horas semanales.',
        );
      }

      // Checks that the appointment ends on or after its start date.
      final datesValid = !a.endsOn.isBefore(a.startsOn);
      if (!datesValid) {
        issue(
          'dates',
          '$label: la fecha final debe ser igual o posterior a la inicial.',
        );
      }
      if (a.blocks.isEmpty) {
        issue('blocks', '$label: agregue bloques horarios.');
      }

      var total = 0;
      for (final b in a.blocks) {
        if (b.day < 1 ||
            b.day > 6 ||
            b.start < 0 ||
            b.end > 1440 ||
            b.end <= b.start) {
          issue(
            'time',
            '$label: día u horas inválidas; la hora final debe ser posterior a la inicial.',
          );
          continue;
        }
        if (b.start < 780 && b.end > 720) {
          issue(
            'lunch',
            '$label · ${dayNames[b.day - 1]} ${timeText(b.start)}–${timeText(b.end)}: el intervalo de 12:00 a 13:00 está excluido. Divida el bloque.',
          );
        }

        // Accumulates the duration of each valid schedule block.
        total += b.end - b.start;
        if (datesValid) entries.add((job: a, block: b, label: label));
      }

      hours.add(HourSummary(label, a.weeklyMinutes, total));
      final workload = a.workloadType;
      if (workload != null) {
        if (external || a.weeklyMinutes != workload.minutes) {
          issue(
            'workloadType',
            '$label: la jornada docente debe coincidir con el tipo seleccionado y ser institucional.',
          );
        }
        if (a.blocks.any((b) => b.activity == null)) {
          issue(
            'activity',
            '$label: clasifique cada bloque como clase o consulta.',
          );
        }
        final teaching = a.minutesFor(ScheduleActivity.teaching);
        final consultation = a.minutesFor(ScheduleActivity.consultation);
        if (consultation * 2 > teaching) {
          issue(
            'consultationLimit',
            '$label: las consultas no pueden superar 30 minutos por cada hora de clase registrada.',
          );
        }
        if (teaching != workload.teachingMinutes ||
            consultation != workload.consultationMinutes) {
          issue(
            'teachingWorkload',
            '$label: ${workload.label} requiere ${durationText(workload.teachingMinutes)} de clases y ${durationText(workload.consultationMinutes)} de consultas por semana.',
          );
        }
      } else if (a.blocks.any((b) => b.activity != null)) {
        issue(
          'activity',
          '$label: seleccione una jornada docente para clasificar clases y consultas.',
        );
      }
      if (total != a.weeklyMinutes) {
        issue(
          'workload',
          '$label: esperadas ${a.weeklyMinutes / 60} h, declaradas ${total / 60} h, diferencia ${(total - a.weeklyMinutes) / 60} h.',
        );
      }
    }

    // Detects overlapping time blocks that occur on the same weekday
    // during the period when both appointments are valid.
    for (var i = 0; i < entries.length; i++) {
      for (var j = i + 1; j < entries.length; j++) {
        final a = entries[i];
        final b = entries[j];
        if (a.block.day != b.block.day) continue;
        final start = max(a.block.start, b.block.start);
        final end = min(a.block.end, b.block.end);
        final from = a.job.startsOn.isAfter(b.job.startsOn)
            ? a.job.startsOn
            : b.job.startsOn;
        final until = a.job.endsOn.isBefore(b.job.endsOn)
            ? a.job.endsOn
            : b.job.endsOn;
        if (start < end && _hasDay(from, until, a.block.day)) {
          issue(
            'overlap',
            '${dayNames[a.block.day - 1]}: traslape ${timeText(start)}–${timeText(end)} (${end - start} min) entre ${a.label} [${timeText(a.block.start)}–${timeText(a.block.end)}] y ${b.label} [${timeText(b.block.start)}–${timeText(b.block.end)}].',
          );
        }
      }
    }

    // The active appointment set changes only when a validity period starts
    // or ends, so these boundaries define the intervals to evaluate.
    final boundaries = <DateTime>{
      for (final e in entries) e.job.startsOn,
      for (final e in entries) e.job.endsOn.add(const Duration(days: 1)),
    }.toList()..sort();

    final reported = <int>{};
    for (var i = 0; i + 1 < boundaries.length; i++) {
      final from = boundaries[i];
      final until = boundaries[i + 1].subtract(const Duration(days: 1));
      for (var day = 1; day <= 6; day++) {
        if (reported.contains(day) || !_hasDay(from, until, day)) continue;
        final minutes = entries
            .where(
              (e) =>
                  e.block.day == day &&
                  !e.job.startsOn.isAfter(from) &&
                  !e.job.endsOn.isBefore(from),
            )
            .fold<int>(0, (sum, e) => sum + e.block.end - e.block.start);
        if (minutes > 600) {
          issue(
            'dailyLimit',
            '${dayNames[day - 1]}: ${minutes / 60} horas en vigencias coincidentes; el máximo diario es 10 horas.',
          );
          reported.add(day);
        }
      }
    }

    return ValidationResult(errors, hours);
  }

  /// Checks whether [from] through [until] contains the specified weekday.
  ///
  /// Weekdays use the numbering convention where Monday is 1 and Saturday
  /// is 6. The date range includes both endpoints.
  bool _hasDay(DateTime from, DateTime until, int day) =>
      !from.add(Duration(days: (day - from.weekday + 7) % 7)).isAfter(until);
}
