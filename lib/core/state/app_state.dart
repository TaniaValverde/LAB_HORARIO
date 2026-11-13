import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../features/declaration/domain/entities/declaration.dart';
import '../../features/declaration/domain/entities/declaration_form.dart';
import '../../features/profile/data/profile_repository.dart';
import '../../features/validation/domain/validate_schedule.dart';

/// Holds the profile of the authenticated user and the state of its loading.
class AuthState extends ChangeNotifier {
  AuthState(this._profiles);
  final ProfileRepository _profiles;
  bool loading = true;
  UserProfile? profile;
  Object? error;

  /// Loads the profile for [user], toggling [loading] around the request.
  ///
  /// Failures are not rethrown: they are stored in [error] so the UI can
  /// react to them. A previously loaded [profile] is kept if the call fails.
  Future<void> load(User user) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      profile = await _profiles.load(user);
    } catch (value) {
      error = value;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

/// Holds the declaration currently being edited or reviewed.
class DeclarationState extends ChangeNotifier {
  DeclarationState(this.declaration);
  Declaration declaration;
  String? error;

  /// Swaps the current declaration, e.g. after a state transition or after a
  /// new version is created. Declarations are replaced, never mutated.
  void replace(Declaration value) {
    declaration = value;
    notifyListeners();
  }

  void setError(String? value) {
    error = value;
    notifyListeners();
  }
}

/// Holds the latest result of the schedule validation.
class ValidationState extends ChangeNotifier {
  ValidationResult? result;

  /// Runs the schedule validation on [form] and stores the outcome.
  ///
  /// Pass `notify: false` when calling during a build phase or when the
  /// caller will trigger the rebuild itself.
  ValidationResult validate(DeclarationForm form, {bool notify = true}) {
    result = const ValidateSchedule()(form);
    if (notify) notifyListeners();
    return result!;
  }
}

/// Tracks an in-flight signing operation.
///
/// Callers must pair every [begin] with a [finish], including on failure, so
/// [busy] never stays stuck.
class SignatureFlowState extends ChangeNotifier {
  bool busy = false;
  Object? error;

  /// Marks the operation as started and clears any previous error.
  void begin() {
    busy = true;
    error = null;
    notifyListeners();
  }

  /// Marks the operation as completed; pass [failure] if it did not succeed.
  void finish([Object? failure]) {
    busy = false;
    error = failure;
    notifyListeners();
  }
}

/// Holds the reviewer's draft observation and the busy flag of the review
/// actions (approve or return).
///
/// A return requires a non-empty [observation]; that rule is enforced by the
/// caller, not by this class.
class ReviewState extends ChangeNotifier {
  bool busy = false;
  String? observation;

  void setObservation(String? value) {
    observation = value;
    notifyListeners();
  }

  void setBusy(bool value) {
    busy = value;
    notifyListeners();
  }
}

/// App-wide theme mode, exposed as a singleton so it can be read outside the
/// widget tree.
class ThemeState extends ChangeNotifier {
  ThemeState._();
  static final ThemeState instance = ThemeState._();
  ThemeMode mode = ThemeMode.light;

  void toggle() {
    mode = mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
}

class ThemeToggleAction extends StatelessWidget {
  const ThemeToggleAction({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ThemeState.instance,
    builder: (context, _) => IconButton(
      tooltip: ThemeState.instance.mode == ThemeMode.dark
          ? 'Activar modo claro'
          : 'Activar modo oscuro',
      onPressed: ThemeState.instance.toggle,
      icon: Icon(
        ThemeState.instance.mode == ThemeMode.dark
            ? Icons.light_mode_outlined
            : Icons.dark_mode_outlined,
      ),
    ),
  );
}
