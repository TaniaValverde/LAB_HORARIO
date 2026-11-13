import '../entities/audit_event.dart';
import '../entities/declaration.dart';
import '../entities/declaration_form.dart';
import '../../../validation/domain/validate_schedule.dart';
import '../repositories/audit_repository.dart';
import '../repositories/declaration_repository.dart';
import '../../../roles/domain/entities/app_role.dart';
import '../../../roles/domain/usecases/authorize_declaration_action.dart';

/// Actions that can change a declaration workflow state.
enum DeclarationAction {
  validate,
  acceptOathAndSign,
  submitToSuperior,
  superiorSign,
  returnForCorrection,
  sendToHr,
  receiveAtHr,
  finalize,
}

/// Defined reasons for rejecting a workflow transition.
enum DeclarationFlowFailure {
  notFound,
  invalidTransition,
  oathRequired,
  signatureRequired,
  observationRequired,
  pdfRequired,
  roleNotAllowed,
  validationFailed,
}

/// Domain error raised during a workflow transition.
class DeclarationFlowException implements Exception {
  const DeclarationFlowException(this.reason);
  final DeclarationFlowFailure reason;
}

/// Validates prototype permissions/state, updates the declaration and records audit.
///
/// Repositories are injected for the prototype and domain tests.
/// The integrated application's privileged transitions use server callables.
class AdvanceDeclaration {
  const AdvanceDeclaration({
    required this.declarations,
    required this.audit,
    this.authorize = const AuthorizeDeclarationAction(),
  });

  final DeclarationRepository declarations;
  final AuditRepository audit;
  final AuthorizeDeclarationAction authorize;

  Future<Declaration> call({
    required String declarationId,
    required String actorId,
    required AppRole actorRole,
    required DeclarationAction action,
    bool acceptOath = false,
    String? signature,
    String? observation,
    String? pdfPath,
    DateTime? now,
  }) async {
    final declaration = await declarations.getById(declarationId);
    if (declaration == null) {
      throw const DeclarationFlowException(DeclarationFlowFailure.notFound);
    }
    if (!authorize(actorRole, action)) {
      throw const DeclarationFlowException(
        DeclarationFlowFailure.roleNotAllowed,
      );
    }
    final time = now ?? DateTime.now();
    Declaration updated;
    switch (action) {
      case DeclarationAction.validate:
        _requireStatus(declaration, DeclarationStatus.draft);
        if (actorId != declaration.personId ||
            !const ValidateSchedule()(
              DeclarationForm.fromMap(declaration.payload),
            ).valid) {
          throw const DeclarationFlowException(
            DeclarationFlowFailure.validationFailed,
          );
        }
        updated = declaration.copyWith(status: DeclarationStatus.validated);
      case DeclarationAction.acceptOathAndSign:
        _requireStatus(declaration, DeclarationStatus.validated);
        // The prototype combines oath and signature; the integrated app separates them.
        if (!acceptOath) {
          throw const DeclarationFlowException(
            DeclarationFlowFailure.oathRequired,
          );
        }
        if (signature == null || signature.trim().isEmpty) {
          throw const DeclarationFlowException(
            DeclarationFlowFailure.signatureRequired,
          );
        }
        updated = declaration.copyWith(
          status: DeclarationStatus.signedByDeclarant,
          oathAcceptedAt: time,
          declarantSignedAt: time,
          declarantSignature: signature.trim(),
        );
      case DeclarationAction.submitToSuperior:
        _requireStatus(declaration, DeclarationStatus.signedByDeclarant);
        updated = declaration.copyWith(
          status: DeclarationStatus.pendingSuperiorSignature,
        );
      case DeclarationAction.superiorSign:
        _requireStatus(declaration, DeclarationStatus.pendingSuperiorSignature);
        if (signature == null || signature.trim().isEmpty) {
          throw const DeclarationFlowException(
            DeclarationFlowFailure.signatureRequired,
          );
        }
        updated = declaration.copyWith(
          status: DeclarationStatus.signedBySuperior,
          superiorSignedAt: time,
          superiorSignature: signature.trim(),
        );
      case DeclarationAction.returnForCorrection:
        _requireStatus(declaration, DeclarationStatus.pendingSuperiorSignature);
        if (observation == null || observation.trim().isEmpty) {
          throw const DeclarationFlowException(
            DeclarationFlowFailure.observationRequired,
          );
        }
        updated = declaration.copyWith(
          status: DeclarationStatus.returned,
          returnObservation: observation.trim(),
        );
      case DeclarationAction.sendToHr:
        _requireStatus(declaration, DeclarationStatus.signedBySuperior);
        updated = declaration.copyWith(status: DeclarationStatus.sentToHr);
      case DeclarationAction.receiveAtHr:
        _requireStatus(declaration, DeclarationStatus.sentToHr);
        updated = declaration.copyWith(
          status: DeclarationStatus.receivedByHr,
          hrReceivedAt: time,
        );
      case DeclarationAction.finalize:
        _requireStatus(declaration, DeclarationStatus.receivedByHr);
        if (pdfPath == null || pdfPath.trim().isEmpty) {
          throw const DeclarationFlowException(
            DeclarationFlowFailure.pdfRequired,
          );
        }
        updated = declaration.copyWith(
          status: DeclarationStatus.finalized,
          finalizedAt: time,
          finalPdfPath: pdfPath.trim(),
        );
    }
    await declarations.update(updated);
    // Record the actor and action after persisting the prototype state.
    await audit.append(
      AuditEvent(
        id: '${declaration.id}_${time.microsecondsSinceEpoch}',
        declarationId: declaration.id,
        actorId: actorId,
        action: action.name,
        occurredAt: time,
        details: observation,
      ),
    );
    return updated;
  }

  /// Prevents skipping workflow steps or acting from an invalid state.
  void _requireStatus(Declaration declaration, DeclarationStatus expected) {
    if (declaration.status != expected) {
      throw const DeclarationFlowException(
        DeclarationFlowFailure.invalidTransition,
      );
    }
  }
}
