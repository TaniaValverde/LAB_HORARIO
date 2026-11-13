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
const declarationsToDelete = [];

before(async () => {
  app = initializeApp({ projectId }, `hu17-test-${randomUUID()}`);
  firestore = getFirestore(app);
  firestore.settings({ host: '127.0.0.1:8180', ssl: false });
});

after(async () => {
  for (const account of accounts) {
    for (const declarationId of declarationsToDelete.filter((id) => id.startsWith(`${account.uid}_`))) {
      await firestore.recursiveDelete(firestore.doc(`declarations/${declarationId}`)).catch(() => {});
    }
    await firestore.recursiveDelete(
      firestore.doc(`supervisor_assignments/${account.uid}`),
    ).catch(() => {});
    await firestore.doc(`users/${account.uid}`).delete().catch(() => {});
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
      email: `hu17-${randomUUID()}@example.test`,
      password: 'LocalTest123!',
      returnSecureToken: true,
    }),
  });
  const body = await response.text();
  if (!response.ok) throw new Error(`Auth Emulator sign-up failed (${response.status}): ${body}`);
  const auth = JSON.parse(body);
  const account = { uid: auth.localId, idToken: auth.idToken };
  accounts.push(account);
  await firestore.doc(`users/${account.uid}`).set({
    name: `Actor ${role}`,
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

async function assign(admin, declarant, supervisor) {
  return call('assignDeclarantSupervisor', admin, {
    declarantId: declarant.uid,
    supervisorId: supervisor.uid,
  });
}

async function seedDeclaration(declarant, id, status = 'pendingSuperiorSignature') {
  declarationsToDelete.push(id);
  const declaration = {
    personId: declarant.uid,
    periodId: '2026-II',
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    status,
    version: 1,
    parentVersionId: null,
    revision: 2,
    payload: {
      schemaVersion: 1,
      profile: { name: `Nombre ${id}` },
      appointments: [],
      externalJobs: [],
      observations: '',
    },
    oathAcceptedAt: null,
    declarantSignedAt: Timestamp.now(),
    declarantSignature: `signature-${id}`,
    superiorSignedAt: status === 'signedBySuperior' ? Timestamp.now() : null,
    superiorSignature: status === 'signedBySuperior' ? `superior-signature-${id}` : null,
    returnObservation: null,
    hrReceivedAt: null,
    finalizedAt: null,
    finalPdfPath: null,
  };
  const reference = firestore.doc(`declarations/${id}`);
  await reference.set(declaration);
  await reference.collection('versions').doc('1').set(declaration);
  await reference.collection('events').doc('declarantSigned_v1_r2').set({
    id: 'declarantSigned_v1_r2',
    declarationId: id,
    actorId: declarant.uid,
    action: 'declarantSigned',
    occurredAt: declaration.declarantSignedAt,
    details: `version=1;revision=2;signatureId=signature-${id}`,
  });
  return { declaration, reference };
}

test('admin y Recursos Humanos asignan declarantes con historial atómico e idempotente', async () => {
  const admin = await actor('administrator');
  const hr = await actor('humanResources');
  const declarant = await actor('declarant');
  const supervisor = await actor('supervisor');
  const first = await assign(admin, declarant, supervisor);
  assert.equal(first.result.alreadyAssigned, false);
  assert.equal(first.result.revision, 1);
  const assignmentRef = firestore.doc(`supervisor_assignments/${declarant.uid}`);
  const firstAssignment = (await assignmentRef.get()).data();
  const firstEvent = await assignmentRef.collection('events').doc('supervisorAssigned_v1').get();
  assert.equal(firstAssignment.supervisorId, supervisor.uid);
  assert.equal(firstEvent.get('assignedBy'), admin.uid);
  const retry = await assign(admin, declarant, supervisor);
  assert.equal(retry.result.alreadyAssigned, true);
  assert.equal((await assignmentRef.collection('events').get()).size, 1);

  const nextSupervisor = await actor('supervisor');
  const changed = await call('assignDeclarantSupervisor', hr, {
    declarantId: declarant.uid,
    supervisorId: nextSupervisor.uid,
  });
  assert.equal(changed.result.revision, 2);
  assert.equal((await assignmentRef.get()).get('supervisorId'), nextSupervisor.uid);
  assert.equal((await assignmentRef.collection('events').get()).size, 2);
});

test('no reasigna un superior si el evento vigente no coincide con la asignación', async () => {
  const admin = await actor('administrator');
  const declarant = await actor('declarant');
  const firstSupervisor = await actor('supervisor');
  const nextSupervisor = await actor('supervisor');
  await assign(admin, declarant, firstSupervisor);

  const assignmentRef = firestore.doc(`supervisor_assignments/${declarant.uid}`);
  const eventRef = assignmentRef.collection('events').doc('supervisorAssigned_v1');
  const assignmentBefore = (await assignmentRef.get()).data();
  await eventRef.update({ assignedBy: 'inconsistent-actor' });
  const eventBefore = (await eventRef.get()).data();

  const rejected = await call('assignDeclarantSupervisor', admin, {
    declarantId: declarant.uid,
    supervisorId: nextSupervisor.uid,
  });

  assert.equal(rejected.error.status, 'FAILED_PRECONDITION');
  assert.deepEqual((await assignmentRef.get()).data(), assignmentBefore);
  assert.deepEqual((await eventRef.get()).data(), eventBefore);
  assert.equal((await assignmentRef.collection('events').get()).size, 1);
});

test('rechaza asignaciones no autorizadas e inválidas sin escrituras parciales', async () => {
  const declarant = await actor('declarant');
  const supervisor = await actor('supervisor');
  const unauthorized = await call('assignDeclarantSupervisor', declarant, {
    declarantId: declarant.uid,
    supervisorId: supervisor.uid,
  });
  assert.equal(unauthorized.error.status, 'PERMISSION_DENIED');
  const unauthenticated = await call('assignDeclarantSupervisor', declarant, {
    declarantId: declarant.uid,
    supervisorId: supervisor.uid,
  }, false);
  assert.equal(unauthenticated.error.status, 'UNAUTHENTICATED');

  const admin = await actor('administrator');
  const inactiveAdmin = await actor('administrator', { active: false });
  const inactiveActor = await call('assignDeclarantSupervisor', inactiveAdmin, {
    declarantId: declarant.uid,
    supervisorId: supervisor.uid,
  });
  assert.equal(inactiveActor.error.status, 'PERMISSION_DENIED');
  const inactiveSupervisor = await actor('supervisor', { active: false });
  const inactiveTarget = await call('assignDeclarantSupervisor', admin, {
    declarantId: declarant.uid,
    supervisorId: inactiveSupervisor.uid,
  });
  assert.equal(inactiveTarget.error.status, 'FAILED_PRECONDITION');
  const wrongRoleTarget = await actor('humanResources');
  const wrongRole = await call('assignDeclarantSupervisor', admin, {
    declarantId: declarant.uid,
    supervisorId: wrongRoleTarget.uid,
  });
  assert.equal(wrongRole.error.status, 'FAILED_PRECONDITION');
  const inactiveDeclarant = await actor('declarant', { active: false });
  const invalidOwner = await call('assignDeclarantSupervisor', admin, {
    declarantId: inactiveDeclarant.uid,
    supervisorId: supervisor.uid,
  });
  assert.equal(invalidOwner.error.status, 'FAILED_PRECONDITION');
  const missingOwner = await call('assignDeclarantSupervisor', admin, {
    declarantId: 'missing-declarant',
    supervisorId: supervisor.uid,
  });
  assert.equal(missingOwner.error.status, 'FAILED_PRECONDITION');
  const nonexistent = await call('assignDeclarantSupervisor', admin, {
    declarantId: declarant.uid,
    supervisorId: 'missing-supervisor',
  });
  assert.equal(nonexistent.error.status, 'FAILED_PRECONDITION');
  assert.equal((await firestore.doc(`supervisor_assignments/${declarant.uid}`).get()).exists, false);
  assert.equal((await firestore.doc(`supervisor_assignments/${declarant.uid}/events/supervisorAssigned_v1`).get()).exists, false);
});

test('la bandeja solo entrega declaraciones pendientes de la asignación vigente y el detalle vuelve a autorizar', async () => {
  const admin = await actor('administrator');
  const oldSupervisor = await actor('supervisor');
  const newSupervisor = await actor('supervisor');
  const declarant = await actor('declarant');
  const signedDeclarant = await actor('declarant');
  const pendingId = `${declarant.uid}_pending`;
  const completedId = `${signedDeclarant.uid}_signed`;
  const { declaration: pending, reference: pendingRef } = await seedDeclaration(declarant, pendingId);
  const { declaration: completed, reference: completedRef } = await seedDeclaration(
    signedDeclarant, completedId, 'signedBySuperior',
  );
  await assign(admin, declarant, oldSupervisor);
  await assign(admin, signedDeclarant, oldSupervisor);

  assert.equal((await call('getSupervisorInbox', declarant)).error.status, 'PERMISSION_DENIED');
  assert.equal((await call('getSupervisorDeclaration', declarant, { declarationId: pendingId })).error.status, 'PERMISSION_DENIED');
  const oldInbox = await call('getSupervisorInbox', oldSupervisor);
  assert.deepEqual(oldInbox.result.declarations.map((row) => row.declarationId), [pendingId]);
  const allowedDetail = await call('getSupervisorDeclaration', oldSupervisor, { declarationId: pendingId });
  assert.equal(allowedDetail.result.id, pendingId);
  const deniedDetail = await call('getSupervisorDeclaration', newSupervisor, { declarationId: pendingId });
  assert.equal(deniedDetail.error.status, 'PERMISSION_DENIED');

  const changed = await call('assignDeclarantSupervisor', admin, {
    declarantId: declarant.uid,
    supervisorId: newSupervisor.uid,
  });
  assert.equal(changed.result.revision, 2);
  assert.deepEqual((await call('getSupervisorInbox', oldSupervisor)).result.declarations, []);
  assert.deepEqual((await call('getSupervisorInbox', newSupervisor)).result.declarations.map((row) => row.declarationId), [pendingId]);
  assert.equal((await call('getSupervisorDeclaration', oldSupervisor, { declarationId: pendingId })).error.status, 'PERMISSION_DENIED');
  const newDetail = await call('getSupervisorDeclaration', newSupervisor, { declarationId: pendingId });
  assert.equal(newDetail.result.status, 'pendingSuperiorSignature');

  assert.deepEqual((await pendingRef.get()).data(), pending);
  assert.deepEqual((await pendingRef.collection('versions').doc('1').get()).data(), pending);
  assert.equal((await pendingRef.collection('events').doc('declarantSigned_v1_r2').get()).exists, true);
  assert.deepEqual((await completedRef.get()).data(), completed);
  assert.deepEqual((await completedRef.collection('versions').doc('1').get()).data(), completed);
});

test('bandeja y detalle rechazan asignaciones incompletas o corruptas sin alterar el historial', async () => {
  const supervisor = await actor('supervisor');
  const declarant = await actor('declarant');
  const declarationId = `${declarant.uid}_corrupt_assignment`;
  const { declaration, reference } = await seedDeclaration(declarant, declarationId);
  const assignmentRef = firestore.doc(`supervisor_assignments/${declarant.uid}`);
  const eventRef = assignmentRef.collection('events').doc('fixture_v1');
  const base = {
    declarantId: declarant.uid,
    supervisorId: supervisor.uid,
    revision: 1,
    updatedAt: Timestamp.now(),
    updatedBy: 'admin-fixture',
  };
  const corruptions = [
    ['declarantId', 'another-declarant'],
    ['revision', 0],
    ['revision', 1.5],
    ['revision', Number.MAX_SAFE_INTEGER + 1],
    ['updatedAt', 'not-a-timestamp'],
    ['updatedBy', ''],
    ['updatedBy', '   '],
  ];

  for (const [field, value] of corruptions) {
    await assignmentRef.set({ ...base, [field]: value });
    await eventRef.set({ fixture: `${field}-${String(value)}` });
    const result = await call('getSupervisorDeclaration', supervisor, {
      declarationId,
    });
    assert.equal(result.error.status, 'FAILED_PRECONDITION', `${field}=${String(value)}`);
    const inbox = await call('getSupervisorInbox', supervisor);
    assert.equal(inbox.error.status, 'FAILED_PRECONDITION', `inbox ${field}=${String(value)}`);
    assert.deepEqual((await assignmentRef.get()).data(), {
      ...base,
      [field]: value,
    });
    assert.deepEqual((await eventRef.get()).data(), {
      fixture: `${field}-${String(value)}`,
    });
    assert.deepEqual((await reference.get()).data(), declaration);
    assert.deepEqual((await reference.collection('versions').doc('1').get()).data(), declaration);
    assert.equal((await reference.collection('events').doc('declarantSigned_v1_r2').get()).exists, true);
  }

  await assignmentRef.set({ declarantId: declarant.uid, supervisorId: supervisor.uid, revision: 1, updatedAt: Timestamp.now() });
  const missingUpdatedBy = await call('getSupervisorDeclaration', supervisor, { declarationId });
  assert.equal(missingUpdatedBy.error.status, 'FAILED_PRECONDITION');
  const inboxMissingUpdatedBy = await call('getSupervisorInbox', supervisor);
  assert.equal(inboxMissingUpdatedBy.error.status, 'FAILED_PRECONDITION');
  assert.deepEqual((await reference.get()).data(), declaration);
  assert.deepEqual((await reference.collection('versions').doc('1').get()).data(), declaration);
});
