import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'approved_schedule_document.dart';

/// Produces local visual copies; never reads or writes the final PDF in Storage.
class ScheduleExport {
  Future<ui.Image> _render(
    ApprovedScheduleDocument document, {
    int? page,
  }) async {
    final size = page == null ? document.size : document.pageSize;
    final recorder = ui.PictureRecorder();
    ApprovedSchedulePainter(
      document,
      page: page,
    ).paint(ui.Canvas(recorder), size);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(size.width.ceil(), size.height.ceil());
    } finally {
      picture.dispose();
    }
  }

  Future<Uint8List> png(ApprovedScheduleDocument document) async {
    if (document.size.height > 16000) {
      throw StateError(
        'El horario es demasiado extenso para una imagen. Descárguelo en PDF.',
      );
    }
    final image = await _render(document);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw StateError('No se pudo generar la imagen del horario.');
      }
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      image.dispose();
    }
  }

  /// Embeds opaque RGB pages in a minimal PDF without platform-specific codecs.
  Future<Uint8List> pdf(ApprovedScheduleDocument document) async {
    final objects = <Uint8List>[];
    Uint8List ascii(String value) => Uint8List.fromList(asciiEncode(value));
    objects.add(ascii('<< /Type /Catalog /Pages 2 0 R >>'));
    final kids = [for (var i = 0; i < document.pages; i++) '${3 + i * 3} 0 R']
        .join(' ');
    objects.add(
      ascii('<< /Type /Pages /Kids [$kids] /Count ${document.pages} >>'),
    );
    for (var i = 0; i < document.pages; i++) {
      final image = await _render(document, page: i);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) {
          throw StateError('No se pudo generar una página del horario.');
        }
        final rgba = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final rgb = Uint8List(image.width * image.height * 3);
        for (int source = 0, target = 0; source < rgba.length; source += 4) {
          rgb[target++] = rgba[source];
          rgb[target++] = rgba[source + 1];
          rgb[target++] = rgba[source + 2];
        }
        final pageId = 3 + i * 3;
        objects.add(
          ascii(
            '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 842 595] /Resources << /XObject << /Schedule ${pageId + 2} 0 R >> >> /Contents ${pageId + 1} 0 R >>',
          ),
        );
        const commands = 'q 822 0 0 585 10 5 cm /Schedule Do Q';
        objects.add(
          ascii(
            '<< /Length ${commands.length} >>\nstream\n$commands\nendstream',
          ),
        );
        objects.add(
          (BytesBuilder(copy: false)
                ..add(
                  ascii(
                    '<< /Type /XObject /Subtype /Image /Width ${image.width} /Height ${image.height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Length ${rgb.length} >>\nstream\n',
                  ),
                )
                ..add(rgb)
                ..add(ascii('\nendstream')))
              .takeBytes(),
        );
      } finally {
        image.dispose();
      }
    }
    final result = BytesBuilder(copy: false)..add(ascii('%PDF-1.4\n'));
    final offsets = <int>[0];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(result.length);
      result
        ..add(ascii('${i + 1} 0 obj\n'))
        ..add(objects[i])
        ..add(ascii('\nendobj\n'));
    }
    final xref = result.length;
    result.add(ascii('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n'));
    for (final offset in offsets.skip(1)) {
      result.add(ascii('${offset.toString().padLeft(10, '0')} 00000 n \n'));
    }
    result.add(
      ascii(
        'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
      ),
    );
    return result.takeBytes();
  }
}

List<int> asciiEncode(String text) => ascii.encode(text);
