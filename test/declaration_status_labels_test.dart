import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/features/declaration/data/repositories/in_memory_audit_repository.dart';
import 'package:declara_horario/features/declaration/data/repositories/in_memory_declaration_repository.dart';
import 'package:declara_horario/features/declaration/domain/entities/audit_event.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration_form.dart';
import 'package:declara_horario/features/declaration/presentation/declaration_editor.dart';

import 'schedule_validation_test.dart' show job, profile;
import 'support/fake_oath.dart';

void main() {
  group('Nombre oficial de los estados', () {
    test('cada estado expone el nombre institucional', () {
      expect(DeclarationStatus.draft.label, 'BORRADOR');
      expect(DeclarationStatus.validated.label, 'VALIDADA');
      expect(
        DeclarationStatus.pendingDeclarantSignature.label,
        'PENDIENTE_FIRMA_DECLARANTE',
      );
      expect(
        DeclarationStatus.signedByDeclarant.label,
        'FIRMADA_POR_DECLARANTE',
      );
      expect(
        DeclarationStatus.pendingSuperiorSignature.label,
        'PENDIENTE_FIRMA_SUPERIOR',
      );
      expect(DeclarationStatus.signedBySuperior.label, 'FIRMADA_POR_SUPERIOR');
      expect(DeclarationStatus.returned.label, 'DEVUELTA');
      expect(DeclarationStatus.sentToHr.label, 'ENVIADA_A_RRHH');
      expect(DeclarationStatus.receivedByHr.label, 'RECIBIDA_RRHH');
      expect(DeclarationStatus.finalized.label, 'FINALIZADA');
      expect(DeclarationStatus.annulled.label, 'ANULADA');
    });

    test('traduce el valor persistido y descarta los desconocidos', () {
      expect(DeclarationStatus.labelOf('pendingSuperiorSignature'),
          'PENDIENTE_FIRMA_SUPERIOR');
      expect(DeclarationStatus.labelOf('sentToHr'), 'ENVIADA_A_RRHH');
      expect(DeclarationStatus.labelOf('desconocido'), isNull);
      expect(DeclarationStatus.labelOf(null), isNull);
    });
  });

  testWidgets('La versión devuelta muestra la observación del superior', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryDeclarationRepository();
    final audit = InMemoryAuditRepository();
    final d = Declaration(
      id: 'returned-id',
      personId: 'uid',
      periodId: 'II',
      createdAt: DateTime(2026),
      status: DeclarationStatus.returned,
      returnObservation: 'Falta indicar el lugar de trabajo del bloque de tarde.',
      payload: DeclarationForm(profile: profile, appointments: [job()]).toMap(),
    );
    await repo.save(d);
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarationEditor(
          oath: FakeOath(),
          declaration: d,
          repository: repo,
          audit: audit,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Estado: DEVUELTA'), findsOneWidget);
    expect(
      find.text(
        'Observación del superior (pendiente de corrección)',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Falta indicar el lugar de trabajo del bloque de tarde.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('La versión de corrección conserva la observación de la devolución', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryDeclarationRepository();
    final audit = InMemoryAuditRepository();
    await audit.append(
      AuditEvent(
        id: 'returnedForCorrection_v1_r3',
        declarationId: 'v2-id',
        actorId: 'supervisor-uid',
        action: 'returnedForCorrection',
        occurredAt: DateTime(2026, 10, 18),
        details: 'Ajustar la jornada del nombrado de la mañana.',
        version: 1,
        estadoAnterior: 'pendingSuperiorSignature',
        estadoNuevo: 'returned',
      ),
    );
    final d = Declaration(
      id: 'v2-id',
      personId: 'uid',
      periodId: 'II',
      createdAt: DateTime(2026),
      version: 2,
      parentVersionId: 'uid_II',
      status: DeclarationStatus.draft,
      payload: DeclarationForm(profile: profile, appointments: [job()]).toMap(),
    );
    await repo.save(d);
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarationEditor(
          oath: FakeOath(),
          declaration: d,
          repository: repo,
          audit: audit,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Estado: BORRADOR'), findsOneWidget);
    expect(
      find.text('Observación registrada en la devolución anterior'),
      findsOneWidget,
    );
    expect(
      find.text('Ajustar la jornada del nombrado de la mañana.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('El historial muestra los nombres oficiales de los estados', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryDeclarationRepository();
    final audit = InMemoryAuditRepository();
    await audit.append(
      AuditEvent(
        id: 'formUpdated_v1',
        declarationId: 'id',
        actorId: 'uid',
        action: 'formUpdated',
        occurredAt: DateTime(2026, 10, 18),
        version: 1,
        estadoAnterior: 'draft',
        estadoNuevo: 'validated',
      ),
    );
    final d = Declaration(
      id: 'id',
      personId: 'uid',
      periodId: 'II',
      createdAt: DateTime(2026),
      payload: DeclarationForm(profile: profile, appointments: [job()]).toMap(),
    );
    await repo.save(d);
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarationEditor(
          oath: FakeOath(),
          declaration: d,
          repository: repo,
          audit: audit,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('BORRADOR → VALIDADA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
