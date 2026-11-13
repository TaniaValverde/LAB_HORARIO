import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration.dart';
import 'package:declara_horario/features/declaration/presentation/declarant_signature_section.dart';

void main() {
  final declaration = Declaration(
    id: 'alice_period',
    personId: 'alice',
    periodId: 'II-2026',
    createdAt: DateTime.utc(2026),
    status: DeclarationStatus.pendingDeclarantSignature,
    revision: 1,
    oathAcceptedAt: DateTime.utc(2026, 10, 12),
    payload: const {
      'profile': {'name': 'Persona de prueba'},
      'appointments': [<String, Object?>{}],
      'externalJobs': <Object?>[],
    },
  );

  testWidgets('muestra el resumen y exige confirmación explícita', (
    tester,
  ) async {
    var signed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeclarantSignatureSection(
            declaration: declaration,
            canSign: true,
            busy: false,
            onSign: () async => signed = true,
          ),
        ),
      ),
    );

    expect(find.text('Versión formal 1 · revisión 1'), findsOneWidget);
    expect(find.text('Persona declarante: Persona de prueba'), findsOneWidget);
    final button = find.widgetWithText(FilledButton, 'Firmar esta versión');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(signed, isTrue);
  });

  testWidgets('presenta errores de firma de manera visible', (tester) async {
    const message = 'La versión cambió. Recargue la declaración.';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeclarantSignatureSection(
            declaration: declaration,
            canSign: true,
            busy: false,
            message: message,
            onSign: () async {},
          ),
        ),
      ),
    );

    expect(find.text(message), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
