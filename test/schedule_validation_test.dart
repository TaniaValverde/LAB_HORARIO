import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration_form.dart';
import 'package:declara_horario/features/profile/domain/declaring_profile.dart';
import 'package:declara_horario/features/schedule/domain/schedule.dart';
import 'package:declara_horario/features/validation/domain/validate_schedule.dart';

const profile = DeclaringProfile(
  name: 'Persona Prueba',
  identification: '123',
  phone: '88888888',
  email: 'persona@example.com',
  unit: 'Sede del Sur',
);
Appointment job({
  String id = 'a',
  List<ScheduleBlock> blocks = const [
    ScheduleBlock(day: 1, start: 480, end: 720),
  ],
  int minutes = 240,
  String institution = '',
  DateTime? from,
  DateTime? until,
}) => Appointment(
  id: id,
  workplace: 'Sede',
  position: 'Docente',
  weeklyMinutes: minutes,
  startsOn: from ?? DateTime(2026, 10, 1),
  endsOn: until ?? DateTime(2026, 12, 31),
  blocks: blocks,
  institution: institution,
);
Set<String> codes(DeclarationForm f) =>
    const ValidateSchedule()(f).issues.map((e) => e.code).toSet();
void main() {
  test('Formulario válido y serialización sin perder horarios ni perfil', () {
    final f = DeclarationForm(
      profile: profile,
      appointments: [job()],
      observations: 'Atención',
    );
    expect(const ValidateSchedule()(f).valid, isTrue);
    expect(DeclarationForm.fromMap(f.toMap()).toMap(), f.toMap());
  });
  test('Campos obligatorios y nombramiento requerido', () {
    expect(
      codes(DeclarationForm(profile: const DeclaringProfile())),
      containsAll(['profile', 'email', 'appointments']),
    );
  });
  test('Traslape interno exacto y externo', () {
    final a = job(
      blocks: const [ScheduleBlock(day: 1, start: 780, end: 1020)],
      minutes: 240,
    );
    final b = job(
      id: 'b',
      institution: 'Empresa',
      blocks: const [ScheduleBlock(day: 1, start: 960, end: 1200)],
      minutes: 240,
    );
    final result = const ValidateSchedule()(
      DeclarationForm(profile: profile, appointments: [a], externalJobs: [b]),
    );
    expect(
      result.issues.where((e) => e.code == 'overlap').single.message,
      contains('16:00–17:00 (60 min)'),
    );
    expect(
      codes(DeclarationForm(profile: profile, appointments: [a, b])),
      contains('overlap'),
    );
  });
  test('Bloques contiguos no se traslapan', () {
    expect(
      codes(
        DeclarationForm(
          profile: profile,
          appointments: [
            job(
              blocks: const [
                ScheduleBlock(day: 1, start: 480, end: 600),
                ScheduleBlock(day: 1, start: 600, end: 720),
              ],
            ),
          ],
        ),
      ),
      isEmpty,
    );
  });
  test(
    'Vigencias separadas no producen conflicto ni suman el máximo diario',
    () {
      final blocks = [const ScheduleBlock(day: 1, start: 780, end: 1140)];
      final a = job(
        blocks: blocks,
        minutes: 360,
        until: DateTime(2026, 10, 15),
      );
      final b = job(
        id: 'b',
        blocks: blocks,
        minutes: 360,
        from: DateTime(2026, 10, 16),
      );
      expect(
        codes(DeclarationForm(profile: profile, appointments: [a, b])),
        isEmpty,
      );
    },
  );
  test(
    'Coincidencia de vigencia sin ocurrencia de lunes no genera traslape',
    () {
      final a = job(from: DateTime(2026, 10, 6), until: DateTime(2026, 10, 7));
      expect(
        codes(DeclarationForm(profile: profile, appointments: [a, a])),
        isEmpty,
      );
    },
  );
  test('Vigencias comparten un lunes inclusivo', () {
    final a = job(until: DateTime(2026, 10, 12));
    final b = job(from: DateTime(2026, 10, 12));
    expect(
      codes(DeclarationForm(profile: profile, appointments: [a, b])),
      contains('overlap'),
    );
  });
  test('Almuerzo se rechaza y los bordes 12:00 y 13:00 se aceptan', () {
    expect(
      codes(
        DeclarationForm(
          profile: profile,
          appointments: [
            job(
              blocks: const [ScheduleBlock(day: 1, start: 660, end: 840)],
              minutes: 180,
            ),
          ],
        ),
      ),
      contains('lunch'),
    );
    expect(
      codes(
        DeclarationForm(
          profile: profile,
          appointments: [
            job(
              blocks: const [
                ScheduleBlock(day: 1, start: 660, end: 720),
                ScheduleBlock(day: 1, start: 780, end: 840),
              ],
              minutes: 120,
            ),
          ],
        ),
      ),
      isEmpty,
    );
  });
  test(
    'Máximo 10 horas suma institución y externos; exactamente 10 se acepta',
    () {
      final a = job();
      final b = job(
        id: 'b',
        institution: 'Externa',
        blocks: const [ScheduleBlock(day: 1, start: 780, end: 1140)],
        minutes: 360,
      );
      expect(
        codes(
          DeclarationForm(
            profile: profile,
            appointments: [a],
            externalJobs: [b],
          ),
        ),
        isEmpty,
      );
      final c = job(
        id: 'c',
        blocks: const [ScheduleBlock(day: 1, start: 1140, end: 1141)],
        minutes: 1,
      );
      expect(
        codes(
          DeclarationForm(
            profile: profile,
            appointments: [a, c],
            externalJobs: [b],
          ),
        ),
        contains('dailyLimit'),
      );
    },
  );
  test(
    'Horas invertidas, domingo, jornada diferente y fechas inválidas bloquean',
    () {
      final f = DeclarationForm(
        profile: profile,
        appointments: [
          job(
            from: DateTime(2027),
            until: DateTime(2026),
            blocks: const [
              ScheduleBlock(day: 1, start: 600, end: 500),
              ScheduleBlock(day: 7, start: 600, end: 650),
            ],
          ),
        ],
      );
      expect(codes(f), containsAll(['time', 'workload', 'dates']));
    },
  );
  test('Traslapes entre dos empleos externos', () {
    expect(
      codes(
        DeclarationForm(
          profile: profile,
          appointments: [job()],
          externalJobs: [
            job(institution: 'A'),
            job(institution: 'B'),
          ],
        ),
      ),
      contains('overlap'),
    );
  });
  test('Parsing estricto de fecha y horas', () {
    expect(parseDate('2026-02-30'), isNull);
    expect(parseDate('2028-02-29'), isNotNull);
    expect(parseTime('24:00'), isNull);
    expect(parseTime('12:60'), isNull);
    expect(parseTime('08:30'), 510);
  });
}
