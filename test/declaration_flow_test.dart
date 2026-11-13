import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/features/declaration/data/repositories/in_memory_audit_repository.dart';
import 'package:declara_horario/features/declaration/data/repositories/in_memory_declaration_repository.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration_form.dart';
import 'package:declara_horario/features/declaration/domain/usecases/advance_declaration.dart';
import 'package:declara_horario/features/declaration/domain/usecases/create_declaration.dart';
import 'package:declara_horario/features/declaration/domain/usecases/update_declaration_form.dart';
import 'package:declara_horario/features/period/data/repositories/in_memory_period_repository.dart';
import 'package:declara_horario/features/period/domain/entities/academic_period.dart';
import 'package:declara_horario/features/roles/domain/entities/app_role.dart';

import 'schedule_validation_test.dart' show job, profile;

void main() {
  late InMemoryDeclarationRepository repo;
  late InMemoryAuditRepository audit;
  final now = DateTime(2026, 10, 7);
  setUp(() {
    repo = InMemoryDeclarationRepository();
    audit = InMemoryAuditRepository();
  });
  Declaration declaration({
    bool valid = true,
    DeclarationStatus status = DeclarationStatus.draft,
  }) => Declaration(
    id: 'uid_period',
    personId: 'uid',
    periodId: 'period',
    createdAt: now,
    status: status,
    payload: valid
        ? DeclarationForm(profile: profile, appointments: [job()]).toMap()
        : {},
  );
  test(
    'No se valida una declaración vacía desde el caso de uso de Persona 2',
    () async {
      await repo.save(declaration(valid: false));
      await expectLater(
        AdvanceDeclaration(declarations: repo, audit: audit)(
          declarationId: 'uid_period',
          actorId: 'uid',
          actorRole: AppRole.declarant,
          action: DeclarationAction.validate,
        ),
        throwsA(
          isA<DeclarationFlowException>().having(
            (e) => e.reason,
            'reason',
            DeclarationFlowFailure.validationFailed,
          ),
        ),
      );
      expect(
        (await repo.getById('uid_period'))!.status,
        DeclarationStatus.draft,
      );
      expect(await audit.getForDeclaration('uid_period'), isEmpty);
    },
  );
  test('Validar conserva payload y registra auditoría', () async {
    final original = declaration();
    await repo.save(original);
    await AdvanceDeclaration(declarations: repo, audit: audit)(
      declarationId: original.id,
      actorId: 'uid',
      actorRole: AppRole.declarant,
      action: DeclarationAction.validate,
    );
    final saved = (await repo.getById(original.id))!;
    expect(saved.status, DeclarationStatus.validated);
    expect(saved.payload, original.payload);
    expect(
      (await audit.getForDeclaration(original.id)).single.action,
      'validate',
    );
  });
  test('Otro usuario no puede validar la declaración', () async {
    await repo.save(declaration());
    await expectLater(
      AdvanceDeclaration(declarations: repo, audit: audit)(
        declarationId: 'uid_period',
        actorId: 'otro',
        actorRole: AppRole.declarant,
        action: DeclarationAction.validate,
      ),
      throwsA(isA<DeclarationFlowException>()),
    );
  });
  test('Edición de versión devuelta se bloquea', () async {
    final d = declaration(status: DeclarationStatus.returned);
    await repo.save(d);
    await expectLater(repo.update(d.copyWith(payload: {})), throwsStateError);
  });
  test('Actualización con revisión antigua no sobrescribe cambios', () async {
    final d = declaration();
    await repo.save(d);
    await repo.update(d.copyWith(payload: {'observations': 'Nueva'}));
    await expectLater(repo.update(d), throwsStateError);
    expect((await repo.getById(d.id))!.payload['observations'], 'Nueva');
  });
  test('Creación usa perfil, período activo y bloquea duplicados', () async {
    final create = CreateDeclaration(
      declarations: repo,
      audit: audit,
      periods: InMemoryPeriodRepository([
        AcademicPeriod(
          id: 'period',
          name: 'II 2026',
          startsAt: DateTime(2026, 8),
          endsAt: DateTime(2026, 12, 31),
          isActive: true,
        ),
      ]),
    );
    final payload = DeclarationForm(profile: profile).toMap();
    final d = await create(personId: 'uid', now: now, payload: payload);
    expect(d.status, DeclarationStatus.draft);
    expect(d.payload, payload);
    final createdEvent = (await audit.getForDeclaration(d.id)).single;
    expect(createdEvent.action, 'created');
    expect(createdEvent.actorId, 'uid');
    expect(createdEvent.id, 'created_v1');
    expect(createdEvent.version, 1);
    expect(createdEvent.estadoAnterior, isNull);
    expect(createdEvent.estadoNuevo, 'draft');
    await expectLater(
      create(personId: 'uid', now: now),
      throwsA(isA<DeclarationCreationException>()),
    );
  });
  test('Edición del prototipo conserva el evento formUpdated', () async {
    final original = declaration();
    await repo.save(original);

    final updated =
        await UpdateDeclarationForm(declarations: repo, audit: audit)(
          declaration: original.copyWith(
            payload: {'observations': 'Actualizado'},
          ),
          actorId: 'uid',
          now: now.add(const Duration(minutes: 1)),
        );

    expect(updated.revision, 1);
    expect(
      (await repo.getById(original.id))!.payload['observations'],
      'Actualizado',
    );
    final event = (await audit.getForDeclaration(original.id)).single;
    expect(event.action, 'formUpdated');
    expect(event.id, 'formUpdated_v1');
    expect(event.version, 1);
    expect(event.estadoAnterior, 'draft');
    expect(event.estadoNuevo, 'draft');
  });
  test('No se crea en un período deshabilitado', () async {
    final create = CreateDeclaration(
      declarations: repo,
      audit: audit,
      periods: InMemoryPeriodRepository([
        AcademicPeriod(
          id: 'period',
          name: 'II',
          startsAt: DateTime(2026),
          endsAt: DateTime(2027),
          isActive: false,
        ),
      ]),
    );
    await expectLater(
      create(personId: 'uid', now: now),
      throwsA(isA<DeclarationCreationException>()),
    );
    expect(await repo.getAll(), isEmpty);
  });
  test('No se crea fuera de las fechas de vigencia del período', () async {
    final create = CreateDeclaration(
      declarations: repo,
      audit: audit,
      periods: InMemoryPeriodRepository([
        AcademicPeriod(
          id: 'period',
          name: 'II',
          startsAt: DateTime(2026, 10, 8),
          endsAt: DateTime(2026, 12, 31),
          isActive: true,
        ),
      ]),
    );
    await expectLater(
      create(personId: 'uid', now: now),
      throwsA(
        isA<DeclarationCreationException>().having(
          (error) => error.reason,
          'reason',
          DeclarationCreationFailure.outsidePeriodDates,
        ),
      ),
    );
    expect(await repo.getAll(), isEmpty);
    expect(await audit.getForDeclaration('uid_period'), isEmpty);
  });
}
