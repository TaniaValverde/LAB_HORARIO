import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const projectId = 'demo-declara-horario';
const draftOath = JSON.parse(readFileSync(
  new URL('./fixtures/declarant_oath_v1_0_draft.json', import.meta.url),
  'utf8',
));
const authUrl = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const functionUrl = `http://127.0.0.1:5001/${projectId}/us-central1/acceptOath`;
const signFunctionUrl = `http://127.0.0.1:5001/${projectId}/us-central1/signDeclaration`;
const submitFunctionUrl = `http://127.0.0.1:5001/${projectId}/us-central1/submitDeclarationToSupervisor`;
const inboxFunctionUrl = `http://127.0.0.1:5001/${projectId}/us-central1/getSupervisorInbox`;
const statusFunctionUrl = `http://127.0.0.1:5001/${projectId}/us-central1/getDeclarationStatus`;
let app;
let firestore;
const createdAccounts = [];
const additionalDeclarationIds = [];

before(async () => {
  app = initializeApp({ projectId }, `hu15-test-${randomUUID()}`);
  firestore = getFirestore(app);
  firestore.settings({ host: '127.0.0.1:8180', ssl: false });
  await clearOathConfiguration();
});

beforeEach(clearOathConfiguration);

after(async () => {
  for (const account of createdAccounts) {
    await firestore.recursiveDelete(firestore.doc(`declarations/${account.declarationId}`))
      .catch(() => {});
    await firestore.doc(`supervisor_assignments/${account.uid}`).delete().catch(() => {});
    await firestore.doc(`users/${account.uid}`).delete().catch(() => {});
    await fetch(`${authUrl}/accounts:delete?key=fake-api-key`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idToken: account.idToken }),
    }).catch(() => {});
  }
  for (const declarationId of additionalDeclarationIds) {
    await firestore.recursiveDelete(firestore.doc(`declarations/${declarationId}`)).catch(() => {});
  }
  await clearOathConfiguration();
  if (app) await deleteApp(app);
});

async function newActor(role = 'declarant', profileOptions = { active: true }) {
  const token = await fetch(`${authUrl}/accounts:signUp?key=fake-api-key`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: `hu15-${randomUUID()}@example.test`,
      password: 'LocalTest123!',
      returnSecureToken: true,
    }),
  });
  const responseBody = await token.text();
  if (!token.ok) {
    throw new Error(`Auth Emulator sign-up failed (HTTP ${token.status}): ${responseBody}`);
  }
  const auth = JSON.parse(responseBody);
  const declarationId = `${auth.localId}_period`;
  const account = { uid: auth.localId, idToken: auth.idToken, declarationId };
  createdAccounts.push(account);
  const profile = { name: 'Persona de prueba', role };
  if (Object.hasOwn(profileOptions, 'active') && profileOptions.active !== undefined) {
    profile.active = profileOptions.active;
  }
  await firestore.doc(`users/${account.uid}`).set(profile);
  return account;
}

function validPayload() {
  return {
    schemaVersion: 1,
    profile: {
      name: 'Persona de prueba', identification: '123', phone: '88888888',
      email: 'contacto@example.test', unit: 'Sur',
    },
    appointments: [{
      id: 'appointment-1', workplace: 'Sede Central', position: 'Docente',
      weeklyMinutes: 240, startsOn: '2026-01-01', endsOn: '2026-12-31',
      institution: '', blocks: [{ day: 1, start: 480, end: 720 }],
    }],
    externalJobs: [],
    observations: '',
  };
}

async function seedDeclaration(account, {
  personId = account.uid,
  status = 'validated',
  revision = 0,
  payload = validPayload(),
} = {}) {
  const declaration = {
    personId,
    periodId: 'period',
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    status,
    version: 1,
    parentVersionId: null,
    revision,
    payload,
    oathAcceptedAt: null,
    declarantSignedAt: null,
    declarantSignature: null,
    superiorSignedAt: null,
    superiorSignature: null,
    returnObservation: null,
    hrReceivedAt: null,
    finalizedAt: null,
    finalPdfPath: null,
  };
  await firestore.doc(`declarations/${account.declarationId}`).set(declaration);
  await firestore.doc(`declarations/${account.declarationId}/versions/1`).set(declaration);
  return declaration;
}

async function clearOathConfiguration() {
  await firestore?.doc('system_config/declarant_oath').delete().catch(() => {});
  await firestore?.recursiveDelete(
    firestore.doc('institutional_texts/declarant_oath'),
  ).catch(() => {});
}

