import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} from 'firebase/firestore';
import { deleteObject, getBytes, ref, uploadString } from 'firebase/storage';

let env;
const projectId = process.env.FIRESTORE_TEST_PROJECT_ID ?? 'demo-declara-horario';
const profile = {
  name: 'Persona de prueba',
  identification: '123',
  phone: '88888888',
  email: 'test@example.com',
  unit: 'Sur',
  role: 'declarant',
  active: true,
};
const payload = {
  schemaVersion: 1,
  profile: {
    name: profile.name,
    identification: profile.identification,
    phone: profile.phone,
    email: profile.email,
    unit: profile.unit,
  },
  appointments: [{
    id: 'appointment-1',
    workplace: 'Sede Central',
    position: 'Docente',
    weeklyMinutes: 240,
    startsOn: '2026-01-01',
    endsOn: '2026-12-31',
    institution: '',
    blocks: [{ day: 1, start: 480, end: 720 }],
  }],
  externalJobs: [],
  observations: 'Observación de prueba',
};

function declaration(overrides = {}) {
  return {
    personId: 'alice',
    periodId: 'period',
    createdAt: Timestamp.now(),
    updatedAt: serverTimestamp(),
    status: 'draft',
    version: 1,
    parentVersionId: null,
    revision: 0,
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
    ...overrides,
  };
}

function auditEvent(id, declarationId, actorId, action = 'created', version = 1,
  estadoAnterior = action === 'created' ? null : 'draft', estadoNuevo = 'draft') {
  return {
    id,
    declarationId,
    actorId,
    action,
    occurredAt: serverTimestamp(),
    details: null,
    version,
    estadoAnterior,
    estadoNuevo,
  };
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1',
      port: 8180,
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
    storage: {
      host: '127.0.0.1',
      port: 9199,
      rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8'),
    },
  });
});

test('PDF finales no admiten lectura ni escritura directa desde Flutter', async () => {
  const path = 'final-declarations/alice_period/v1.pdf';
  await env.withSecurityRulesDisabled(async (context) => {
    await uploadString(ref(context.storage(), path), '%PDF-1.4 test fixture');
  });
  const storage = env.authenticatedContext('alice').storage();
  await assertFails(uploadString(ref(storage, path), '%PDF-1.4 overwritten'));
  await assertFails(getBytes(ref(storage, path)));
  await env.withSecurityRulesDisabled(async (context) => {
    await deleteObject(ref(context.storage(), path));
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    await setDoc(doc(database, 'users/alice'), profile);
    await setDoc(doc(database, 'users/bob'), profile);
    await setDoc(doc(database, 'academic_periods/period'), {
      name: 'II',
      isActive: true,
      startsAt: Timestamp.fromMillis(Date.now() - 86400000),
      endsAt: Timestamp.fromMillis(Date.now() + 86400000),
    });
  });
});

const db = (uid = 'alice') => env.authenticatedContext(uid).firestore();
const declarationRef = (database) => doc(database, 'declarations/alice_period');
const versionRef = (database, id = '1') =>
  doc(database, `declarations/alice_period/versions/${id}`);
const eventRef = (database, id) =>
  doc(database, `declarations/alice_period/events/${id}`);

async function create(database, {
  declarationData = declaration(),
  includeVersion = true,
  includeEvent = true,
  readRelatedDocs = false,
  eventId = 'created_v1',
  eventData,
} = {}) {
  const root = declarationRef(database);
  const version = versionRef(database);
  const event = eventRef(database, eventId);
  const period = doc(database, 'academic_periods/period');
  return runTransaction(database, async (transaction) => {
    await transaction.get(root);
    if (readRelatedDocs) {
      await transaction.get(version);
      await transaction.get(event);
    }
    await transaction.get(period);
    transaction.set(root, declarationData);
    if (includeVersion) transaction.set(version, declarationData);
    if (includeEvent) {
      transaction.set(
        event,
        eventData ?? auditEvent(eventId, 'alice_period', 'alice'),
      );
    }
  });
}

async function submitEdit(database, proposed, {
  eventId = `formUpdated_v${proposed.revision}`,
  eventData,
  includeVersion = true,
  includeEvent = true,
} = {}) {
  const root = declarationRef(database);
  const version = versionRef(database);
  const event = eventRef(database, eventId);
  return runTransaction(database, async (transaction) => {
    await transaction.get(root);
    await transaction.get(version);
    await transaction.get(event);
    transaction.set(root, proposed);
    if (includeVersion) transaction.set(version, proposed);
    if (includeEvent) {
      transaction.set(
        event,
        eventData ?? auditEvent(eventId, 'alice_period', 'alice', 'formUpdated',
          proposed.version, 'draft', proposed.status),
      );
    }
  });
}

