import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

import 'profile_load_exception.dart';

String userError(Object error) {
  if (error is ProfileLoadException) {
    final operation = switch (error.step) {
      ProfileLoadStep.read => 'consultar',
      ProfileLoadStep.create => 'crear',
      ProfileLoadStep.parse => 'interpretar',
    };
    return switch (error.code) {
      'permission-denied' =>
        'No se pudo $operation su perfil local por falta de permiso. Revise que la sesión y Firestore Emulator usen demo-declara-horario.',
      'invalid-argument' =>
        'Firestore Emulator rechazó la operación para $operation su perfil (invalid-argument). Revise la consola de desarrollo para ver el detalle.',
      'unavailable' || 'network-request-failed' =>
        'No se pudo conectar con Firestore Emulator para $operation su perfil. Confirme que el emulador esté activo en 127.0.0.1:8180.',
      _ =>
        'No se pudo $operation su perfil local (${error.code}). Revise la consola de desarrollo para ver el detalle.',
    };
  }
  if (error is FirebaseFunctionsException) {
    final knownMessage = switch (error.message) {
      'No hay texto del juramento aprobado.' ||
      'No hay un texto institucional del juramento aprobado y configurado.' => 'No está configurado un texto aprobado del juramento. Solicite revisar la configuración del juramento; su declaración permanece guardada.',
      'La versión aprobada del texto está incompleta.' ||
      'La versión aprobada del texto institucional está incompleta o es inconsistente.' => 'El texto configurado del juramento está incompleto o es inconsistente. Solicite revisar esa versión del texto; su declaración permanece guardada.',
      'No existe el perfil indicado.' => 'No se encontró un perfil para ese UID. Verifique el UID y que la persona haya ingresado al sistema al menos una vez.',
      'Se requiere un perfil administrador activo para asignar roles.' =>
        'Solo un administrador activo puede asignar roles.',
      'No puede cambiar su propio rol.' => 'No puede cambiar su propio rol.',
      'El perfil tiene un rol actual inválido.' => 'El perfil tiene un rol actual inválido. Solicite revisión a administración.',
      'El historial de roles del perfil es inconsistente.' =>
        'El historial de roles del perfil requiere revisión administrativa.',
      'El evento de cambio de rol ya existe.' => 'El historial de roles no permite registrar este cambio. Solicite revisión a administración.',
      'No existe un perfil para el UID del declarante.' => 'No se encontró un perfil para el UID del declarante. Verifique el UID y que la persona haya ingresado al sistema al menos una vez.',
      'El perfil indicado para el declarante no tiene el rol declarante.' =>
        'El perfil seleccionado no tiene el rol de declarante.',
      'El perfil del declarante está inactivo.' => 'El perfil del declarante está inactivo. Solicite su habilitación a administración.',
      'No existe un perfil para el UID del superior.' => 'No se encontró un perfil para el UID del superior. Verifique el UID y que la persona haya ingresado al sistema al menos una vez.',
      'El perfil indicado para el superior no tiene el rol supervisor.' =>
        'El perfil seleccionado no tiene el rol de superior jerárquico.',
      'El perfil del superior está inactivo.' => 'El perfil del superior está inactivo. Solicite su habilitación a administración.',
      'La asignación existente está incompleta o es inconsistente.' ||
      'No se pudo verificar el historial de la asignación actual.' => 'La asignación o su historial requieren revisión administrativa; no se aplicaron cambios.',
      'Solo administración o Recursos Humanos activos pueden asignar superiores.' => 'Solo administración o Recursos Humanos con perfil activo pueden asignar superiores.',
      _ => null,
    };
    if (knownMessage != null) return knownMessage;
    return switch (error.code) {
      'unauthenticated' => 'Inicie sesión para realizar esta operación.',
      'permission-denied' =>
        'Su perfil no está autorizado para realizar esta operación.',
      'not-found' => 'No se encontró el perfil indicado. Verifique el UID y el acceso inicial al sistema.',
      'failed-precondition' => 'No se cumplen las condiciones necesarias para esta operación. Actualice los datos; si persiste, solicite revisión administrativa.',
      'invalid-argument' => 'Revise los datos ingresados e inténtelo de nuevo.',
      'already-exists' => 'La operación ya está registrada o existe una inconsistencia en el historial.',
      'unavailable' =>
        'El servicio no está disponible. Inténtelo de nuevo más tarde.',
      _ =>
        'No se pudo completar la operación (${error.code}). Inténtelo de nuevo.',
    };
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'Correo o contraseña incorrectos.',
      'invalid-email' => 'Ingrese un correo válido.',
      'user-disabled' => 'Esta cuenta está deshabilitada.',
      'too-many-requests' =>
        'Demasiados intentos. Espere unos minutos e inténtelo de nuevo.',
      'network-request-failed' || 'unavailable' =>
        'No se pudo conectar. Revise su conexión e inténtelo de nuevo.',
      'permission-denied' => 'No tiene permiso para esta operación. Revise las reglas de Firestore con administración.',
      'operation-not-allowed' => 'El inicio de sesión por correo debe habilitarse en Firebase Authentication.',
      _ =>
        'No se pudo completar la operación (${error.code}). Inténtelo de nuevo.',
    };
  }
  if (error is StateError) return error.message;
  return 'No se pudo completar la operación. Revise los datos e inténtelo de nuevo.';
}
