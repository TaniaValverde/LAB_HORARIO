import 'package:declara_horario/features/declaration/domain/entities/declaration.dart';
import 'package:declara_horario/features/declaration/domain/usecases/approved_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/approved_schedule_fixture.dart';

void main() {
  test(
    'Only superior-approved states with signature evidence are included',
    () {
      final result = approvedSchedules([
        for (final status in DeclarationStatus.values)
          scheduleFixture(period: status.name, status: status),
        scheduleFixture(period: 'unsigned', signed: false),
        scheduleFixture(person: 'someone-else', period: 'private'),
      ], 'owner');
      expect(
        result.map((d) => d.status),
        unorderedEquals([
          DeclarationStatus.signedBySuperior,
          DeclarationStatus.sentToHr,
          DeclarationStatus.receivedByHr,
          DeclarationStatus.finalized,
        ]),
      );
    },
  );

  test('Latest version wins and obsolete approvals never reappear', () {
    final first = scheduleFixture();
    final second = scheduleFixture(version: 2);
    expect(approvedSchedules([first, second], 'owner').single.id, second.id);
    expect(
      approvedSchedules([
        first,
        second.copyWith(status: DeclarationStatus.returned),
      ], 'owner'),
      isEmpty,
    );
    expect(
      approvedSchedules([
        first,
        second.copyWith(status: DeclarationStatus.annulled),
      ], 'owner'),
      isEmpty,
    );
  });
}