async function readWithoutRules(path) {
  let result;
  await env.withSecurityRulesDisabled(async (context) => {
    result = await getDoc(doc(context.firestore(), path));
  });
  return result;
}

test('DECLARANTE existente permite crear declaración y completar perfil sin cambiar role ni active', async () => {
  await env.withSecurityRulesDisabled((context) => setDoc(
    doc(context.firestore(), 'users/alice'),
    { name: 'Persona de prueba', email: 'test@example.com', role: 'DECLARANTE', active: true },
  ));
  const database = db();
  await assertSucceeds(create(database));
  await assertSucceeds(updateDoc(doc(database, 'users/alice'), {
    name: 'Persona de prueba',
    email: 'test@example.com',
    identification: '123',
    phone: '88888888',
    unit: 'Sur',
  }));
  const saved = (await getDoc(doc(database, 'users/alice'))).data();
  if (saved.role !== 'DECLARANTE' || saved.active !== true) {
    throw new Error('Se alteró el perfil existente');
  }
  await assertFails(updateDoc(doc(database, 'users/alice'), { role: 'declarant' }));
  await assertFails(updateDoc(doc(database, 'users/alice'), { active: false }));
  await assertFails(updateDoc(doc(database, 'users/alice'), { supervisorId: 'bob' }));
});

test('un usuario no puede crear campos de administración ni autoasignarse otro estado', async () => {
  await assertFails(setDoc(doc(db('carol'), 'users/carol'), { ...profile, isAdministrator: true }));
  await assertFails(setDoc(doc(db('carol'), 'users/carol'), { ...profile, active: false }));
  await assertFails(setDoc(doc(db('carol'), 'users/carol'), (({ active, ...rest }) => rest)(profile)));
});

test('el perfil debe estar activo para crear o modificar declaraciones y el texto institucional es server-only', async () => {
  const database = db();
  const currentDeclaration = declaration();
  await env.withSecurityRulesDisabled((context) => updateDoc(
    doc(context.firestore(), 'users/alice'), { active: false },
  ));
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'declarations/alice_period'), currentDeclaration);
    await setDoc(doc(context.firestore(), 'declarations/alice_period/versions/1'), currentDeclaration);
  });
  await assertFails(create(database));
  await assertFails(submitEdit(database, declaration({
    ...currentDeclaration,
    revision: 1,
  })));
  await assertFails(setDoc(doc(db('bob'), 'system_config/declarant_oath'), {
    status: 'approved', approvedVersion: 1,
  }));
  await assertFails(setDoc(doc(
    db('bob'),
    'institutional_texts/declarant_oath/versions/1',
  ), {
    status: 'approved', version: 1, text: 'CLIENT PROVIDED', approvedAt: Timestamp.now(),
  }));
});

test('perfil propio se puede crear/editar pero no elevar rol', async () => {
  const carol = db('carol');
  await assertSucceeds(setDoc(doc(carol, 'users/carol'), profile));
  await assertSucceeds(updateDoc(doc(carol, 'users/carol'), { name: 'Nuevo nombre' }));
  await assertFails(updateDoc(doc(carol, 'users/carol'), { role: 'administrator' }));
  await assertFails(setDoc(doc(db('mallory'), 'users/mallory'), { ...profile, role: 'administrator' }));
});

test('períodos, roles y el historial de cambios de rol son server-only', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users/admin'), {
      ...profile,
      role: 'administrator',
    });
  });
  const admin = db('admin');
  await assertFails(setDoc(doc(admin, 'academic_periods/new-period'), {
    name: 'Nuevo período',
    startsAt: Timestamp.now(),
    endsAt: Timestamp.fromMillis(Date.now() + 86400000),
    isActive: true,
  }));
  await assertFails(updateDoc(doc(admin, 'users/alice'), { role: 'administrator' }));
  await assertFails(updateDoc(doc(admin, 'users/admin'), { role: 'supervisor' }));
  await assertFails(setDoc(doc(admin, 'users/alice/role_events/roleChanged_v1'), {
    id: 'roleChanged_v1',
    action: 'roleChanged',
    targetUid: 'alice',
    actorId: 'admin',
    previousRole: 'declarant',
    role: 'administrator',
    revision: 1,
    occurredAt: serverTimestamp(),
  }));
});

