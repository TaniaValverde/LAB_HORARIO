import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'supervisor_assignment_panel.dart';
import 'human_resources_inbox_screen.dart';
import '../../../core/state/app_state.dart';

/// Landing screen for users with the human resources role.
///
/// Combines the supervisor assignment panel with the inbox of declarations
/// that have been signed by both parties and are awaiting administrative
/// reception and closure.
class HumanResourcesDashboard extends StatelessWidget {
  const HumanResourcesDashboard({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Recursos Humanos'),
      actions: [
        const ThemeToggleAction(),
        TextButton.icon(
          onPressed: FirebaseAuth.instance.signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Salir'),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Recursos Humanos · $name',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            const SupervisorAssignmentPanel(),
            const SizedBox(height: 20),
            const HumanResourcesInboxScreen(),
          ],
        ),
      ),
    ),
  );
}
