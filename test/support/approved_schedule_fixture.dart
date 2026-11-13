import 'package:declara_horario/features/declaration/domain/entities/declaration.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration_form.dart';
import 'package:declara_horario/features/profile/domain/declaring_profile.dart';
import 'package:declara_horario/features/schedule/domain/schedule.dart';

Declaration scheduleFixture({
  String person = 'owner',
  String period = '2026-II',
  int version = 1,
  DeclarationStatus status = DeclarationStatus.signedBySuperior,
  bool signed = true,
  int rows = 2,
}) => Declaration(
  id: '${person}_${period}_v$version',
  personId: person,
  periodId: period,
  version: version,
  revision: 8,
  status: status,
  createdAt: DateTime(2026, 10, 1),
  superiorSignedAt: signed ? DateTime(2026, 10, 28) : null,
  superiorSignature: signed ? 'superiorSignature_v${version}_r5' : null,
  payload: DeclarationForm(
    profile: const DeclaringProfile(
      name: 'Docente de prueba',
      identification: '123',
      email: 'docente@example.test',
      phone: '88888888',
      unit: 'Sede del Sur',
    ),
    appointments: [
      Appointment(
        id: 'job',
        workplace: 'Sede del Sur',
        position: 'Interino',
        courseCode: 'IF0009',
        weeklyMinutes: rows * 60,
        startsOn: DateTime(2026, 10, 1),
        endsOn: DateTime(2026, 12, 31),
        blocks: [
          for (var i = 0; i < rows; i++)
            ScheduleBlock(
              day: 1,
              start: 360 + i * 60,
              end: 420 + i * 60,
              activity: i.isEven
                  ? ScheduleActivity.teaching
                  : ScheduleActivity.consultation,
            ),
          const ScheduleBlock(
            day: 6,
            start: 480,
            end: 540,
            activity: ScheduleActivity.teaching,
          ),
        ],
      ),
    ],
  ).toMap(),
);
