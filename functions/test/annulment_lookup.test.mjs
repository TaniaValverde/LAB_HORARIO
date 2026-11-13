import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
// No emulator fixtures: all reads are intercepted, so shared demo data is untouched.
process.env.GCLOUD_PROJECT = 'demo-annulment-unit';
const { findDeclarationsForAnnulment } = require('../lib/index.js');
const { getFirestore } = require('firebase-admin/firestore');
const db = getFirestore();

test('lookup checks identity, active administrator and returns bounded metadata', async () => {
  const original = db.runTransaction;
  let profile = { role: 'administrator', active: true };
  let reads = 0;
  db.runTransaction = async (callback) => callback({
    get: async () => {
      reads++;
      if (reads === 1) return { data: () => profile };
      return { docs: Array.from({ length: 51 }, (_, i) => ({
        id: `d${i}`, data: () => ({ personId: 'person', periodId: '2026',
          payload: { profile: { name: 'Docente', identification: 'private' } },
          status: 'draft', version: 2, revision: 9 }),
      })) };
    },
  });
  try {
    await assert.rejects(findDeclarationsForAnnulment.run({ data: { periodId: '2026' } }), { code: 'unauthenticated' });
    for (profile of [{ role: 'declarant', active: true }, { role: 'administrator', active: false }]) {
      reads = 0;
      await assert.rejects(findDeclarationsForAnnulment.run({ auth: { uid: 'admin' }, data: { periodId: '2026' } }), { code: 'permission-denied' });
      assert.equal(reads, 1);
    }
    profile = { role: 'administrator', active: true };
    reads = 0;
    const result = await findDeclarationsForAnnulment.run({ auth: { uid: 'admin' }, data: { periodId: '2026' } });
    assert.equal(result.declarations.length, 50);
    assert.equal(result.next, 'd49');
    assert.equal(result.declarations[0].revision, 9);
    assert.equal(result.declarations[0].payload, undefined);
    await assert.rejects(findDeclarationsForAnnulment.run({ auth: { uid: 'admin' }, data: { periodId: '2026', after: 'bad/path' } }), { code: 'invalid-argument' });
  } finally {
    db.runTransaction = original;
  }
});