test('supervisores no pueden leer declaraciones asignadas directamente ni alterar asignaciones', async () => {
  const declarationId = 'alice_period';
  await env.withSecurityRulesDisabled(async (context) => {
    const admin = context.firestore();
    await setDoc(doc(admin, 'users/supervisor'), {
      ...profile,
      role: 'supervisor',
    });
    await setDoc(doc(admin, 'supervisor_assignments/alice'), {
      declarantId: 'alice',
      supervisorId: 'supervisor',
      revision: 1,
      updatedAt: Timestamp.now(),
      updatedBy: 'admin',
    });
    await setDoc(doc(admin, `declarations/${declarationId}`), declaration());
  });

  const supervisorDb = db('supervisor');
  await assertFails(getDoc(doc(supervisorDb, `declarations/${declarationId}`)));
  await assertFails(getDocs(query(
    collection(supervisorDb, 'declarations'),
    where('personId', '==', 'alice'),
  )));
  await assertFails(getDoc(doc(supervisorDb, 'supervisor_assignments/alice')));
  await assertFails(setDoc(doc(supervisorDb, 'supervisor_assignments/alice'), {
    declarantId: 'alice', supervisorId: 'supervisor', revision: 2,
  }));
});

test('creación atómica escribe declaración, versions/1 y events/created_v1', async () => {
  const database = db();
  await assertSucceeds(create(database));
  const root = (await getDoc(declarationRef(database))).data();
  const version = (await getDoc(versionRef(database))).data();
  const createdEvent = (await getDoc(eventRef(database, 'created_v1'))).data();
  if (root.revision !== 0 || root.payload.profile.identification !== '123') {
    throw new Error('La declaración no conserva el esquema esperado');
  }
  if (version.revision !== root.revision || version.payload.appointments[0].blocks[0].day !== 1) {
    throw new Error('La versión no coincide con la declaración');
  }
  if (createdEvent.id !== 'created_v1' || createdEvent.actorId !== 'alice' || createdEvent.action !== 'created') {
    throw new Error('El evento created no conserva los campos canónicos');
  }
});

test('la transacción de creación puede leer versiones y eventos relacionados aún inexistentes', async () => {
  // FirestoreDeclarationRepository.saveWithAudit hace estas lecturas antes de escribir.
  await assertSucceeds(create(db(), { readRelatedDocs: true }));
});

test('creación rechaza propietario incorrecto y no deja escrituras parciales', async () => {
  const data = declaration({ personId: 'bob' });
  await assertFails(create(db(), { declarationData: data }));
  for (const path of [
    'declarations/alice_period',
    'declarations/alice_period/versions/1',
    'declarations/alice_period/events/created_v1',
  ]) {
    if ((await readWithoutRules(path)).exists()) throw new Error(`Quedó escritura parcial: ${path}`);
  }
});

test('creación rechaza actor incorrecto aunque incluya declaración y versión', async () => {
  await assertFails(create(db(), {
    eventData: auditEvent('created_v1', 'alice_period', 'bob'),
  }));
});

test('creación rechaza si falta el evento obligatorio y no guarda documentos parciales', async () => {
  await assertFails(create(db(), { includeEvent: false }));
  for (const path of [
    'declarations/alice_period',
    'declarations/alice_period/versions/1',
    'declarations/alice_period/events/created_v1',
  ]) {
    if ((await readWithoutRules(path)).exists()) throw new Error(`Quedó escritura parcial: ${path}`);
  }
});

test('creación rechaza si falta versions/1 aunque declaración y evento estén presentes', async () => {
  await assertFails(create(db(), { includeVersion: false }));
  for (const path of [
    'declarations/alice_period',
    'declarations/alice_period/versions/1',
    'declarations/alice_period/events/created_v1',
  ]) {
    if ((await readWithoutRules(path)).exists()) throw new Error(`Quedó escritura parcial: ${path}`);
  }
});

test('creación rechaza una forma de payload que no coincide con DeclarationForm.toMap()', async () => {
  const badPayload = { ...payload, extra: true };
  await assertFails(create(db(), { declarationData: declaration({ payload: badPayload }) }));
});

