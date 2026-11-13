import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Downloads a PDF file in the browser using the provided byte data.
///
/// Creates a browser [web.Blob] with the PDF content, generates a temporary
/// object URL and triggers the download through a hidden anchor element.
/// The anchor is removed and the object URL is revoked after the download
/// is triggered.
Future<void> downloadPdf(Uint8List bytes, String fileName) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
