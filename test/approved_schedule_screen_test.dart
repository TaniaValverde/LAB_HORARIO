import 'dart:async';
import 'dart:typed_data';

import 'package:declara_horario/features/declaration/domain/entities/declaration.dart';
import 'package:declara_horario/features/declaration/presentation/approved_schedule_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/approved_schedule_fixture.dart';

void main() {
  late StreamController<List<Declaration>> data;
  late StreamController<String?> identity;
  late List<Declaration> fresh;
  late List<String> downloads;
  setUp(() {
    data = StreamController();
    identity = StreamController();
    fresh = [scheduleFixture()];
    downloads = [];
  });
  tearDown(() async {
    await data.close();
    await identity.close();
  });
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ApprovedScheduleScreen(
          personId: 'owner',
          watch: () => data.stream,
          loadFresh: () async => fresh,
          identities: identity.stream,
          isCurrentUser: () => true,
          encode: (document, pdf) async => Uint8List.fromList([1, 2]),
          download: (bytes, name, mime) async {
            downloads.add('$name|$mime');
          },
        ),
      ),
    );
    data.add(fresh);
    identity.add('owner');
    await tester.pumpAndSettle();
  }

  testWidgets('Approved period provides both downloads after re-reading data', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Descargar PNG'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descargar PDF'));
    await tester.pumpAndSettle();
    expect(downloads, [
      'horario_2026-II_v1.png|image/png',
      'horario_2026-II_v1.pdf|application/pdf',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'A revoked approval blocks an export even before the stream updates',
    (tester) async {
      await open(tester);
      fresh = [scheduleFixture(status: DeclarationStatus.annulled)];
      await tester.tap(find.text('Descargar PNG'));
      await tester.pumpAndSettle();
      expect(downloads, isEmpty);
      expect(find.textContaining('ya no está aprobada'), findsOneWidget);
    },
  );

  testWidgets('Identity changes remove the schedule and download actions', (
    tester,
  ) async {
    await open(tester);
    identity.add('another-user');
    await tester.pumpAndSettle();
    expect(find.textContaining('La sesión cambió'), findsOneWidget);
    expect(find.text('Descargar PNG'), findsNothing);
  });

  testWidgets('Empty and permission-error states never retain old data', (
    tester,
  ) async {
    await open(tester);
    data.add([]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Todavía no tiene'), findsOneWidget);
    data.add(fresh);
    await tester.pumpAndSettle();
    data.addError(StateError('Acceso denegado'));
    await tester.pumpAndSettle();
    expect(find.text('Acceso denegado'), findsOneWidget);
    expect(find.text('Descargar PDF'), findsNothing);
  });
}
