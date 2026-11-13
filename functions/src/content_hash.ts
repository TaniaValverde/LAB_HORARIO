import { createHash } from 'node:crypto';

function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record).sort().map((key) =>
      `${JSON.stringify(key)}:${canonical(record[key])}`,
    ).join(',')}}`;
  }
  if (value === null || typeof value === 'boolean' || typeof value === 'number' || typeof value === 'string') {
    return JSON.stringify(value) ?? 'null';
  }
  throw new TypeError('El contenido de la declaración no es JSON canónico.');
}

export function computeDeclarationContentHash(input: {
  payload: unknown;
  version: number;
  personId: string;
  periodId: string;
}): string {
  const canonicalPayload = canonical({
    payload: input.payload,
    version: input.version,
    personId: input.personId,
    periodId: input.periodId,
  });
  return createHash('sha256').update(canonicalPayload, 'utf8').digest('hex');
}
