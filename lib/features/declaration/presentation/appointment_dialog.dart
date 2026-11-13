import 'package:flutter/material.dart';

import '../../schedule/domain/schedule.dart';
import 'time_input_formatter.dart';
import 'date_input_formatter.dart';

class AppointmentDialog extends StatefulWidget {
  const AppointmentDialog({super.key, required this.external, this.initial});
  final bool external;
  final Appointment? initial;
  @override
  State<AppointmentDialog> createState() => _AppointmentDialogState();
}

class _BlockInput {
  _BlockInput([ScheduleBlock? b])
    : day = b?.day ?? 1,
      activity = b?.activity ?? ScheduleActivity.teaching,
      start = TextEditingController(text: b == null ? '' : timeText(b.start)),
      end = TextEditingController(text: b == null ? '' : timeText(b.end));
  int day;
  ScheduleActivity activity;
  final TextEditingController start;
  final TextEditingController end;
  void dispose() {
    start.dispose();
    end.dispose();
  }
}

class _AppointmentDialogState extends State<AppointmentDialog> {
  final _key = GlobalKey<FormState>();
  late final _institution = TextEditingController(
    text: widget.initial?.institution ?? '',
  );
  late final _place = TextEditingController(
    text: widget.initial?.workplace ?? '',
  );
  late final _position = TextEditingController(
    text: widget.initial?.position ?? '',
  );
  late final _courseCode = TextEditingController(
    text: widget.initial?.courseCode ?? '',
  );
  late final _hours = TextEditingController(
    text: widget.initial == null ? '' : '${widget.initial!.weeklyMinutes / 60}',
  );
  late final _start = TextEditingController(
    text: widget.initial == null ? '' : dateText(widget.initial!.startsOn),
  );
  late final _end = TextEditingController(
    text: widget.initial == null ? '' : dateText(widget.initial!.endsOn),
  );
  late final _blocks =
      widget.initial?.blocks.map((b) => _BlockInput(b)).toList() ??
      <_BlockInput>[];
  String? _error;
  late WorkloadType? _workloadType = widget.initial?.workloadType;
  late bool _legacy = widget.initial != null && _workloadType == null;
  bool get _teaching => !widget.external && !_legacy;
  static const _categories = ['Interino', 'En propiedad'];
  @override
  void dispose() {
    for (final c in [
      _institution,
      _place,
      _position,
      _courseCode,
      _hours,
      _start,
      _end,
    ]) {
      c.dispose();
    }
    for (final b in _blocks) {
      b.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_key.currentState!.validate()) return;
    if (_blocks.isEmpty) {
      setState(() => _error = 'Agregue al menos un bloque horario.');
      return;
    }
    Navigator.pop(
      context,
      Appointment(
        id:
            widget.initial?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        workplace: _place.text.trim(),
        position: _position.text.trim(),
        courseCode: widget.external || _courseCode.text.trim().isEmpty
            ? null
            : _courseCode.text.trim(),
        institution: widget.external ? _institution.text.trim() : '',
        weeklyMinutes: _teaching
            ? _workloadType!.minutes
            : (double.parse(_hours.text.replaceAll(',', '.')) * 60).round(),
        workloadType: _teaching ? _workloadType : null,
        startsOn: parseDate(_start.text)!,
        endsOn: parseDate(_end.text)!,
        blocks: _blocks
            .map(
              (b) => ScheduleBlock(
                day: b.day,
                start: parseTime(b.start.text)!,
                end: parseTime(b.end.text)!,
                activity: _teaching ? b.activity : null,
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.external ? 'Horario en otra institución' : 'Nombramiento',
    ),
    content: SizedBox(
      width: 650,
      child: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.external) _text(_institution, 'Institución'),
              _text(_place, 'Lugar de trabajo'),
              if (!widget.external)
                _text(
                  _courseCode,
                  'Sigla del curso (opcional)',
                  hint: 'Ej.: IF0009',
                  validator: (value) => (value ?? '').trim().length > 40
                      ? 'Ingrese una sigla de hasta 40 caracteres.'
                      : null,
                ),
              if (widget.external)
                _text(_position, 'Cargo o categoría')
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    initialValue: _categories.contains(_position.text)
                        ? _position.text
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Categoría',
                      helperText:
                          widget.initial != null &&
                              !_categories.contains(widget.initial!.position)
                          ? 'Categoría anterior: ${widget.initial!.position}. Seleccione una categoría para aplicar cambios.'
                          : null,
                      helperMaxLines: 3,
                    ),
                    items: [
                      for (final category in _categories)
                        DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ),
                    ],
                    validator: (value) =>
                        value == null ? 'Seleccione una categoría.' : null,
                    onChanged: (value) => _position.text = value ?? '',
                  ),
                ),
              if (_teaching)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<WorkloadType>(
                    initialValue: _workloadType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de jornada',
                    ),
                    items: [
                      for (final type in WorkloadType.values)
                        DropdownMenuItem(
                          value: type,
                          child: Text(
                            '${type.label} · ${durationText(type.minutes)}/semana',
                          ),
                        ),
                    ],
                    validator: (value) =>
                        value == null ? 'Seleccione el tipo de jornada.' : null,
                    onChanged: (value) => setState(() => _workloadType = value),
                  ),
                ),
              if (!_teaching)
                _text(
                  _hours,
                  'Jornada pactada (horas semanales)',
                  validator: (v) {
                    final h = double.tryParse((v ?? '').replaceAll(',', '.'));
                    return h == null ||
                            !h.isFinite ||
                            h <= 0 ||
                            h > 60 ||
                            (h * 60 - (h * 60).round()).abs() > 0.00001
                        ? 'Ingrese de 0 a 60 horas, con precisión de minutos.'
                        : null;
                  },
                ),
              if (!widget.external && _legacy)
                TextButton(
                  onPressed: () => setState(() => _legacy = false),
                  child: const Text('Cambiar a jornada con clases y consultas'),
                ),
              if (_teaching && _workloadType != null) _workloadSummary(),
              _text(
                _start,
                'Inicio de vigencia (AAAA-MM-DD)',
                isDate: true,
                validator: (v) => parseDate(v ?? '') == null
                    ? 'Fecha inválida, use AAAA-MM-DD.'
                    : null,
              ),
              _text(
                _end,
                'Fin de vigencia (AAAA-MM-DD)',
                isDate: true,
                validator: (v) {
                  final d = parseDate(v ?? '');
                  final s = parseDate(_start.text);
                  return d == null || (s != null && d.isBefore(s))
                      ? 'Ingrese una fecha válida, igual o posterior al inicio.'
                      : null;
                },
              ),
              const Text(
                'Bloques semanales · Use formato de 24 horas. Escriba 0800 para obtener 08:00; los dos puntos se agregan automáticamente. El almuerzo debe quedar fuera de los bloques.',
              ),
              for (final b in _blocks)
                Padding(
                  key: ObjectKey(b),
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: b.day,
                        decoration: const InputDecoration(labelText: 'Día'),
                        items: [
                          for (var day = 1; day <= 6; day++)
                            DropdownMenuItem(
                              value: day,
                              child: Text(dayNames[day - 1]),
                            ),
                        ],
                        onChanged: (d) => setState(() => b.day = d!),
                      ),
                      const SizedBox(height: 10),
                      if (_teaching) ...[
                        DropdownButtonFormField<ScheduleActivity>(
                          initialValue: b.activity,
                          decoration: const InputDecoration(
                            labelText: 'Actividad',
                          ),
                          items: [
                            for (final activity in ScheduleActivity.values)
                              DropdownMenuItem(
                                value: activity,
                                child: Text(activity.label),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => b.activity = value!),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _text(
                              b.start,
                              'Inicio HH:MM',
                              isTime: true,
                              validator: (v) => parseTime(v ?? '') == null
                                  ? 'Hora inválida.'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _text(
                              b.end,
                              'Fin HH:MM',
                              isTime: true,
                              validator: (v) {
                                final end = parseTime(v ?? '');
                                final start = parseTime(b.start.text);
                                return end == null ||
                                        (start != null && end <= start)
                                    ? 'Debe ser posterior al inicio.'
                                    : null;
                              },
                            ),
                          ),
                          IconButton(
                            tooltip: 'Eliminar bloque',
                            onPressed: () {
                              setState(() => _blocks.remove(b));
                              WidgetsBinding.instance.addPostFrameCallback(
                                (_) => b.dispose(),
                              );
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: () => setState(() => _blocks.add(_BlockInput())),
                icon: const Icon(Icons.add),
                label: const Text('Agregar bloque'),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _submit,
        child: const Text('Aplicar al formulario'),
      ),
    ],
  );
  Widget _workloadSummary() {
    final workload = _workloadType!;
    int minutes(ScheduleActivity activity) =>
        _blocks.where((b) => b.activity == activity).fold(0, (total, b) {
          final start = parseTime(b.start.text);
          final end = parseTime(b.end.text);
          return total +
              (start != null && end != null && end > start ? end - start : 0);
        });
    final teaching = minutes(ScheduleActivity.teaching);
    final consultation = minutes(ScheduleActivity.consultation);
    final limit = (teaching ~/ 2).clamp(0, workload.consultationMinutes);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Clases: ${durationText(teaching)} de ${durationText(workload.teachingMinutes)}',
          ),
          Text(
            'Consultas: ${durationText(consultation)} de ${durationText(workload.consultationMinutes)}',
          ),
          Text(
            'Límite de consultas según las clases registradas: ${durationText(limit)}.',
          ),
          Text(
            'Total registrado: ${durationText(teaching + consultation)} de ${durationText(workload.minutes)}.',
          ),
          const Text(
            'Por cada hora de clase corresponden 30 minutos de consulta. Complete ambas cantidades para validar la declaración.',
          ),
          if (consultation > limit || teaching > workload.teachingMinutes)
            Text(
              'Las horas registradas superan el límite de clases o consultas.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }

  Widget _text(
    TextEditingController c,
    String label, {
    String? Function(String?)? validator,
    bool isTime = false,
    bool isDate = false,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c,
      decoration: InputDecoration(
        labelText: label,
        hintText:
            hint ??
            (isTime
                ? 'HH:MM'
                : isDate
                ? 'AAAA-MM-DD'
                : null),
      ),
      keyboardType: isTime || isDate ? TextInputType.number : null,
      inputFormatters: isTime
          ? [const TimeInputFormatter()]
          : isDate
          ? [const DateInputFormatter()]
          : null,
      onChanged: isTime ? (_) => setState(() {}) : null,
      validator:
          validator ??
          (v) => v == null || v.trim().isEmpty ? 'Campo obligatorio.' : null,
    ),
  );
}
