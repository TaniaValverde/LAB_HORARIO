import assert from 'node:assert/strict';
import { test } from 'node:test';
import { validateSchedulePayload } from '../lib/schedule_validation.js';
import { computeDeclarationContentHash } from '../lib/content_hash.js';

function payload(workloadType = 'quarterTime') {
  const weeklyMinutes = { fullTime: 2400, halfTime: 1200, quarterTime: 600 }[workloadType];
  return {
    schemaVersion: 1,
    profile: { name: 'Test', identification: '1', phone: '1', email: 'test@example.test', unit: 'UCR' },
    appointments: [{
      id: 'job', workplace: 'UCR', position: 'Docente', institution: '',
      startsOn: '2026-01-01', endsOn: '2026-12-31', weeklyMinutes, workloadType,
      blocks: Array.from({ length: weeklyMinutes / 600 }, (_, index) => [
        { day: index + 1, start: 360, end: 720, activity: 'teaching' },
        { day: index + 1, start: 780, end: 820, activity: 'teaching' },
        { day: index + 1, start: 840, end: 1040, activity: 'consultation' },
      ]).flat(),
    }], externalJobs: [], observations: '',
  };
}

for (const type of ['fullTime', 'halfTime', 'quarterTime']) {
  test(`server accepts exact ${type} class/consultation distribution`, () => {
    assert.equal(validateSchedulePayload(payload(type)).valid, true);
  });
}

for (const [name, change] of [
  ['unknown workload', (job) => { job.workloadType = 'other'; }],
  ['null workload', (job) => { job.workloadType = null; }],
  ['mismatched workload', (job) => { job.weeklyMinutes = 1200; }],
  ['unknown activity', (job) => { job.blocks[0].activity = 'other'; }],
  ['missing activity', (job) => { delete job.blocks[0].activity; }],
  ['consultations without workload', (job) => { delete job.workloadType; }],
  ['wrong ratio with correct total', (job) => { job.blocks[0].activity = 'consultation'; }],
  ['incomplete consultation hours', (job) => { job.blocks.pop(); }],
  ['consultation lunch and overlap', (job) => { job.blocks[2].start = 660; job.blocks[2].end = 860; }],
]) {
  test(`server rejects ${name}`, () => {
    const form = payload();
    change(form.appointments[0]);
    assert.equal(validateSchedulePayload(form).valid, false);
  });
}

test('server rejects teaching fields for external employment', () => {
  const form = payload();
  form.externalJobs.push({ ...structuredClone(form.appointments[0]), institution: 'External' });
  assert.equal(validateSchedulePayload(form).valid, false);
});

test('legacy payload is accepted unchanged', () => {
  const form = payload();
  delete form.appointments[0].workloadType;
  form.appointments[0].blocks.forEach((block) => { delete block.activity; });
  const before = JSON.stringify(form);
  assert.equal(validateSchedulePayload(form).valid, true);
  assert.equal(JSON.stringify(form), before);
});

test('signature hash covers workload and block activity', () => {
  const input = { payload: payload(), version: 1, personId: 'person', periodId: 'period' };
  const original = computeDeclarationContentHash(input);
  const activityChanged = structuredClone(input);
  activityChanged.payload.appointments[0].blocks[0].activity = 'consultation';
  assert.notEqual(computeDeclarationContentHash(activityChanged), original);
  const workloadChanged = structuredClone(input);
  workloadChanged.payload.appointments[0].workloadType = 'fullTime';
  assert.notEqual(computeDeclarationContentHash(workloadChanged), original);
});

test('course code is validated and covered by the signature hash', () => {
  const form = payload();
  const input = { payload: form, version: 1, personId: 'person', periodId: 'period' };
  const legacyHash = computeDeclarationContentHash(input);
  form.appointments[0].courseCode = 'IF0009';
  assert.equal(validateSchedulePayload(form).valid, true);
  assert.notEqual(computeDeclarationContentHash(input), legacyHash);
  for (const invalid of ['', '   ', null, 123, 'A'.repeat(41)]) {
    form.appointments[0].courseCode = invalid;
    assert.equal(validateSchedulePayload(form).valid, false);
  }
});

test('external employment cannot supply a course code', () => {
  const form = payload();
  form.externalJobs.push({ id: 'external', institution: 'Other', workplace: 'Office', position: 'Job',
    startsOn: '2026-01-01', endsOn: '2026-12-31', weeklyMinutes: 60,
    blocks: [{ day: 2, start: 480, end: 540 }], courseCode: 'IF0009' });
  assert.equal(validateSchedulePayload(form).valid, false);
  delete form.externalJobs[0].courseCode;
  assert.equal(validateSchedulePayload(form).valid, true);
});