test('la creación cliente sigue limitada a la versión formal 1 con todos los documentos relacionados', async () => {
  const database = db();
  const data = declaration({ version: 2, parentVersionId: null });
  const root = doc(database, 'declarations/alice_period');
  const version = doc(database, 'declarations/alice_period/versions/2');
  const event = doc(database, 'declarations/alice_period/events/created_v1');
  const period = doc(database, 'academic_periods/period');
  await assertFails(runTransaction(database, async (transaction) => {
    await transaction.get(root);
    await transaction.get(version);
    await transaction.get(event);
    await transaction.get(period);
    transaction.set(root, data);
    transaction.set(version, data);
    transaction.set(event, auditEvent('created_v1', 'alice_period', 'alice'));
  }));
  for (const path of [
    'declarations/alice_period',
    'declarations/alice_period/versions/2',
    'declarations/alice_period/events/created_v1',
  ]) {
    if ((await readWithoutRules(path)).exists()) throw new Error(`Quedó escritura parcial: ${path}`);
  }
});

test('sin autenticación no se puede leer', async () => {
  await create(db());
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'declarations/alice_period')));
});

test('se consulta por propietario y se rechaza leer o editar declaración ajena', async () => {
  const database = db();
  await create(database);
  await assertSucceeds(getDocs(query(collection(database, 'declarations'), where('personId', '==', 'alice'))));
  await assertFails(getDoc(declarationRef(db('bob'))));
  const initial = (await getDoc(declarationRef(database))).data();
  await assertFails(submitEdit(db('bob'), declaration({ ...initial, revision: 1, updatedAt: serverTimestamp() })));
});

test('la lectura previa de hijos ausentes no expone hijos ajenos ni documentos huérfanos', async () => {
  const database = db();
  await create(database);
  const bob = db('bob');
  await assertFails(getDoc(versionRef(bob)));
  await assertFails(getDoc(eventRef(bob, 'not-created')));

  await env.withSecurityRulesDisabled(async (context) => {
    const admin = context.firestore();
    await setDoc(doc(admin, 'declarations/ghost_period/versions/1'), declaration());
    await setDoc(doc(admin, 'declarations/ghost_period/events/created_v1'),
      auditEvent('created_v1', 'ghost_period', 'ghost'));
  });
  await assertFails(getDoc(doc(bob, 'declarations/ghost_period/versions/1')));
  await assertFails(getDoc(doc(bob, 'declarations/ghost_period/events/created_v1')));
});

test('edición atómica escribe revisión consecutiva, versión y formUpdated_v1', async () => {
  const database = db();
  await create(database);
  const current = (await getDoc(declarationRef(database))).data();
  const proposed = declaration({
    ...current,
    payload: { ...payload, observations: 'Formulario editado' },
    revision: 1,
    updatedAt: serverTimestamp(),
  });
  await assertSucceeds(submitEdit(database, proposed));
  const root = (await getDoc(declarationRef(database))).data();
  const version = (await getDoc(versionRef(database))).data();
  const event = (await getDoc(eventRef(database, 'formUpdated_v1'))).data();
  if (root.revision !== 1 || root.payload.observations !== 'Formulario editado') {
    throw new Error('La edición no quedó guardada');
  }
  if (version.revision !== 1 || version.payload.observations !== root.payload.observations) {
    throw new Error('La versión no se actualizó junto con la declaración');
  }
  if (event.id !== 'formUpdated_v1' || event.action !== 'formUpdated' || event.actorId !== 'alice') {
    throw new Error('El evento formUpdated no es canónico');
  }
});

test('edición de una versión formal existente actualiza versions/{version} sin cambiarla', async () => {
  const database = db();
  const id = 'alice_period_v2';
  const initial = declaration({
    version: 2,
    parentVersionId: 'alice_period',
    updatedAt: Timestamp.now(),
  });
  await env.withSecurityRulesDisabled(async (context) => {
    const admin = context.firestore();
    await setDoc(doc(admin, `declarations/${id}`), initial);
    await setDoc(doc(admin, `declarations/${id}/versions/2`), initial);
  });

  const root = doc(database, `declarations/${id}`);
  const version = doc(database, `declarations/${id}/versions/2`);
  const event = doc(database, `declarations/${id}/events/formUpdated_v1`);
  const proposed = declaration({
    ...initial,
    payload: { ...payload, observations: 'Edición de la versión formal 2' },
    revision: 1,
    updatedAt: serverTimestamp(),
  });
  await assertSucceeds(runTransaction(database, async (transaction) => {
    await transaction.get(root);
    await transaction.get(version);
    await transaction.get(event);
    transaction.set(root, proposed);
    transaction.set(version, proposed);
    transaction.set(event, auditEvent('formUpdated_v1', id, 'alice', 'formUpdated',
      proposed.version, 'draft', proposed.status));
  }));

  const saved = (await getDoc(root)).data();
  const mirrored = (await getDoc(version)).data();
  if (saved.version !== 2 || saved.parentVersionId !== 'alice_period' || saved.revision !== 1) {
    throw new Error('La edición alteró la identidad de la versión formal');
  }
  if (mirrored.version !== 2 || mirrored.revision !== 1 ||
      mirrored.payload.observations !== 'Edición de la versión formal 2') {
    throw new Error('No se actualizó el espejo de la versión formal 2');
  }
});

