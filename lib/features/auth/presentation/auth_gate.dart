import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/errors/user_error.dart';
import '../../../core/state/app_state.dart';
import '../../declaration/presentation/declarant_dashboard.dart';
import '../../profile/data/profile_repository.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError) {
        return Scaffold(body: Center(child: Text(userError(snapshot.error!))));
      }
      final user = snapshot.data;
      return user == null
          ? const LoginPage()
          : ProfileGate(key: ValueKey(user.uid), user: user);
    },
  );
}

class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key, required this.user});
  final User user;
  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  late final AuthState _auth = AuthState(ProfileRepository());

  @override
  void initState() {
    super.initState();
    _auth.load(widget.user);
  }

  @override
  void dispose() {
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _auth,
    builder: (context, _) {
      if (_auth.profile != null) {
        return DeclarantDashboard(user: widget.user, profile: _auth.profile!);
      }
      return Scaffold(
        appBar: AppBar(
          title: const Text('DeclaraHorario'),
          actions: [
            const ThemeToggleAction(),
            TextButton(
              onPressed: () => FirebaseAuth.instance.signOut(),
              child: const Text('Cerrar sesión'),
            ),
          ],
        ),
        body: Center(
          child: _auth.error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(userError(_auth.error!)),
                    FilledButton(
                      onPressed: () => _auth.load(widget.user),
                      child: const Text('Reintentar'),
                    ),
                  ],
                )
              : _auth.loading
              ? const CircularProgressIndicator()
              : const Text('No se pudo cargar el perfil.'),
        ),
      );
    },
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _message;
  Future<void> _submit({bool reset = false}) async {
    if (_email.text.trim().isEmpty || (!reset && _password.text.isEmpty)) {
      setState(() => _message = 'Ingrese el correo y la contraseña.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (reset) {
        await FirebaseAuth.instance.sendPasswordResetEmail(
          email: _email.text.trim(),
        );
        if (mounted) {
          setState(
            () => _message = 'Si existe una cuenta, recibirá instrucciones para restablecer la contraseña.',
          );
        }
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = userError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _showPassword = false;

  ColorScheme get _colors => Theme.of(context).colorScheme;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: _colors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: SizedBox(
              width: double.infinity,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 56,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 390),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                        decoration: BoxDecoration(
                          color: _colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: _colors.outlineVariant),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x120E2D4D),
                              blurRadius: 18,
                              offset: Offset(0, 7),
                            ),
                          ],
                        ),
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: _colors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    'PORTAL INSTITUCIONAL',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: _colors.onSurfaceVariant,
                                      letterSpacing: 1.05,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Iniciar sesión',
                                style: textTheme.headlineSmall?.copyWith(
                                  color: _colors.onSurface,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 22,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Ingrese con su cuenta institucional habilitada.',
                                style: textTheme.bodySmall?.copyWith(
                                  color: _colors.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 20),
                              _fieldLabel('CORREO ELECTRÓNICO'),
                              const SizedBox(height: 5),
                              TextField(
                                controller: _email,
                                enabled: !_busy,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.username],
                                style: const TextStyle(fontSize: 12),
                                decoration: _inputDecoration(
                                  hint: 'usuario@ucr.ac.cr',
                                  icon: Icons.mail_outline,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _fieldLabel('CONTRASEÑA'),
                              const SizedBox(height: 5),
                              TextField(
                                controller: _password,
                                enabled: !_busy,
                                obscureText: !_showPassword,
                                autofillHints: const [AutofillHints.password],
                                onSubmitted: (_) {
                                  if (!_busy) _submit();
                                },
                                style: const TextStyle(fontSize: 12),
                                decoration: _inputDecoration(
                                  hint: '••••••••••••',
                                  icon: Icons.lock_outline,
                                  suffix: IconButton(
                                    tooltip: _showPassword
                                        ? 'Ocultar contraseña'
                                        : 'Mostrar contraseña',
                                    onPressed: () => setState(
                                      () => _showPassword = !_showPassword,
                                    ),
                                    icon: Icon(
                                      _showPassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _submit(reset: true),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.only(
                                      top: 5,
                                      bottom: 2,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    '¿Olvidó o desea recuperar su contraseña?',
                                    style: TextStyle(fontSize: 9),
                                  ),
                                ),
                              ),
                              if (_message != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _message!,
                                  semanticsLabel: _message,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 15),
                              SizedBox(
                                height: 39,
                                child: FilledButton(
                                  onPressed: _busy ? null : _submit,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _colors.primary,
                                    foregroundColor: _colors.onPrimary,
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  child: Text(
                                    _busy ? 'Conectando…' : 'Iniciar sesión',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 17),
                              Divider(height: 1, color: _colors.outlineVariant),
                              const SizedBox(height: 14),
                              Text(
                                '¿Problemas para ingresar?',
                                textAlign: TextAlign.center,
                                style: textTheme.bodySmall?.copyWith(
                                  color: _colors.onSurfaceVariant,
                                  fontSize: 9,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Contacte al administrador del sistema.',
                                textAlign: TextAlign.center,
                                style: textTheme.bodySmall?.copyWith(
                                  color: _colors.primary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 9),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.lock,
                                    size: 10,
                                    color: _colors.primary,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      'Conexión cifrada de alta seguridad (SSL/TLS)',
                                      style: textTheme.bodySmall?.copyWith(
                                        color: _colors.onSurfaceVariant,
                                        fontSize: 8,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 17),
                    Text(
                      '© 2025 Universidad de Costa Rica. Sistema de Gestión de\nDeclaraciones Juradas de Horario.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: _colors.onSurfaceVariant,
                        fontSize: 8,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) => Text(
    label,
    style: TextStyle(
      color: _colors.onSurface,
      fontSize: 9,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.45,
    ),
  );

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: _colors.onSurfaceVariant, fontSize: 11),
    prefixIcon: Icon(icon, size: 16, color: _colors.onSurfaceVariant),
    suffixIcon: suffix,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: _colors.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: _colors.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: _colors.primary, width: 1.3),
    ),
  );
}
