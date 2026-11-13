import '../../declaration/domain/entities/declaration.dart';

/// Contract for generating a final PDF and saving it to durable storage.
abstract interface class FinalDeclarationPdfGenerator {
  /// Returns the persistent path or URL of the stored PDF.
  Future<String> generateAndStore(Declaration declaration);
}

/// Simulated PDF implementation for the retained in-memory prototype.
class InMemoryFinalDeclarationPdfGenerator
    implements FinalDeclarationPdfGenerator {
  @override
  Future<String> generateAndStore(Declaration declaration) async =>
      'memory://declarations/${declaration.id}/final.pdf';
}
