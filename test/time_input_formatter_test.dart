import 'package:declara_horario/features/declaration/presentation/time_input_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const formatter = TimeInputFormatter();
  TextEditingValue value(String text, [int? cursor]) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: cursor ?? text.length),
  );

  test(
    'Typing digits inserts the separator and keeps the cursor at the end',
    () {
      var current = value('');
      for (final digit in '0800'.split('')) {
        current = formatter.formatEditUpdate(
          current,
          value('${current.text}$digit'),
        );
        expect(current.selection.baseOffset, current.text.length);
      }
      expect(current.text, '08:00');
    },
  );

  test('Pasting accepts both compact and formatted times', () {
    for (final input in ['1330', '13:30']) {
      expect(formatter.formatEditUpdate(value(''), value(input)).text, '13:30');
    }
  });

  test('Backspace can clear the entire field including the separator', () {
    var current = value('08:00');
    for (final expected in ['08:0', '08:', '0', '']) {
      current = formatter.formatEditUpdate(
        current,
        value(current.text.substring(0, current.text.length - 1)),
      );
      expect(current.text, expected);
      expect(current.selection.baseOffset, expected.length);
    }
  });

  test('Replacing hours preserves minutes and the cursor position', () {
    final result = formatter.formatEditUpdate(
      const TextEditingValue(
        text: '08:30',
        selection: TextSelection(baseOffset: 0, extentOffset: 2),
      ),
      value('14:30', 2),
    );
    expect(result.text, '14:30');
    expect(result.selection.baseOffset, 3);
  });

  test(
    'Extra digits are rejected and invalid ranges remain for validation',
    () {
      expect(
        formatter.formatEditUpdate(value('08:00'), value('08:001')),
        value('08:00'),
      );
      expect(
        formatter.formatEditUpdate(value(''), value('2560')).text,
        '25:60',
      );
      expect(formatter.formatEditUpdate(value('08:00'), value('')).text, '');
    },
  );
}
