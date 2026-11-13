import 'package:declara_horario/features/declaration/presentation/appointment_dialog.dart';
import 'package:declara_horario/features/declaration/presentation/weekly_schedule.dart';
import 'package:declara_horario/features/schedule/domain/schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'teaching_workload_test.dart' show teachingJob;

void main() {
  testWidgets(
    'Institutional category is a closed choice and legacy values are not replaced silently',
    (tester) async {
      final old = teachingJob(WorkloadType.quarterTime);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppointmentDialog(external: false, initial: old),
          ),
        ),
      );
      final category = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byType(DropdownButtonFormField<String>),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(category.items!.map((item) => item.value), [
        'Interino',
        'En propiedad',
      ]);
      expect(
        find.widgetWithText(TextFormField, 'Cargo o categoría'),
        findsNothing,
      );
      await tester.tap(find.text('Aplicar al formulario'));
      await tester.pumpAndSettle();
      expect(find.text('Seleccione una categoría.'), findsOneWidget);
      expect(old.position, 'Docente');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Desktop schedule scrollbars remain visible and can be dragged', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final appointment = teachingJob(
      WorkloadType.fullTime,
      blocks: [
        for (var i = 0; i < 12; i++)
          ScheduleBlock(
            day: 1,
            start: 360 + i * 30,
            end: 390 + i * 30,
            activity: ScheduleActivity.teaching,
          ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeeklySchedule(
            appointments: [appointment],
            externalJobs: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bars = tester.widgetList<Scrollbar>(find.byType(Scrollbar)).toList();
    expect(bars, hasLength(2));
    for (final bar in bars) {
      expect(bar.thumbVisibility, isTrue);
      expect(bar.interactive, isTrue);
      expect(bar.controller!.position.maxScrollExtent, greaterThan(0));
    }
    final horizontal = bars.singleWhere(
      (b) => b.scrollbarOrientation == ScrollbarOrientation.bottom,
    );
    final vertical = bars.singleWhere((b) => b != horizontal);
    final bounds = tester.getRect(find.byWidget(horizontal));
    await tester.dragFrom(
      Offset(bounds.left + 30, bounds.bottom - 4),
      const Offset(160, 0),
    );
    await tester.pumpAndSettle();
    expect(horizontal.controller!.offset, greaterThan(0));
    await tester.dragFrom(
      Offset(bounds.right - 4, bounds.top + 25),
      const Offset(0, 100),
    );
    await tester.pumpAndSettle();
    expect(vertical.controller!.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'New appointment selects workload, calculates hours and returns typed blocks',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Appointment? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await showDialog<Appointment>(
                    context: context,
                    builder: (_) => const AppointmentDialog(external: false),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<WorkloadType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('¼ de tiempo · 10 h/semana').last);
      await tester.pumpAndSettle();
      for (final entry in {
        'Lugar de trabajo': 'UCR',
        'Sigla del curso (opcional)': 'IF0009',
        'Inicio de vigencia (AAAA-MM-DD)': '20260101',
        'Fin de vigencia (AAAA-MM-DD)': '20261231',
      }.entries) {
        await tester.enterText(
          find.widgetWithText(TextFormField, entry.key),
          entry.value,
        );
      }
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Interino').last);
      await tester.pumpAndSettle();
      for (final times in [
        ('0600', '1200'),
        ('1300', '1340'),
        ('1400', '1720'),
      ]) {
        await tester.ensureVisible(find.text('Agregar bloque'));
        await tester.tap(find.text('Agregar bloque'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Inicio HH:MM').last,
          times.$1,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Fin HH:MM').last,
          times.$2,
        );
        await tester.pump();
      }
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<ScheduleActivity>).last,
      );
      await tester.tap(
        find.byType(DropdownButtonFormField<ScheduleActivity>).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Consulta').last);
      await tester.pumpAndSettle();
      expect(find.text('Total registrado: 10 h de 10 h.'), findsOneWidget);
      expect(
        find.text(
          'Límite de consultas según las clases registradas: 3 h 20 min.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Aplicar al formulario'));
      await tester.pumpAndSettle();
      expect(saved?.workloadType, WorkloadType.quarterTime);
      expect(saved?.weeklyMinutes, 600);
      expect(saved?.courseCode, 'IF0009');
      expect(Appointment.fromMap(saved!.toMap()).courseCode, 'IF0009');
      expect(saved?.startsOn, DateTime(2026, 1, 1));
      expect(saved?.endsOn, DateTime(2026, 12, 31));
      expect(saved?.position, 'Interino');
      expect(saved?.minutesFor(ScheduleActivity.teaching), 400);
      expect(saved?.minutesFor(ScheduleActivity.consultation), 200);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Mobile weekly view is readable without horizontal scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> show(List<Appointment> appointments) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WeeklySchedule(
                appointments: appointments,
                externalJobs: const [],
              ),
            ),
          ),
        ),
      );
      await show([]);
      expect(find.textContaining('Agregue bloques'), findsOneWidget);
      await show([teachingJob(WorkloadType.quarterTime)]);
      expect(find.text('Lunes'), findsOneWidget);
      expect(find.text('06:00–12:00'), findsOneWidget);
      expect(find.text('Consulta'), findsOneWidget);
      expect(find.text('14:00–17:20'), findsOneWidget);
      expect(
        tester
            .widgetList<SingleChildScrollView>(
              find.byType(SingleChildScrollView),
            )
            .every((scroll) => scroll.scrollDirection == Axis.vertical),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await show([]);
      expect(find.text('14:00–17:20'), findsNothing);
      expect(find.textContaining('Agregue bloques'), findsOneWidget);
    },
  );
}