async function seedOathConfiguration({
  status = 'approved',
  approvedVersion = 1,
  version = approvedVersion,
  text = 'TEST FIXTURE ONLY — NOT INSTITUTIONAL WORDING',
  versionStatus = 'approved',
  includeVersionDocument = true,
} = {}) {
  await firestore.doc('system_config/declarant_oath').set({
    status,
    approvedVersion,
  });
  if (includeVersionDocument && Number.isSafeInteger(version) && version > 0) {
    await firestore.doc(
      `institutional_texts/declarant_oath/versions/${version}`,
    ).set({
      status: versionStatus,
      version,
      text,
      approvedAt: Timestamp.now(),
    });
  }
}

async function seedPendingSignature(account, { status = 'pendingDeclarantSignature' } = {}) {
  await seedOathConfiguration();
  const acceptedAt = Timestamp.now();
  const declaration = {
    ...(await seedDeclaration(account, { status, revision: 1 })),
    updatedAt: acceptedAt,
    oathAcceptedAt: acceptedAt,
  };
  await firestore.doc(`declarations/${account.declarationId}`).set(declaration);
  await firestore.doc(`declarations/${account.declarationId}/versions/1`).set(declaration);
  await firestore.doc(
    `declarations/${account.declarationId}/events/oathAccepted_v1_r1`,
  ).set({
    id: 'oathAccepted_v1_r1',
    declarationId: account.declarationId,
    actorId: account.uid,
    action: 'oathAccepted',
    occurredAt: acceptedAt,
    details: 'version=1;revision=1;oathTextVersion=1',
  });
  return declaration;
}

async function invoke(account, data = {}, authenticated = true) {
  const response = await fetch(functionUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(authenticated ? { Authorization: `Bearer ${account.idToken}` } : {}),
    },
    body: JSON.stringify({ data: {
      declarationId: account.declarationId,
      expectedVersion: 1,
      expectedRevision: 0,
      accepted: true,
      expectedOathTextVersion: 1,
      ...data,
    } }),
  });
  return response.json();
}

async function invokeSign(account, data = {}, authenticated = true) {
  const response = await fetch(signFunctionUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(authenticated ? { Authorization: `Bearer ${account.idToken}` } : {}),
    },
    body: JSON.stringify({ data: {
      declarationId: account.declarationId,
      expectedVersion: 1,
      expectedRevision: 1,
      confirmed: true,
      ...data,
    } }),
  });
  return response.json();
}

async function invokeCallable(url, account, data = {}, authenticated = true) {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(authenticated ? { Authorization: `Bearer ${account.idToken}` } : {}),
    },
    body: JSON.stringify({ data }),
  });
  return response.json();
}

async function assertPendingUnchanged(account, original) {
  const root = (await firestore.doc(`declarations/${account.declarationId}`).get()).data();
  const mirror = (await firestore.doc(`declarations/${account.declarationId}/versions/1`).get()).data();
  const event = await firestore.doc(
    `declarations/${account.declarationId}/events/declarantSigned_v1_r2`,
  ).get();
  assert.deepEqual(root, original);
  assert.deepEqual(mirror, original);
  assert.equal(event.exists, false);
}

async function assertNoPartialAcceptance(account, expectedStatus = 'validated') {
  const root = (await firestore.doc(`declarations/${account.declarationId}`).get()).data();
  const version = (await firestore.doc(`declarations/${account.declarationId}/versions/1`).get()).data();
  const event = await firestore.doc(`declarations/${account.declarationId}/events/oathAccepted_v1_r1`).get();
  assert.equal(root.status, expectedStatus);
  assert.equal(root.revision, 0);
  assert.equal(version.status, expectedStatus);
  assert.equal(version.revision, 0);
  assert.equal(event.exists, false);
}

test('direct invocation rejects acceptance when no institutional text is configured', async () => {
  const account = await newActor();
  await seedDeclaration(account);
  const result = await invoke(account);
  assert.equal(result.error.status, 'FAILED_PRECONDITION');
  await assertNoPartialAcceptance(account);
});

test('rejects a text configuration that is not approved', async () => {
  const account = await newActor();
  await seedDeclaration(account);
  await seedOathConfiguration({ status: 'pending' });
  const result = await invoke(account);
  assert.equal(result.error.status, 'FAILED_PRECONDITION');
  await assertNoPartialAcceptance(account);
});

