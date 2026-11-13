import 'package:declara_horario/features/declaration/presentation/date_input_formatter.dart';
import 'package:declara_horario/features/schedule/domain/schedule.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const formatter = DateInputFormatter();
  TextEditingValue value(String text, [int? cursor]) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: cursor ?? text.length),
  );

  test('Typing adds both separators and advances the cursor', () {
    var current = value('');
    final expected = [
      '2',
      '20',
      '202',
      '2026-',
      '2026-1',
      '2026-10-',
      '2026-10-2',
      '2026-10-28',
    ];
    for (var i = 0; i < 8; i++) {
      current = formatter.formatEditUpdate(
        current,
        value('${current.text}${'20261028'[i]}'),
      );
      expect(current.text, expected[i]);
      expect(current.selection.baseOffset, current.text.length);
    }
  });

  test('Backspace clears the date across both separators', () {
    var current = value('2026-10-28');
    for (final expected in [
      '2026-10-2',
      '2026-10-',
      '2026-1',
      '2026-',
      '202',
      '20',
      '2',
      '',
    ]) {
      current = formatter.formatEditUpdate(
        current,
        value(current.text.substring(0, current.text.length - 1)),
      );
      expect(current.text, expected);
      expect(current.selection.baseOffset, current.text.length);
    }
  });

  test('Pasting accepts compact and formatted dates', () {
    for (final text in ['20261028', '2026-10-28']) {
      expect(
        formatter.formatEditUpdate(value(''), value(text)).text,
        '2026-10-28',
      );
    }
  });

  test('Replacing month preserves the day and cursor', () {
    final result = formatter.formatEditUpdate(
      const TextEditingValue(
        text: '2026-10-28',
        selection: TextSelection(baseOffset: 5, extentOffset: 7),
      ),
      value('2026-11-28', 7),
    );
    expect(result.text, '2026-11-28');
    expect(result.selection.baseOffset, 8);
    expect(formatter.formatEditUpdate(result, value('')).text, '');
  });

  test('Extra digits are rejected and calendar validation remains intact', () {
    final old = value('2026-10-28');
    expect(formatter.formatEditUpdate(old, value('2026-10-280')), old);
    expect(
      parseDate(formatter.formatEditUpdate(value(''), value('20260230')).text),
      isNull,
    );
    expect(
      parseDate(formatter.formatEditUpdate(value(''), value('20240229')).text),
      DateTime(2024, 2, 29),
    );
  });
}
