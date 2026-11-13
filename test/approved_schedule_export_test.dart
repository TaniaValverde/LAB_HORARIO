import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:declara_horario/features/schedule/presentation/approved_schedule_document.dart';
import 'package:declara_horario/features/schedule/presentation/schedule_export.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/approved_schedule_fixture.dart';

void main() {
  testWidgets('PNG includes the whole schedule and PDF paginates all rows', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const qa = bool.fromEnvironment('SCHEDULE_QA');
      if (qa && Platform.environment['SCHEDULE_QA_FONT'] != null) {
        final font = await File(Platform.environment['SCHEDULE_QA_FONT']!)
            .readAsBytes();
        await (FontLoader(
          'Roboto',
        )..addFont(Future.value(ByteData.sublistView(font)))).load();
      }
      final document = ApprovedScheduleDocument(scheduleFixture(rows: 6));
      final exporter = ScheduleExport();
      final png = await exporter.png(document);
      expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, document.size.width.toInt());
      expect(frame.image.height, document.size.height.toInt());
      expect(frame.image.height, greaterThan(560));
      frame.image.dispose();
      codec.dispose();
      final pdf = await exporter.pdf(document);
      expect(ascii.decode(pdf.take(8).toList()), '%PDF-1.4');
      final raw = latin1.decode(pdf);
      expect(raw, contains('/Count 2'));
      expect(RegExp(r'/Type /Page ').allMatches(raw).length, 2);
      final xref = int.parse(
        RegExp(r'startxref\n(\d+)').firstMatch(raw)!.group(1)!,
      );
      expect(ascii.decode(pdf.sublist(xref, xref + 4)), 'xref');
      if (qa) {
        await Directory('build/schedule-qa').create(recursive: true);
        await File('build/schedule-qa/horario.png').writeAsBytes(png);
        await File('build/schedule-qa/horario.pdf').writeAsBytes(pdf);
      }
    });
  });
}