test('el propietario puede leer el historial canónico en orden cronológico', async () => {
  const database = db();
  await create(database);
  const current = (await getDoc(declarationRef(database))).data();
  await assertSucceeds(submitEdit(database, declaration({
    ...current,
    revision: 1,
    updatedAt: serverTimestamp(),
  })));
  const history = await getDocs(query(
    collection(database, 'declarations/alice_period/events'),
    orderBy('occurredAt'),
  ));
  const ids = history.docs.map((event) => event.id);
  if (ids.join(',') !== 'created_v1,formUpdated_v1') {
    throw new Error(`El historial canónico tiene orden inesperado: ${ids.join(',')}`);
  }
});

test('edición rechaza actor incorrecto y conserva revisión, versión e historial', async () => {
  const database = db();
  await create(database);
  const original = (await getDoc(declarationRef(database))).data();
  await assertFails(submitEdit(database, declaration({ ...original, revision: 1, updatedAt: serverTimestamp() }), {
    eventData: auditEvent('formUpdated_v1', 'alice_period', 'bob', 'formUpdated'),
  }));
  if ((await getDoc(declarationRef(database))).data().revision !== 0) {
    throw new Error('La transacción rechazada modificó la declaración');
  }
  if ((await getDoc(versionRef(database))).data().revision !== 0) {
    throw new Error('La transacción rechazada modificó la versión');
  }
  if ((await getDoc(eventRef(database, 'formUpdated_v1'))).exists()) {
    throw new Error('La transacción rechazada creó el evento');
  }
});

test('edición rechaza si omite el evento obligatorio sin guardar cambios parciales', async () => {
  const database = db();
  await create(database);
  const original = (await getDoc(declarationRef(database))).data();
  const proposed = declaration({ ...original, revision: 1, updatedAt: serverTimestamp() });
  await assertFails(submitEdit(database, proposed, { includeEvent: false }));
  if ((await getDoc(declarationRef(database))).data().revision !== 0 ||
      (await getDoc(versionRef(database))).data().revision !== 0 ||
      (await getDoc(eventRef(database, 'formUpdated_v1'))).exists()) {
    throw new Error('La transacción rechazada dejó cambios parciales');
  }
});

test('edición rechaza si omite la versión aunque la declaración y el evento estén presentes', async () => {
  const database = db();
  await create(database);
  const original = (await getDoc(declarationRef(database))).data();
  await assertFails(submitEdit(database, declaration({ ...original, revision: 1, updatedAt: serverTimestamp() }), {
    includeVersion: false,
  }));
  if ((await getDoc(declarationRef(database))).data().revision !== 0 ||
      (await getDoc(versionRef(database))).data().revision !== 0 ||
      (await getDoc(eventRef(database, 'formUpdated_v1'))).exists()) {
    throw new Error('La transacción rechazada dejó cambios parciales');
  }
});

test('edición rechaza una revisión no consecutiva con todas las escrituras relacionadas', async () => {
  const database = db();
  await create(database);
  const original = (await getDoc(declarationRef(database))).data();
  await assertFails(submitEdit(database, declaration({ ...original, revision: 2, updatedAt: serverTimestamp() })));
  if ((await getDoc(declarationRef(database))).data().revision !== 0 ||
      (await getDoc(versionRef(database))).data().revision !== 0 ||
      (await getDoc(eventRef(database, 'formUpdated_v2'))).exists()) {
    throw new Error('La revisión no consecutiva produjo escrituras parciales');
  }
});

