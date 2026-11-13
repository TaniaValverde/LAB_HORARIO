import 'package:declara_horario/features/auth/presentation/auth_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Login follows the selected theme when returning from a module', (
    tester,
  ) async {
    final dark = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
    );
    final light = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
    );
    final mode = ValueNotifier(ThemeMode.light);
    final loggedIn = ValueNotifier(true);
    addTearDown(mode.dispose);
    addTearDown(loggedIn.dispose);
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: Listenable.merge([mode, loggedIn]),
        builder: (context, _) => MaterialApp(
          theme: light,
          darkTheme: dark,
          themeMode: mode.value,
          home: loggedIn.value
              ? const Scaffold(body: Text('Módulo'))
              : const LoginPage(),
        ),
      ),
    );
    mode.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    loggedIn.value = false;
    await tester.pumpAndSettle();
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      dark.colorScheme.surface,
    );
    final card = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration is BoxDecoration)
        .first;
    expect(
      (card.decoration as BoxDecoration).color,
      dark.colorScheme.surfaceContainerLow,
    );
    expect(
      tester.widget<Text>(find.text('CORREO ELECTRÓNICO')).style!.color,
      dark.colorScheme.onSurface,
    );
    await tester.enterText(
      find.byType(TextField).first,
      'docente@example.test',
    );
    final inputContext = tester.element(find.byType(TextField).first);
    expect(Theme.of(inputContext).brightness, Brightness.dark);
    mode.value = ThemeMode.light;
    await tester.pumpAndSettle();
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      light.colorScheme.surface,
    );
    expect(find.text('docente@example.test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
