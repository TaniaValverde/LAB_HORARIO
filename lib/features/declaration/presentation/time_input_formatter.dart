import 'package:flutter/services.dart';

/// Formats four digits as HH:MM; range validation belongs to the form.
class TimeInputFormatter extends TextInputFormatter {
  const TimeInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    var text = newValue.text;
    var selection = newValue.selection;

    // Backspace over the generated separator also removes the preceding digit.
    if (oldValue.selection.isCollapsed &&
        selection.isCollapsed &&
        oldValue.selection.baseOffset == 3 &&
        selection.baseOffset == 2 &&
        oldValue.text.length >= 3 &&
        oldValue.text[2] == ':' &&
        text == oldValue.text.replaceRange(2, 3, '')) {
      text = text.replaceRange(1, 2, '');
      selection = const TextSelection.collapsed(offset: 1);
    }

    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 4) return oldValue;
    final formatted = digits.length >= 2
        ? '${digits.substring(0, 2)}:${digits.substring(2)}'
        : digits;

    int offset(int position) {
      if (position < 0) return formatted.length;
      final count = text
          .substring(0, position.clamp(0, text.length))
          .replaceAll(RegExp(r'[^0-9]'), '')
          .length;
      return count >= 2 ? count + 1 : count;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection(
        baseOffset: offset(selection.baseOffset),
        extentOffset: offset(selection.extentOffset),
        affinity: selection.affinity,
        isDirectional: selection.isDirectional,
      ),
    );
  }
}
