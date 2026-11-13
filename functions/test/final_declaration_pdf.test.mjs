import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildFinalDeclarationPdf } from '../lib/final_declaration_pdf.js';

test('el PDF incluye el texto aprobado y las fechas de firma leídas como Timestamp', () => {
  const declarantSignedAt = new Date('2026-10-19T12:00:00.000Z');
  const superiorSignedAt = new Date('2026-10-19T12:05:00.000Z');
  const timestamp = (value) => ({ toDate: () => value });
  const oathText = 'Texto institucional aprobado exclusivamente para esta prueba.';
  const pdf = buildFinalDeclarationPdf({
    declarationId: 'declaration-test',
    declaration: {
      personId: 'declarant-uid', periodId: '2026-II', status: 'receivedByHr',
      version: 1, revision: 6, payload: {
        profile: { name: 'Persona de prueba', identification: '123' },
        appointments: [], externalJobs: [], observations: '',
      },
      declarantSignature: 'declarantSignature_v1_r2',
      declarantSignedAt: timestamp(declarantSignedAt),
      superiorSignature: 'superiorSignature_v1_r3',
      superiorSignedAt: timestamp(superiorSignedAt),
    },
    declarantSignatureEvent: { actorId: 'declarant-uid', contentHash: 'a'.repeat(64) },
    superiorSignatureEvent: { actorId: 'supervisor-uid', contentHash: 'b'.repeat(64) },
    oathTextVersion: 7,
    oathText,
  });
  const encoded = pdf.toString('ascii');
  const containsPdfText = (value) => encoded.includes(Buffer.from(value).toString('hex').toUpperCase());

  assert.ok(pdf.subarray(0, 8).equals(Buffer.from('%PDF-1.4')));
  assert.ok(containsPdfText('JURAMENTO INSTITUCIONAL APROBADO (VERSION 7)'));
  assert.ok(containsPdfText(oathText));
  assert.ok(containsPdfText(declarantSignedAt.toISOString()));
  assert.ok(containsPdfText(superiorSignedAt.toISOString()));
  assert.ok(containsPdfText('declarantSignature_v1_r2'));
  assert.ok(containsPdfText('superiorSignature_v1_r3'));
  assert.ok(containsPdfText('a'.repeat(64)));
  assert.ok(containsPdfText('b'.repeat(64)));
});

test('el PDF identifica jornada, clases y consultas sin perder el detalle horario', () => {
  const pdf = buildFinalDeclarationPdf({
    declarationId: 'teaching-test', declaration: {
      payload: { appointments: [{
        workplace: 'UCR', position: 'Docente', workloadType: 'quarterTime', weeklyMinutes: 600, courseCode: 'IF0009',
        startsOn: '2026-01-01', endsOn: '2026-12-31', blocks: [
          { day: 1, start: 360, end: 720, activity: 'teaching' },
          { day: 1, start: 780, end: 820, activity: 'teaching' },
          { day: 1, start: 840, end: 1040, activity: 'consultation' },
        ],
      }], externalJobs: [] },
    }, declarantSignatureEvent: {}, superiorSignatureEvent: {}, oathTextVersion: 1, oathText: 'Prueba',
  });
  const encoded = pdf.toString('ascii');
  for (const text of [
    'Tipo de jornada: 1/4 de tiempo',
    'Sigla del curso: IF0009',
    'Clases: 6 h 40 min; consultas: 3 h 20 min',
    'Dia 1: 840-1040 minutos desde medianoche - Consulta',
  ]) {
    assert.ok(encoded.includes(Buffer.from(text).toString('hex').toUpperCase()), text);
  }
});
