import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/errors/profile_load_exception.dart';
import '../domain/declaring_profile.dart';
import '../../roles/domain/entities/app_role.dart';

/// Represents a user's profile together with their application role and status.
///
/// [details] contains the declaring profile information, [role] identifies
/// the user's application role, and [active] indicates whether the account
/// is enabled.
class UserProfile {
  const UserProfile(this.details, this.role, {required this.active});

  final DeclaringProfile details;
  final AppRole role;
  final bool active;
}

/// Repository responsible for loading and saving user profiles in Firestore.
///
/// Profiles are stored in the `users` collection and identified by the
/// Firebase Authentication user ID. When a profile does not exist, [load]
/// creates a default declarant profile. Loading failures are reported through
/// [ProfileLoadException] with the step and error code associated with the
/// operation.
class ProfileRepository {
  ProfileRepository({FirebaseFirestore? firestore})
    : db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore db;

  /// Loads the profile associated with [user].
  ///
  /// Reads the user's document from Firestore. If no profile exists, creates
  /// one using the available authentication details and assigns the default
  /// declarant role with an active status.
  ///
  /// Existing profiles are converted into a [UserProfile] after their role
  /// is parsed and their profile data is mapped. Read, creation and parsing
  /// failures are logged in debug mode and reported as [ProfileLoadException].
  /// Throws a [StateError] if the stored role is not recognized.
  Future<UserProfile> load(User user) async {
    final profileRef = db.collection('users').doc(user.uid);
    late final DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await profileRef.get();
    } catch (error, stackTrace) {
      _logFailure(ProfileLoadStep.read, user.uid, error, stackTrace);
      throw ProfileLoadException(
        step: ProfileLoadStep.read,
        code: _errorCode(error),
      );
    }

    final data = doc.data();
    if (data == null) {
      final p = DeclaringProfile(
        name: user.displayName ?? '',
        email: user.email ?? '',
      );
      try {
        await profileRef.set({
          ...p.toMap(),
          'role': 'declarant',
          'active': true,
        });
      } catch (error, stackTrace) {
        _logFailure(ProfileLoadStep.create, user.uid, error, stackTrace);
        throw ProfileLoadException(
          step: ProfileLoadStep.create,
          code: _errorCode(error),
        );
      }
      return UserProfile(p, AppRole.declarant, active: true);
    }
    final role = parseAppRole(data['role']);
    if (role == null) {
      throw StateError(
        'El perfil no tiene un rol reconocido. Contacte a administración.',
      );
    }
    try {
      return UserProfile(
        DeclaringProfile.fromMap(data),
        role,
        active: data['active'] == true,
      );
    } catch (error, stackTrace) {
      _logFailure(ProfileLoadStep.parse, user.uid, error, stackTrace);
      throw ProfileLoadException(
        step: ProfileLoadStep.parse,
        code: _errorCode(error),
      );
    }
  }

  /// Updates the stored profile for the specified Firebase user ID.
  ///
  /// Writes the fields provided by [profile] to the existing user document.
  Future<void> save(String uid, DeclaringProfile profile) =>
      db.collection('users').doc(uid).update(profile.toMap());

  /// Logs profile-loading failures when the application is running in debug
  /// mode.
  ///
  /// Includes the operation step and error details while replacing occurrences
  /// of the user's ID in the logged message to avoid exposing it directly.
  void _logFailure(
    ProfileLoadStep step,
    String uid,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!kDebugMode) return;
    final details = error is FirebaseException
        ? '${error.plugin}/${error.code}: ${error.message}'
        : '${error.runtimeType}: $error';
    debugPrint(
      '[ProfileRepository] ${step.name} users/{uid} failed: '
      '${details.replaceAll(uid, '{uid}')}',
    );
    debugPrintStack(stackTrace: stackTrace);
  }

  /// Extracts a stable error identifier from [error].
  ///
  /// Returns the Firebase error code for [FirebaseException] instances
  /// or the error's runtime type for other exceptions.
  String _errorCode(Object error) =>
      error is FirebaseException ? error.code : error.runtimeType.toString();
}
