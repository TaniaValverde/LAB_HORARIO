import 'package:flutter/material.dart';

import '../../schedule/domain/schedule.dart';

/// Displays the current form values without changing or persisting them.
class WeeklySchedule extends StatefulWidget {
  const WeeklySchedule({
    super.key,
    required this.appointments,
    required this.externalJobs,
  });

  final List<Appointment> appointments;
  final List<Appointment> externalJobs;

  @override
  State<WeeklySchedule> createState() => _WeeklyScheduleState();
}

class _WeeklyScheduleState extends State<WeeklySchedule> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final entries = [
      for (final job in widget.appointments)
        for (final block in job.blocks)
          (job: job, block: block, external: false),
      for (final job in widget.externalJobs)
        for (final block in job.blocks)
          (job: job, block: block, external: true),
    ]..sort((a, b) => a.block.start.compareTo(b.block.start));

    if (entries.isEmpty) {
      return const Text(
        'Agregue bloques en los nombramientos para ver aquí su horario semanal.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Se actualiza al aplicar o eliminar un nombramiento. '
          'Se muestran todas las vigencias; consulte las fechas de cada bloque.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _legend(colors.primaryContainer, 'Clases / institucional'),
            _legend(colors.secondaryContainer, 'Consultas'),
            _legend(colors.tertiaryContainer, 'Otra institución'),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 640) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var day = 1; day <= 6; day++)
                    _mobileDay(day, entries, colors),
                ],
              );
            }
            final availableWidth = constraints.maxWidth - 16;
            final width = availableWidth < 1056 ? 1056.0 : availableWidth;
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 440),
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context)
                    .copyWith(scrollbars: false),
                child: Scrollbar(
                  controller: _vertical,
                  thumbVisibility: true,
                  trackVisibility: true,
                  interactive: true,
                  notificationPredicate: (notice) =>
                      notice.metrics.axis == Axis.vertical,
                  child: Scrollbar(
                    controller: _horizontal,
                    thumbVisibility: true,
                    trackVisibility: true,
                    interactive: true,
                    scrollbarOrientation: ScrollbarOrientation.bottom,
                    notificationPredicate: (notice) =>
                        notice.metrics.axis == Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: _vertical,
                      primary: false,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16, bottom: 16),
                        child: SingleChildScrollView(
                          controller: _horizontal,
                          primary: false,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: width,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var day = 1; day <= 6; day++)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: colors
                                                  .surfaceContainerHighest,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              dayNames[day - 1],
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall,
                                            ),
                                          ),
                                          if (!entries.any(
                                            (e) => e.block.day == day,
                                          ))
                                            const Padding(
                                              padding: EdgeInsets.all(12),
                                              child: Text('Sin bloques'),
                                            ),
                                          for (final entry in entries.where(
                                            (e) => e.block.day == day,
                                          ))
                                            Container(
                                              margin: const EdgeInsets.only(
                                                top: 8,
                                              ),
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: entry.external
                                                    ? colors.tertiaryContainer
                                                    : entry.block.activity ==
                                                          ScheduleActivity
                                                              .consultation
                                                    ? colors.secondaryContainer
                                                    : colors.primaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: DefaultTextStyle.merge(
                                                style: TextStyle(
                                                  color: entry.external
                                                      ? colors
                                                            .onTertiaryContainer
                                                      : entry.block.activity ==
                                                            ScheduleActivity
                                                                .consultation
                                                      ? colors
                                                            .onSecondaryContainer
                                                      : colors
                                                            .onPrimaryContainer,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '${timeText(entry.block.start)}–${timeText(entry.block.end)}',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    if (entry.block.activity !=
                                                        null)
                                                      Text(
                                                        entry
                                                            .block
                                                            .activity!
                                                            .label,
                                                      ),
                                                    Text(
                                                      entry.external
                                                          ? entry
                                                                .job
                                                                .institution
                                                          : entry.job.workplace,
                                                    ),
                                                    Text(entry.job.position),
                                                    if (entry.job.courseCode !=
                                                        null)
                                                      Text(
                                                        'Curso: ${entry.job.courseCode}',
                                                      ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      '${dateText(entry.job.startsOn)}\na ${dateText(entry.job.endsOn)}',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _mobileDay(
    int day,
    List<({Appointment job, ScheduleBlock block, bool external})> entries,
    ColorScheme colors,
  ) {
    final dayEntries = entries.where((e) => e.block.day == day);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                dayNames[day - 1],
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (dayEntries.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Sin bloques'),
              ),
            for (final entry in dayEntries)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: entry.external
                      ? colors.tertiaryContainer
                      : entry.block.activity == ScheduleActivity.consultation
                      ? colors.secondaryContainer
                      : colors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    color: entry.external
                        ? colors.onTertiaryContainer
                        : entry.block.activity == ScheduleActivity.consultation
                        ? colors.onSecondaryContainer
                        : colors.onPrimaryContainer,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${timeText(entry.block.start)}–${timeText(entry.block.end)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (entry.block.activity != null)
                        Text(entry.block.activity!.label),
                      Text(
                        entry.external
                            ? entry.job.institution
                            : entry.job.workplace,
                      ),
                      Text(entry.job.position),
                      if (entry.job.courseCode != null)
                        Text('Curso: ${entry.job.courseCode}'),
                      Text(
                        '${dateText(entry.job.startsOn)} a ${dateText(entry.job.endsOn)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.square_rounded, size: 16, color: color),
      const SizedBox(width: 6),
      Text(label),
    ],
  );
}
