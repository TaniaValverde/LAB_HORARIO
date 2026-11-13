import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/features/declaration/presentation/oath_acceptance_section.dart';

void main() {
  testWidgets('no permite aceptar mientras falta el texto institucional', (
    tester,
  ) async {
    var accepted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OathAcceptanceSection(
            officialOathText: null,
            canAccept: true,
            busy: false,
            onAccept: () async {
              accepted = true;
            },
          ),
        ),
      ),
    );

    expect(find.textContaining('pendiente de aprobación'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Aceptar juramento'),
    );
    expect(button.onPressed, isNull);
    expect(accepted, isFalse);
  });

  testWidgets('requiere confirmación explícita cuando hay texto disponible', (
    tester,
  ) async {
    var accepted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OathAcceptanceSection(
            officialOathText: 'Texto institucional aprobado de prueba.',
            canAccept: true,
            busy: false,
            onAccept: () async {
              accepted = true;
            },
          ),
        ),
      ),
    );

    final buttonFinder = find.widgetWithText(FilledButton, 'Aceptar juramento');
    expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNotNull);
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
  });
}