test('edición rechaza una revisión obsoleta repetida y no duplica su evento', async () => {
  const database = db();
  await create(database);
  const staleBase = (await getDoc(declarationRef(database))).data();
  const firstRevision = declaration({ ...staleBase, revision: 1, updatedAt: serverTimestamp() });
  await assertSucceeds(submitEdit(database, firstRevision));
  const staleRetry = declaration({ ...staleBase, revision: 1, updatedAt: serverTimestamp() });
  await assertFails(submitEdit(database, staleRetry));
  if ((await getDoc(declarationRef(database))).data().revision !== 1 ||
      !(await getDoc(eventRef(database, 'formUpdated_v1'))).exists()) {
    throw new Error('El reintento obsoleto alteró el estado confirmado');
  }
});

test('no se cambian propietario, período, versión, fecha de creación ni campos protegidos', async () => {
  const database = db();
  await create(database);
  const original = (await getDoc(declarationRef(database))).data();
  const protectedChanges = [
    { personId: 'bob' },
    { periodId: 'otro' },
    { version: 2 },
    { createdAt: Timestamp.fromMillis(original.createdAt.toMillis() + 1) },
    { parentVersionId: 'other-version' },
    { declarantSignature: 'firma-falsificada' },
    { superiorSignature: 'firma-falsificada' },
    { status: 'signedByDeclarant' },
  ];
  for (const change of protectedChanges) {
    await assertFails(submitEdit(database, declaration({
      ...original,
      ...change,
      revision: 1,
      updatedAt: serverTimestamp(),
    })));
  }
  if ((await getDoc(declarationRef(database))).data().revision !== 0 ||
      (await getDoc(versionRef(database))).data().revision !== 0 ||
      (await getDoc(eventRef(database, 'formUpdated_v1'))).exists()) {
    throw new Error('Una modificación protegida dejó cambios parciales');
  }
});

test('no se pueden sobrescribir ni eliminar eventos canónicos existentes', async () => {
  const database = db();
  await create(database);
  const created = eventRef(database, 'created_v1');
  await assertFails(updateDoc(created, { action: 'otro' }));
  await assertFails(deleteDoc(created));
  const original = (await getDoc(created)).data();
  if (original.action !== 'created') throw new Error('El evento histórico se modificó');
  await assertFails(submitEdit(database, declaration({
    ...(await getDoc(declarationRef(database))).data(),
    revision: 1,
    updatedAt: serverTimestamp(),
  }), { eventId: 'created_v1' }));
});

