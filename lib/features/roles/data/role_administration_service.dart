import 'package:cloud_functions/cloud_functions.dart';

import '../domain/entities/app_role.dart';

/// Defines the contract for assigning application roles to users.
///
/// Implementations must provide the server-authorized role assignment
/// operation and return the result of the assignment.
abstract interface class RoleAdministrationRepository {
  /// Assigns [role] to the user identified by [targetUid].
  ///
  /// Returns the result containing the assigned role, revision and whether
  /// the role was already assigned.
  Future<RoleAssignmentResult> assign({
    required String targetUid,
    required AppRole role,
  });
}

/// Represents the result of a user role assignment.
///
/// Includes the target user's identifier, the assigned role, the resulting
/// revision and whether the requested role was already assigned.
class RoleAssignmentResult {
  /// Creates a role assignment result.
  const RoleAssignmentResult({
    required this.targetUid,
    required this.role,
    required this.revision,
    required this.alreadyAssigned,
  });

  final String targetUid;
  final AppRole role;
  final int revision;
  final bool alreadyAssigned;
}

/// Assigns application roles through a server-authorized Cloud Function.
///
/// Implements [RoleAdministrationRepository] and delegates role assignments
/// to the `assignUserRole` callable instead of writing directly to Firestore.
class RoleAdministrationService implements RoleAdministrationRepository {
  RoleAdministrationService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Requests a role assignment for the specified user.
  ///
  /// Trims [targetUid] and sends the user identifier and role name to the
  /// `assignUserRole` Cloud Function. Validates the response fields before
  /// creating a [RoleAssignmentResult].
  ///
  /// Throws a [FirebaseFunctionsException] with the `internal` code if the
  /// response does not contain the expected values or data types.
  @override
  Future<RoleAssignmentResult> assign({
    required String targetUid,
    required AppRole role,
  }) async {
    final response = await _functions.httpsCallable('assignUserRole').call({
      'targetUid': targetUid.trim(),
      'role': role.name,
    });
    final raw = response.data;
    if (raw is! Map ||
        raw['targetUid'] != targetUid.trim() ||
        raw['role'] != role.name ||
        raw['revision'] is! int ||
        raw['alreadyAssigned'] is! bool) {
      throw FirebaseFunctionsException(
        code: 'internal',
        message: 'La respuesta de asignación de rol tiene un formato inválido.',
      );
    }
    return RoleAssignmentResult(
      targetUid: targetUid.trim(),
      role: role,
      revision: raw['revision'] as int,
      alreadyAssigned: raw['alreadyAssigned'] as bool,
    );
  }
}
