import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/features/roles/domain/entities/app_role.dart';

void main() {
  test('Ambas representaciones del declarante conservan el mismo permiso', () {
    expect(parseAppRole('DECLARANTE'), AppRole.declarant);
    expect(parseAppRole('declarant'), AppRole.declarant);
  });
  test('Los roles existentes mantienen su interpretación', () {
    for (final role in AppRole.values) {
      expect(parseAppRole(role.name), role);
    }
  });
  test('Un valor desconocido o ausente no recibe permisos por defecto', () {
    for (final value in [null, '', 'Tania', 'ADMIN', 1, ['declarant']]) {
      expect(parseAppRole(value), isNull);
    }
  });
}
