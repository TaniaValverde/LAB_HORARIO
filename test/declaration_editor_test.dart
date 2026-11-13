import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/features/declaration/data/repositories/in_memory_audit_repository.dart';
import 'package:declara_horario/features/declaration/data/repositories/in_memory_declaration_repository.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration_form.dart';
import 'package:declara_horario/features/declaration/presentation/declaration_editor.dart';
import 'package:declara_horario/features/declaration/presentation/appointment_dialog.dart';
import 'package:declara_horario/features/schedule/domain/schedule.dart';

import 'schedule_validation_test.dart' show profile, job;
import 'support/fake_oath.dart';
import 'support/fake_signature.dart';

void main() {
  testWidgets('Formulario carga el perfil y guarda VALIDADA', (tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryDeclarationRepository();
    final audit = InMemoryAuditRepository();
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
    expect(find.text('Persona Prueba'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Validar declaración'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Validar declaración'));
    await tester.tap(find.text('Validar declaración'));
    await tester.pumpAndSettle();
    expect((await repo.getById('id'))!.status, DeclarationStatus.validated);
    expect((await audit.getForDeclaration('id')).single.action, 'formUpdated');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Editor VALIDADA bloquea juramento hasta incorporar texto oficial',
    (tester) async {
      final repo = InMemoryDeclarationRepository();
      final d = Declaration(
        id: 'id',
        personId: 'uid',
        periodId: 'II',
        createdAt: DateTime(2026),
        status: DeclarationStatus.validated,
        payload: DeclarationForm(
          profile: profile,
          appointments: [job()],
        ).toMap(),
      );
      await repo.save(d);
      await tester.pumpWidget(
        MaterialApp(
          home: DeclarationEditor(
            oath: FakeOath(),
            declaration: d,
            repository: repo,
            audit: InMemoryAuditRepository(),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Aceptación bajo juramento'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Aceptación bajo juramento'), findsOneWidget);
      expect(find.textContaining('pendiente de aprobación'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Aceptar juramento'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Editor confirma y delega firma a la operación inyectada', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryDeclarationRepository();
    final audit = InMemoryAuditRepository();
    final signature = FakeSignature();
    final d = Declaration(
      id: 'signed-id',
      personId: 'uid',
      periodId: 'II',
      createdAt: DateTime.utc(2026),
      status: DeclarationStatus.pendingDeclarantSignature,
      oathAcceptedAt: DateTime.utc(2026, 10, 18),
      payload: DeclarationForm(profile: profile, appointments: [job()]).toMap(),
    );
    await repo.save(d);
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarationEditor(
          declaration: d,
          repository: repo,
          audit: audit,
          oath: FakeOath(),
          signature: signature,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Confirmo que firmo esta versión de la declaración.'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.text('Confirmo que firmo esta versión de la declaración.'),
    );
    await tester.tap(
      find.text('Confirmo que firmo esta versión de la declaración.'),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Firmar esta versión'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Firmar esta versión'));
    await tester.tap(find.text('Firmar esta versión'));
    await tester.pumpAndSettle();

    expect(signature.confirmed, isTrue);
    expect(signature.signedDeclaration?.id, 'signed-id');
    expect(
      find.text(
        'Firma electrónica interna registrada para la versión 1, revisión 1.',
      ),
      findsOneWidget,
    );
    expect(
      (await repo.getById('signed-id'))!.status,
      DeclarationStatus.pendingDeclarantSignature,
    );
    expect(await audit.getForDeclaration('signed-id'), isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('En móvil bloquea validación vacía y permite guardar borrador', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryDeclarationRepository();
    final audit = InMemoryAuditRepository();
    final d = Declaration(
      id: 'id',
      personId: 'uid',
      periodId: 'II',
      createdAt: DateTime(2026),
    );
    await repo.save(d);
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarationEditor(
          oath: FakeOath(),
          declaration: d,
          repository: repo,
          audit: audit,
          mobileLab: true,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Validar declaración'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Validar declaración'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Validar declaración'));
    await tester.pumpAndSettle();
    expect((await repo.getById('id'))!.status, DeclarationStatus.draft);
    await tester.scrollUntilVisible(
      find.textContaining('Corríjalos antes de validar'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Corríjalos antes de validar'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Guardar borrador'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Guardar borrador'));
    await tester.tap(find.text('Guardar borrador'));
    await tester.pumpAndSettle();
    expect((await repo.getById('id'))!.revision, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Diálogo de nombramiento en móvil agrega bloques sin overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppointmentDialog(external: false)),
      ),
    );
    await tester.ensureVisible(find.text('Agregar bloque'));
    await tester.tap(find.text('Agregar bloque'));
    await tester.pumpAndSettle();
    expect(find.text('Inicio HH:MM'), findsOneWidget);
    final startField = find.widgetWithText(TextFormField, 'Inicio HH:MM');
    final endField = find.widgetWithText(TextFormField, 'Fin HH:MM');
    await tester.enterText(startField, '0800');
    await tester.enterText(endField, '1130');
    expect(tester.widget<TextFormField>(startField).controller!.text, '08:00');
    expect(tester.widget<TextFormField>(endField).controller!.text, '11:30');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Android laboratory does not expose signature or approval actions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = InMemoryDeclarationRepository();
      final d = Declaration(
        id: 'android-lab',
        personId: 'uid',
        periodId: 'II',
        createdAt: DateTime(2026),
        status: DeclarationStatus.validated,
        payload: DeclarationForm(
          profile: profile,
          appointments: [job()],
        ).toMap(),
      );
      await repo.save(d);
      await tester.pumpWidget(
        MaterialApp(
          home: DeclarationEditor(
            declaration: d,
            repository: repo,
            audit: InMemoryAuditRepository(),
            mobileLab: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alcance de la versión móvil'), findsOneWidget);
      expect(find.text('Aceptar juramento'), findsNothing);
      expect(find.text('Firmar esta versión'), findsNothing);
      expect(find.text('Enviar al superior'), findsNothing);
      expect(
        find.textContaining('No realiza ni simula firmas'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Android directs invalid overlap to detailed review and keeps draft status',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = InMemoryDeclarationRepository();
      final d = Declaration(
        id: 'overlapping-android',
        personId: 'uid',
        periodId: 'II',
        createdAt: DateTime(2026),
        payload: DeclarationForm(
          profile: profile,
          appointments: [
            job(
              blocks: const [ScheduleBlock(day: 1, start: 480, end: 720)],
              minutes: 240,
            ),
          ],
          externalJobs: [
            job(
              id: 'external',
              institution: 'Otra institución',
              blocks: const [ScheduleBlock(day: 1, start: 660, end: 840)],
              minutes: 180,
            ),
          ],
        ).toMap(),
      );
      await repo.save(d);
      await tester.pumpWidget(
        MaterialApp(
          home: DeclarationEditor(
            declaration: d,
            repository: repo,
            audit: InMemoryAuditRepository(),
            mobileLab: true,
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Validar declaración'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Validar declaración'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('traslape 11:00–12:00 (60 min)'),
        findsOneWidget,
      );
      expect(
        (await repo.getById('overlapping-android'))!.status,
        DeclarationStatus.draft,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