test('development draft 1.0 cannot be accepted through a direct callable invocation', async () => {
  const account = await newActor();
  await seedDeclaration(account);
  await firestore.doc('system_config/declarant_oath').set({
    status: draftOath.status,
    approvedVersion: draftOath.version,
  });
  await firestore.doc(
    `institutional_texts/declarant_oath/versions/${draftOath.version}`,
  ).set({
    status: draftOath.status,
    version: draftOath.version,
    text: draftOath.text,
  });

  const result = await invoke(account);

  assert.equal(result.error.status, 'FAILED_PRECONDITION');
  await assertNoPartialAcceptance(account);
});

test('rejects an invalid approved version or inconsistent version document', async () => {
  const account = await newActor();
  await seedDeclaration(account);
  await seedOathConfiguration({ approvedVersion: 'one' });
  const invalidPointer = await invoke(account);
  assert.equal(invalidPointer.error.status, 'FAILED_PRECONDITION');
  await assertNoPartialAcceptance(account);

  await seedOathConfiguration({ version: 2 });
  const inconsistentVersion = await invoke(account);
  assert.equal(inconsistentVersion.error.status, 'FAILED_PRECONDITION');
  await assertNoPartialAcceptance(account);

  await seedOathConfiguration({ text: '' });
  const emptyText = await invoke(account);
  assert.equal(emptyText.error.status, 'FAILED_PRECONDITION');
  await assertNoPartialAcceptance(account);
});

test('rejects profiles with missing or inactive active flag', async () => {
  for (const profileOptions of [{ active: undefined }, { active: false }]) {
    const account = await newActor('declarant', profileOptions);
    await seedDeclaration(account);
    const result = await invoke(account);
    assert.equal(result.error.status, 'PERMISSION_DENIED');
    await assertNoPartialAcceptance(account);
  }
});

test('accepts the oath atomically with server identity/time and canonical event', async () => {
  const account = await newActor();
  await seedDeclaration(account);
  await seedOathConfiguration();
  const result = await invoke(account, {
    actorId: 'forged-user',
    occurredAt: '2000-01-01T00:00:00Z',
  });
  assert.equal(result.result.alreadyAccepted, false);
  assert.equal(result.result.eventId, 'oathAccepted_v1_r1');
  assert.equal(result.result.oathTextVersion, 1);

  const root = (await firestore.doc(`declarations/${account.declarationId}`).get()).data();
  const mirror = (await firestore.doc(`declarations/${account.declarationId}/versions/1`).get()).data();
  const event = (await firestore.doc(`declarations/${account.declarationId}/events/oathAccepted_v1_r1`).get()).data();
  assert.equal(root.status, 'pendingDeclarantSignature');
  assert.equal(root.revision, 1);
  assert.ok(root.oathAcceptedAt instanceof Timestamp);
  assert.equal(mirror.status, root.status);
  assert.equal(mirror.revision, root.revision);
  assert.ok(mirror.oathAcceptedAt instanceof Timestamp);
  assert.equal(event.actorId, account.uid);
  assert.equal(event.action, 'oathAccepted');
  assert.equal(event.details, 'version=1;revision=1;oathTextVersion=1');
  assert.ok(event.occurredAt instanceof Timestamp);
});

test('rejects an unauthenticated caller without partial writes', async () => {
  const account = await newActor();
  await seedDeclaration(account);
  await seedOathConfiguration();
  const result = await invoke(account, {}, false);
  assert.equal(result.error.status, 'UNAUTHENTICATED');
  await assertNoPartialAcceptance(account);
});

test('rejects an actor whose profile role is not declarant', async () => {
  const account = await newActor('supervisor');
  await seedDeclaration(account);
  await seedOathConfiguration();
  const result = await invoke(account);
  assert.equal(result.error.status, 'PERMISSION_DENIED');
  await assertNoPartialAcceptance(account);
});

test('rejects a declaration owned by a different user', async () => {
  const account = await newActor();
  await seedDeclaration(account, { personId: 'another-owner' });
  await seedOathConfiguration();
  const result = await invoke(account);
  assert.equal(result.error.status, 'PERMISSION_DENIED');
  await assertNoPartialAcceptance(account);
});

test('rejects a declaration that is not validated', async () => {
  const account = await newActor();
  await seedDeclaration(account, { status: 'draft' });
  await seedOathConfiguration();
  const result = await invoke(account);
  assert.equal(result.error.status, 'FAILED_PRECONDITION');
  await assertNoPartialAcceptance(account, 'draft');
});

