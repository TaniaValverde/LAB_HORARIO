import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/core/errors/profile_load_exception.dart';
import 'package:declara_horario/core/errors/user_error.dart';

void main() {
  test('identifica la configuración del juramento sin culpar al perfil', () {
    for (final message in [
      'No hay texto del juramento aprobado.',
      'La versión aprobada del texto está incompleta.',
    ]) {
      final result = userError(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: message,
        ),
      );
      expect(result, contains('juramento'));
      expect(result, contains('declaración permanece guardada'));
      expect(result, isNot(contains('perfil')));
    }
  });
  test('explica que el UID de rol no tiene un perfil de la aplicación', () {
    final error = FirebaseFunctionsException(
      code: 'not-found',
      message: 'No existe el perfil indicado.',
    );

    expect(
      userError(error),
      contains('que la persona haya ingresado al sistema al menos una vez'),
    );
  });

  test(
    'explica perfiles y asignaciones inválidos sin exponer identificadores',
    () {
      final error = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'No se pudo verificar el historial de la asignación actual.',
      );

      expect(userError(error), contains('requieren revisión administrativa'));
      expect(userError(error), isNot(contains('supervisorId')));
    },
  );

  test('distingue un fallo al crear el perfil en Firestore Emulator', () {
    final error = ProfileLoadException(
      step: ProfileLoadStep.create,
      code: 'invalid-argument',
    );

    expect(userError(error), contains('crear su perfil'));
    expect(userError(error), contains('invalid-argument'));
  });
}
