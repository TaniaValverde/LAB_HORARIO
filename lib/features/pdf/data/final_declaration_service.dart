import 'dart:convert';

import 'pdf_download_unsupported.dart'
    if (dart.library.html) 'pdf_download_web.dart'
    as platform_download;

import 'package:cloud_functions/cloud_functions.dart';

import '../../declaration/domain/entities/declaration.dart';

/// Client for the Cloud Functions that handle the final PDF of a declaration:
/// generation, download and finalization.
///
/// The PDF is produced and stored server-side. This class only sends the
/// requests and delivers the downloaded file to the browser. The server
/// performs the authoritative validation of roles and state.
///
/// `generate` and `finalize` send `expectedVersion` and `expectedRevision` as
/// optimistic-concurrency guards, so the server can reject the request if the
/// declaration changed after it was read.
class FinalDeclarationService {
  FinalDeclarationService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Asks the server to generate the final PDF for the signed version of
  /// [declaration] and link it to that version.
  Future<void> generate(Declaration declaration) async {
    await _functions.httpsCallable('generateFinalDeclarationPdf').call({
      'declarationId': declaration.id,
      'expectedVersion': declaration.version,
      'expectedRevision': declaration.revision,
      'confirmed': true,
    });
  }

  /// Closes the process, moving a received declaration with a final PDF to its
  /// finalized state.
  Future<void> finalize(Declaration declaration) async {
    await _functions.httpsCallable('finalizeDeclaration').call({
      'declarationId': declaration.id,
      'expectedVersion': declaration.version,
      'expectedRevision': declaration.revision,
      'confirmed': true,
    });
  }

  /// Downloads the final PDF of [declaration] and hands it to the browser.
  ///
  /// The server returns the file as a base64 string inside the callable
  /// response. Throws a [FormatException] if the response does not have the
  /// expected shape. The save step is platform-specific, selected through a
  /// conditional import: it works on web and is unsupported elsewhere.
  Future<void> download(Declaration declaration) async {
    final response = await _functions
        .httpsCallable('downloadFinalDeclarationPdf')
        .call({
          'declarationId': declaration.id,
          'expectedVersion': declaration.version,
        });
    final value = response.data;
    if (value is! Map ||
        value['base64'] is! String ||
        value['fileName'] is! String) {
      throw const FormatException('El servidor no devolvió un PDF válido.');
    }
    final bytes = base64Decode(value['base64'] as String);
    await platform_download.downloadPdf(bytes, value['fileName'] as String);
  }
}