test('rejects an obsolete revision', async () => {
  const account = await newActor();
  await seedDeclaration(account);
  await seedOathConfiguration();
  const result = await invoke(account, { expectedRevision: 5 });
  assert.equal(result.error.status, 'FAILED_PRECONDITION');
  await assertNoPartialAcceptance(account);
});

test('requires an explicit true confirmation', async (t) => {
  for (const accepted of [false, undefined]) {
    const account = await newActor();
    await seedDeclaration(account);
    await seedOathConfiguration();
    const result = await invoke(account, { accepted });
    assert.equal(result.error.status, 'INVALID_ARGUMENT');
    await assertNoPartialAcceptance(account);
  }
});

test('retries of the same accepted operation return success without duplicating the event', async () => {
  const account = await newActor();
  await seedDeclaration(account);
  await seedOathConfiguration();
  assert.equal((await invoke(account)).result.alreadyAccepted, false);
  const retry = await invoke(account);
  assert.equal(retry.result.alreadyAccepted, true);
  const events = await firestore.collection(`declarations/${account.declarationId}/events`).get();
  assert.deepEqual(events.docs.map((doc) => doc.id), ['oathAccepted_v1_r1']);
});

test('an idempotent retry remains bound to its historical approved oath version', async () => {
  const account = await newActor();
  await seedDeclaration(account);
  await seedOathConfiguration();
  assert.equal((await invoke(account)).result.alreadyAccepted, false);

  await seedOathConfiguration({ approvedVersion: 2, version: 2 });
  const retry = await invoke(account);
  assert.equal(retry.result.alreadyAccepted, true);
  assert.equal(retry.result.oathTextVersion, 1);
  const event = (await firestore.doc(
    `declarations/${account.declarationId}/events/oathAccepted_v1_r1`,
  ).get()).data();
  assert.equal(event.details, 'version=1;revision=1;oathTextVersion=1');
});

test('rejects a pre-existing unconfirmed event without changing the declaration', async () => {
  const account = await newActor();
  await seedDeclaration(account);
  await seedOathConfiguration();
  const eventData = {
    id: 'oathAccepted_v1_r1', declarationId: account.declarationId,
    actorId: account.uid, action: 'oathAccepted', occurredAt: Timestamp.now(),
    details: 'version=1;revision=1;oathTextVersion=1',
  };
  await firestore.doc(`declarations/${account.declarationId}/events/oathAccepted_v1_r1`).set(eventData);
  const originalDeclaration = (await firestore.doc(`declarations/${account.declarationId}`).get()).data();
  const originalMirror = (await firestore.doc(`declarations/${account.declarationId}/versions/1`).get()).data();
  const result = await invoke(account);
  assert.equal(result.error.status, 'ALREADY_EXISTS');
  const declaration = (await firestore.doc(`declarations/${account.declarationId}`).get()).data();
  const mirror = (await firestore.doc(`declarations/${account.declarationId}/versions/1`).get()).data();
  const event = (await firestore.doc(`declarations/${account.declarationId}/events/oathAccepted_v1_r1`).get()).data();
  assert.deepEqual(declaration, originalDeclaration);
  assert.deepEqual(mirror, originalMirror);
  assert.deepEqual(event, eventData);
  const events = await firestore.collection(`declarations/${account.declarationId}/events`).get();
  assert.deepEqual(events.docs.map((doc) => doc.id), ['oathAccepted_v1_r1']);
});

test('rejects retries when the prior event or version mirror is inconsistent', async () => {
  for (const corruption of ['eventId', 'eventTimestamp', 'mirror']) {
    const account = await newActor();
    await seedDeclaration(account);
    await seedOathConfiguration();
    assert.equal((await invoke(account)).result.alreadyAccepted, false);

    const rootRef = firestore.doc(`declarations/${account.declarationId}`);
    const mirrorRef = firestore.doc(`declarations/${account.declarationId}/versions/1`);
    const eventRef = firestore.doc(`declarations/${account.declarationId}/events/oathAccepted_v1_r1`);
    const originalDeclaration = (await rootRef.get()).data();
    if (corruption === 'eventId') await eventRef.update({ id: 'wrong-event-id' });
    if (corruption === 'eventTimestamp') await eventRef.update({ occurredAt: 'not-a-timestamp' });
    if (corruption === 'mirror') await mirrorRef.update({ revision: 99 });
    const corruptedEvent = (await eventRef.get()).data();
    const corruptedMirror = (await mirrorRef.get()).data();

    const retry = await invoke(account);
    assert.equal(retry.error.status, 'FAILED_PRECONDITION', corruption);
    assert.deepEqual((await rootRef.get()).data(), originalDeclaration);
    assert.deepEqual((await eventRef.get()).data(), corruptedEvent);
    assert.deepEqual((await mirrorRef.get()).data(), corruptedMirror);
  }
});

