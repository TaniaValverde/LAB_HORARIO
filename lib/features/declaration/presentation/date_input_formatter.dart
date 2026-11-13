import 'package:flutter/services.dart';

/// Inserts date separators while leaving calendar validation to the form.
class DateInputFormatter extends TextInputFormatter {
  const DateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    var text = newValue.text;
    var selection = newValue.selection;
    final cursor = oldValue.selection.baseOffset;

    // Backspace over an automatic separator must not trap the cursor there.
    if (oldValue.selection.isCollapsed &&
        selection.isCollapsed &&
        (cursor == 5 || cursor == 8) &&
        selection.baseOffset == cursor - 1 &&
        oldValue.text.length >= cursor &&
        oldValue.text[cursor - 1] == '-' &&
        text == oldValue.text.replaceRange(cursor - 1, cursor, '')) {
      text = text.replaceRange(cursor - 2, cursor - 1, '');
      selection = TextSelection.collapsed(offset: cursor - 2);
    }

    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 8) return oldValue;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if (i == 3 || i == 5) buffer.write('-');
    }
    final formatted = buffer.toString();
    int offset(int position) {
      if (position < 0) return formatted.length;
      final count = text
          .substring(0, position.clamp(0, text.length))
          .replaceAll(RegExp(r'[^0-9]'), '')
          .length;
      return count + (count >= 4 ? 1 : 0) + (count >= 6 ? 1 : 0);
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
