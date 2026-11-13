import '../../../declaration/domain/usecases/advance_declaration.dart';
import '../entities/app_role.dart';

/// Determines which application roles are allowed to perform declaration
/// workflow actions.
///
/// Centralizes the role-based authorization rules used to control access
/// to each action in the declaration process.
class AuthorizeDeclarationAction {
  const AuthorizeDeclarationAction();

  /// Checks whether [role] is authorized to perform [action].
  ///
  /// Declarants can validate, accept the oath and sign, or submit declarations
  /// to their superior. Supervisors can sign as superior or return declarations
  /// for correction. Human resources can send, receive and finalize declarations.
  /// Administrators are allowed to perform all actions.
  ///
  /// Returns true when the role is permitted to perform the action,
  /// and false otherwise.
  bool call(AppRole role, DeclarationAction action) => switch (action) {
    DeclarationAction.validate || DeclarationAction.acceptOathAndSign =>
      role == AppRole.declarant || role == AppRole.administrator,
    DeclarationAction.submitToSuperior =>
      role == AppRole.declarant || role == AppRole.administrator,
    DeclarationAction.superiorSign || DeclarationAction.returnForCorrection =>
      role == AppRole.supervisor || role == AppRole.administrator,
    DeclarationAction.sendToHr ||
    DeclarationAction.receiveAtHr ||
    DeclarationAction.finalize =>
      role == AppRole.humanResources || role == AppRole.administrator,
  };
}