test('rejects invalid server-side schedule content without partial writes', async () => {
  const account = await newActor();
  const payload = validPayload();
  payload.appointments[0].blocks[0].start = 720;
  payload.appointments[0].blocks[0].end = 960;
  await seedDeclaration(account, { payload });
  await seedOathConfiguration();
  const result = await invoke(account);
  assert.equal(result.error.status, 'FAILED_PRECONDITION');
  await assertNoPartialAcceptance(account);
});

test('signs the pending version atomically with server identity and time', async () => {
  const account = await newActor();
  const pending = await seedPendingSignature(account);
  const result = await invokeSign(account, { actorId: 'forged-user', signedAt: '2000-01-01' });
  assert.equal(result.result.alreadySigned, false);
  assert.equal(result.result.signatureId, 'declarantSignature_v1_r2');
  assert.equal(result.result.eventId, 'declarantSigned_v1_r2');
  assert.equal(result.result.revision, 2);

  const root = (await firestore.doc(`declarations/${account.declarationId}`).get()).data();
  const mirror = (await firestore.doc(`declarations/${account.declarationId}/versions/1`).get()).data();
  const event = (await firestore.doc(
    `declarations/${account.declarationId}/events/declarantSigned_v1_r2`,
  ).get()).data();
  assert.equal(root.status, 'signedByDeclarant');
  assert.equal(root.revision, 2);
  assert.equal(root.version, 1);
  assert.equal(root.declarantSignature, 'declarantSignature_v1_r2');
  assert.ok(root.declarantSignedAt instanceof Timestamp);
  assert.equal(mirror.status, root.status);
  assert.equal(mirror.revision, root.revision);
  assert.equal(mirror.declarantSignature, root.declarantSignature);
  assert.ok(mirror.declarantSignedAt.isEqual(root.declarantSignedAt));
  assert.equal(event.actorId, account.uid);
  assert.equal(event.action, 'declarantSigned');
  assert.equal(event.details,
    'version=1;revision=2;signatureId=declarantSignature_v1_r2');
  assert.ok(event.occurredAt.isEqual(root.declarantSignedAt));
  assert.ok(root.oathAcceptedAt.isEqual(pending.oathAcceptedAt));
  assert.ok(result.result.signedAt);
});

test('signed declarant explicitly submits the version and it appears in the assigned supervisor inbox', async () => {
  const account = await newActor();
  const supervisor = await newActor('supervisor');
  const pending = await seedPendingSignature(account);
  const signed = await invokeSign(account);
  assert.equal(signed.result.alreadySigned, false);
  assert.equal((await firestore.doc(`declarations/${account.declarationId}`).get()).get('status'), 'signedByDeclarant');

  await firestore.doc(`supervisor_assignments/${account.uid}`).set({
    declarantId: account.uid,
    supervisorId: supervisor.uid,
    revision: 1,
    updatedAt: Timestamp.now(),
    updatedBy: 'trusted-test-fixture',
  });
  const beforeSubmit = await invokeCallable(statusFunctionUrl, account, {
    declarationId: account.declarationId,
  });
  assert.equal(beforeSubmit.result.responsible.type, 'declarant');
  assert.equal(beforeSubmit.result.responsible.uid, account.uid);

  const request = {
    declarationId: account.declarationId,
    expectedVersion: 1,
    expectedRevision: 2,
    confirmed: true,
  };
  const submitted = await invokeCallable(submitFunctionUrl, account, request);
  assert.equal(submitted.result.alreadySubmitted, false);
  assert.equal(submitted.result.revision, 3);
  assert.equal(submitted.result.eventId, 'submitToSuperior_v1_r3');

  const declarationRef = firestore.doc(`declarations/${account.declarationId}`);
  const declaration = (await declarationRef.get()).data();
  const mirror = (await declarationRef.collection('versions').doc('1').get()).data();
  const event = (await declarationRef.collection('events').doc('submitToSuperior_v1_r3').get()).data();
  assert.equal(declaration.status, 'pendingSuperiorSignature');
  assert.equal(declaration.revision, 3);
  assert.deepEqual(mirror, declaration);
  assert.equal(event.actorId, account.uid);
  assert.equal(event.action, 'submitToSuperior');
  assert.equal(event.details, 'version=1;revision=2;submittedRevision=3');
  assert.ok(event.occurredAt.isEqual(declaration.updatedAt));
  assert.equal(declaration.declarantSignedAt.toDate().toISOString(), signed.result.signedAt);
  assert.ok(pending.oathAcceptedAt.isEqual(declaration.oathAcceptedAt));

  const afterSubmit = await invokeCallable(statusFunctionUrl, account, {
    declarationId: account.declarationId,
  });
  assert.equal(afterSubmit.result.responsible.type, 'supervisor');
  assert.equal(afterSubmit.result.responsible.uid, supervisor.uid);
  const inbox = await invokeCallable(inboxFunctionUrl, supervisor);
  assert.deepEqual(inbox.result.declarations.map((row) => row.declarationId), [account.declarationId]);

  const retry = await invokeCallable(submitFunctionUrl, account, request);
  assert.equal(retry.result.alreadySubmitted, true);
  assert.equal((await declarationRef.collection('events').get()).size, 3);
});

