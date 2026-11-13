import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/features/declaration/presentation/declaration_list.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration.dart';

void main() {
  testWidgets('preserva la lista al insertar mensajes y abre la declaración', (
    tester,
  ) async {
    final source = StreamController<List<Declaration>>.broadcast();
    addTearDown(source.close);
    final d = Declaration(
      id: 'test',
      personId: 'uid',
      periodId: 'prueba',
      createdAt: DateTime(2026),
    );
    Declaration? opened;
    var subscriptions = 0;
    Stream<List<Declaration>> watch() {
      subscriptions++;
      return source.stream;
    }

    Widget panel(bool message) => MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            if (message) const Text('Ya tiene una declaración'),
            DeclarationList(
              key: const ValueKey('uid'),
              watch: watch,
              onOpen: (d) => opened = d,
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(panel(false));
    source.add([d]);
    await tester.pump();
    await tester.pumpWidget(panel(true));
    expect(subscriptions, 1);
    expect(find.text('Período prueba · Versión 1'), findsOneWidget);
    await tester.tap(find.text('Período prueba · Versión 1'));
    expect(opened, same(d));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'espera limitada y actualización recuperan una consulta atascada',
    (tester) async {
      final source = StreamController<List<Declaration>>.broadcast();
      addTearDown(source.close);
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeclarationList(
              watch: () =>
                  ++calls == 1 ? source.stream : Stream.value(<Declaration>[]),
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.tap(find.text('Actualizar lista'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Aún no tiene declaraciones.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
