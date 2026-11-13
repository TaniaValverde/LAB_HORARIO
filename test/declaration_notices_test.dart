import 'package:flutter_test/flutter_test.dart';
import 'package:declara_horario/features/realtime/declaration_notices.dart';

void main() {
  test('accepts known status and rejects malformed socket messages', () {
    final data = {
      'id': 'my-declaration',
      'version': 1,
      'revision': 3,
      'status': 'returned',
    };
    expect(parseDeclarationNotice(data), contains('DEVUELTA'));
    expect(parseDeclarationNotice({...data, 'status': 'unknown'}), isNull);
    expect(parseDeclarationNotice({...data, 'revision': '3'}), isNull);
    expect(parseDeclarationNotice(null), isNull);
    expect(parseDeclarationNotice({...data, 'id': ''}), isNull);
  });
}
