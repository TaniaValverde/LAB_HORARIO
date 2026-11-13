import assert from 'node:assert/strict';
import { test } from 'node:test';
import { computeDeclarationContentHash } from '../lib/content_hash.js';

test('el hash canónico no depende del orden de claves y cambia con el contenido', () => {
  const first = computeDeclarationContentHash({
    payload: { profile: { name: 'Ana', email: 'ana@example.test' }, observations: '' },
    version: 1, personId: 'person-1', periodId: '2026-II',
  });
  const reordered = computeDeclarationContentHash({
    payload: { observations: '', profile: { email: 'ana@example.test', name: 'Ana' } },
    version: 1, personId: 'person-1', periodId: '2026-II',
  });
  const changed = computeDeclarationContentHash({
    payload: { profile: { name: 'Ana', email: 'ana@example.test' }, observations: 'Cambio' },
    version: 1, personId: 'person-1', periodId: '2026-II',
  });
  assert.equal(first, reordered);
  assert.notEqual(first, changed);
  assert.match(first, /^[a-f0-9]{64}$/);
});
