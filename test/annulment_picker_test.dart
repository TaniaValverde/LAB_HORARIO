import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/features/admin/data/annulment_lookup_service.dart';
import 'package:declara_horario/features/admin/presentation/annulment_picker.dart';
import 'package:declara_horario/features/period/domain/entities/academic_period.dart';

void main() {
  testWidgets('selects metadata, searches and disables terminal declarations', (
    tester,
  ) async {
    AnnulmentCandidate? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Abrir'),
              onPressed: () async {
                selected = await showDialog<AnnulmentCandidate>(
                  context: context,
                  builder: (_) => AnnulmentPicker(
                    periods: [
                      AcademicPeriod(
                        id: 'p',
                        name: 'Período',
                        startsAt: DateTime(2026),
                        endsAt: DateTime(2027),
                        isActive: true,
                      ),
                    ],
                    lookup: (period, after) async => (
                      next: null,
                      items: [
                        for (final status in ['draft', 'finalized', 'annulled'])
                          AnnulmentCandidate({
                            'id': status,
                            'name': status,
                            'personId': 'person',
                            'periodId': period,
                            'status': status,
                            'version': 2,
                            'revision': 8,
                          }),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Período (p)').last);
    await tester.pumpAndSettle();
    final terminal = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'finalized'),
    );
    expect(terminal.enabled, false);
    await tester.enterText(find.byType(TextField), 'DRA');
    await tester.pumpAndSettle();
    expect(find.text('finalized'), findsNothing);
    await tester.tap(find.text('draft'));
    await tester.pumpAndSettle();
    expect(selected!.id, 'draft');
    expect(selected!.version, 2);
    expect(selected!.revision, 8);
  });
}
