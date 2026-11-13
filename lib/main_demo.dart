// Entry point that preserves Persona 2's declaration workspace screen.
// This prototype uses simulated roles and in-memory storage.

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'features/declaration/presentation/declaration_page.dart';

/// Initializes Firebase and launches the declaration application.
///
/// Ensures that Flutter bindings are initialized before setting up Firebase.
/// Once Firebase initialization completes, launches the application with
/// [DeclarationPage] as the home screen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MaterialApp(home: DeclarationPage()));
}
