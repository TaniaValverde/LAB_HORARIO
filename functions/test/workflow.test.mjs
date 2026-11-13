import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

const projectId = 'demo-declara-horario';
const authUrl = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const functionsUrl = `http://127.0.0.1:5001/${projectId}/us-central1`;
let app;
let firestore;
const actors = [];
const declarationIds = [];
const oathTextVersions = [];
let nextOathTextVersion = 10000;
process.env.FIREBASE_STORAGE_EMULATOR_HOST = '127.0.0.1:9199';

before(() => {
  app = initializeApp({ projectId }, `workflow-${randomUUID()}`);
  firestore = getFirestore(app);
  firestore.settings({ host: '127.0.0.1:8180', ssl: false });
});

after(async () => {
  for (const id of declarationIds) {
    await firestore.recursiveDelete(firestore.doc(`declarations/${id}`)).catch(() => {});
    await getStorage(app).bucket(`${projectId}.appspot.com`)
      .file(`final-declarations/${id}/v1.pdf`).delete({ ignoreNotFound: true }).catch(() => {});
  }
  for (const version of oathTextVersions) {
    await firestore.doc(`institutional_texts/declarant_oath/versions/${version}`).delete().catch(() => {});
  }
  for (const actor of actors) {
    await firestore.recursiveDelete(firestore.doc(`supervisor_assignments/${actor.uid}`)).catch(() => {});
    await firestore.recursiveDelete(firestore.doc(`users/${actor.uid}`)).catch(() => {});
    await fetch(`${authUrl}/accounts:delete?key=fake-api-key`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idToken: actor.idToken }),
    }).catch(() => {});
  }
  if (app) await deleteApp(app);
});

async function actor(role, active = true) {
  const response = await fetch(`${authUrl}/accounts:signUp?key=fake-api-key`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: `${role}-${randomUUID()}@example.test`, password: 'LocalTest123!', returnSecureToken: true }),
  });
  const body = await response.text();
  if (!response.ok) throw new Error(`Auth Emulator sign-up failed (${response.status}): ${body}`);
  const auth = JSON.parse(body);
  const result = { uid: auth.localId, idToken: auth.idToken };
  actors.push(result);
  await firestore.doc(`users/${result.uid}`).set({ role, active, name: `Test ${role}` });
  return result;
}