test('signature rejects unauthenticated, inactive, missing-active, wrong-role and wrong-owner actors', async () => {
  const unauthenticated = await newActor();
  let pending = await seedPendingSignature(unauthenticated);
  let result = await invokeSign(unauthenticated, {}, false);
  assert.equal(result.error.status, 'UNAUTHENTICATED');
  await assertPendingUnchanged(unauthenticated, pending);

  for (const profileOptions of [{ active: undefined }, { active: false }]) {
    const account = await newActor('declarant', profileOptions);
    pending = await seedPendingSignature(account);
    result = await invokeSign(account);
    assert.equal(result.error.status, 'PERMISSION_DENIED');
    await assertPendingUnchanged(account, pending);
  }

  const supervisor = await newActor('supervisor');
  pending = await seedPendingSignature(supervisor);
  result = await invokeSign(supervisor);
  assert.equal(result.error.status, 'PERMISSION_DENIED');
  await assertPendingUnchanged(supervisor, pending);

  const wrongOwner = await newActor();
  pending = await seedPendingSignature(wrongOwner);
  const otherOwnerDeclaration = { ...pending, personId: 'another-owner' };
  await firestore.doc(`declarations/${wrongOwner.declarationId}`).set(otherOwnerDeclaration);
  await firestore.doc(`declarations/${wrongOwner.declarationId}/versions/1`).set(otherOwnerDeclaration);
  result = await invokeSign(wrongOwner);
  assert.equal(result.error.status, 'PERMISSION_DENIED');
  const event = await firestore.doc(
    `declarations/${wrongOwner.declarationId}/events/declarantSigned_v1_r2`,
  ).get();
  assert.deepEqual((await firestore.doc(`declarations/${wrongOwner.declarationId}`).get()).data(), otherOwnerDeclaration);
  assert.deepEqual((await firestore.doc(`declarations/${wrongOwner.declarationId}/versions/1`).get()).data(), otherOwnerDeclaration);
  assert.equal(event.exists, false);
});

test('signature rejects wrong state, stale version or revision and missing confirmation atomically', async () => {
  const account = await newActor();
  const wrongState = await seedPendingSignature(account, { status: 'validated' });
  let result = await invokeSign(account);
  assert.equal(result.error.status, 'FAILED_PRECONDITION');
  await assertPendingUnchanged(account, wrongState);

  const staleAccount = await newActor();
  const pending = await seedPendingSignature(staleAccount);
  result = await invokeSign(staleAccount, { expectedRevision: 0 });
  assert.equal(result.error.status, 'FAILED_PRECONDITION');
  await assertPendingUnchanged(staleAccount, pending);
  result = await invokeSign(staleAccount, { expectedVersion: 2 });
  assert.equal(result.error.status, 'FAILED_PRECONDITION');
  await assertPendingUnchanged(staleAccount, pending);
  result = await invokeSign(staleAccount, { expectedRevision: -1 });
  assert.equal(result.error.status, 'INVALID_ARGUMENT');
  await assertPendingUnchanged(staleAccount, pending);

  for (const confirmed of [false, undefined]) {
    result = await invokeSign(staleAccount, { confirmed });
    assert.equal(result.error.status, 'INVALID_ARGUMENT');
    await assertPendingUnchanged(staleAccount, pending);
  }
});

