import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:declara_horario/features/declaration/data/repositories/in_memory_audit_repository.dart';
import 'package:declara_horario/features/declaration/data/repositories/in_memory_declaration_repository.dart';
import 'package:declara_horario/features/declaration/data/services/declarant_oath_service.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration_form.dart';
import 'package:declara_horario/features/declaration/presentation/declaration_editor.dart';

import 'schedule_validation_test.dart' show profile, job;
import 'support/fake_oath.dart';

void main() {
  late FakeOath oath;
  late InMemoryDeclarationRepository repo;
  late Declaration declaration;
  setUp(() {
    oath = FakeOath()
      ..text = const ApprovedOath(
        version: 3,
        text: 'Texto aprobado de prueba.',
      );
    repo = InMemoryDeclarationRepository();
    declaration = Declaration(
      id: 'd',
      personId: 'u',
      periodId: 'II',
      createdAt: DateTime(2026),
      status: DeclarationStatus.validated,
      payload: DeclarationForm(profile: profile, appointments: [job()]).toMap(),
    );
  });
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await repo.save(declaration);
    await tester.pumpWidget(
      MaterialApp(
        home: DeclarationEditor(
          declaration: declaration,
          repository: repo,
          audit: InMemoryAuditRepository(),
          oath: oath,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Actualizar texto del juramento'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.ensureVisible(
      find.text('Confirmo expresamente mi aceptación.'),
    );
    await tester.tap(find.text('Confirmo expresamente mi aceptación.'));
    await tester.pumpAndSettle();
  }

  Future<void> accept(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Aceptar juramento'));
    await tester.tap(find.text('Aceptar juramento'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Recarga fecha y revisión del servidor y habilita firma sin salir',
    (tester) async {
      final serverTime = DateTime.utc(2026, 10, 16, 12);
      oath.onAccept = (d) async {
        await repo.update(
          d.copyWith(
            status: DeclarationStatus.pendingDeclarantSignature,
            oathAcceptedAt: serverTime,
          ),
        );
        return OathAcceptanceResult(
          declarationId: d.id,
          version: d.version,
          revision: d.revision + 1,
          eventId: 'event',
          oathTextVersion: 3,
          alreadyAccepted: false,
        );
      };
      await open(tester);
      expect(find.text('Texto aprobado de prueba.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Aceptar juramento'),
            )
            .onPressed,
        isNull,
      );
      await confirm(tester);
      await accept(tester);
      expect(oath.acceptedTextVersion, 3);
      expect((await repo.getById('d'))!.oathAcceptedAt, serverTime);
      await tester.ensureVisible(
        find.text('Confirmo que firmo esta versión de la declaración.'),
      );
      await tester.tap(
        find.text('Confirmo que firmo esta versión de la declaración.'),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Firmar esta versión'),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Cambio del texto exige volver a confirmar y no acepta la versión nueva silenciosamente',
    (tester) async {
      oath.onAccept = (_) async {
        oath.text = const ApprovedOath(
          version: 4,
          text: 'Nuevo texto aprobado.',
        );
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Cambió el texto',
        );
      };
      await open(tester);
      await confirm(tester);
      await accept(tester);
      expect(find.text('Nuevo texto aprobado.'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Aceptar juramento'),
            )
            .onPressed,
        isNull,
      );
      expect((await repo.getById('d'))!.status, DeclarationStatus.validated);
    },
  );
  testWidgets('Error de carga permite reintentar sin aceptación automática', (
    tester,
  ) async {
    oath.loadError = StateError('Sin conexión');
    await open(tester);
    expect(find.textContaining('No se pudo consultar'), findsOneWidget);
    oath.loadError = null;
    await tester.tap(find.text('Actualizar texto del juramento'));
    await tester.pumpAndSettle();
    expect(find.text('Texto aprobado de prueba.'), findsOneWidget);
    expect(oath.loads, 2);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Aceptar juramento'),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets('Respuesta sin fecha persistida mantiene la firma bloqueada', (
    tester,
  ) async {
    oath.onAccept = (d) async => OathAcceptanceResult(
      declarationId: d.id,
      version: d.version,
      revision: 1,
      eventId: 'event',
      oathTextVersion: 3,
      alreadyAccepted: false,
    );
    await open(tester);
    await confirm(tester);
    await accept(tester);
    expect(
      find.textContaining('no se pudo actualizar la pantalla'),
      findsOneWidget,
    );
    expect(find.text('Firmar esta versión'), findsNothing);
  });
}
