import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const projectId = 'demo-declara-horario';
const authUrl = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const functionsUrl = `http://127.0.0.1:5001/${projectId}/us-central1`;
let app;
let firestore;
const accounts = [];
const periodIds = [];

before(() => {
  app = initializeApp({ projectId }, `admin-test-${randomUUID()}`);
  firestore = getFirestore(app);
  firestore.settings({ host: '127.0.0.1:8180', ssl: false });
});

after(async () => {
  for (const id of periodIds) {
    await firestore.doc(`academic_periods/${id}`).delete().catch(() => {});
  }
  for (const account of accounts) {
    await firestore.recursiveDelete(firestore.doc(`users/${account.uid}`)).catch(() => {});
    await fetch(`${authUrl}/accounts:delete?key=fake-api-key`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idToken: account.idToken }),
    }).catch(() => {});
  }
  if (app) await deleteApp(app);
});

async function actor(role, { active = true } = {}) {
  const response = await fetch(`${authUrl}/accounts:signUp?key=fake-api-key`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: `admin-${randomUUID()}@example.test`,
      password: 'LocalTest123!',
      returnSecureToken: true,
    }),
  });
  const body = await response.text();
  if (!response.ok) {
    throw new Error(`Auth Emulator sign-up failed (${response.status}): ${body}`);
  }
  const auth = JSON.parse(body);
  const account = { uid: auth.localId, idToken: auth.idToken };
  accounts.push(account);
  await firestore.doc(`users/${account.uid}`).set({
    name: `Test ${role}`,
    role,
    active,
  });
  return account;
}

