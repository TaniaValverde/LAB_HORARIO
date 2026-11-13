type JsonMap = Record<string, unknown>;
type ValidationResult = { valid: true } | { valid: false; reason: string };

function isMap(value: unknown): value is JsonMap {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function hasOnlyKeys(value: JsonMap, allowed: string[]): boolean {
  return Object.keys(value).every((key) => allowed.includes(key));
}

/** Mirrors the pure ValidateSchedule rules without importing Flutter code. */
export function validateSchedulePayload(value: unknown): ValidationResult {
  if (!isMap(value) || !hasOnlyKeys(value, [
    'schemaVersion', 'profile', 'appointments', 'externalJobs', 'observations',
  ]) || value.schemaVersion !== 1 || !isMap(value.profile) ||
      !Array.isArray(value.appointments) || !Array.isArray(value.externalJobs) ||
      typeof value.observations !== 'string' || value.observations.length > 10000 ||
      value.appointments.length > 50 || value.externalJobs.length > 50) {
    return { valid: false, reason: 'El contenido no corresponde al formulario v1.' };
  }

  const profile = value.profile;
  const profileKeys = ['name', 'identification', 'phone', 'email', 'unit'];
  if (!hasOnlyKeys(profile, profileKeys) || profileKeys.some((key) =>
    typeof profile[key] !== 'string' || !(profile[key] as string).trim())) {
    return { valid: false, reason: 'El perfil de la declaración está incompleto.' };
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(profile.email as string)) {
    return { valid: false, reason: 'El correo de contacto no es válido.' };
  }
  if (value.appointments.length === 0) {
    return { valid: false, reason: 'Agregue al menos un nombramiento institucional.' };
  }

  const jobs: Array<{ start: number; end: number; blocks: Array<{day: number; start: number; end: number}> }> = [];
  const entries: Array<{ job: number; day: number; start: number; end: number; from: number; until: number }> = [];
  const sources = [...value.appointments.map((job) => ({ job, external: false })),
    ...value.externalJobs.map((job) => ({ job, external: true }))];

  for (let index = 0; index < sources.length; index++) {
    const { job: raw, external } = sources[index];
    if (!isMap(raw) || !hasOnlyKeys(raw, [
      'id', 'workplace', 'position', 'weeklyMinutes', 'startsOn', 'endsOn', 'institution', 'blocks', 'workloadType', 'courseCode',
    ]) || typeof raw.workplace !== 'string' || typeof raw.position !== 'string' ||
        typeof raw.institution !== 'string' || typeof raw.id !== 'string' ||
        !Number.isInteger(raw.weeklyMinutes) || !Array.isArray(raw.blocks)) {
      return { valid: false, reason: 'Un nombramiento tiene una estructura inválida.' };
    }
    if (!raw.workplace.trim() || !raw.position.trim() ||
        (external && !raw.institution.trim())) {
      return { valid: false, reason: 'Complete institución/lugar y cargo.' };
    }
    const weeklyMinutes = raw.weeklyMinutes as number;
    if (Object.prototype.hasOwnProperty.call(raw, 'courseCode') &&
        (external || typeof raw.courseCode !== 'string' || !raw.courseCode.trim() || raw.courseCode.length > 40)) {
      return { valid: false, reason: 'La sigla debe tener de 1 a 40 caracteres y pertenecer a un nombramiento institucional.' };
    }
    // Optional teaching fields extend v1 without reinterpreting legacy signatures.
    const teaching = Object.prototype.hasOwnProperty.call(raw, 'workloadType');
    const workloads: Record<string, number> = { fullTime: 2400, halfTime: 1200, quarterTime: 600 };
    if (teaching && (external || typeof raw.workloadType !== 'string' ||
        !Object.prototype.hasOwnProperty.call(workloads, raw.workloadType) ||
        weeklyMinutes !== workloads[raw.workloadType])) {
      return { valid: false, reason: 'El tipo de jornada docente debe ser institucional y coincidir con las horas pactadas.' };
    }
    if (weeklyMinutes <= 0 || weeklyMinutes > 3600) {
      return { valid: false, reason: 'La jornada debe ser mayor a 0 y como máximo 60 horas semanales.' };
    }
    const from = parseDate(raw.startsOn);
    const until = parseDate(raw.endsOn);
    if (from === null || until === null || until < from) {
      return { valid: false, reason: 'La fecha final debe ser igual o posterior a la inicial.' };
    }
    if (raw.blocks.length === 0) {
      return { valid: false, reason: 'Agregue bloques horarios.' };
    }
    let total = 0;
    let teachingMinutes = 0;
    let consultationMinutes = 0;
    const blocks: Array<{day: number; start: number; end: number}> = [];
    for (const rawBlock of raw.blocks) {
      if (!isMap(rawBlock) || !hasOnlyKeys(rawBlock, teaching ? ['day', 'start', 'end', 'activity'] : ['day', 'start', 'end']) ||
          !Number.isInteger(rawBlock.day) || !Number.isInteger(rawBlock.start) ||
          !Number.isInteger(rawBlock.end)) {
        return { valid: false, reason: 'Un bloque horario tiene una estructura inválida.' };
      }
      const day = rawBlock.day as number;
      const start = rawBlock.start as number;
      const end = rawBlock.end as number;
      if (teaching) {
        if (rawBlock.activity !== 'teaching' && rawBlock.activity !== 'consultation') {
          return { valid: false, reason: 'Clasifique cada bloque docente como clase o consulta.' };
        }
        if (rawBlock.activity === 'teaching') teachingMinutes += end - start;
        else consultationMinutes += end - start;
      }
      if (day < 1 || day > 6 || start < 0 || end > 1440 || end <= start) {
        return { valid: false, reason: 'Día u horas inválidas; la hora final debe ser posterior a la inicial.' };
      }
      if (start < 780 && end > 720) {
        return { valid: false, reason: 'El intervalo de 12:00 a 13:00 está excluido.' };
      }
      total += end - start;
      blocks.push({ day, start, end });
      entries.push({ job: index, day, start, end, from, until });
    }
    if (total !== weeklyMinutes) {
      return { valid: false, reason: 'La suma de bloques debe coincidir con las horas semanales pactadas.' };
    }
    if (teaching && (consultationMinutes * 2 !== teachingMinutes ||
        consultationMinutes !== weeklyMinutes / 3)) {
      return { valid: false, reason: 'La jornada debe completarse con clases y 30 minutos de consulta por cada hora de clase.' };
    }
    jobs.push({ start: from, end: until, blocks });
  }

  for (let i = 0; i < entries.length; i++) {
    for (let j = i + 1; j < entries.length; j++) {
      const a = entries[i];
      const b = entries[j];
      if (a.day !== b.day || Math.max(a.start, b.start) >= Math.min(a.end, b.end)) continue;
      const from = Math.max(a.from, b.from);
      const until = Math.min(a.until, b.until);
      if (from <= until && hasWeekday(from, until, a.day)) {
        return { valid: false, reason: 'Hay bloques horarios que se traslapan durante vigencias coincidentes.' };
      }
    }
  }

  for (let day = 1; day <= 6; day++) {
    const boundaries = [...new Set(jobs.flatMap((job) => [job.start, job.end + 1]))].sort((a, b) => a - b);
    for (let i = 0; i + 1 < boundaries.length; i++) {
      const from = boundaries[i];
      const until = boundaries[i + 1] - 1;
      if (!hasWeekday(from, until, day)) continue;
      const minutes = entries.filter((entry) => entry.day === day &&
        entry.from <= from && entry.until >= from)
        .reduce((sum, entry) => sum + entry.end - entry.start, 0);
      if (minutes > 600) {
        return { valid: false, reason: 'La jornada diaria supera el máximo de 10 horas.' };
      }
    }
  }
  return { valid: true };
}

function parseDate(value: unknown): number | null {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const millis = Date.parse(`${value}T00:00:00.000Z`);
  if (!Number.isFinite(millis) || new Date(millis).toISOString().slice(0, 10) !== value) return null;
  return Math.floor(millis / 86400000);
}

function hasWeekday(from: number, until: number, mondayBasedDay: number): boolean {
  const jsDay = new Date(from * 86400000).getUTCDay();
  const mondayBasedFrom = jsDay === 0 ? 7 : jsDay;
  return from + ((mondayBasedDay - mondayBasedFrom + 7) % 7) <= until;
}