test('retries of a completed signature are idempotent and do not duplicate audit', async () => {
  const account = await newActor();
  const originalPending = await seedPendingSignature(account);
  assert.equal((await invokeSign(account)).result.alreadySigned, false);
  const signed = (await firestore.doc(`declarations/${account.declarationId}`).get()).data();
  const eventBefore = (await firestore.doc(
    `declarations/${account.declarationId}/events/declarantSigned_v1_r2`,
  ).get()).data();
  const retry = await invokeSign(account);
  assert.equal(retry.result.alreadySigned, true);
  assert.equal(retry.result.signatureId, 'declarantSignature_v1_r2');
  assert.deepEqual((await firestore.doc(`declarations/${account.declarationId}`).get()).data(), signed);
  assert.deepEqual((await firestore.doc(`declarations/${account.declarationId}/versions/1`).get()).data(), signed);
  assert.deepEqual((await firestore.doc(
    `declarations/${account.declarationId}/events/declarantSigned_v1_r2`,
  ).get()).data(), eventBefore);
  const events = await firestore.collection(`declarations/${account.declarationId}/events`).get();
  assert.deepEqual(events.docs.map((doc) => doc.id).sort(), [
    'declarantSigned_v1_r2', 'oathAccepted_v1_r1',
  ]);
  assert.ok(signed.oathAcceptedAt.isEqual(originalPending.oathAcceptedAt));
});

test('signature rejects inconsistent pre-existing events or version mirrors without partial writes', async () => {
  for (const corruption of ['event', 'mirror']) {
    const account = await newActor();
    const pending = await seedPendingSignature(account);
    const eventRef = firestore.doc(
      `declarations/${account.declarationId}/events/declarantSigned_v1_r2`,
    );
    const mirrorRef = firestore.doc(`declarations/${account.declarationId}/versions/1`);
    if (corruption === 'event') {
      await eventRef.set({
        id: 'declarantSigned_v1_r2', declarationId: account.declarationId,
        actorId: account.uid, action: 'declarantSigned', occurredAt: Timestamp.now(),
        details: 'malformed',
      });
    } else {
      await mirrorRef.update({ revision: 99 });
    }
    const eventBefore = (await eventRef.get()).data();
    const mirrorBefore = (await mirrorRef.get()).data();
    const result = await invokeSign(account);
    assert.equal(result.error.status, corruption === 'event' ? 'ALREADY_EXISTS' : 'FAILED_PRECONDITION');
    assert.deepEqual((await firestore.doc(`declarations/${account.declarationId}`).get()).data(), pending);
    assert.deepEqual((await mirrorRef.get()).data(), mirrorBefore);
    if (eventBefore !== undefined) assert.deepEqual((await eventRef.get()).data(), eventBefore);
  }
});

