import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../declaration/domain/entities/declaration.dart';
import '../../declaration/domain/entities/declaration_form.dart';
import '../domain/schedule.dart';

typedef ScheduleEntry = ({Appointment job, ScheduleBlock block});

/// One shared paper layout for the screen, PNG and paginated PDF exports.
class ApprovedScheduleDocument {
  ApprovedScheduleDocument(this.declaration)
    : form = DeclarationForm.fromMap(declaration.payload);

  final Declaration declaration;
  final DeclarationForm form;
  static const width = 1440.0;
  static const header = 210.0;
  static const rowHeight = 190.0;
  static const rowsPerPage = 4;

  List<ScheduleEntry> entries(int day) => [
    for (final job in form.appointments)
      for (final block in job.blocks)
        if (block.day == day) (job: job, block: block),
  ]..sort((a, b) => a.block.start.compareTo(b.block.start));

  int get rows => math.max(
    1,
    [for (var day = 1; day <= 6; day++) entries(day).length].reduce(math.max),
  );
  int get pages => (rows / rowsPerPage).ceil();
  Size get size => Size(width, header + rows * rowHeight + 55);
  Size get pageSize => const Size(width, header + rowsPerPage * rowHeight + 55);
}

class ApprovedSchedulePainter extends CustomPainter {
  ApprovedSchedulePainter(this.document, {this.page});
  final ApprovedScheduleDocument document;
  final int? page;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    void text(
      String value,
      double x,
      double y,
      double width, {
      double font = 17,
      Color color = const Color(0xFF243447),
      bool bold = false,
      int lines = 2,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: font,
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: lines,
        ellipsis: '…',
      )..layout(maxWidth: width);
      painter.paint(canvas, Offset(x, y));
    }

    text('MI HORARIO APROBADO', 24, 22, 1360, font: 30, bold: true);
    text(document.form.profile.name, 24, 67, 1360, font: 22);
    text(
      'Período: ${document.declaration.periodId} · Versión ${document.declaration.version} · Aprobación del superior: ${dateText(document.declaration.superiorSignedAt!.toLocal())}',
      24,
      105,
      1360,
    );
    text(
      'Nombramientos institucionales · Clases y consultas · Consulte la vigencia de cada bloque.',
      24,
      137,
      1360,
      font: 16,
    );
    const gap = 10.0;
    const column = (ApprovedScheduleDocument.width - 48 - gap * 5) / 6;
    for (var day = 1; day <= 6; day++) {
      final x = 24 + (day - 1) * (column + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 175, column, 30),
          const Radius.circular(6),
        ),
        Paint()..color = const Color(0xFF173B60),
      );
      text(
        dayNames[day - 1],
        x + 10,
        180,
        column - 20,
        color: Colors.white,
        bold: true,
      );
      final all = document.entries(day);
      final start = page == null
          ? 0
          : page! * ApprovedScheduleDocument.rowsPerPage;
      final visible = page == null
          ? all
          : all.skip(start).take(ApprovedScheduleDocument.rowsPerPage).toList();
      if (visible.isEmpty) {
        text(
          all.isEmpty ? 'Sin bloques' : 'Sin más bloques',
          x + 10,
          230,
          column - 20,
        );
      }
      for (var i = 0; i < visible.length; i++) {
        final entry = visible[i];
        final y =
            ApprovedScheduleDocument.header +
            i * ApprovedScheduleDocument.rowHeight;
        final consultation =
            entry.block.activity == ScheduleActivity.consultation;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, column, 180),
            const Radius.circular(8),
          ),
          Paint()
            ..color = consultation
                ? const Color(0xFFE4F3EC)
                : const Color(0xFFE8F0FC),
        );
        text(
          '${timeText(entry.block.start)}–${timeText(entry.block.end)}',
          x + 10,
          y + 10,
          column - 20,
          font: 21,
          bold: true,
        );
        text(
          entry.block.activity?.label ?? 'Institucional',
          x + 10,
          y + 42,
          column - 20,
          font: 14,
          bold: true,
        );
        text(
          entry.job.courseCode ?? 'Sin sigla registrada',
          x + 10,
          y + 63,
          column - 20,
          font: 16,
          bold: true,
        );
        text(entry.job.workplace, x + 10, y + 105, column - 20, font: 14);
        text(
          entry.job.position,
          x + 10,
          y + 141,
          column - 20,
          font: 13,
          lines: 1,
        );
        text(
          '${dateText(entry.job.startsOn)} a ${dateText(entry.job.endsOn)}',
          x + 10,
          y + 161,
          column - 20,
          font: 12,
          lines: 1,
        );
      }
    }
    text(
      'Copia visual del horario aprobado. No sustituye el PDF final de la declaración.${page == null ? '' : ' · Página ${page! + 1}/${document.pages}'}',
      24,
      size.height - 32,
      1380,
      font: 14,
    );
  }

  @override
  bool shouldRepaint(covariant ApprovedSchedulePainter oldDelegate) =>
      oldDelegate.document != document || oldDelegate.page != page;
}
