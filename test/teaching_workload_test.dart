import 'package:declara_horario/features/declaration/domain/entities/declaration_form.dart';
import 'package:declara_horario/features/schedule/domain/schedule.dart';
import 'package:declara_horario/features/validation/domain/validate_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schedule_validation_test.dart' show profile, job;

Appointment teachingJob(WorkloadType type, {List<ScheduleBlock>? blocks}) =>
    Appointment(
      id: 'teaching',
      workplace: 'UCR',
      position: 'Docente',
      weeklyMinutes: type.minutes,
      workloadType: type,
      startsOn: DateTime(2026, 1, 1),
      endsOn: DateTime(2026, 12, 31),
      blocks:
          blocks ??
          [
            for (var day = 1; day <= type.minutes ~/ 600; day++) ...[
              ScheduleBlock(
                day: day,
                start: 360,
                end: 720,
                activity: ScheduleActivity.teaching,
              ),
              ScheduleBlock(
                day: day,
                start: 780,
                end: 820,
                activity: ScheduleActivity.teaching,
              ),
              ScheduleBlock(
                day: day,
                start: 840,
                end: 1040,
                activity: ScheduleActivity.consultation,
              ),
            ],
          ],
    );

void main() {
  test('Course code round-trips without changing legacy maps', () {
    final legacy = job().toMap();
    expect(Appointment.fromMap(legacy).toMap(), legacy);
    expect(legacy.containsKey('courseCode'), isFalse);
    final withCode = {...legacy, 'courseCode': 'IF0009'};
    expect(Appointment.fromMap(withCode).toMap(), withCode);
    for (final code in ['IF0009', '', 'A' * 41]) {
      final appointment = Appointment.fromMap({...legacy, 'courseCode': code});
      final result = const ValidateSchedule()(
        DeclarationForm(profile: profile, appointments: [appointment]),
      );
      expect(result.valid, code == 'IF0009');
    }
  });
  for (final type in WorkloadType.values) {
    test(
      '${type.name}: exact workload validates and survives serialization',
      () {
        final appointment = teachingJob(type);
        final form = DeclarationForm(
          profile: profile,
          appointments: [appointment],
        );
        expect(const ValidateSchedule()(form).issues, isEmpty);
        expect(
          appointment.minutesFor(ScheduleActivity.teaching),
          type.teachingMinutes,
        );
        expect(
          appointment.minutesFor(ScheduleActivity.consultation),
          type.consultationMinutes,
        );
        expect(DeclarationForm.fromMap(form.toMap()).toMap(), form.toMap());
      },
    );
  }

  Set<String> issues(List<ScheduleBlock> blocks) => const ValidateSchedule()(
    DeclarationForm(
      profile: profile,
      appointments: [teachingJob(WorkloadType.quarterTime, blocks: blocks)],
    ),
  ).issues.map((issue) => issue.code).toSet();

  test(
    'Excess consultations are rejected even when total matches workload',
    () {
      expect(
        issues([
          const ScheduleBlock(
            day: 1,
            start: 360,
            end: 660,
            activity: ScheduleActivity.teaching,
          ),
          const ScheduleBlock(
            day: 2,
            start: 360,
            end: 660,
            activity: ScheduleActivity.consultation,
          ),
        ]),
        containsAll(['consultationLimit', 'teachingWorkload']),
      );
    },
  );

  test('Incomplete hours and missing activity cannot validate', () {
    expect(
      issues([const ScheduleBlock(day: 1, start: 480, end: 600)]),
      containsAll(['activity', 'teachingWorkload', 'workload']),
    );
  });

  test('Consultations participate in overlap and lunch checks', () {
    final blocks = [...teachingJob(WorkloadType.quarterTime).blocks];
    blocks[2] = const ScheduleBlock(
      day: 1,
      start: 660,
      end: 860,
      activity: ScheduleActivity.consultation,
    );
    expect(issues(blocks), containsAll(['overlap', 'lunch']));
  });

  test('Legacy appointment maps remain unchanged and valid', () {
    final legacy = job().toMap();
    expect(legacy.containsKey('workloadType'), isFalse);
    expect(Appointment.fromMap(legacy).toMap(), legacy);
    expect(
      const ValidateSchedule()(
        DeclarationForm(profile: profile, appointments: [job()]),
      ).valid,
      isTrue,
    );
  });

  test('Teaching workloads are not accepted as external jobs', () {
    final result = const ValidateSchedule()(
      DeclarationForm(
        profile: profile,
        appointments: [job()],
        externalJobs: [teachingJob(WorkloadType.quarterTime)],
      ),
    );
    expect(result.issues.map((issue) => issue.code), contains('workloadType'));
  });
}