test('a new formal version can accept and sign without changing its previous signed version', async () => {
  const account = await newActor();
  await seedOathConfiguration();
  const oldOathAt = Timestamp.fromMillis(Date.now() - 3000);
  await firestore.doc('institutional_texts/declarant_oath/versions/1').update({
    approvedAt: Timestamp.fromMillis(Date.now() - 4000),
  });
  const oldSignature = {
    id: 'declarantSigned_v1_r2', declarationId: account.declarationId,
    actorId: account.uid, action: 'declarantSigned', occurredAt: Timestamp.now(),
    details: 'version=1;revision=2;signatureId=declarantSignature_v1_r2',
  };
  const oldVersion = {
    ...(await seedDeclaration(account, { status: 'signedByDeclarant', revision: 2 })),
    oathAcceptedAt: oldOathAt,
    declarantSignedAt: oldSignature.occurredAt,
    declarantSignature: 'declarantSignature_v1_r2',
  };
  await firestore.doc(`declarations/${account.declarationId}/versions/1`).set(oldVersion);
  await firestore.doc(`declarations/${account.declarationId}/events/oathAccepted_v1_r1`).set({
    id: 'oathAccepted_v1_r1', declarationId: account.declarationId,
    actorId: account.uid, action: 'oathAccepted', occurredAt: oldOathAt,
    details: 'version=1;revision=1;oathTextVersion=1',
  });
  await firestore.doc(`declarations/${account.declarationId}/events/declarantSigned_v1_r2`).set(oldSignature);
  const newDeclarationId = `${account.declarationId}_v2`;
  additionalDeclarationIds.push(newDeclarationId);
  const current = {
    ...oldVersion,
    status: 'validated',
    version: 2,
    revision: 0,
    parentVersionId: account.declarationId,
    oathAcceptedAt: null,
    declarantSignedAt: null,
    declarantSignature: null,
    superiorSignedAt: null,
    superiorSignature: null,
    returnObservation: null,
    hrReceivedAt: null,
    finalizedAt: null,
    finalPdfPath: null,
  };
  await firestore.doc(`declarations/${newDeclarationId}`).set(current);
  await firestore.doc(`declarations/${newDeclarationId}/versions/2`).set(current);
  const previousVersionBefore = (await firestore.doc(`declarations/${account.declarationId}/versions/1`).get()).data();
  const previousEventBefore = (await firestore.doc(`declarations/${account.declarationId}/events/declarantSigned_v1_r2`).get()).data();
  const accepted = await invoke(account, {
    declarationId: newDeclarationId,
    expectedVersion: 2,
    expectedRevision: 0,
  });
  assert.equal(accepted.result.alreadyAccepted, false);
  const result = await invokeSign(account, {
    declarationId: newDeclarationId,
    expectedVersion: 2,
    expectedRevision: 1,
  });
  assert.equal(result.result.alreadySigned, false);
  assert.equal(result.result.signatureId, 'declarantSignature_v2_r2');
  assert.deepEqual((await firestore.doc(`declarations/${account.declarationId}/versions/1`).get()).data(), previousVersionBefore);
  assert.deepEqual((await firestore.doc(`declarations/${account.declarationId}/events/declarantSigned_v1_r2`).get()).data(), previousEventBefore);
  assert.equal((await firestore.doc(`declarations/${newDeclarationId}`).get()).get('status'), 'signedByDeclarant');
});

async function readApprovedOath(account, authenticated = true) {
  const response = await fetch(functionUrl.replace(/acceptOath$/, 'getApprovedDeclarantOath'), {
    method: 'POST', headers: { 'Content-Type': 'application/json',
      ...(authenticated ? { Authorization: `Bearer ${account.idToken}` } : {}) },
    body: JSON.stringify({ data: {} }),
  });
  return response.json();
}

test('approved text endpoint returns exactly the approved version and wording', async () => {
  const account = await newActor();
  await seedOathConfiguration({ text: 'Texto aprobado para la prueba de lectura.' });
  const response = await readApprovedOath(account);
  assert.deepEqual(response.result, { version: 1, text: 'Texto aprobado para la prueba de lectura.' });
});

test('approved text endpoint rejects anonymous, inactive and wrong-role callers', async () => {
  const account = await newActor();
  await seedOathConfiguration();
  assert.equal((await readApprovedOath(account, false)).error.status, 'UNAUTHENTICATED');
  const inactive = await newActor('declarant', { active: false });
  assert.equal((await readApprovedOath(inactive)).error.status, 'PERMISSION_DENIED');
  const supervisor = await newActor('supervisor');
  assert.equal((await readApprovedOath(supervisor)).error.status, 'PERMISSION_DENIED');
});

test('approved text endpoint does not return missing or unapproved wording', async () => {
  const account = await newActor();
  assert.equal((await readApprovedOath(account)).error.status, 'FAILED_PRECONDITION');
  await seedOathConfiguration({ versionStatus: 'draft' });
  assert.equal((await readApprovedOath(account)).error.status, 'FAILED_PRECONDITION');
});

test('a new approved version after reading rejects acceptance without partial writes', async () => {
  const account = await newActor();
  await seedDeclaration(account);
  await seedOathConfiguration();
  const displayed = await readApprovedOath(account);
  await seedOathConfiguration({ approvedVersion: 2, version: 2 });
  const response = await invoke(account, { expectedOathTextVersion: displayed.result.version });
  assert.equal(response.error.status, 'FAILED_PRECONDITION');
  await assertNoPartialAcceptance(account);
  const refreshed = await readApprovedOath(account);
  const accepted = await invoke(account, { expectedOathTextVersion: refreshed.result.version });
  assert.equal(accepted.result.oathTextVersion, 2);
});

test('acceptance rejects a missing displayed-text version', async () => {
  const account = await newActor();
  await seedDeclaration(account);
  await seedOathConfiguration();
  assert.equal((await invoke(account, { expectedOathTextVersion: null })).error.status, 'INVALID_ARGUMENT');
  await assertNoPartialAcceptance(account);
});