async function call(name, account, data = {}, authenticated = true) {
  const response = await fetch(`${functionsUrl}/${name}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(authenticated ? { Authorization: `Bearer ${account.idToken}` } : {}),
    },
    body: JSON.stringify({ data }),
  });
  return response.json();
}

function periodData(id, overrides = {}) {
  return {
    id,
    name: 'II ciclo 2026',
    startsAt: '2026-08-01T00:00:00.000Z',
    endsAt: '2026-12-31T23:59:59.999Z',
    isActive: true,
    ...overrides,
  };
}

test('administrador crea, actualiza, habilita y deshabilita períodos', async () => {
  const admin = await actor('administrator');
  const id = `period-${randomUUID()}`;
  periodIds.push(id);
  const created = await call('saveAcademicPeriod', admin, {
    ...periodData(id),
    createOnly: true,
  });
  assert.deepEqual(created.result, { id, created: true });

  const ref = firestore.doc(`academic_periods/${id}`);
  const initial = (await ref.get()).data();
  assert.equal(initial.name, 'II ciclo 2026');
  assert.equal(initial.isActive, true);
  assert.ok(initial.startsAt instanceof Timestamp);
  assert.ok(initial.endsAt instanceof Timestamp);
  assert.ok(initial.createdAt instanceof Timestamp);
  assert.equal(initial.createdBy, admin.uid);
  assert.equal(initial.updatedBy, admin.uid);

  const disabled = await call('saveAcademicPeriod', admin, {
    ...periodData(id, { isActive: false, name: 'II ciclo 2026 (cerrado)' }),
    createOnly: false,
  });
  assert.deepEqual(disabled.result, { id, created: false });
  const updated = (await ref.get()).data();
  assert.equal(updated.isActive, false);
  assert.equal(updated.name, 'II ciclo 2026 (cerrado)');
  assert.deepEqual(updated.createdAt, initial.createdAt);
  assert.equal(updated.createdBy, initial.createdBy);
  assert.equal(updated.updatedBy, admin.uid);

  await call('saveAcademicPeriod', admin, {
    ...periodData(id, { isActive: true }),
    createOnly: false,
  });
  assert.equal((await ref.get()).get('isActive'), true);
});

test('solo administradores activos pueden administrar períodos y se rechazan rangos inválidos', async () => {
  const admin = await actor('administrator');
  const inactiveAdmin = await actor('administrator', { active: false });
  const declarant = await actor('declarant');
  const id = `period-${randomUUID()}`;
  periodIds.push(id);

  const anonymous = await call(
    'saveAcademicPeriod', admin,
    { ...periodData(id), createOnly: true },
    false,
  );
  assert.equal(anonymous.error.status, 'UNAUTHENTICATED');
  const wrongRole = await call('saveAcademicPeriod', declarant, {
    ...periodData(id),
    createOnly: true,
  });
  assert.equal(wrongRole.error.status, 'PERMISSION_DENIED');
  const inactive = await call('saveAcademicPeriod', inactiveAdmin, {
    ...periodData(id),
    createOnly: true,
  });
  assert.equal(inactive.error.status, 'PERMISSION_DENIED');

  const invalidRange = await call('saveAcademicPeriod', admin, {
    ...periodData(id, {
      startsAt: '2026-12-31T23:59:59.999Z',
      endsAt: '2026-08-01T00:00:00.000Z',
    }),
    createOnly: true,
  });
  assert.equal(invalidRange.error.status, 'INVALID_ARGUMENT');
  assert.equal((await firestore.doc(`academic_periods/${id}`).get()).exists, false);
});

test('administrador asigna roles con historial atómico y el reintento no duplica eventos', async () => {
  const admin = await actor('administrator');
  const target = await actor('declarant');
  const first = await call('assignUserRole', admin, {
    targetUid: target.uid,
    role: 'supervisor',
  });
  assert.deepEqual(first.result, {
    targetUid: target.uid,
    role: 'supervisor',
    revision: 1,
    alreadyAssigned: false,
  });
  const targetRef = firestore.doc(`users/${target.uid}`);
  const profile = (await targetRef.get()).data();
  assert.equal(profile.role, 'supervisor');
  assert.equal(profile.roleRevision, 1);
  assert.equal(profile.roleUpdatedBy, admin.uid);
  assert.ok(profile.roleUpdatedAt instanceof Timestamp);
  const eventRef = targetRef.collection('role_events').doc('roleChanged_v1');
  const event = (await eventRef.get()).data();
  assert.equal(event.action, 'roleChanged');
  assert.equal(event.actorId, admin.uid);
  assert.equal(event.targetUid, target.uid);
  assert.equal(event.previousRole, 'declarant');
  assert.equal(event.role, 'supervisor');
  assert.ok(event.occurredAt instanceof Timestamp);

  const retry = await call('assignUserRole', admin, {
    targetUid: target.uid,
    role: 'supervisor',
  });
  assert.equal(retry.result.alreadyAssigned, true);
  assert.equal((await targetRef.collection('role_events').get()).size, 1);

  const changed = await call('assignUserRole', admin, {
    targetUid: target.uid,
    role: 'humanResources',
  });
  assert.equal(changed.result.revision, 2);
  assert.equal((await targetRef.get()).get('role'), 'humanResources');
  assert.equal((await targetRef.collection('role_events').get()).size, 2);
});

test('rechaza asignaciones de rol sin permisos, autoasignaciones y perfiles inexistentes', async () => {
  const admin = await actor('administrator');
  const inactiveAdmin = await actor('administrator', { active: false });
  const declarant = await actor('declarant');
  const target = await actor('declarant');

  const noAuth = await call('assignUserRole', admin, {
    targetUid: target.uid,
    role: 'administrator',
  }, false);
  assert.equal(noAuth.error.status, 'UNAUTHENTICATED');
  const wrongRole = await call('assignUserRole', declarant, {
    targetUid: target.uid,
    role: 'supervisor',
  });
  assert.equal(wrongRole.error.status, 'PERMISSION_DENIED');
  const inactive = await call('assignUserRole', inactiveAdmin, {
    targetUid: target.uid,
    role: 'supervisor',
  });
  assert.equal(inactive.error.status, 'PERMISSION_DENIED');
  const self = await call('assignUserRole', admin, {
    targetUid: admin.uid,
    role: 'administrator',
  });
  assert.equal(self.error.status, 'PERMISSION_DENIED');
  const missing = await call('assignUserRole', admin, {
    targetUid: 'missing-user',
    role: 'supervisor',
  });
  assert.equal(missing.error.status, 'NOT_FOUND');
  const invalidRole = await call('assignUserRole', admin, {
    targetUid: target.uid,
    role: 'root',
  });
  assert.equal(invalidRole.error.status, 'INVALID_ARGUMENT');

  assert.equal((await firestore.doc(`users/${target.uid}`).get()).get('role'), 'declarant');
  assert.equal((await firestore.doc(`users/${target.uid}/role_events/roleChanged_v1`).get()).exists, false);
});
