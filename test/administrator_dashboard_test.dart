import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/features/admin/presentation/administrator_dashboard.dart';
import 'package:declara_horario/features/period/domain/entities/academic_period.dart';
import 'package:declara_horario/features/period/domain/repositories/period_repository.dart';
import 'package:declara_horario/features/roles/data/role_administration_service.dart';
import 'package:declara_horario/features/roles/domain/entities/app_role.dart';

class _Periods implements PeriodRepository {
  final List<AcademicPeriod> items = [];

  @override
  Future<List<AcademicPeriod>> getAll() async => List.unmodifiable(items);

  @override
  Future<void> save(AcademicPeriod period) async => items.add(period);

  @override
  Future<void> update(AcademicPeriod period) async {
    final index = items.indexWhere((item) => item.id == period.id);
    if (index < 0) throw StateError('missing period');
    items[index] = period;
  }
}

class _Roles implements RoleAdministrationRepository {
  String? targetUid;
  AppRole? role;
  int calls = 0;

  @override
  Future<RoleAssignmentResult> assign({
    required String targetUid,
    required AppRole role,
  }) async {
    calls++;
    this.targetUid = targetUid;
    this.role = role;
    return RoleAssignmentResult(
      targetUid: targetUid,
      role: role,
      revision: 1,
      alreadyAssigned: false,
    );
  }
}

Finder _roleUidField() =>
    find.byKey(const ValueKey('administrator-role-target-uid'));

void main() {
  testWidgets('filters active periods by partial identifier while typing', (
    tester,
  ) async {
    final periods = _Periods();
    for (final id in ['2026-II', '2027-I', '2026-old']) {
      periods.items.add(
        AcademicPeriod(
          id: id,
          name: 'Ciclo',
          startsAt: DateTime(2026),
          endsAt: DateTime(2027),
          isActive: id != '2026-old',
        ),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: AdministratorDashboard(
          operatorUid: 'admin',
          name: 'Admin',
          periods: periods,
          roles: _Roles(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ciclo (2026-old)'), findsNothing);
    expect(find.text('Ciclo (2026-II)'), findsOneWidget);
    final search = find.widgetWithText(TextField, 'Buscar por identificador');
    await tester.enterText(search, ' 26-iI ');
    await tester.pumpAndSettle();
    expect(find.text('Ciclo (2026-II)'), findsOneWidget);
    expect(find.text('Ciclo (2027-I)'), findsNothing);
    await tester.tap(find.text('Inactivos'));
    await tester.pumpAndSettle();
    expect(
      find.text('No hay períodos que coincidan con los filtros.'),
      findsOneWidget,
    );
    await tester.enterText(search, 'OLD');
    await tester.pumpAndSettle();
    expect(find.text('Ciclo (2026-old)'), findsOneWidget);
    await tester.tap(find.byTooltip('Limpiar búsqueda'));
    await tester.tap(find.text('Activos'));
    await tester.pumpAndSettle();
    expect(find.text('Ciclo (2026-II)'), findsOneWidget);
    expect(find.text('Ciclo (2027-I)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('administra períodos y asigna roles desde el panel autenticado', (
    tester,
  ) async {
    final periods = _Periods();
    final roles = _Roles();
    await tester.pumpWidget(
      MaterialApp(
        home: AdministratorDashboard(
          operatorUid: 'admin-uid',
          name: 'Admin de prueba',
          periods: periods,
          roles: roles,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Administración · Admin de prueba'), findsOneWidget);
    expect(find.text('No hay períodos configurados.'), findsOneWidget);

    await tester.tap(find.text('Crear período'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    final dialogFields = find.descendant(
      of: dialog,
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogFields.at(0), '2026-II');
    await tester.enterText(dialogFields.at(1), 'II ciclo 2026');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    expect(periods.items, hasLength(1));
    expect(periods.items.single.isActive, isTrue);
    expect(find.text('II ciclo 2026 (2026-II)'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    expect(periods.items.single.isActive, isFalse);
    expect(find.text('II ciclo 2026 (2026-II)'), findsNothing);
    await tester.tap(find.text('Inactivos'));
    await tester.pumpAndSettle();
    expect(find.text('II ciclo 2026 (2026-II)'), findsOneWidget);

    final roleUidField = _roleUidField();
    await tester.scrollUntilVisible(
      roleUidField,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(roleUidField, 'declarant-uid');
    final assignRoleButton = find.text('Asignar rol');
    await tester.scrollUntilVisible(
      assignRoleButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(assignRoleButton);
    await tester.pumpAndSettle();
    expect(roles.targetUid, 'declarant-uid');
    expect(roles.role, AppRole.declarant);
    expect(roles.calls, 1);
    expect(
      find.textContaining('El cambio se verá al iniciar una nueva sesión.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'el panel rechaza una autoasignación antes de llamar al servicio',
    (tester) async {
      final roles = _Roles();
      await tester.pumpWidget(
        MaterialApp(
          home: AdministratorDashboard(
            operatorUid: 'admin-uid',
            name: 'Admin',
            periods: _Periods(),
            roles: roles,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final roleUidField = _roleUidField();
      await tester.scrollUntilVisible(
        roleUidField,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(roleUidField, 'admin-uid');
      final assignRoleButton = find.text('Asignar rol');
      await tester.scrollUntilVisible(
        assignRoleButton,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(assignRoleButton);
      await tester.pumpAndSettle();
      expect(find.text('No puede cambiar su propio rol.'), findsOneWidget);
      expect(roles.targetUid, isNull);
      expect(roles.calls, 0);
    },
  );
}
