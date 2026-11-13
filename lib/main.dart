import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'core/firebase/local_auth_stub.dart'
    if (dart.library.js_interop) 'core/firebase/local_auth_web.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'core/state/app_state.dart';
import 'core/theme/ucr_theme.dart';

/// Indicates whether Firebase services should connect to local emulators.
///
/// The value is provided through the `FIREBASE_EMULATORS` environment
/// configuration and defaults to false when not specified.
const _useFirebaseEmulators = bool.fromEnvironment('FIREBASE_EMULATORS');

Future<bool> _isAndroidEmulator() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    const channel = MethodChannel('declara_horario/platform');
    return await channel.invokeMethod<bool>('isAndroidEmulator') ?? false;
  } on MissingPluginException {
    return false;
  }
}

/// Initializes Firebase services and launches the application.
///
/// Prepares local authentication support before initializing Firebase.
/// When emulator mode is enabled, uses demo Firebase options and configures
/// Firestore, Authentication and Cloud Functions to connect to local services.
///
/// If initialization fails, displays an error screen instead of launching
/// the main application.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    prepareLocalAuth(_useFirebaseEmulators);
    await Firebase.initializeApp(
      options: _useFirebaseEmulators
          ? const FirebaseOptions(
              apiKey: 'demo-api-key',
              appId: '1:123456789:web:declara-horario-demo',
              messagingSenderId: '123456789',
              projectId: 'demo-declara-horario',
            )
          : DefaultFirebaseOptions.currentPlatform,
    );
    if (_useFirebaseEmulators) {
      final host = await _isAndroidEmulator() ? '10.0.2.2' : '127.0.0.1';
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8180);
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
    }
    runApp(const DeclaraHorarioApp());
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'No se pudo iniciar Firebase. Revise la configuración y recargue la página.',
            ),
          ),
        ),
      ),
    );
  }
}

/// Root widget of the DeclaraHorario application.
///
/// Configures the application title, light and dark themes, Material 3
/// appearance and authentication entry point. Listens to [ThemeState.instance]
/// so changes to the selected theme are reflected in the interface.
class DeclaraHorarioApp extends StatelessWidget {
  const DeclaraHorarioApp({super.key});

  /// Builds the application and applies the currently selected theme.
  ///
  /// Uses [AuthGate] as the home screen to control access according to
  /// the authentication state.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ThemeState.instance,
    builder: (context, _) => MaterialApp(
      title: 'DeclaraHorario',
      debugShowCheckedModeBanner: false,
      theme: UcrTheme.light,
      darkTheme: UcrTheme.dark,
      themeMode: ThemeState.instance.mode,
      home: const AuthGate(),
    ),
  );
}