async function call(name, account, data = {}, authenticated = true) {
  const response = await fetch(`${functionsUrl}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...(authenticated ? { Authorization: `Bearer ${account.idToken}` } : {}) },
    body: JSON.stringify({ data }),
  });
  const body = await response.json();
  return { ...body, httpStatus: response.status };
}

const payload = {
  schemaVersion: 1,
  profile: { name: 'Declarante', identification: '1', phone: '1', email: 'd@example.test', unit: 'UCR' },
  appointments: [{ id: 'job', workplace: 'UCR', position: 'Docente', weeklyMinutes: 240,
    startsOn: '2026-01-01', endsOn: '2026-12-31', institution: '',
    blocks: [{ day: 1, start: 480, end: 720 }] }],
  externalJobs: [], observations: '',
};

async function seedDeclaration(owner, supervisor, status = 'pendingSuperiorSignature') {
  const id = `${owner.uid}_${randomUUID()}`;
  declarationIds.push(id);
  const oathTextVersion = nextOathTextVersion++;
  const oathText = `Texto institucional de prueba version ${oathTextVersion}`;
  oathTextVersions.push(oathTextVersion);
  const approvedAt = Timestamp.fromMillis(Date.now() - 6000);
  await firestore.doc(`institutional_texts/declarant_oath/versions/${oathTextVersion}`).set({
    status: 'approved', version: oathTextVersion, text: oathText, approvedAt,
  });
  const oathAt = Timestamp.fromMillis(Date.now() - 4000);
  const signedAt = Timestamp.fromMillis(Date.now() - 3000);
  const superiorAt = Timestamp.fromMillis(Date.now() - 2000);
  const submittedAt = Timestamp.fromMillis(Date.now() - 1000);
  const receivedAt = Timestamp.now();
  const finalizedAt = Timestamp.fromMillis(Date.now() + 1000);
  const revision = status === 'pendingSuperiorSignature' || status === 'signedByDeclarant' ? 2 : status === 'returned' || status === 'signedBySuperior' ? 3 : status === 'sentToHr' ? 4 : status === 'receivedByHr' ? 5 : status === 'finalized' ? 7 : 5;
  const updatedAt = status === 'returned' || status === 'receivedByHr' ? receivedAt : status === 'signedBySuperior' ? superiorAt : status === 'sentToHr' ? submittedAt : status === 'finalized' ? finalizedAt : signedAt;
  const declaration = {
    personId: owner.uid, periodId: '2026-II', createdAt: Timestamp.fromMillis(Date.now() - 5000),
    updatedAt, status, version: 1, revision, parentVersionId: null, payload,
    oathAcceptedAt: oathAt, declarantSignedAt: signedAt,
    declarantSignature: 'declarantSignature_v1_r2',
    superiorSignedAt: ['signedBySuperior', 'sentToHr', 'receivedByHr', 'finalized'].includes(status) ? superiorAt : null,
    superiorSignature: ['signedBySuperior', 'sentToHr', 'receivedByHr', 'finalized'].includes(status) ? 'superiorSignature_v1_r3' : null,
    returnObservation: status === 'returned' ? 'Revisar jornada' : null,
    hrReceivedAt: ['receivedByHr', 'finalized'].includes(status) ? receivedAt : null,
    finalizedAt: status === 'finalized' ? finalizedAt : null,
    finalPdfPath: status === 'finalized' ? `final-declarations/${id}/v1.pdf` : null,
  };
  const ref = firestore.doc(`declarations/${id}`);
  await ref.set(declaration);
  await ref.collection('versions').doc('1').set(declaration);
  await ref.collection('events').doc('oathAccepted_v1_r1').set({
    id: 'oathAccepted_v1_r1', declarationId: id, actorId: owner.uid,
    action: 'oathAccepted', occurredAt: oathAt,
    details: `version=1;revision=1;oathTextVersion=${oathTextVersion}`,
  });
  await ref.collection('events').doc('declarantSigned_v1_r2').set({
    id: 'declarantSigned_v1_r2', declarationId: id, actorId: owner.uid,
    action: 'declarantSigned', occurredAt: signedAt,
    details: 'version=1;revision=2;signatureId=declarantSignature_v1_r2',
  });
  if (status === 'returned') await ref.collection('events').doc('returned_v1_r3').set({
    id: 'returned_v1_r3', declarationId: id, actorId: supervisor.uid,
    action: 'returnedForCorrection', occurredAt: receivedAt, details: 'Revisar jornada',
  });
  if (['signedBySuperior', 'sentToHr', 'receivedByHr', 'finalized'].includes(status)) {
    await ref.collection('events').doc('superiorSigned_v1_r3').set({
      id: 'superiorSigned_v1_r3', declarationId: id, actorId: supervisor.uid,
      action: 'superiorSigned', occurredAt: superiorAt,
      details: 'version=1;revision=3;signatureId=superiorSignature_v1_r3',
    });
  }
  if (['sentToHr', 'receivedByHr', 'finalized'].includes(status)) await ref.collection('events').doc('sentToHr_v1_r4').set({
    id: 'sentToHr_v1_r4', declarationId: id, actorId: supervisor.uid,
    action: 'sentToHr', occurredAt: submittedAt, details: 'version=1;revision=4',
  });
  if (['receivedByHr', 'finalized'].includes(status)) {
    await ref.collection('events').doc('hrReceived_v1_r5').set({
      id: 'hrReceived_v1_r5', declarationId: id, actorId: supervisor.uid,
      action: 'hrReceived', occurredAt: receivedAt, details: 'version=1;revision=5',
    });
  }
  const assignmentUpdatedAt = Timestamp.now();
  await firestore.doc(`supervisor_assignments/${owner.uid}`).set({
    declarantId: owner.uid, supervisorId: supervisor.uid, revision: 1,
    updatedAt: assignmentUpdatedAt, updatedBy: 'trusted-seed',
  });
  await firestore.doc(`supervisor_assignments/${owner.uid}/events/supervisorAssigned_v1`).set({
    id: 'supervisorAssigned_v1', action: 'supervisorAssigned',
    declarantId: owner.uid, previousSupervisorId: null,
    supervisorId: supervisor.uid, revision: 1,
    assignedBy: 'trusted-seed', occurredAt: assignmentUpdatedAt,
  });
  return { id, ref, declaration, oathText, oathTextVersion };
}

test('getDeclarationStatus identifies the next responsible actor by workflow status', async () => {
  const owner = await actor('declarant');
  const supervisor = await actor('supervisor');

  for (const [status, expectedType, expectedName] of [
    ['signedByDeclarant', 'declarant', owner.uid],
    ['pendingSuperiorSignature', 'supervisor', supervisor.uid],
    ['signedBySuperior', 'supervisor', supervisor.uid],
    ['sentToHr', 'humanResources', 'Recursos Humanos / Administración'],
    ['receivedByHr', 'humanResources', 'Recursos Humanos / Administración'],
  ]) {
    const seeded = await seedDeclaration(owner, supervisor, status);
    const result = await call('getDeclarationStatus', owner, { declarationId: seeded.id });
    assert.equal(result.result.status, status);
    assert.equal(result.result.responsible.type, expectedType, status);
    if (expectedType === 'supervisor' || expectedType === 'declarant') {
      assert.equal(result.result.responsible.uid, expectedName, status);
    } else {
      assert.equal(result.result.responsible.name, expectedName, status);
    }
  }

  const finalized = await seedDeclaration(owner, supervisor, 'finalized');
  const result = await call('getDeclarationStatus', owner, { declarationId: finalized.id });
  assert.equal(result.result.status, 'finalized');
  assert.equal(result.result.responsible, null);
});

test('getDeclarationTimeline devuelve transición de estado y tolera eventos históricos', async () => {
  const owner = await actor('declarant');
  const supervisor = await actor('supervisor');
  const seeded = await seedDeclaration(owner, supervisor);
  const signed = await call('signAsSuperior', supervisor, {
    declarationId: seeded.id, expectedVersion: 1, expectedRevision: 2, confirmed: true,
  });
  assert.equal(signed.result.alreadySigned, false);
  const timeline = await call('getDeclarationTimeline', owner, { declarationId: seeded.id });
  const signatureEvent = timeline.result.events.find((event) => event.action === 'superiorSigned');
  assert.equal(signatureEvent.version, 1);
  assert.equal(signatureEvent.estadoAnterior, 'pendingSuperiorSignature');
  assert.equal(signatureEvent.estadoNuevo, 'signedBySuperior');
  const historicalEvent = timeline.result.events.find((event) => event.action === 'oathAccepted');
  assert.equal(historicalEvent.version, null);
  assert.equal(historicalEvent.estadoAnterior, null);
});

test('annulDeclaration registra una anulación terminal con motivo y espejo', async () => {
  const owner = await actor('declarant');
  const supervisor = await actor('supervisor');
  const administrator = await actor('administrator');
  const seeded = await seedDeclaration(owner, supervisor);
  const result = await call('annulDeclaration', administrator, {
    declarationId: seeded.id, reason: 'Duplicada por error de captura',
    expectedVersion: 1, expectedRevision: 2, confirmed: true,
  });
  assert.equal(result.result.annulled, true);
  const saved = (await seeded.ref.get()).data();
  assert.equal(saved.status, 'annulled');
  assert.equal(saved.annulmentReason, 'Duplicada por error de captura');
  assert.deepEqual((await seeded.ref.collection('versions').doc('1').get()).data(), saved);
  assert.equal((await seeded.ref.collection('events').doc('annulled_v1_r3').get()).get('action'), 'annulled');
  const status = await call('getDeclarationStatus', owner, { declarationId: seeded.id });
  assert.equal(status.result.responsible, null);
});

test('annulDeclaration exige motivo obligatorio', async () => {
  const owner = await actor('declarant');
  const supervisor = await actor('supervisor');
  const administrator = await actor('administrator');
  const seeded = await seedDeclaration(owner, supervisor);
  const result = await call('annulDeclaration', administrator, {
    declarationId: seeded.id, reason: '  ', expectedVersion: 1,
    expectedRevision: 2, confirmed: true,
  });
  assert.equal(result.error.status, 'INVALID_ARGUMENT');
  assert.equal((await seeded.ref.get()).get('status'), 'pendingSuperiorSignature');
});

test('annulDeclaration rechaza roles no autorizados y declaraciones finalizadas', async () => {
  const owner = await actor('declarant');
  const supervisor = await actor('supervisor');
  const administrator = await actor('administrator');
  const seeded = await seedDeclaration(owner, supervisor);
  const denied = await call('annulDeclaration', supervisor, {
    declarationId: seeded.id, reason: 'Motivo', expectedVersion: 1,
    expectedRevision: 2, confirmed: true,
  });
  assert.equal(denied.error.status, 'PERMISSION_DENIED');
  const finalized = await seedDeclaration(owner, supervisor, 'finalized');
  const rejected = await call('annulDeclaration', administrator, {
    declarationId: finalized.id, reason: 'Motivo', expectedVersion: 1,
    expectedRevision: 7, confirmed: true,
  });
  assert.equal(rejected.error.status, 'FAILED_PRECONDITION');
  assert.equal((await finalized.ref.get()).get('status'), 'finalized');
});

test('signAsSuperior registra firma y evento atómicamente y permite reintento idempotente', async () => {
  const owner = await actor('declarant');
  const supervisor = await actor('supervisor');
  const seeded = await seedDeclaration(owner, supervisor);
  const request = { declarationId: seeded.id, expectedVersion: 1, expectedRevision: 2, confirmed: true };
  const first = await call('signAsSuperior', supervisor, request);
  assert.equal(first.result.alreadySigned, false);
  const saved = (await seeded.ref.get()).data();
  assert.equal(saved.status, 'signedBySuperior');
  assert.equal(saved.revision, 3);
  assert.equal(saved.superiorSignature, 'superiorSignature_v1_r3');
  assert.deepEqual((await seeded.ref.collection('versions').doc('1').get()).data(), saved);
  assert.equal((await seeded.ref.collection('events').doc('superiorSigned_v1_r3').get()).get('action'), 'superiorSigned');
  const outbox = await call('getSupervisorOutbox', supervisor);
  assert.equal(outbox.result.declarations.length, 1);
  const sent = await call('sendDeclarationToHr', supervisor, {
    declarationId: seeded.id, expectedVersion: 1, expectedRevision: 3, confirmed: true,
  });
  assert.equal(sent.result.alreadySent, false);
  assert.equal((await seeded.ref.get()).get('status'), 'sentToHr');
  assert.equal((await call('getSupervisorOutbox', supervisor)).result.declarations.length, 0);
  const retry = await call('signAsSuperior', supervisor, request);
  assert.equal(retry.result.alreadySigned, true);
  assert.equal((await seeded.ref.collection('events').get()).size, 4);
});

test('la reasignación conserva con el firmante original el envío de una firma ya registrada', async () => {
  const owner = await actor('declarant');
  const originalSupervisor = await actor('supervisor');
  const nextSupervisor = await actor('supervisor');
  const administrator = await actor('administrator');
  const seeded = await seedDeclaration(owner, originalSupervisor);

  const signed = await call('signAsSuperior', originalSupervisor, {
    declarationId: seeded.id, expectedVersion: 1, expectedRevision: 2, confirmed: true,
  });
  assert.equal(signed.result.alreadySigned, false);

  const reassigned = await call('assignDeclarantSupervisor', administrator, {
    declarantId: owner.uid, supervisorId: nextSupervisor.uid,
  });
  assert.ok(
    reassigned.result,
    `assignDeclarantSupervisor failed: HTTP ${reassigned.httpStatus}; JSON ${JSON.stringify(reassigned)}`,
  );
  assert.equal(reassigned.result.revision, 2);
  assert.equal((await seeded.ref.get()).get('status'), 'signedBySuperior');
  assert.equal((await seeded.ref.collection('events').doc('superiorSigned_v1_r3').get()).get('actorId'), originalSupervisor.uid);

  const originalInbox = await call('getSupervisorOutbox', originalSupervisor);
  assert.deepEqual(originalInbox.result.declarations.map((entry) => entry.declarationId), [seeded.id]);
  const newInbox = await call('getSupervisorOutbox', nextSupervisor);
  assert.deepEqual(newInbox.result.declarations, []);

  const sent = await call('sendDeclarationToHr', originalSupervisor, {
    declarationId: seeded.id, expectedVersion: 1, expectedRevision: 3, confirmed: true,
  });
  assert.equal(sent.result.alreadySent, false);
  const denied = await call('sendDeclarationToHr', nextSupervisor, {
    declarationId: seeded.id, expectedVersion: 1, expectedRevision: 3, confirmed: true,
  });
  assert.equal(denied.error.status, 'PERMISSION_DENIED');
  const final = (await seeded.ref.get()).data();
  assert.equal(final.status, 'sentToHr');
  assert.equal(final.revision, 4);
  assert.equal((await seeded.ref.collection('events').doc('superiorSigned_v1_r3').get()).get('actorId'), originalSupervisor.uid);
});

test('returnForCorrection exige observación, asignación y conserva la transacción', async () => {
  const owner = await actor('declarant');
  const supervisor = await actor('supervisor');
  const other = await actor('supervisor');
  const seeded = await seedDeclaration(owner, supervisor);
  const denied = await call('returnForCorrection', other, {
    declarationId: seeded.id, expectedVersion: 1, expectedRevision: 2,
    observation: 'Revisar jornada', confirmed: true,
  });
  assert.equal(denied.error.status, 'PERMISSION_DENIED');
  assert.equal((await seeded.ref.get()).get('status'), 'pendingSuperiorSignature');
  const result = await call('returnForCorrection', supervisor, {
    declarationId: seeded.id, expectedVersion: 1, expectedRevision: 2,
    observation: 'Revisar jornada', confirmed: true,
  });
  assert.equal(result.result.alreadyReturned, false);
  const saved = (await seeded.ref.get()).data();
  assert.equal(saved.status, 'returned');
  assert.equal(saved.returnObservation, 'Revisar jornada');
  assert.deepEqual((await seeded.ref.collection('versions').doc('1').get()).data(), saved);
  assert.equal((await seeded.ref.collection('events').doc('returned_v1_r3').get()).get('details'), 'Revisar jornada');
});

test('createDeclarationVersion agrega una versión separada y conserva la anterior', async () => {
  const owner = await actor('declarant');
  const supervisor = await actor('supervisor');
  const seeded = await seedDeclaration(owner, supervisor, 'returned');
  const before = (await seeded.ref.get()).data();
  const result = await call('createDeclarationVersion', owner, {
    declarationId: seeded.id, expectedVersion: 1, expectedRevision: 3,
  });
  assert.equal(result.result.declarationId, `${seeded.id}_v2`);
  assert.deepEqual((await seeded.ref.get()).data(), before);
  const next = firestore.doc(`declarations/${seeded.id}_v2`);
  const nextData = (await next.get()).data();
  assert.equal(nextData.status, 'draft');
  assert.equal(nextData.version, 2);
  assert.equal(nextData.revision, 0);
  assert.equal(nextData.parentVersionId, seeded.id);
  assert.equal((await next.collection('events').doc('versionCreated_v2').get()).exists, true);
});

test('Resources Humanos recibe solo declaraciones enviadas y conserva espejo e historial', async () => {
  const owner = await actor('declarant');
  const supervisor = await actor('supervisor');
  const hr = await actor('humanResources');
  const seeded = await seedDeclaration(owner, supervisor, 'sentToHr');
  const pending = await seedDeclaration(owner, supervisor);
  const result = await call('receiveDeclarationAtHr', hr, {
    declarationId: seeded.id, expectedVersion: 1, expectedRevision: 4, confirmed: true,
  });
  assert.equal(result.result.alreadyReceived, false);
  const saved = (await seeded.ref.get()).data();
  assert.equal(saved.status, 'receivedByHr');
  assert.ok(saved.hrReceivedAt instanceof Timestamp);
  assert.deepEqual((await seeded.ref.collection('versions').doc('1').get()).data(), saved);
  assert.equal((await seeded.ref.collection('events').doc('hrReceived_v1_r5').get()).exists, true);
  const inbox = await call('getHumanResourcesInbox', hr);
  assert.ok(inbox.result.declarations.some((entry) => entry.declarationId === seeded.id));
  assert.ok(!inbox.result.declarations.some((entry) => entry.declarationId === pending.id));
  assert.ok(inbox.result.declarations.every((entry) => ['sentToHr', 'receivedByHr'].includes(entry.status)));
});

test('finalizeDeclaration falla cerrado si el PDF final seguro todavía no existe', async () => {
  const owner = await actor('declarant');
  const supervisor = await actor('supervisor');
  const hr = await actor('humanResources');
  const seeded = await seedDeclaration(owner, supervisor, 'receivedByHr');
  const before = (await seeded.ref.get()).data();
  const result = await call('finalizeDeclaration', hr, {
    declarationId: seeded.id, expectedVersion: 1, expectedRevision: 5, confirmed: true,
  });
  assert.equal(result.error.status, 'FAILED_PRECONDITION');
  assert.deepEqual((await seeded.ref.get()).data(), before);
  assert.equal((await seeded.ref.collection('events').get()).size, 5);
});

test('genera el PDF solo tras verificar firmas, lo entrega al propietario y finaliza con historial', async () => {
  const owner = await actor('declarant');
  const supervisor = await actor('supervisor');
  const unrelatedSupervisor = await actor('supervisor');
  const hr = await actor('humanResources');
  const seeded = await seedDeclaration(owner, supervisor, 'receivedByHr');
  const generated = await call('generateFinalDeclarationPdf', hr, {
    declarationId: seeded.id, expectedVersion: 1, expectedRevision: 5, confirmed: true,
  });
  assert.equal(generated.result.alreadyGenerated, false);
  assert.equal(generated.result.finalPdfPath, `final-declarations/${seeded.id}/v1.pdf`);
  const afterGeneration = (await seeded.ref.get()).data();
  assert.equal(afterGeneration.status, 'receivedByHr');
  assert.equal(afterGeneration.revision, 6);
  assert.equal((await seeded.ref.collection('events').doc('pdfGenerated_v1_r6').get()).exists, true);
  assert.deepEqual((await seeded.ref.collection('versions').doc('1').get()).data(), afterGeneration);

  const downloaded = await call('downloadFinalDeclarationPdf', owner, {
    declarationId: seeded.id, expectedVersion: 1,
  });
  assert.equal(downloaded.result.fileName, `declaracion-${seeded.id}-v1.pdf`);
  const pdfBytes = Buffer.from(downloaded.result.base64, 'base64');
  assert.ok(pdfBytes.subarray(0, 8).equals(Buffer.from('%PDF-1.4')));
  assert.ok(pdfBytes.toString('ascii').includes(
    Buffer.from(afterGeneration.declarantSignedAt.toDate().toISOString()).toString('hex').toUpperCase(),
  ));
  assert.ok(pdfBytes.toString('ascii').includes(Buffer.from(seeded.oathText).toString('hex').toUpperCase()));
  const forbidden = await call('downloadFinalDeclarationPdf', unrelatedSupervisor, {
    declarationId: seeded.id, expectedVersion: 1,
  });
  assert.equal(forbidden.error.status, 'PERMISSION_DENIED');

  const finalized = await call('finalizeDeclaration', hr, {
    declarationId: seeded.id, expectedVersion: 1, expectedRevision: 6, confirmed: true,
  });
  assert.equal(finalized.result.alreadyFinalized, false);
  const saved = (await seeded.ref.get()).data();
  assert.equal(saved.status, 'finalized');
  assert.ok(saved.finalizedAt instanceof Timestamp);
  assert.equal(saved.finalPdfPath, generated.result.finalPdfPath);
  assert.deepEqual((await seeded.ref.collection('versions').doc('1').get()).data(), saved);
});

test('rechaza generar PDF si los eventos canónicos de firma están incompletos', async () => {
  const owner = await actor('declarant');
  const supervisor = await actor('supervisor');
  const hr = await actor('humanResources');
  const seeded = await seedDeclaration(owner, supervisor, 'receivedByHr');
  const before = (await seeded.ref.get()).data();
  await seeded.ref.collection('events').doc('declarantSigned_v1_r2').update({
    details: 'version=1;revision=2',
  });

  const result = await call('generateFinalDeclarationPdf', hr, {
    declarationId: seeded.id, expectedVersion: 1, expectedRevision: 5, confirmed: true,
  });

  assert.equal(result.error.status, 'FAILED_PRECONDITION');
  assert.deepEqual((await seeded.ref.get()).data(), before);
  const [pdfExists] = await getStorage(app).bucket(`${projectId}.appspot.com`)
    .file(`final-declarations/${seeded.id}/v1.pdf`).exists();
  assert.equal(pdfExists, false);
});

test('historial admite DECLARANTE histórico y conserva propiedad y perfil activo', async () => {
  const owner = await actor('DECLARANTE');
  const other = await actor('DECLARANTE');
  const supervisor = await actor('supervisor');
  const seeded = await seedDeclaration(owner, supervisor, 'signedByDeclarant');
  const timeline = await call('getDeclarationTimeline', owner, { declarationId: seeded.id });
  assert.equal(timeline.httpStatus, 200, JSON.stringify(timeline));
  assert.ok(timeline.result.events.some(event => event.action === 'declarantSigned'));
  const denied = await call('getDeclarationTimeline', other, { declarationId: seeded.id });
  assert.equal(denied.error.status, 'PERMISSION_DENIED');
  await firestore.doc(`users/${owner.uid}`).update({ active: false });
  const inactive = await call('getDeclarationTimeline', owner, { declarationId: seeded.id });
  assert.equal(inactive.error.status, 'PERMISSION_DENIED');
});

test('superior firma después del envío aunque la revisión de la firma anterior sea menor', async () => {
  const owner = await actor('declarant');
  const supervisor = await actor('supervisor');
  const seeded = await seedDeclaration(owner, supervisor, 'signedByDeclarant');
  const submitted = await call('submitDeclarationToSupervisor', owner, {
    declarationId: seeded.id, expectedVersion: 1, expectedRevision: 2, confirmed: true,
  });
  assert.equal(submitted.result?.revision, 3, JSON.stringify(submitted));
  const request = { declarationId: seeded.id, expectedVersion: 1, expectedRevision: 3, confirmed: true };
  const signed = await call('signAsSuperior', supervisor, request);
  assert.equal(signed.result?.revision, 4, JSON.stringify(signed));
  const saved = (await seeded.ref.get()).data();
  assert.equal(saved.status, 'signedBySuperior');
  assert.equal(saved.declarantSignature, 'declarantSignature_v1_r2');
  assert.equal(saved.superiorSignature, 'superiorSignature_v1_r4');
  assert.deepEqual((await seeded.ref.collection('versions').doc('1').get()).data(), saved);
  assert.equal((await call('signAsSuperior', supervisor, request)).result?.alreadySigned, true);
});


test('returnForCorrection accepts the historical signature after submission', async () => {
  const owner = await actor('declarant');
  const supervisor = await actor('supervisor');
  const seeded = await seedDeclaration(owner, supervisor, 'signedByDeclarant');
  const sent = await call('submitDeclarationToSupervisor', owner, {
    declarationId: seeded.id, expectedVersion: 1, expectedRevision: 2, confirmed: true,
  });
  assert.equal(sent.result?.revision, 3, JSON.stringify(sent));
  const request = { declarationId: seeded.id, expectedVersion: 1, expectedRevision: 3,
    observation: 'Agregar observaciones', confirmed: true };
  const result = await call('returnForCorrection', supervisor, request);
  assert.equal(result.result?.revision, 4, JSON.stringify(result));
  const saved = (await seeded.ref.get()).data();
  assert.equal(saved.status, 'returned');
  assert.equal(saved.declarantSignature, 'declarantSignature_v1_r2');
  assert.equal(saved.returnObservation, request.observation);
  assert.deepEqual((await seeded.ref.collection('versions').doc('1').get()).data(), saved);
  assert.equal((await call('returnForCorrection', supervisor, request)).result?.alreadyReturned, true);
  const created = await call('createDeclarationVersion', owner, {
    declarationId: seeded.id, expectedVersion: 1, expectedRevision: 4,
  });
  assert.equal(created.result?.version, 2, JSON.stringify(created));
  declarationIds.push(created.result.declarationId);
  const next = (await firestore.doc(`declarations/${created.result.declarationId}`).get()).data();
  assert.equal(next.status, 'draft');
  assert.equal(next.parentVersionId, seeded.id);
  assert.equal(next.declarantSignature, null);
  assert.equal(next.oathAcceptedAt, null);
  assert.deepEqual(next.payload, saved.payload);
  assert.deepEqual((await seeded.ref.get()).data(), saved);

});
