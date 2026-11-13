import 'package:declara_horario/features/declaration/data/services/declarant_oath_service.dart';
import 'package:declara_horario/features/declaration/domain/entities/declaration.dart';

class FakeOath implements DeclarantOathRepository {
  ApprovedOath? text;
  Object? loadError;
  int loads = 0;
  int? acceptedTextVersion;
  Future<OathAcceptanceResult> Function(Declaration)? onAccept;

  @override
  Future<ApprovedOath?> loadApprovedText() async {
    loads++;
    if (loadError != null) throw loadError!;
    return text;
  }

  @override
  Future<OathAcceptanceResult> accept({
    required Declaration declaration,
    required bool explicitlyConfirmed,
    required int expectedOathTextVersion,
  }) async {
    if (!explicitlyConfirmed) throw StateError('Falta confirmación');
    acceptedTextVersion = expectedOathTextVersion;
    return onAccept!(declaration);
  }
}
