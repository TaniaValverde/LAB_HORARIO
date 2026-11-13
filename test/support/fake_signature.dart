import 'package:declara_horario/features/declaration/data/services/declarant_signature_service.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration.dart';

class FakeSignature implements DeclarantSignatureRepository {
  bool? confirmed;
  Declaration? signedDeclaration;

  @override
  Future<DeclarantSignatureResult> sign({
    required Declaration declaration,
    required bool explicitlyConfirmed,
  }) async {
    confirmed = explicitlyConfirmed;
    signedDeclaration = declaration;
    return DeclarantSignatureResult(
      declarationId: declaration.id,
      version: declaration.version,
      revision: declaration.revision + 1,
      signatureId:
          'declarantSignature_v${declaration.version}_r${declaration.revision + 1}',
      eventId:
          'declarantSigned_v${declaration.version}_r${declaration.revision + 1}',
      signedAt: DateTime.utc(2026, 10, 19, 12),
      alreadySigned: false,
    );
  }
}