test('no se acepta juramento sin registro aprobado y transici?n at?mica', async () => {
  const database = db();
  await create(database);
  const draft = (await getDoc(declarationRef(database))).data();
  await assertSucceeds(submitEdit(database, declaration({
    ...draft,
    status: 'validated',
    revision: 1,
    updatedAt: serverTimestamp(),
  })));

  const root = declarationRef(database);
  const version = versionRef(database);
  const event = eventRef(database, 'oathAccepted_v1_r2');
  const validated = (await getDoc(root)).data();
  const forged = declaration({
    ...validated,
    status: 'pendingDeclarantSignature',
    revision: 2,
    oathAcceptedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  await assertFails(runTransaction(database, async (transaction) => {
    await transaction.get(root);
    await transaction.get(version);
    await transaction.get(event);
    transaction.set(root, forged);
    transaction.set(version, forged);
    transaction.set(event, auditEvent(
      'oathAccepted_v1_r2', 'alice_period', 'alice', 'oathAccepted',
    ));
  }));

  if ((await getDoc(root)).data().status !== 'validated' ||
      (await getDoc(root)).data().revision !== 1 ||
      (await getDoc(version)).data().status !== 'validated' ||
      (await getDoc(version)).data().revision !== 1 ||
      (await getDoc(event)).exists()) {
    throw new Error('La escritura directa rechazada dejó cambios parciales');
  }
});

test('un cliente no puede firmar directamente ni modificar el espejo o crear el evento', async () => {
  const database = db();
  const acceptedAt = Timestamp.now();
  const pending = declaration({
    status: 'pendingDeclarantSignature',
    revision: 1,
    oathAcceptedAt: acceptedAt,
    updatedAt: acceptedAt,
  });
  const acceptedEvent = {
    ...auditEvent('oathAccepted_v1_r1', 'alice_period', 'alice', 'oathAccepted'),
    occurredAt: acceptedAt,
    details: 'version=1;revision=1;oathTextVersion=1',
  };
  await env.withSecurityRulesDisabled(async (context) => {
    const admin = context.firestore();
    await setDoc(doc(admin, 'declarations/alice_period'), pending);
    await setDoc(doc(admin, 'declarations/alice_period/versions/1'), pending);
    await setDoc(doc(admin, 'declarations/alice_period/events/oathAccepted_v1_r1'), acceptedEvent);
  });

  const root = declarationRef(database);
  const version = versionRef(database);
  const event = eventRef(database, 'declarantSigned_v1_r2');
  const signed = declaration({
    ...pending,
    status: 'signedByDeclarant',
    revision: 2,
    declarantSignedAt: serverTimestamp(),
    declarantSignature: 'declarantSignature_v1_r2',
    updatedAt: serverTimestamp(),
  });
  await assertFails(runTransaction(database, async (transaction) => {
    await transaction.get(root);
    await transaction.get(version);
    await transaction.get(event);
    transaction.set(root, signed);
    transaction.set(version, signed);
    transaction.set(event, auditEvent(
      'declarantSigned_v1_r2', 'alice_period', 'alice', 'declarantSigned',
    ));
  }));

  if ((await getDoc(root)).data().status !== 'pendingDeclarantSignature' ||
      (await getDoc(root)).data().revision !== 1 ||
      (await getDoc(version)).data().status !== 'pendingDeclarantSignature' ||
      (await getDoc(version)).data().revision !== 1 ||
      (await getDoc(event)).exists()) {
    throw new Error('La firma directa rechazada dejó cambios parciales');
  }
});

test('el período inactivo impide creación aunque se envíen las tres escrituras', async () => {
  await env.withSecurityRulesDisabled((context) => updateDoc(
    doc(context.firestore(), 'academic_periods/period'),
    { isActive: false },
  ));
  await assertFails(create(db()));
});

test('el período fuera de vigencia impide creación sin escrituras parciales', async () => {
  await env.withSecurityRulesDisabled((context) => updateDoc(
    doc(context.firestore(), 'academic_periods/period'), {
      startsAt: Timestamp.fromMillis(Date.now() - 3 * 86400000),
      endsAt: Timestamp.fromMillis(Date.now() - 86400000),
      isActive: true,
    },
  ));
  await assertFails(create(db()));
  if ((await readWithoutRules('declarations/alice_period')).exists()) {
    throw new Error('La operación rechazada dejó una declaración guardada');
  }
  if ((await readWithoutRules('declarations/alice_period/versions/1')).exists()) {
    throw new Error('La operación rechazada dejó una versión guardada');
  }
  if ((await readWithoutRules('declarations/alice_period/events/created_v1')).exists()) {
    throw new Error('La operación rechazada dejó un evento guardado');
  }
});

test('las reglas rechazan toda escritura Spark directa de aceptación y firma', async () => {
  const database = db();
  const root = declarationRef(database);
  const version = versionRef(database);
  const oathEvent = eventRef(database, 'oathAccepted_v1_r2');
  const signatureEvent = eventRef(database, 'declarantSigned_v1_r2');
  const validated = declaration({ status: 'validated', revision: 1 });
  const oathTransition = declaration({
    ...validated,
    status: 'pendingDeclarantSignature',
    revision: 2,
    oathAcceptedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await env.withSecurityRulesDisabled(async (context) => {
    const admin = context.firestore();
    await setDoc(doc(admin, 'declarations/alice_period'), validated);
    await setDoc(doc(admin, 'declarations/alice_period/versions/1'), validated);
  });
  await assertFails(runTransaction(database, async (transaction) => {
    await transaction.get(root);
    await transaction.get(version);
    await transaction.get(oathEvent);
    transaction.set(root, oathTransition);
    transaction.set(version, oathTransition);
    transaction.set(oathEvent, {
      ...auditEvent('oathAccepted_v1_r2', 'alice_period', 'alice', 'oathAccepted'),
      details: 'version=1;revision=2;oathTextVersion=1',
    });
  }));
  await assertFails(setDoc(oathEvent, {
    ...auditEvent('oathAccepted_v1_r2', 'alice_period', 'alice', 'oathAccepted'),
  }));
  if ((await getDoc(root)).data().status !== 'validated' ||
      (await getDoc(version)).data().status !== 'validated' ||
      (await getDoc(oathEvent)).exists()) {
    throw new Error('La aceptación directa rechazada dejó cambios parciales');
  }

  const pending = declaration({
    ...validated,
    status: 'pendingDeclarantSignature',
    oathAcceptedAt: Timestamp.now(),
  });
  await env.withSecurityRulesDisabled(async (context) => {
    const admin = context.firestore();
    await setDoc(doc(admin, 'declarations/alice_period'), pending);
    await setDoc(doc(admin, 'declarations/alice_period/versions/1'), pending);
  });
  const signatureTransition = declaration({
    ...pending,
    status: 'signedByDeclarant',
    revision: 2,
    declarantSignedAt: serverTimestamp(),
    declarantSignature: 'declarantSignature_v1_r2',
    updatedAt: serverTimestamp(),
  });
  await assertFails(runTransaction(database, async (transaction) => {
    await transaction.get(root);
    await transaction.get(version);
    await transaction.get(signatureEvent);
    transaction.set(root, signatureTransition);
    transaction.set(version, signatureTransition);
    transaction.set(signatureEvent, {
      ...auditEvent('declarantSigned_v1_r2', 'alice_period', 'alice', 'declarantSigned'),
      details: 'version=1;revision=2;signatureId=declarantSignature_v1_r2',
    });
  }));
  await assertFails(setDoc(signatureEvent, {
    ...auditEvent('declarantSigned_v1_r2', 'alice_period', 'alice', 'declarantSigned'),
  }));
  if ((await getDoc(root)).data().status !== 'pendingDeclarantSignature' ||
      (await getDoc(version)).data().status !== 'pendingDeclarantSignature' ||
      (await getDoc(signatureEvent)).exists()) {
    throw new Error('La firma directa rechazada dejó cambios parciales');
  }
});

test('los eventos canónicos existentes de juramento y firma no se actualizan ni eliminan', async () => {
  const oathAt = Timestamp.fromMillis(Date.now() - 2_000);
  const signedAt = Timestamp.fromMillis(Date.now() - 1_000);
  const signedDeclaration = declaration({
    status: 'signedByDeclarant',
    revision: 2,
    oathAcceptedAt: oathAt,
    declarantSignedAt: signedAt,
    declarantSignature: 'declarantSignature_v1_r2',
    updatedAt: signedAt,
  });
  const oathEvent = {
    id: 'oathAccepted_v1_r1',
    declarationId: 'alice_period',
    actorId: 'alice',
    action: 'oathAccepted',
    occurredAt: oathAt,
    details: 'version=1;revision=1;oathTextVersion=1',
  };
  const signatureEvent = {
    id: 'declarantSigned_v1_r2',
    declarationId: 'alice_period',
    actorId: 'alice',
    action: 'declarantSigned',
    occurredAt: signedAt,
    details: 'version=1;revision=2;signatureId=declarantSignature_v1_r2',
  };

  await env.withSecurityRulesDisabled(async (context) => {
    const admin = context.firestore();
    await setDoc(doc(admin, 'declarations/alice_period'), signedDeclaration);
    await setDoc(doc(admin, 'declarations/alice_period/versions/1'), signedDeclaration);
    await setDoc(doc(admin, 'declarations/alice_period/events/oathAccepted_v1_r1'), oathEvent);
    await setDoc(doc(admin, 'declarations/alice_period/events/declarantSigned_v1_r2'), signatureEvent);
  });

  const database = db();
  const oathRef = eventRef(database, 'oathAccepted_v1_r1');
  const signatureRef = eventRef(database, 'declarantSigned_v1_r2');
  for (const reference of [oathRef, signatureRef]) {
    await assertFails(updateDoc(reference, { details: 'alterado por cliente' }));
    await assertFails(deleteDoc(reference));
  }

  await env.withSecurityRulesDisabled(async (context) => {
    const admin = context.firestore();
    const savedOath = await getDoc(doc(admin, 'declarations/alice_period/events/oathAccepted_v1_r1'));
    const savedSignature = await getDoc(doc(admin, 'declarations/alice_period/events/declarantSigned_v1_r2'));
    const savedOathData = savedOath.data();
    const savedSignatureData = savedSignature.data();
    if (savedOathData.id !== oathEvent.id || savedOathData.declarationId !== oathEvent.declarationId ||
        savedOathData.actorId !== oathEvent.actorId || savedOathData.action !== oathEvent.action ||
        !savedOathData.occurredAt.isEqual(oathEvent.occurredAt) || savedOathData.details !== oathEvent.details ||
        savedSignatureData.id !== signatureEvent.id || savedSignatureData.declarationId !== signatureEvent.declarationId ||
        savedSignatureData.actorId !== signatureEvent.actorId || savedSignatureData.action !== signatureEvent.action ||
        !savedSignatureData.occurredAt.isEqual(signatureEvent.occurredAt) || savedSignatureData.details !== signatureEvent.details) {
      throw new Error('Un evento canónico cambió tras una operación cliente rechazada');
    }
  });
});
