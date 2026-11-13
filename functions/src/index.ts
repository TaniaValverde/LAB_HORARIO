import { initializeApp, getApps } from 'firebase-admin/app';
import { FieldPath, FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { isDeepStrictEqual } from 'node:util';
import { computeDeclarationContentHash } from './content_hash';
import { buildFinalDeclarationPdf } from './final_declaration_pdf';
import { validateSchedulePayload } from './schedule_validation';

if (getApps().length === 0) initializeApp();

const db = getFirestore();
const roles = new Set(['declarant', 'DECLARANTE']);
const reviewerRoles = new Set(['administrator', 'humanResources']);
const assignableRoles = new Set([
  'declarant', 'supervisor', 'humanResources', 'administrator',
]);
const oathConfigRef = db.doc('system_config/declarant_oath');

type JsonMap = Record<string, unknown>;

/** Creates or updates an academic period through an active administrator. */
export const saveAcademicPeriod = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.id !== 'string' ||
      !/^[A-Za-z0-9_-]{1,100}$/.test(data.id) ||
      typeof data.name !== 'string' || !data.name.trim() || data.name.length > 120 ||
      typeof data.startsAt !== 'string' || typeof data.endsAt !== 'string' ||
      typeof data.isActive !== 'boolean' || typeof data.createOnly !== 'boolean') {
    throw new HttpsError('invalid-argument', 'Indique un período válido.');
  }
  const startsAtMillis = Date.parse(data.startsAt);
  const endsAtMillis = Date.parse(data.endsAt);
  if (!Number.isFinite(startsAtMillis) || !Number.isFinite(endsAtMillis) ||
      endsAtMillis < startsAtMillis) {
    throw new HttpsError('invalid-argument', 'El rango de vigencia del período no es válido.');
  }
  const periodId = data.id as string;
  const periodName = (data.name as string).trim();
  const isActive = data.isActive as boolean;
  const createOnly = data.createOnly as boolean;

  const userRef = db.doc(`users/${uid}`);
  const periodRef = db.doc(`academic_periods/${periodId}`);
  return db.runTransaction(async (transaction) => {
    const [userSnapshot, periodSnapshot] = await Promise.all([
      transaction.get(userRef), transaction.get(periodRef),
    ]);
    const actor = userSnapshot.data();
    if (actor?.role !== 'administrator' || actor?.active !== true) {
      throw new HttpsError('permission-denied', 'Se requiere un perfil administrador activo para administrar períodos.');
    }
    if (createOnly && periodSnapshot.exists) {
      throw new HttpsError('already-exists', 'Ya existe un período con ese identificador.');
    }
    if (!createOnly && !periodSnapshot.exists) {
      throw new HttpsError('not-found', 'No existe el período que desea modificar.');
    }
    const now = FieldValue.serverTimestamp();
    const existingPeriod = periodSnapshot.data();
    const creationMetadata = periodSnapshot.exists
      ? {
        ...(existingPeriod?.createdAt === undefined
          ? {}
          : { createdAt: existingPeriod.createdAt }),
        ...(existingPeriod?.createdBy === undefined
          ? {}
          : { createdBy: existingPeriod.createdBy }),
      }
      : { createdAt: now, createdBy: uid };
    transaction.set(periodRef, {
      name: periodName,
      startsAt: Timestamp.fromMillis(startsAtMillis),
      endsAt: Timestamp.fromMillis(endsAtMillis),
      isActive,
      updatedAt: now,
      updatedBy: uid,
      ...creationMetadata,
    });
    return { id: periodId, created: !periodSnapshot.exists };
  });
});

/** Assigns a role to another existing profile; role changes are server-only. */
export const assignUserRole = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.targetUid !== 'string' || !data.targetUid.trim() ||
      typeof data.role !== 'string' || !assignableRoles.has(data.role)) {
    throw new HttpsError('invalid-argument', 'Indique el UID y un rol válido.');
  }
  if (data.targetUid === uid) {
    throw new HttpsError('permission-denied', 'No puede cambiar su propio rol.');
  }
  const targetUid = data.targetUid as string;
  const assignedRole = data.role as string;

  const actorRef = db.doc(`users/${uid}`);
  const targetRef = db.doc(`users/${targetUid}`);
  return db.runTransaction(async (transaction) => {
    const [actorSnapshot, targetSnapshot] = await Promise.all([
      transaction.get(actorRef), transaction.get(targetRef),
    ]);
    const actor = actorSnapshot.data();
    if (actor?.role !== 'administrator' || actor?.active !== true) {
      throw new HttpsError('permission-denied', 'Se requiere un perfil administrador activo para asignar roles.');
    }
    if (!targetSnapshot.exists) {
      throw new HttpsError('not-found', 'No existe el perfil indicado.');
    }
    const target = targetSnapshot.data()!;
    const currentRole = target.role === 'DECLARANTE' ? 'declarant' : target.role;
    if (typeof currentRole !== 'string' || !assignableRoles.has(currentRole)) {
      throw new HttpsError('failed-precondition', 'El perfil tiene un rol actual inválido.');
    }
    const currentRevision = target.roleRevision ?? 0;
    if (!Number.isSafeInteger(currentRevision) || (currentRevision as number) < 0) {
      throw new HttpsError('failed-precondition', 'El historial de roles del perfil es inconsistente.');
    }
    if (currentRole === assignedRole) {
      return { targetUid, role: assignedRole, revision: currentRevision, alreadyAssigned: true };
    }

    const revision = (currentRevision as number) + 1;
    const eventId = `roleChanged_v${revision}`;
    const eventRef = targetRef.collection('role_events').doc(eventId);
    if ((await transaction.get(eventRef)).exists) {
      throw new HttpsError('already-exists', 'El evento de cambio de rol ya existe.');
    }
    const serverTime = FieldValue.serverTimestamp();
    transaction.update(targetRef, {
      role: assignedRole,
      roleRevision: revision,
      roleUpdatedAt: serverTime,
      roleUpdatedBy: uid,
    });
    transaction.create(eventRef, {
      id: eventId,
      action: 'roleChanged',
      targetUid,
      actorId: uid,
      previousRole: currentRole,
      role: assignedRole,
      revision,
      occurredAt: serverTime,
    });
    return { targetUid, role: assignedRole, revision, alreadyAssigned: false };
  });
});

function isMap(value: unknown): value is JsonMap {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isValidSupervisorAssignment(value: unknown, declarantId: string): value is JsonMap {
  if (!isMap(value)) return false;
  return value.declarantId === declarantId &&
    typeof value.supervisorId === 'string' && value.supervisorId.trim().length > 0 &&
    Number.isSafeInteger(value.revision) && (value.revision as number) >= 1 &&
    value.updatedAt instanceof Timestamp &&
    typeof value.updatedBy === 'string' && value.updatedBy.trim().length > 0;
}

function isValidSupervisorAssignmentEvent(value: unknown, assignment: JsonMap): boolean {
  if (!isMap(value)) return false;
  const expectedKeys = [
    'action', 'assignedBy', 'declarantId', 'id', 'occurredAt',
    'previousSupervisorId', 'revision', 'supervisorId',
  ];
  const revision = assignment.revision as number;
  const previousSupervisorId = value.previousSupervisorId;
  return isDeepStrictEqual(Object.keys(value).sort(), expectedKeys) &&
    value.id === `supervisorAssigned_v${revision}` &&
    value.action === 'supervisorAssigned' &&
    value.declarantId === assignment.declarantId &&
    value.supervisorId === assignment.supervisorId &&
    value.revision === revision &&
    value.assignedBy === assignment.updatedBy &&
    value.occurredAt instanceof Timestamp &&
    assignment.updatedAt instanceof Timestamp &&
    value.occurredAt.isEqual(assignment.updatedAt) &&
    (revision === 1
      ? previousSupervisorId === null
      : typeof previousSupervisorId === 'string' &&
        previousSupervisorId.trim().length > 0 &&
        previousSupervisorId !== assignment.supervisorId);
}

function superiorSignatureRevision(declaration: JsonMap): number | null {
  if (typeof declaration.superiorSignature !== 'string') return null;
  const match = /^superiorSignature_v([1-9][0-9]*)_r([1-9][0-9]*)$/.exec(declaration.superiorSignature);
  if (!match || Number(match[1]) !== declaration.version) return null;
  const revision = Number(match[2]);
  return Number.isSafeInteger(revision) ? revision : null;
}

function matchesSuperiorSignatureEvent(
  event: JsonMap | undefined,
  declarationId: string,
  declaration: JsonMap,
  actorId: string,
): boolean {
  const signatureRevision = superiorSignatureRevision(declaration);
  const eventId = signatureRevision === null
    ? ''
    : `superiorSigned_v${declaration.version}_r${signatureRevision}`;
  return signatureRevision !== null && event?.id === eventId &&
    event.declarationId === declarationId && event.actorId === actorId &&
    event.action === 'superiorSigned' &&
    event.details === `version=${declaration.version};revision=${signatureRevision};signatureId=${declaration.superiorSignature}` &&
    ((event.contentHash === undefined && declaration.superiorContentHash == null) ||
      (event.contentHash === computeDeclarationContentHash({
        payload: declaration.payload, version: declaration.version as number,
        personId: declaration.personId as string, periodId: declaration.periodId as string,
      }) && event.contentHash === declaration.superiorContentHash)) &&
    event.occurredAt instanceof Timestamp && declaration.superiorSignedAt instanceof Timestamp &&
    event.occurredAt.isEqual(declaration.superiorSignedAt);
}

function storageBucket() {
  const configured = process.env.DECLARATION_STORAGE_BUCKET;
  const projectId = process.env.GCLOUD_PROJECT;
  const name = configured || (projectId ? `${projectId}.appspot.com` : '');
  if (!name) throw new HttpsError('failed-precondition', 'Configure DECLARATION_STORAGE_BUCKET para almacenar documentos finales.');
  return getStorage().bucket(name);
}

async function requireFinalPdfObject(declarationId: string, version: number, sourceRevision?: number) {
  const path = `final-declarations/${declarationId}/v${version}.pdf`;
  try {
    const file = storageBucket().file(path);
    const [exists] = await file.exists();
    if (!exists) throw new HttpsError('failed-precondition', 'El PDF final no existe en el almacenamiento seguro.');
    const [metadata] = await file.getMetadata();
    const custom = metadata.metadata ?? {};
    if (metadata.contentType !== 'application/pdf' || custom.declarationId !== declarationId ||
        custom.formalVersion !== String(version) ||
        (sourceRevision !== undefined && custom.sourceRevision !== String(sourceRevision))) {
      throw new HttpsError('failed-precondition', 'El objeto PDF no corresponde a esta versión.');
    }
    return { file, metadata, path };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('failed-precondition', 'No se pudo verificar el PDF en Firebase Storage. Revise el bucket y su emulador/configuración.');
  }
}

function hasOnlyKeys(value: JsonMap, allowed: string[]): boolean {
  return Object.keys(value).every((key) => allowed.includes(key));
}

function declarationAuditState(version: number, previous: string, next: string): JsonMap {
  return { version, estadoAnterior: previous, estadoNuevo: next };
}

function isCanonicalDeclarationEvent(value: unknown): value is JsonMap {
  if (!isMap(value)) return false;
  const base = ['action', 'actorId', 'declarationId', 'details', 'id', 'occurredAt'];
  const audit = ['version', 'estadoAnterior', 'estadoNuevo'];
  const optional = ['contentHash'];
  const keys = Object.keys(value).sort();
  return base.every((key) => key in value) &&
    keys.every((key) => [...base, ...audit, ...optional].includes(key)) &&
    (value.contentHash === undefined || (typeof value.contentHash === 'string' && /^[a-f0-9]{64}$/.test(value.contentHash))) &&
    (audit.every((key) => key in value)
      ? Number.isSafeInteger(value.version) && (value.version as number) >= 1 &&
        typeof value.estadoAnterior === 'string' && typeof value.estadoNuevo === 'string'
      : audit.every((key) => !(key in value)));
}

/** Read-only access to the approved wording; registry writes remain server-only. */
export const getApprovedDeclarantOath = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  return db.runTransaction(async (transaction) => {
    const user = await transaction.get(db.doc(`users/${uid}`));
    if (!roles.has(user.get('role')) || user.get('active') !== true) {
      throw new HttpsError('permission-denied', 'Se requiere un perfil de declarante activo.');
    }
    const config = (await transaction.get(oathConfigRef)).data();
    if (!config || !isDeepStrictEqual(Object.keys(config).sort(), ['approvedVersion', 'status']) ||
        config.status !== 'approved' || !Number.isSafeInteger(config.approvedVersion) || config.approvedVersion < 1) {
      throw new HttpsError('failed-precondition', 'No hay texto del juramento aprobado.');
    }
    const version = config.approvedVersion as number;
    const text = (await transaction.get(db.doc(`institutional_texts/declarant_oath/versions/${version}`))).data();
    if (!text || !isDeepStrictEqual(Object.keys(text).sort(), ['approvedAt', 'status', 'text', 'version']) ||
        text.status !== 'approved' || text.version !== version || typeof text.text !== 'string' ||
        !text.text.trim() || !(text.approvedAt instanceof Timestamp) || text.approvedAt.toMillis() > Date.now()) {
      throw new HttpsError('failed-precondition', 'La versión aprobada del texto está incompleta.');
    }
    return { version, text: text.text };
  });
});

/** Accepts the oath, but does not sign the declaration. */
export const acceptOath = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');

  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarationId !== 'string' || !data.declarationId.trim() ||
      !Number.isSafeInteger(data.expectedVersion) || (data.expectedVersion as number) < 1 ||
      !Number.isSafeInteger(data.expectedRevision) || (data.expectedRevision as number) < 0 ||
      data.accepted !== true || !Number.isSafeInteger(data.expectedOathTextVersion) ||
      (data.expectedOathTextVersion as number) < 1) {
    throw new HttpsError('invalid-argument', 'Confirme explícitamente el juramento e indique versión y revisión esperadas.');
  }

  const declarationId = data.declarationId;
  const expectedVersion = data.expectedVersion as number;
  const expectedRevision = data.expectedRevision as number;
  const newRevision = expectedRevision + 1;
  const eventId = `oathAccepted_v${expectedVersion}_r${newRevision}`;
  const declarationRef = db.collection('declarations').doc(declarationId);
  const userRef = db.collection('users').doc(uid);
  const versionRef = declarationRef.collection('versions').doc(String(expectedVersion));
  const eventRef = declarationRef.collection('events').doc(eventId);

  return db.runTransaction(async (transaction) => {
    const [userSnapshot, declarationSnapshot, versionSnapshot, eventSnapshot,
      oathConfigSnapshot] = await Promise.all([
      transaction.get(userRef), transaction.get(declarationRef),
      transaction.get(versionRef), transaction.get(eventRef),
      transaction.get(oathConfigRef),
    ]);
    if (!declarationSnapshot.exists) throw new HttpsError('not-found', 'No existe la declaración.');
    const declaration = declarationSnapshot.data()!;
    if (declaration.personId !== uid) {
      throw new HttpsError('permission-denied', 'Solo la persona propietaria puede aceptar el juramento.');
    }
    const role = userSnapshot.data()?.role;
    if (!roles.has(role) || userSnapshot.data()?.active !== true) {
      throw new HttpsError('permission-denied', 'El perfil no tiene permiso de declarante activo.');
    }
    if (declaration.version !== expectedVersion) {
      throw new HttpsError('failed-precondition', 'La versión formal indicada no está habilitada.');
    }

    const existingEvent = eventSnapshot.data();
    const eventDetailsMatch = typeof existingEvent?.details === 'string'
      ? /^version=(\d+);revision=(\d+);oathTextVersion=(\d+)$/.exec(existingEvent.details)
      : null;
    const recordedOathVersion = eventDetailsMatch ? Number(eventDetailsMatch[3]) : 0;
    const recordedOathSnapshot = recordedOathVersion > 0
      ? await transaction.get(db.doc(
        `institutional_texts/declarant_oath/versions/${recordedOathVersion}`,
      ))
      : null;
    const recordedOath = recordedOathSnapshot?.data();
    const acceptedAt = declaration.oathAcceptedAt;
    const eventOccurredAt = existingEvent?.occurredAt;
    const timestampsMatch = acceptedAt instanceof Timestamp &&
      eventOccurredAt instanceof Timestamp && declaration.updatedAt instanceof Timestamp &&
      acceptedAt.isEqual(eventOccurredAt) && acceptedAt.isEqual(declaration.updatedAt);
    const recordedOathIsValid = recordedOathSnapshot?.exists === true &&
      recordedOath !== undefined &&
      isDeepStrictEqual(Object.keys(recordedOath).sort(), [
        'approvedAt', 'status', 'text', 'version',
      ]) && recordedOath.status === 'approved' &&
      recordedOath.version === recordedOathVersion &&
      typeof recordedOath.text === 'string' && recordedOath.text.trim().length > 0 &&
      recordedOath.approvedAt instanceof Timestamp &&
      eventOccurredAt instanceof Timestamp &&
      recordedOath.approvedAt.toMillis() <= eventOccurredAt.toMillis();
    const expectedDetails =
      `version=${expectedVersion};revision=${newRevision};oathTextVersion=${recordedOathVersion}`;
    const eventHasCanonicalFields = isCanonicalDeclarationEvent(existingEvent);
    const alreadyApplied = declaration.revision === newRevision &&
      declaration.status === 'pendingDeclarantSignature' &&
      declaration.version === expectedVersion && timestampsMatch && eventHasCanonicalFields &&
      eventDetailsMatch?.[1] === String(expectedVersion) &&
      eventDetailsMatch?.[2] === String(newRevision) && recordedOathIsValid &&
      isDeepStrictEqual(versionSnapshot.data(), declaration) &&
      existingEvent?.id === eventId && existingEvent?.actorId === uid &&
      existingEvent?.action === 'oathAccepted' && existingEvent?.declarationId === declarationId &&
      existingEvent?.details === expectedDetails;
    if (alreadyApplied) {
      if (data.expectedOathTextVersion !== recordedOathVersion) {
        throw new HttpsError('failed-precondition', 'La aceptación registrada corresponde a otro texto.');
      }
      return {
        declarationId, version: expectedVersion, revision: newRevision, eventId,
        oathTextVersion: recordedOathVersion, alreadyAccepted: true,
      };
    }
    if (declaration.revision !== expectedRevision) {
      throw new HttpsError('failed-precondition', 'La declaración cambió; vuelva a cargarla antes de aceptar.');
    }
    if (declaration.status !== 'validated' || declaration.oathAcceptedAt != null) {
      throw new HttpsError('failed-precondition', 'Solo se puede aceptar el juramento en una declaración VALIDADA.');
    }

    // Server-controlled registry. Firestore rules intentionally grant no
    // client access to these paths. Keep each approved text at its versioned
    // path so audit events can identify the exact wording accepted.
    const oathConfig = oathConfigSnapshot.data();
    if (!oathConfigSnapshot.exists || !oathConfig ||
        !isDeepStrictEqual(Object.keys(oathConfig).sort(), ['approvedVersion', 'status']) ||
        oathConfig.status !== 'approved' || !Number.isSafeInteger(oathConfig.approvedVersion) ||
        (oathConfig.approvedVersion as number) < 1) {
      throw new HttpsError('failed-precondition', 'No hay un texto institucional del juramento aprobado y configurado.');
    }
    const oathTextVersion = oathConfig.approvedVersion as number;
    if (data.expectedOathTextVersion !== oathTextVersion) {
      throw new HttpsError('failed-precondition', 'El texto aprobado cambió; vuelva a leerlo y confirme nuevamente.');
    }
    const acceptedDetails =
      `version=${expectedVersion};revision=${newRevision};oathTextVersion=${oathTextVersion}`;
    const oathTextRef = db.doc(`institutional_texts/declarant_oath/versions/${oathTextVersion}`);
    const oathTextSnapshot = await transaction.get(oathTextRef);
    const oathText = oathTextSnapshot.data();
    if (!oathTextSnapshot.exists || !oathText ||
        !isDeepStrictEqual(Object.keys(oathText).sort(), ['approvedAt', 'status', 'text', 'version']) ||
        oathText.status !== 'approved' || oathText.version !== oathTextVersion ||
        typeof oathText.text !== 'string' || oathText.text.trim().length === 0 ||
        !(oathText.approvedAt instanceof Timestamp) || oathText.approvedAt.toMillis() > Date.now()) {
      throw new HttpsError('failed-precondition', 'La versión aprobada del texto institucional está incompleta o es inconsistente.');
    }
    if (!versionSnapshot.exists || versionSnapshot.get('version') !== expectedVersion ||
        versionSnapshot.get('revision') !== expectedRevision ||
        versionSnapshot.get('personId') !== uid || versionSnapshot.get('status') !== 'validated' ||
        !isDeepStrictEqual(versionSnapshot.get('payload'), declaration.payload)) {
      throw new HttpsError('failed-precondition', 'El espejo de la versión formal no coincide con la declaración.');
    }
    if (!versionSnapshot.get('createdAt')?.isEqual(declaration.createdAt)) {
      throw new HttpsError('failed-precondition', 'La identidad de la versión formal no coincide.');
    }
    if (!eventSnapshot.exists) {
      const validation = validateSchedulePayload(declaration.payload);
      if (!validation.valid) {
        throw new HttpsError('failed-precondition', `El contenido no supera la validación del servidor: ${validation.reason}`);
      }
    } else {
      throw new HttpsError('already-exists', 'El evento de aceptación ya existe y no corresponde a una operación confirmada.');
    }

    const serverTime = FieldValue.serverTimestamp();
    const updated = {
      ...declaration,
      status: 'pendingDeclarantSignature',
      revision: newRevision,
      oathAcceptedAt: serverTime,
      updatedAt: serverTime,
    };
    transaction.set(declarationRef, updated);
    transaction.set(versionRef, updated);
    transaction.create(eventRef, {
      id: eventId,
      declarationId,
      actorId: uid,
      action: 'oathAccepted',
      occurredAt: serverTime,
      details: acceptedDetails,
      ...declarationAuditState(expectedVersion, 'validated', 'pendingDeclarantSignature'),
    });
    return {
      declarationId, version: expectedVersion, revision: newRevision, eventId,
      oathTextVersion, alreadyAccepted: false,
    };
  });
});

/** Signs the already oath-accepted formal version; it does not accept the oath. */
export const signDeclaration = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');

  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarationId !== 'string' || !data.declarationId.trim() ||
      !Number.isSafeInteger(data.expectedVersion) || (data.expectedVersion as number) < 1 ||
      !Number.isSafeInteger(data.expectedRevision) ||
      (data.expectedRevision as number) < 0 || data.confirmed !== true) {
    throw new HttpsError('invalid-argument', 'Confirme explícitamente la firma e indique versión y revisión esperadas.');
  }

  const declarationId = data.declarationId;
  const expectedVersion = data.expectedVersion as number;
  const expectedRevision = data.expectedRevision as number;
  // Revision 0 is a well-formed but stale value for signing; like other
  // stale version/revision requests, it is rejected as failed-precondition.
  const signedRevision = expectedRevision + 1;
  const signatureId = `declarantSignature_v${expectedVersion}_r${signedRevision}`;
  const eventId = `declarantSigned_v${expectedVersion}_r${signedRevision}`;
  const declarationRef = db.collection('declarations').doc(declarationId);
  const userRef = db.collection('users').doc(uid);
  const versionRef = declarationRef.collection('versions').doc(String(expectedVersion));
  const eventRef = declarationRef.collection('events').doc(eventId);
  const oathEventRef = declarationRef.collection('events')
    .doc(`oathAccepted_v${expectedVersion}_r${expectedRevision}`);

  const alreadySigned = await db.runTransaction(async (transaction) => {
    const [userSnapshot, declarationSnapshot, versionSnapshot, eventSnapshot,
      oathEventSnapshot] = await Promise.all([
      transaction.get(userRef), transaction.get(declarationRef),
      transaction.get(versionRef), transaction.get(eventRef),
      transaction.get(oathEventRef),
    ]);
    if (!declarationSnapshot.exists) throw new HttpsError('not-found', 'No existe la declaración.');
    const declaration = declarationSnapshot.data()!;
    if (declaration.personId !== uid) {
      throw new HttpsError('permission-denied', 'Solo la persona propietaria puede firmar la declaración.');
    }
    const role = userSnapshot.data()?.role;
    if (!roles.has(role) || userSnapshot.data()?.active !== true) {
      throw new HttpsError('permission-denied', 'El perfil no tiene permiso de declarante activo.');
    }
    if (declaration.version !== expectedVersion) {
      throw new HttpsError('failed-precondition', 'La versión formal indicada no está habilitada.');
    }

    const oathEvent = oathEventSnapshot.data();
    const oathDetails = typeof oathEvent?.details === 'string'
      ? /^version=(\d+);revision=(\d+);oathTextVersion=(\d+)$/.exec(oathEvent.details)
      : null;
    const oathTextVersion = oathDetails ? Number(oathDetails[3]) : 0;
    const oathTextSnapshot = oathTextVersion > 0
      ? await transaction.get(db.doc(
        `institutional_texts/declarant_oath/versions/${oathTextVersion}`,
      ))
      : null;
    const oathText = oathTextSnapshot?.data();
    const oathTime = declaration.oathAcceptedAt;
    const oathEventTime = oathEvent?.occurredAt;
    const oathEventIsValid = oathEventSnapshot.exists && isCanonicalDeclarationEvent(oathEvent) &&
      oathEvent.id === oathEventRef.id &&
      oathEvent.declarationId === declarationId && oathEvent.actorId === uid &&
      oathEvent.action === 'oathAccepted' && oathDetails?.[1] === String(expectedVersion) &&
      oathDetails?.[2] === String(expectedRevision) &&
      oathTime instanceof Timestamp && oathEventTime instanceof Timestamp &&
      oathTime.isEqual(oathEventTime) && oathTextSnapshot?.exists === true &&
      oathText !== undefined && isDeepStrictEqual(Object.keys(oathText).sort(), [
        'approvedAt', 'status', 'text', 'version',
      ]) && oathText.status === 'approved' && oathText.version === oathTextVersion &&
      typeof oathText.text === 'string' && oathText.text.trim().length > 0 &&
      oathText.approvedAt instanceof Timestamp &&
      oathText.approvedAt.toMillis() <= oathEventTime.toMillis();
    if (!oathEventIsValid) {
      throw new HttpsError('failed-precondition', 'No se pudo verificar el juramento histórico de esta versión.');
    }

    const declarationData = declarationSnapshot.data()!;
    const versionData = versionSnapshot.data();
    const signatureContentHash = computeDeclarationContentHash({
      payload: declaration.payload, version: expectedVersion,
      personId: declaration.personId as string, periodId: declaration.periodId as string,
    });
    const signatureEvent = eventSnapshot.data();
    const signatureEventTime = signatureEvent?.occurredAt;
    const signedAt = declaration.declarantSignedAt;
    const timestampsMatch = signedAt instanceof Timestamp &&
      signatureEventTime instanceof Timestamp && declaration.updatedAt instanceof Timestamp &&
      signedAt.isEqual(signatureEventTime) && signedAt.isEqual(declaration.updatedAt);
    const signatureDetails =
      `version=${expectedVersion};revision=${signedRevision};signatureId=${signatureId}`;
    const signatureEventIsCanonical = isCanonicalDeclarationEvent(signatureEvent) &&
      signatureEvent.id === eventId &&
      signatureEvent.declarationId === declarationId && signatureEvent.actorId === uid &&
      signatureEvent.action === 'declarantSigned' &&
      signatureEvent.details === signatureDetails && signatureEventTime instanceof Timestamp &&
      ((signatureEvent.contentHash === undefined && declaration.declarantContentHash == null) ||
        signatureEvent.contentHash === signatureContentHash);
    const alreadySigned = declaration.status === 'signedByDeclarant' &&
      declaration.revision === signedRevision && declaration.version === expectedVersion &&
      declaration.declarantSignature === signatureId && timestampsMatch &&
      ((declaration.declarantContentHash == null && signatureEvent?.contentHash === undefined) ||
        declaration.declarantContentHash === signatureContentHash) &&
      signatureEventIsCanonical && isDeepStrictEqual(versionData, declarationData);
    if (alreadySigned) return true;

    if (declaration.revision !== expectedRevision) {
      throw new HttpsError('failed-precondition', 'La declaración cambió; vuelva a cargarla antes de firmar.');
    }
    if (eventSnapshot.exists) {
      throw new HttpsError('already-exists', 'El evento de firma ya existe y no corresponde a una firma confirmada.');
    }
    if (declaration.status !== 'pendingDeclarantSignature' ||
        !(declaration.oathAcceptedAt instanceof Timestamp) ||
        declaration.declarantSignedAt != null || declaration.declarantSignature != null ||
        !(declaration.updatedAt instanceof Timestamp) ||
        !declaration.updatedAt.isEqual(declaration.oathAcceptedAt)) {
      throw new HttpsError('failed-precondition', 'Solo se puede firmar la versión pendiente de firma del declarante.');
    }
    if (!versionSnapshot.exists || !isDeepStrictEqual(versionData, declarationData) ||
        declaration.personId !== uid || declaration.version !== expectedVersion) {
      throw new HttpsError('failed-precondition', 'El espejo de la versión formal no coincide con la declaración.');
    }
    const validation = validateSchedulePayload(declaration.payload);
    if (!validation.valid) {
      throw new HttpsError('failed-precondition', `El contenido no supera la validación del servidor: ${validation.reason}`);
    }

    const serverTime = FieldValue.serverTimestamp();
    const updated = {
      ...declaration,
      status: 'signedByDeclarant',
      revision: signedRevision,
      declarantSignedAt: serverTime,
      declarantSignature: signatureId,
      declarantContentHash: signatureContentHash,
      updatedAt: serverTime,
    };
    transaction.set(declarationRef, updated);
    transaction.set(versionRef, updated);
    transaction.create(eventRef, {
      id: eventId,
      declarationId,
      actorId: uid,
      action: 'declarantSigned',
      occurredAt: serverTime,
      details: signatureDetails,
      contentHash: signatureContentHash,
      ...declarationAuditState(expectedVersion, 'pendingDeclarantSignature', 'signedByDeclarant'),
    });
    return false;
  });

  const signedDeclaration = await declarationRef.get();
  const signedAt = signedDeclaration.get('declarantSignedAt');
  if (!(signedAt instanceof Timestamp)) {
    throw new HttpsError('internal', 'No se pudo confirmar la fecha de firma del servidor.');
  }
  return {
    declarationId,
    version: expectedVersion,
    revision: signedRevision,
    signatureId,
    eventId,
    alreadySigned,
    signedAt: signedAt.toDate().toISOString(),
  };
});

/** Explicitly submits a signed declarant version to its currently assigned supervisor. */
export const submitDeclarationToSupervisor = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarationId !== 'string' || !data.declarationId.trim() ||
      !Number.isSafeInteger(data.expectedVersion) || (data.expectedVersion as number) < 1 ||
      !Number.isSafeInteger(data.expectedRevision) || (data.expectedRevision as number) < 1 ||
      data.confirmed !== true) {
    throw new HttpsError('invalid-argument', 'Confirme el envío e indique versión y revisión esperadas.');
  }

  const declarationId = data.declarationId;
  const version = data.expectedVersion as number;
  const revision = data.expectedRevision as number;
  const nextRevision = revision + 1;
  const declarationRef = db.doc(`declarations/${declarationId}`);
  const versionRef = declarationRef.collection('versions').doc(String(version));
  const eventId = `submitToSuperior_v${version}_r${nextRevision}`;
  const eventRef = declarationRef.collection('events').doc(eventId);
  const signatureId = `declarantSignature_v${version}_r${revision}`;
  const signatureEventId = `declarantSigned_v${version}_r${revision}`;

  const alreadySubmitted = await db.runTransaction(async (transaction) => {
    const [profileSnapshot, declarationSnapshot, versionSnapshot, eventSnapshot,
      signatureEventSnapshot] = await Promise.all([
      transaction.get(db.doc(`users/${uid}`)), transaction.get(declarationRef),
      transaction.get(versionRef), transaction.get(eventRef),
      transaction.get(declarationRef.collection('events').doc(signatureEventId)),
    ]);
    const profile = profileSnapshot.data();
    if (!roles.has(profile?.role as string) || profile?.active !== true) {
      throw new HttpsError('permission-denied', 'Se requiere un perfil declarante activo.');
    }
    if (!declarationSnapshot.exists) throw new HttpsError('not-found', 'No existe la declaración.');
    const declaration = declarationSnapshot.data()!;
    if (declaration.personId !== uid) {
      throw new HttpsError('permission-denied', 'Solo la persona propietaria puede enviar la declaración.');
    }
    if (declaration.version !== version) {
      throw new HttpsError('failed-precondition', 'La versión formal indicada ya no está vigente.');
    }
    if (!versionSnapshot.exists || !isDeepStrictEqual(versionSnapshot.data(), declaration)) {
      throw new HttpsError('failed-precondition', 'El espejo de la versión formal no coincide con la declaración.');
    }

    const signedAt = declaration.declarantSignedAt;
    if (!(signedAt instanceof Timestamp) || !(declaration.oathAcceptedAt instanceof Timestamp)) {
      throw new HttpsError('failed-precondition', 'Faltan las fechas verificables del juramento o la firma.');
    }
    const signatureEvent = signatureEventSnapshot.data();
    const signatureDetails = `version=${version};revision=${revision};signatureId=${signatureId}`;
    const signatureIsValid = declaration.declarantSignature === signatureId &&
      signedAt.toMillis() >= declaration.oathAcceptedAt.toMillis() &&
      signatureEventSnapshot.exists && isCanonicalDeclarationEvent(signatureEvent) &&
      signatureEvent.id === signatureEventId &&
      signatureEvent.declarationId === declarationId && signatureEvent.actorId === uid &&
      signatureEvent.action === 'declarantSigned' && signatureEvent.details === signatureDetails &&
      signatureEvent.occurredAt instanceof Timestamp && signatureEvent.occurredAt.isEqual(signedAt);
    if (!signatureIsValid) {
      throw new HttpsError('failed-precondition', 'No se pudo verificar la firma histórica del declarante.');
    }

    const event = eventSnapshot.data();
    const eventDetails = `version=${version};revision=${revision};submittedRevision=${nextRevision}`;
    const downstreamStatuses = [
      'pendingSuperiorSignature', 'returned', 'signedBySuperior', 'sentToHr', 'receivedByHr', 'finalized',
    ];
    const eventIsValid = eventSnapshot.exists && isCanonicalDeclarationEvent(event) &&
      event.id === eventId && event.declarationId === declarationId &&
      event.actorId === uid && event.action === 'submitToSuperior' &&
      event.details === eventDetails && event.occurredAt instanceof Timestamp &&
      event.occurredAt.toMillis() >= signedAt.toMillis() &&
      declaration.updatedAt instanceof Timestamp &&
      event.occurredAt.toMillis() <= declaration.updatedAt.toMillis();
    if (downstreamStatuses.includes(String(declaration.status)) &&
        declaration.revision >= nextRevision && eventIsValid && event !== undefined &&
        event.occurredAt instanceof Timestamp &&
        (declaration.status !== 'pendingSuperiorSignature' ||
          declaration.revision !== nextRevision ||
          (declaration.updatedAt instanceof Timestamp && event.occurredAt.isEqual(declaration.updatedAt)))) {
      return true;
    }
    if (declaration.revision !== revision || declaration.status !== 'signedByDeclarant') {
      throw new HttpsError('failed-precondition', 'La declaración ya cambió; vuelva a cargarla antes de enviarla.');
    }
    if (eventSnapshot.exists) {
      throw new HttpsError('already-exists', 'El evento de envío existe sin una transición íntegra.');
    }

    const assignmentRef = db.doc(`supervisor_assignments/${declaration.personId}`);
    const assignmentSnapshot = await transaction.get(assignmentRef);
    const assignment = assignmentSnapshot.data();
    if (!assignmentSnapshot.exists || !isValidSupervisorAssignment(assignment, declaration.personId)) {
      throw new HttpsError('failed-precondition', 'No existe una asignación vigente válida para el superior.');
    }
    const supervisorSnapshot = await transaction.get(db.doc(`users/${assignment.supervisorId as string}`));
    const supervisor = supervisorSnapshot.data();
    if (!supervisorSnapshot.exists || supervisor?.role !== 'supervisor' || supervisor.active !== true) {
      throw new HttpsError('failed-precondition', 'El superior asignado no tiene un perfil supervisor activo.');
    }

    const serverTime = FieldValue.serverTimestamp();
    const updated = {
      ...declaration,
      status: 'pendingSuperiorSignature',
      revision: nextRevision,
      updatedAt: serverTime,
    };
    transaction.set(declarationRef, updated);
    transaction.set(versionRef, updated);
    transaction.create(eventRef, {
      id: eventId,
      declarationId,
      actorId: uid,
      action: 'submitToSuperior',
      occurredAt: serverTime,
      details: eventDetails,
      ...declarationAuditState(version, 'signedByDeclarant', 'pendingSuperiorSignature'),
    });
    return false;
  });

  return { declarationId, version, revision: nextRevision, eventId, alreadySubmitted };
});

/** Admin/HR-managed current assignment. Assignment history is append-only. */
export const assignDeclarantSupervisor = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarantId !== 'string' || !data.declarantId.trim() ||
      typeof data.supervisorId !== 'string' || !data.supervisorId.trim()) {
    throw new HttpsError('invalid-argument', 'Indique el UID del declarante y del superior.');
  }

  const declarantId = data.declarantId;
  const supervisorId = data.supervisorId;
  const actorRef = db.doc(`users/${uid}`);
  const declarantRef = db.doc(`users/${declarantId}`);
  const supervisorRef = db.doc(`users/${supervisorId}`);
  const assignmentRef = db.doc(`supervisor_assignments/${declarantId}`);

  const result = await db.runTransaction(async (transaction) => {
    const [actorSnapshot, declarantSnapshot, supervisorSnapshot, assignmentSnapshot] =
      await Promise.all([
        transaction.get(actorRef), transaction.get(declarantRef),
        transaction.get(supervisorRef), transaction.get(assignmentRef),
      ]);
    const actor = actorSnapshot.data();
    if (!reviewerRoles.has(actor?.role) || actor?.active !== true) {
      throw new HttpsError('permission-denied', 'Solo administración o Recursos Humanos activos pueden asignar superiores.');
    }
    const declarant = declarantSnapshot.data();
    if (!declarantSnapshot.exists) {
      throw new HttpsError('failed-precondition', 'No existe un perfil para el UID del declarante.');
    }
    if (!roles.has(declarant?.role)) {
      throw new HttpsError('failed-precondition', 'El perfil indicado para el declarante no tiene el rol declarante.');
    }
    if (declarant?.active !== true) {
      throw new HttpsError('failed-precondition', 'El perfil del declarante está inactivo.');
    }
    const supervisor = supervisorSnapshot.data();
    if (!supervisorSnapshot.exists) {
      throw new HttpsError('failed-precondition', 'No existe un perfil para el UID del superior.');
    }
    if (supervisor?.role !== 'supervisor') {
      throw new HttpsError('failed-precondition', 'El perfil indicado para el superior no tiene el rol supervisor.');
    }
    if (supervisor?.active !== true) {
      throw new HttpsError('failed-precondition', 'El perfil del superior está inactivo.');
    }

    const current = assignmentSnapshot.data();
    if (assignmentSnapshot.exists && !isValidSupervisorAssignment(current, declarantId)) {
      throw new HttpsError('failed-precondition', 'La asignación existente está incompleta o es inconsistente.');
    }
    if (assignmentSnapshot.exists && current) {
      const eventRef = assignmentRef.collection('events').doc(
        `supervisorAssigned_v${current.revision}`,
      );
      const eventSnapshot = await transaction.get(eventRef);
      const event = eventSnapshot.data();
      if (!eventSnapshot.exists || !isValidSupervisorAssignmentEvent(event, current)) {
        throw new HttpsError('failed-precondition', 'No se pudo verificar el historial de la asignación actual.');
      }
      if (current.supervisorId === supervisorId) {
        return { revision: current.revision as number, alreadyAssigned: true };
      }
    }

    const revision = (current?.revision as number | undefined ?? 0) + 1;
    const eventId = `supervisorAssigned_v${revision}`;
    const eventRef = assignmentRef.collection('events').doc(eventId);
    if ((await transaction.get(eventRef)).exists) {
      throw new HttpsError('already-exists', 'El evento de asignación ya existe.');
    }
    const serverTime = FieldValue.serverTimestamp();
    transaction.set(assignmentRef, {
      declarantId,
      supervisorId,
      revision,
      updatedAt: serverTime,
      updatedBy: uid,
    });
    transaction.create(eventRef, {
      id: eventId,
      action: 'supervisorAssigned',
      declarantId,
      previousSupervisorId: current?.supervisorId ?? null,
      supervisorId,
      revision,
      assignedBy: uid,
      occurredAt: serverTime,
    });
    return { revision, alreadyAssigned: false };
  });

  return { declarantId, supervisorId, ...result };
});

/** Returns only the caller's currently assigned pending superior reviews. */
export const getSupervisorInbox = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  return db.runTransaction(async (transaction) => {
    const profileSnapshot = await transaction.get(db.doc(`users/${uid}`));
    const profile = profileSnapshot.data();
    if (profile?.role !== 'supervisor' || profile?.active !== true) {
      throw new HttpsError('permission-denied', 'Se requiere un perfil supervisor activo.');
    }
    const assignmentsSnapshot = await transaction.get(
      db.collection('supervisor_assignments').where('supervisorId', '==', uid),
    );
    const assignments = assignmentsSnapshot.docs.map((document) => {
      const assignment = document.data();
      if (!isValidSupervisorAssignment(assignment, document.id) ||
          assignment.supervisorId !== uid) {
        throw new HttpsError('failed-precondition', 'Se encontró una asignación inconsistente.');
      }
      return document.id;
    });
    if (assignments.length === 0) return { declarations: [] };

    const snapshots = [];
    for (let start = 0; start < assignments.length; start += 30) {
      const owners = assignments.slice(start, start + 30);
      snapshots.push(await transaction.get(
        db.collection('declarations').where('personId', 'in', owners),
      ));
    }
    const declarations = snapshots.flatMap((snapshot) => snapshot.docs)
      .filter((document) => document.get('status') === 'pendingSuperiorSignature')
      .map((document) => {
        const declaration = document.data();
        const formProfile = isMap(declaration.payload) && isMap(declaration.payload.profile)
          ? declaration.payload.profile
          : {};
        const createdAt = declaration.createdAt;
        if (!(createdAt instanceof Timestamp)) {
          throw new HttpsError('failed-precondition', 'Una declaración asignada tiene fecha inválida.');
        }
        return {
          declarationId: document.id,
          personId: declaration.personId,
          declarantName: typeof formProfile.name === 'string' ? formProfile.name : '',
          periodId: declaration.periodId,
          status: declaration.status,
          version: declaration.version,
          revision: declaration.revision,
          createdAt: createdAt.toDate().toISOString(),
        };
      });
    declarations.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
    return { declarations };
  });
});

/** Assigned declarations already signed by the supervisor and awaiting HR submission. */
export const getSupervisorOutbox = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  return db.runTransaction(async (transaction) => {
    const profile = (await transaction.get(db.doc(`users/${uid}`))).data();
    if (profile?.role !== 'supervisor' || profile.active !== true) throw new HttpsError('permission-denied', 'Se requiere un perfil supervisor activo.');
    // The signed audit record owns this handoff even if the declarant is later
    // reassigned. Pending reviews use the current assignment; completed signatures
    // remain attributable to the supervisor who actually signed.
    const signedEvents = await transaction.get(
      db.collectionGroup('events').where('actorId', '==', uid),
    );
    const declarations: JsonMap[] = [];
    const seen = new Set<string>();
    for (const eventDocument of signedEvents.docs) {
      const event = eventDocument.data();
      if (event.action !== 'superiorSigned' || typeof event.declarationId !== 'string' ||
          !event.declarationId.trim() || seen.has(event.declarationId)) continue;
      seen.add(event.declarationId);
      const document = await transaction.get(db.doc(`declarations/${event.declarationId}`));
      if (!document.exists) throw new HttpsError('failed-precondition', 'Una declaración firmada del historial ya no existe.');
      const declaration = document.data()!;
      if (declaration.status !== 'signedBySuperior') continue;
      const mirror = await transaction.get(document.ref.collection('versions').doc(String(declaration.version)));
      if (!mirror.exists || !isDeepStrictEqual(mirror.data(), declaration) ||
          !matchesSuperiorSignatureEvent(event, document.id, declaration, uid)) {
        throw new HttpsError('failed-precondition', 'La firma o el espejo de una declaración está inconsistente.');
      }
      const formProfile = isMap(declaration.payload) && isMap(declaration.payload.profile) ? declaration.payload.profile : {};
      declarations.push({ declarationId: document.id, personId: declaration.personId,
        declarantName: typeof formProfile.name === 'string' ? formProfile.name : '',
        periodId: declaration.periodId, status: declaration.status,
        version: declaration.version, revision: declaration.revision });
    }
    return { declarations };
  });
});

/** Reads one pending declaration after rechecking the caller's live assignment. */
export const getSupervisorDeclaration = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarationId !== 'string' || !data.declarationId.trim()) {
    throw new HttpsError('invalid-argument', 'Indique la declaración que desea consultar.');
  }
  const declarationRef = db.doc(`declarations/${data.declarationId}`);
  return db.runTransaction(async (transaction) => {
    const [supervisorSnapshot, declarationSnapshot] = await Promise.all([
      transaction.get(db.doc(`users/${uid}`)), transaction.get(declarationRef),
    ]);
    const supervisor = supervisorSnapshot.data();
    if (supervisor?.role !== 'supervisor' || supervisor?.active !== true) {
      throw new HttpsError('permission-denied', 'Se requiere un perfil supervisor activo.');
    }
    if (!declarationSnapshot.exists) throw new HttpsError('not-found', 'No existe la declaración.');
    const declaration = declarationSnapshot.data()!;
    const assignmentSnapshot = await transaction.get(
      db.doc(`supervisor_assignments/${declaration.personId}`),
    );
    const assignment = assignmentSnapshot.data();
    if (!['pendingSuperiorSignature', 'signedBySuperior'].includes(String(declaration.status))) {
      throw new HttpsError('failed-precondition', 'La declaración ya no está pendiente de revisión o envío.');
    }
    if (declaration.status === 'pendingSuperiorSignature') {
      if (!assignmentSnapshot.exists) {
        throw new HttpsError('permission-denied', 'Esta declaración no está asignada a este superior.');
      }
      if (!isValidSupervisorAssignment(assignment, declaration.personId)) {
        throw new HttpsError('failed-precondition', 'La asignación del superior está incompleta o es inconsistente.');
      }
      if (assignment.supervisorId !== uid) {
        throw new HttpsError('permission-denied', 'Esta declaración no está asignada a este superior.');
      }
    } else {
      const signatureRevision = superiorSignatureRevision(declaration);
      const [mirror, signatureEvent] = await Promise.all([
        transaction.get(declarationRef.collection('versions').doc(String(declaration.version))),
        signatureRevision === null
          ? Promise.resolve(null)
          : transaction.get(declarationRef.collection('events').doc(
            `superiorSigned_v${declaration.version}_r${signatureRevision}`,
          )),
      ]);
      if (!mirror.exists || !isDeepStrictEqual(mirror.data(), declaration) ||
          !signatureEvent?.exists ||
          !matchesSuperiorSignatureEvent(signatureEvent.data(), declarationRef.id, declaration, uid)) {
        throw new HttpsError('failed-precondition', 'La firma o el espejo de la versión está inconsistente.');
      }
    }
    const date = (value: unknown) => value instanceof Timestamp ? value.toDate().toISOString() : null;
    return {
      id: declarationSnapshot.id,
      personId: declaration.personId,
      periodId: declaration.periodId,
      createdAt: date(declaration.createdAt),
      status: declaration.status,
      version: declaration.version,
      revision: declaration.revision,
      parentVersionId: declaration.parentVersionId ?? null,
      oathAcceptedAt: date(declaration.oathAcceptedAt),
      declarantSignedAt: date(declaration.declarantSignedAt),
      declarantSignature: declaration.declarantSignature ?? null,
      superiorSignedAt: date(declaration.superiorSignedAt),
      superiorSignature: declaration.superiorSignature ?? null,
      returnObservation: declaration.returnObservation ?? null,
      hrReceivedAt: date(declaration.hrReceivedAt),
      finalizedAt: date(declaration.finalizedAt),
      finalPdfPath: declaration.finalPdfPath ?? null,
      payload: declaration.payload,
    };
  });
});

/** The assigned supervisor's internal electronic approval of the current version. */
export const signAsSuperior = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarationId !== 'string' || !data.declarationId.trim() ||
      !Number.isSafeInteger(data.expectedVersion) || (data.expectedVersion as number) < 1 ||
      !Number.isSafeInteger(data.expectedRevision) || (data.expectedRevision as number) < 0 ||
      data.confirmed !== true) {
    throw new HttpsError('invalid-argument', 'Confirme explícitamente la revisión e indique versión y revisión esperadas.');
  }
  const declarationId = data.declarationId;
  const version = data.expectedVersion as number;
  const revision = data.expectedRevision as number;
  const nextRevision = revision + 1;
  const signatureId = `superiorSignature_v${version}_r${nextRevision}`;
  const eventId = `superiorSigned_v${version}_r${nextRevision}`;
  const declarationRef = db.doc(`declarations/${declarationId}`);
  const versionRef = declarationRef.collection('versions').doc(String(version));
  const eventRef = declarationRef.collection('events').doc(eventId);

  return db.runTransaction(async (transaction) => {
    const [profileSnapshot, declarationSnapshot, versionSnapshot, eventSnapshot] =
      await Promise.all([
        transaction.get(db.doc(`users/${uid}`)), transaction.get(declarationRef),
        transaction.get(versionRef), transaction.get(eventRef),
      ]);
    const profile = profileSnapshot.data();
    if (profile?.role !== 'supervisor' || profile.active !== true) {
      throw new HttpsError('permission-denied', 'Se requiere un perfil supervisor activo.');
    }
    if (!declarationSnapshot.exists) throw new HttpsError('not-found', 'No existe la declaración.');
    const declaration = declarationSnapshot.data()!;
    if (declaration.version !== version) {
      throw new HttpsError('failed-precondition', 'La versión cambió; vuelva a abrir la declaración.');
    }
    const signatureContentHash = computeDeclarationContentHash({
      payload: declaration.payload, version,
      personId: declaration.personId as string, periodId: declaration.periodId as string,
    });
    const priorSignatureId = declaration.declarantSignature;
    // Submission advances the declaration revision, but does not re-sign it.
    const priorMatch = typeof priorSignatureId === 'string'
      ? /^declarantSignature_v([1-9]\d*)_r([1-9]\d*)$/.exec(priorSignatureId)
      : null;
    const priorRevision = priorMatch ? Number(priorMatch[2]) : NaN;
    if (!priorMatch || Number(priorMatch[1]) !== version ||
        !Number.isSafeInteger(priorRevision) || priorRevision > revision) {
      throw new HttpsError('failed-precondition', 'La firma del declarante no identifica una revisión válida.');
    }
    const priorEventId = `declarantSigned_v${version}_r${priorRevision}`;
    const priorEventSnapshot = await transaction.get(
      declarationRef.collection('events').doc(priorEventId),
    );
    const priorEvent = priorEventSnapshot.data();
    const priorExpectedDetails =
      `version=${version};revision=${priorRevision};signatureId=${priorSignatureId}`;
    const priorSignatureValid = typeof priorSignatureId === 'string' &&
      priorSignatureId === `declarantSignature_v${version}_r${priorRevision}` &&
      priorEventSnapshot.exists && priorEvent?.id === priorEventId &&
      priorEvent.declarationId === declarationId && priorEvent.actorId === declaration.personId &&
      priorEvent.action === 'declarantSigned' && priorEvent.details === priorExpectedDetails &&
      ((priorEvent.contentHash === undefined && declaration.declarantContentHash == null) ||
        (priorEvent.contentHash === signatureContentHash &&
          declaration.declarantContentHash === signatureContentHash)) &&
      priorEvent.occurredAt instanceof Timestamp &&
      declaration.declarantSignedAt instanceof Timestamp &&
      priorEvent.occurredAt.isEqual(declaration.declarantSignedAt);
    if (!priorSignatureValid || !versionSnapshot.exists ||
        !isDeepStrictEqual(versionSnapshot.data(), declaration)) {
      throw new HttpsError('failed-precondition', 'No se pudo verificar la firma histórica ni el espejo de la versión.');
    }
    const event = eventSnapshot.data();
    const signedAt = declaration.superiorSignedAt;
    const details = `version=${version};revision=${nextRevision};signatureId=${signatureId}`;
    const alreadySigned = ['signedBySuperior', 'sentToHr', 'receivedByHr', 'finalized']
      .includes(String(declaration.status)) &&
      declaration.revision >= nextRevision && declaration.superiorSignature === signatureId &&
      signedAt instanceof Timestamp && event?.id === eventId &&
      event.declarationId === declarationId && event.actorId === uid &&
      event.action === 'superiorSigned' && event.details === details &&
      ((event.contentHash === undefined && declaration.superiorContentHash == null) ||
        (event.contentHash === signatureContentHash &&
          declaration.superiorContentHash === signatureContentHash)) &&
      event.occurredAt instanceof Timestamp && signedAt.isEqual(event.occurredAt) &&
      isDeepStrictEqual(versionSnapshot.data(), declaration);
    if (alreadySigned) {
      if (!matchesSuperiorSignatureEvent(event, declarationId, declaration, uid)) {
        throw new HttpsError('permission-denied', 'La firma pertenece a otro superior.');
      }
      return { declarationId, version, revision: nextRevision, signatureId, eventId, alreadySigned: true };
    }
    const assignmentSnapshot = await transaction.get(
      db.doc(`supervisor_assignments/${declaration.personId}`),
    );
    const assignment = assignmentSnapshot.data();
    if (!assignmentSnapshot.exists || !isValidSupervisorAssignment(assignment, declaration.personId)) {
      throw new HttpsError('failed-precondition', 'La asignación vigente del superior está incompleta o es inconsistente.');
    }
    if (assignment.supervisorId !== uid) {
      throw new HttpsError('permission-denied', 'La declaración no está asignada a este superior.');
    }
    if (declaration.revision !== revision) {
      throw new HttpsError('failed-precondition', 'La declaración cambió; vuelva a abrirla antes de firmar.');
    }
    if (eventSnapshot.exists) {
      throw new HttpsError('already-exists', 'El evento de firma existe sin una transición íntegra.');
    }
    if (declaration.status !== 'pendingSuperiorSignature' ||
        !(declaration.declarantSignedAt instanceof Timestamp) ||
        declaration.superiorSignedAt != null || declaration.superiorSignature != null) {
      throw new HttpsError('failed-precondition', 'La declaración no está pendiente de firma del superior.');
    }
    const validation = validateSchedulePayload(declaration.payload);
    if (!validation.valid) {
      throw new HttpsError('failed-precondition', `El contenido no supera la validación del servidor: ${validation.reason}`);
    }
    const now = FieldValue.serverTimestamp();
    const updated = { ...declaration, status: 'signedBySuperior', revision: nextRevision,
      superiorSignedAt: now, superiorSignature: signatureId,
      superiorContentHash: signatureContentHash, updatedAt: now };
    transaction.set(declarationRef, updated);
    transaction.set(versionRef, updated);
    transaction.create(eventRef, { id: eventId, declarationId, actorId: uid,
      action: 'superiorSigned', occurredAt: now, details, contentHash: signatureContentHash,
      ...declarationAuditState(version, 'pendingSuperiorSignature', 'signedBySuperior') });
    return { declarationId, version, revision: nextRevision, signatureId, eventId, alreadySigned: false };
  });
});

/** Returns a signed declaration to its owner; the supervisor observation is auditable. */
export const returnForCorrection = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarationId !== 'string' || !data.declarationId.trim() ||
      typeof data.observation !== 'string' || !data.observation.trim() ||
      data.observation.length > 10000 || !Number.isSafeInteger(data.expectedVersion) ||
      (data.expectedVersion as number) < 1 || !Number.isSafeInteger(data.expectedRevision) ||
      (data.expectedRevision as number) < 0 || data.confirmed !== true) {
    throw new HttpsError('invalid-argument', 'Indique una observación válida y confirme la devolución.');
  }
  const declarationId = data.declarationId;
  const version = data.expectedVersion as number;
  const revision = data.expectedRevision as number;
  const nextRevision = revision + 1;
  const observation = data.observation.trim();
  const eventId = `returned_v${version}_r${nextRevision}`;
  const declarationRef = db.doc(`declarations/${declarationId}`);
  const versionRef = declarationRef.collection('versions').doc(String(version));
  const eventRef = declarationRef.collection('events').doc(eventId);
  return db.runTransaction(async (transaction) => {
    const [profileSnapshot, declarationSnapshot, versionSnapshot, eventSnapshot] =
      await Promise.all([transaction.get(db.doc(`users/${uid}`)), transaction.get(declarationRef),
        transaction.get(versionRef), transaction.get(eventRef)]);
    const profile = profileSnapshot.data();
    if (profile?.role !== 'supervisor' || profile.active !== true) {
      throw new HttpsError('permission-denied', 'Se requiere un perfil supervisor activo.');
    }
    if (!declarationSnapshot.exists) throw new HttpsError('not-found', 'No existe la declaración.');
    const declaration = declarationSnapshot.data()!;
    const assignmentSnapshot = await transaction.get(db.doc(`supervisor_assignments/${declaration.personId}`));
    const assignment = assignmentSnapshot.data();
    if (!assignmentSnapshot.exists || !isValidSupervisorAssignment(assignment, declaration.personId)) {
      throw new HttpsError('failed-precondition', 'La asignación vigente del superior está incompleta o es inconsistente.');
    }
    if (assignment.supervisorId !== uid) throw new HttpsError('permission-denied', 'La declaración no está asignada a este superior.');
    const event = eventSnapshot.data();
    const alreadyReturned = declaration.version === version && declaration.revision === nextRevision &&
      declaration.status === 'returned' && declaration.returnObservation === observation &&
      event?.id === eventId && event.declarationId === declarationId && event.actorId === uid &&
      event.action === 'returnedForCorrection' && event.details === observation &&
      event.occurredAt instanceof Timestamp && declaration.updatedAt instanceof Timestamp &&
      event.occurredAt.isEqual(declaration.updatedAt) && isDeepStrictEqual(versionSnapshot.data(), declaration);
    if (alreadyReturned) return { declarationId, version, revision: nextRevision, eventId, alreadyReturned: true };
    if (declaration.version !== version || declaration.revision !== revision) {
      throw new HttpsError('failed-precondition', 'La versión o revisión cambió; vuelva a abrir la declaración.');
    }
    if (eventSnapshot.exists) throw new HttpsError('already-exists', 'El evento de devolución existe sin una transición íntegra.');
    if (!versionSnapshot.exists || !isDeepStrictEqual(versionSnapshot.data(), declaration) ||
        declaration.status !== 'pendingSuperiorSignature' || !(declaration.declarantSignedAt instanceof Timestamp)) {
      throw new HttpsError('failed-precondition', 'La declaración no está disponible para devolución.');
    }
    const signatureMatch = typeof declaration.declarantSignature === 'string'
      ? /^declarantSignature_v([1-9]\d*)_r([1-9]\d*)$/.exec(declaration.declarantSignature)
      : null;
    const signedRevision = signatureMatch ? Number(signatureMatch[2]) : 0;
    if (!signatureMatch || Number(signatureMatch[1]) !== version ||
        !Number.isSafeInteger(signedRevision) || signedRevision < 2 || signedRevision > revision) {
      throw new HttpsError('failed-precondition', 'La firma del declarante no identifica una revisión válida.');
    }
    const oathEventId = `oathAccepted_v${version}_r${signedRevision - 1}`;
    const declarantEventId = `declarantSigned_v${version}_r${signedRevision}`;
    const [oathEventSnapshot, declarantEventSnapshot] = await Promise.all([
      transaction.get(declarationRef.collection('events').doc(oathEventId)),
      transaction.get(declarationRef.collection('events').doc(declarantEventId)),
    ]);
    const oathEvent = oathEventSnapshot.data();
    const declarantEvent = declarantEventSnapshot.data();
    if (!oathEventSnapshot.exists || oathEvent?.action !== 'oathAccepted' ||
        oathEvent.actorId !== declaration.personId || !(oathEvent.occurredAt instanceof Timestamp) ||
        !declarantEventSnapshot.exists || declarantEvent?.action !== 'declarantSigned' ||
        declarantEvent.actorId !== declaration.personId ||
        declarantEvent.details !== `version=${version};revision=${signedRevision};signatureId=${declaration.declarantSignature}` ||
        !(declarantEvent.occurredAt instanceof Timestamp) ||
        !declarantEvent.occurredAt.isEqual(declaration.declarantSignedAt)) {
      throw new HttpsError('failed-precondition', 'No se pudieron verificar el juramento y la firma histórica del declarante.');
    }
    const now = FieldValue.serverTimestamp();
    const updated = { ...declaration, status: 'returned', revision: nextRevision,
      returnObservation: observation, updatedAt: now };
    transaction.set(declarationRef, updated);
    transaction.set(versionRef, updated);
    transaction.create(eventRef, { id: eventId, declarationId, actorId: uid,
      action: 'returnedForCorrection', occurredAt: now, details: observation,
      ...declarationAuditState(version, 'pendingSuperiorSignature', 'returned') });
    return { declarationId, version, revision: nextRevision, eventId, alreadyReturned: false };
  });
});

/** Creates an immutable new declaration document derived from a returned version. */
export const createDeclarationVersion = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarationId !== 'string' || !data.declarationId.trim() ||
      !Number.isSafeInteger(data.expectedVersion) || (data.expectedVersion as number) < 1 ||
      !Number.isSafeInteger(data.expectedRevision) || (data.expectedRevision as number) < 0) {
    throw new HttpsError('invalid-argument', 'Indique la versión y revisión que desea corregir.');
  }
  const sourceId = data.declarationId;
  const expectedVersion = data.expectedVersion as number;
  const expectedRevision = data.expectedRevision as number;
  const sourceRef = db.doc(`declarations/${sourceId}`);
  const userRef = db.doc(`users/${uid}`);
  return db.runTransaction(async (transaction) => {
    const [profileSnapshot, sourceSnapshot] = await Promise.all([
      transaction.get(userRef), transaction.get(sourceRef),
    ]);
    const profile = profileSnapshot.data();
    if (!roles.has(profile?.role) || profile?.active !== true) {
      throw new HttpsError('permission-denied', 'Se requiere un perfil declarante activo.');
    }
    if (!sourceSnapshot.exists) throw new HttpsError('not-found', 'No existe la declaración devuelta.');
    const source = sourceSnapshot.data()!;
    if (source.personId !== uid) throw new HttpsError('permission-denied', 'Solo la persona propietaria puede crear una nueva versión.');
    if (source.version !== expectedVersion || source.revision !== expectedRevision || source.status !== 'returned') {
      throw new HttpsError('failed-precondition', 'Solo se puede corregir la versión devuelta actual.');
    }
    const sourceVersionRef = sourceRef.collection('versions').doc(String(expectedVersion));
    const sourceVersionSnapshot = await transaction.get(sourceVersionRef);
    if (!sourceVersionSnapshot.exists || !isDeepStrictEqual(sourceVersionSnapshot.data(), source)) {
      throw new HttpsError('failed-precondition', 'El espejo de la versión devuelta está inconsistente.');
    }
    const returnEventId = `returned_v${expectedVersion}_r${expectedRevision}`;
    const returnEventSnapshot = await transaction.get(sourceRef.collection('events').doc(returnEventId));
    const returnEvent = returnEventSnapshot.data();
    // Submission and return each advance the revision; resolve the original signature by its ID.
    const signatureMatch = typeof source.declarantSignature === 'string'
      ? /^declarantSignature_v([1-9]\d*)_r([1-9]\d*)$/.exec(source.declarantSignature)
      : null;
    const signedRevision = signatureMatch ? Number(signatureMatch[2]) : 0;
    if (!signatureMatch || Number(signatureMatch[1]) !== expectedVersion ||
        !Number.isSafeInteger(signedRevision) || signedRevision < 2 || signedRevision >= expectedRevision) {
      throw new HttpsError('failed-precondition', 'La firma del declarante no identifica una revisión válida.');
    }
    const declarantEventId = `declarantSigned_v${expectedVersion}_r${signedRevision}`;
    const declarantEventSnapshot = await transaction.get(sourceRef.collection('events').doc(declarantEventId));
    const declarantEvent = declarantEventSnapshot.data();
    if (!returnEventSnapshot.exists || returnEvent?.action !== 'returnedForCorrection' ||
        typeof returnEvent.actorId !== 'string' || !returnEvent.actorId.trim() ||
        returnEvent.details !== source.returnObservation || !(returnEvent.occurredAt instanceof Timestamp) ||
        !(source.updatedAt instanceof Timestamp) || !returnEvent.occurredAt.isEqual(source.updatedAt) ||
        !declarantEventSnapshot.exists || declarantEvent?.action !== 'declarantSigned' ||
        declarantEvent.actorId !== uid || declarantEvent.details !==
          `version=${expectedVersion};revision=${signedRevision};signatureId=${source.declarantSignature}` ||
        !(declarantEvent.occurredAt instanceof Timestamp) ||
        !declarantEvent.occurredAt.isEqual(source.declarantSignedAt)) {
      throw new HttpsError('failed-precondition', 'No se pudo verificar el historial de la versión devuelta.');
    }
    const nextVersion = expectedVersion + 1;
    const nextId = `${sourceId}_v${nextVersion}`;
    const nextRef = db.doc(`declarations/${nextId}`);
    const nextVersionRef = nextRef.collection('versions').doc(String(nextVersion));
    const eventId = `versionCreated_v${nextVersion}`;
    const eventRef = nextRef.collection('events').doc(eventId);
    const [nextSnapshot, nextMirrorSnapshot, eventSnapshot] = await Promise.all([
      transaction.get(nextRef), transaction.get(nextVersionRef), transaction.get(eventRef),
    ]);
    if (nextSnapshot.exists || nextMirrorSnapshot.exists || eventSnapshot.exists) {
      const existing = nextSnapshot.data();
      const event = eventSnapshot.data();
      const details = `parentDeclarationId=${sourceId};version=${nextVersion}`;
      const alreadyCreated = nextSnapshot.exists && nextMirrorSnapshot.exists && eventSnapshot.exists &&
        existing?.personId === uid && existing.periodId === source.periodId &&
        existing.version === nextVersion && existing.revision === 0 &&
        existing.parentVersionId === sourceId && existing.status === 'draft' &&
        isDeepStrictEqual(existing.payload, source.payload) &&
        existing.oathAcceptedAt == null && existing.declarantSignedAt == null &&
        existing.declarantSignature == null && existing.superiorSignedAt == null &&
        existing.superiorSignature == null && event?.id === eventId &&
        event.declarationId === nextId && event.actorId === uid &&
        event.action === 'versionCreated' && event.details === details &&
        event.occurredAt instanceof Timestamp && existing.createdAt instanceof Timestamp &&
        existing.createdAt.isEqual(event.occurredAt) &&
        isDeepStrictEqual(nextMirrorSnapshot.data(), existing);
      if (alreadyCreated) return { declarationId: nextId, parentDeclarationId: sourceId,
        version: nextVersion, revision: 0, eventId, alreadyCreated: true };
      throw new HttpsError('already-exists', 'La nueva versión ya existe con datos inconsistentes; no se sobrescribirá el historial.');
    }
    const now = FieldValue.serverTimestamp();
    const next = {
      personId: uid, periodId: source.periodId, createdAt: now, updatedAt: now,
      status: 'draft', version: nextVersion, revision: 0, parentVersionId: sourceId,
      payload: source.payload, oathAcceptedAt: null, declarantSignedAt: null,
      declarantSignature: null, superiorSignedAt: null, superiorSignature: null,
      returnObservation: null, hrReceivedAt: null, finalizedAt: null, finalPdfPath: null,
    };
    transaction.create(nextRef, next);
    transaction.create(nextVersionRef, next);
    transaction.create(eventRef, { id: eventId, declarationId: nextId, actorId: uid,
      action: 'versionCreated', occurredAt: now,
      details: `parentDeclarationId=${sourceId};version=${nextVersion}`,
      ...declarationAuditState(nextVersion, 'returned', 'draft') });
    return { declarationId: nextId, parentDeclarationId: sourceId, version: nextVersion,
      revision: 0, eventId, alreadyCreated: false };
  });
});

/** Returns persisted events for the owner or an authorized current reviewer. */
export const getDeclarationTimeline = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarationId !== 'string' || !data.declarationId.trim()) {
    throw new HttpsError('invalid-argument', 'Indique la declaración.');
  }
  const profileSnapshot = await db.doc(`users/${uid}`).get();
  const profile = profileSnapshot.data();
  if (profile?.active !== true ||
      (!assignableRoles.has(profile?.role as string) && !roles.has(profile?.role as string))) {
    throw new HttpsError('permission-denied', 'El perfil no está activo o no tiene un rol autorizado.');
  }
  let currentId = data.declarationId;
  const accumulated: Array<JsonMap> = [];
  const visited = new Set<string>();
  let childDeclaration: JsonMap | null = null;
  for (let depth = 0; depth < 25; depth++) {
    if (visited.has(currentId)) throw new HttpsError('failed-precondition', 'La cadena de versiones contiene un ciclo.');
    visited.add(currentId);
    const declarationSnapshot = await db.doc(`declarations/${currentId}`).get();
    if (!declarationSnapshot.exists) throw new HttpsError('not-found', 'No existe una versión de la declaración.');
    const declaration = declarationSnapshot.data()!;
    if (childDeclaration !== null && (declaration.personId !== childDeclaration.personId ||
        declaration.periodId !== childDeclaration.periodId ||
        declaration.version !== (childDeclaration.version as number) - 1 ||
        childDeclaration.parentVersionId !== currentId)) {
      throw new HttpsError('failed-precondition', 'La relación entre versiones históricas es inconsistente.');
    }
    let allowed = declaration.personId === uid || profile.role === 'administrator' || profile.role === 'humanResources';
    if (profile.role === 'supervisor') {
      const assignmentSnapshot = await db.doc(`supervisor_assignments/${declaration.personId}`).get();
      const assignment = assignmentSnapshot.data();
      if (!assignmentSnapshot.exists || !isValidSupervisorAssignment(assignment, declaration.personId)) {
        throw new HttpsError('failed-precondition', 'La asignación vigente está incompleta o es inconsistente.');
      }
      allowed = assignment.supervisorId === uid;
    }
    if (!allowed) throw new HttpsError('permission-denied', 'No tiene acceso al historial de esta declaración.');
    const eventsSnapshot = await declarationSnapshot.ref.collection('events').orderBy('occurredAt').get();
    for (const event of eventsSnapshot.docs) {
      const value = event.data();
      if ((value.id !== undefined && value.id !== event.id) ||
          value.declarationId !== currentId || typeof value.actorId !== 'string' ||
          !value.actorId.trim() || typeof value.action !== 'string' || !value.action.trim() ||
          !(value.occurredAt instanceof Timestamp) ||
          (value.details !== null && value.details !== undefined && typeof value.details !== 'string')) {
        throw new HttpsError('failed-precondition', 'El historial contiene un evento incompleto o inconsistente.');
      }
      accumulated.push({ ...value, documentId: event.id });
    }
    if (typeof declaration.parentVersionId !== 'string' || !declaration.parentVersionId) break;
    childDeclaration = declaration;
    currentId = declaration.parentVersionId;
    if (depth === 24) throw new HttpsError('failed-precondition', 'La cadena histórica supera la profundidad permitida.');
  }
  accumulated.sort((a, b) => {
    const first = a.occurredAt instanceof Timestamp ? a.occurredAt.toMillis() : 0;
    const second = b.occurredAt instanceof Timestamp ? b.occurredAt.toMillis() : 0;
    return first - second || String(a.documentId).localeCompare(String(b.documentId));
  });
  return { events: accumulated.map((event) => ({
    id: event.id ?? event.documentId, declarationId: event.declarationId,
    actorId: event.actorId, action: event.action,
    occurredAt: event.occurredAt instanceof Timestamp ? event.occurredAt.toDate().toISOString() : null,
    details: event.details ?? null,
    version: event.version ?? null,
    estadoAnterior: event.estadoAnterior ?? null,
    estadoNuevo: event.estadoNuevo ?? null,
  })) };
});

/** Returns persisted status and the role/person responsible for the next action. */
export const getDeclarationStatus = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarationId !== 'string' || !data.declarationId.trim()) {
    throw new HttpsError('invalid-argument', 'Indique la declaración.');
  }
  const [profileSnapshot, declarationSnapshot] = await Promise.all([
    db.doc(`users/${uid}`).get(), db.doc(`declarations/${data.declarationId}`).get(),
  ]);
  const profile = profileSnapshot.data();
  if (profile?.active !== true) throw new HttpsError('permission-denied', 'El perfil no está activo.');
  if (!declarationSnapshot.exists) throw new HttpsError('not-found', 'No existe la declaración.');
  const declaration = declarationSnapshot.data()!;
  let allowed = declaration.personId === uid || profile.role === 'administrator' || profile.role === 'humanResources';
  let assignment: JsonMap | undefined;
  if (profile.role === 'supervisor') {
    const assignmentSnapshot = await db.doc(`supervisor_assignments/${declaration.personId}`).get();
    assignment = assignmentSnapshot.data();
    if (!assignmentSnapshot.exists || !isValidSupervisorAssignment(assignment, declaration.personId)) {
      throw new HttpsError('failed-precondition', 'La asignación vigente está incompleta o es inconsistente.');
    }
    allowed = assignment.supervisorId === uid;
  }
  if (!allowed) {
    throw new HttpsError('permission-denied', 'No tiene acceso al estado de esta declaración.');
  }
  const status = declaration.status;
  let responsible: JsonMap | null = null;
  if (['draft', 'validated', 'pendingDeclarantSignature', 'signedByDeclarant', 'returned'].includes(String(status))) {
    const payload = isMap(declaration.payload) ? declaration.payload : {};
    const ownerDetails = isMap(payload.profile) ? payload.profile : {};
    responsible = {
      type: 'declarant',
      uid: declaration.personId,
      name: typeof ownerDetails.name === 'string' && ownerDetails.name.trim()
        ? ownerDetails.name.trim() : 'Persona declarante',
    };
  } else if (status === 'pendingSuperiorSignature') {
    const assignmentSnapshot = await db.doc(`supervisor_assignments/${declaration.personId}`).get();
    assignment = assignmentSnapshot.data();
    if (!assignmentSnapshot.exists || !isValidSupervisorAssignment(assignment, declaration.personId)) {
      throw new HttpsError('failed-precondition', 'La asignación vigente está incompleta o es inconsistente.');
    }
    const supervisorSnapshot = await db.doc(`users/${assignment.supervisorId as string}`).get();
    const supervisorProfile = supervisorSnapshot.data();
    if (supervisorSnapshot.exists && supervisorProfile?.active === true && supervisorProfile.role === 'supervisor') {
      responsible = {
        type: 'supervisor',
        uid: assignment.supervisorId,
        name: typeof supervisorProfile.name === 'string' && supervisorProfile.name.trim()
          ? supervisorProfile.name.trim() : 'Superior jerárquico',
      };
    }
  } else if (status === 'signedBySuperior') {
    const signatureRevision = superiorSignatureRevision(declaration);
    if (signatureRevision === null) {
      throw new HttpsError('failed-precondition', 'La firma del superior no identifica una versión y revisión válidas.');
    }
    const signatureEventSnapshot = await db.doc(
      `declarations/${declarationSnapshot.id}/events/superiorSigned_v${declaration.version}_r${signatureRevision}`,
    ).get();
    const signatureEvent = signatureEventSnapshot.data();
    const signerId = signatureEvent?.actorId;
    if (!signatureEventSnapshot.exists || typeof signerId !== 'string' || !signerId.trim() ||
        !matchesSuperiorSignatureEvent(signatureEvent, declarationSnapshot.id, declaration, signerId)) {
      throw new HttpsError('failed-precondition', 'No se pudo verificar quién firmó como superior.');
    }
    const signerSnapshot = await db.doc(`users/${signerId}`).get();
    const signer = signerSnapshot.data();
    responsible = {
      type: 'supervisor',
      uid: signerId,
      name: typeof signer?.name === 'string' && signer.name.trim()
        ? signer.name.trim() : 'Superior firmante',
    };
  } else if (status === 'sentToHr' || status === 'receivedByHr') {
    responsible = { type: 'humanResources', name: 'Recursos Humanos / Administración' };
  } else if (status !== 'finalized' && status !== 'annulled') {
    throw new HttpsError('failed-precondition', 'El estado de la declaración no permite determinar el responsable actual.');
  }
  return {
    declarationId: declarationSnapshot.id, status,
    version: declaration.version, revision: declaration.revision,
    updatedAt: declaration.updatedAt instanceof Timestamp ? declaration.updatedAt.toDate().toISOString() : null,
    responsible,
  };
});

/** HR/admin queue for declarations signed by the responsible supervisor. */
export const getHumanResourcesInbox = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const profile = (await db.doc(`users/${uid}`).get()).data();
  if (!reviewerRoles.has(profile?.role) || profile?.active !== true) {
    throw new HttpsError('permission-denied', 'Se requiere un perfil activo de administración o Recursos Humanos.');
  }
  const snapshot = await db.collection('declarations').where('status', 'in', ['sentToHr', 'receivedByHr']).get();
  const declarations: JsonMap[] = [];
  for (const document of snapshot.docs) {
    const declaration = document.data();
    const versionSnapshot = await document.ref.collection('versions').doc(String(declaration.version)).get();
    const action = declaration.status === 'sentToHr' ? 'sentToHr' : 'hrReceived';
    const auditRevision = declaration.status === 'receivedByHr' && declaration.finalPdfPath
      ? (declaration.revision as number) - 1 : declaration.revision;
    const auditEventId = declaration.status === 'sentToHr'
      ? `sentToHr_v${declaration.version}_r${declaration.revision}`
      : `hrReceived_v${declaration.version}_r${auditRevision}`;
    const auditEvent = await document.ref.collection('events').doc(auditEventId).get();
    const expectedTime = action === 'sentToHr' ? declaration.updatedAt : declaration.hrReceivedAt;
    if (!versionSnapshot.exists || !isDeepStrictEqual(versionSnapshot.data(), declaration) ||
        !auditEvent.exists || auditEvent.get('action') !== action ||
        typeof auditEvent.get('actorId') !== 'string' || !auditEvent.get('actorId') ||
        !(auditEvent.get('occurredAt') instanceof Timestamp) ||
        !(expectedTime instanceof Timestamp) ||
        !(auditEvent.get('occurredAt') as Timestamp).isEqual(expectedTime)) {
      throw new HttpsError('failed-precondition', 'Una declaración enviada a Recursos Humanos tiene historial inconsistente.');
    }
    const formProfile = isMap(declaration.payload) && isMap(declaration.payload.profile) ? declaration.payload.profile : {};
    declarations.push({ declarationId: document.id, personId: declaration.personId,
      declarantName: typeof formProfile.name === 'string' ? formProfile.name : '',
      periodId: declaration.periodId, status: declaration.status,
      version: declaration.version, revision: declaration.revision,
      finalPdfPath: declaration.finalPdfPath ?? null,
      updatedAt: declaration.updatedAt.toDate().toISOString() });
  }
  return { declarations };
});

/** Reads one HR queue item after rechecking the operator, status and version mirror. */
export const getHumanResourcesDeclaration = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarationId !== 'string' || !data.declarationId.trim()) {
    throw new HttpsError('invalid-argument', 'Indique la declaración que desea consultar.');
  }
  return db.runTransaction(async (transaction) => {
    const [profileSnapshot, declarationSnapshot] = await Promise.all([
      transaction.get(db.doc(`users/${uid}`)), transaction.get(db.doc(`declarations/${data.declarationId}`)),
    ]);
    const profile = profileSnapshot.data();
    if (!reviewerRoles.has(profile?.role) || profile?.active !== true) {
      throw new HttpsError('permission-denied', 'Se requiere un perfil activo de administración o Recursos Humanos.');
    }
    if (!declarationSnapshot.exists) throw new HttpsError('not-found', 'No existe la declaración.');
    const declaration = declarationSnapshot.data()!;
    if (!['sentToHr', 'receivedByHr'].includes(String(declaration.status))) throw new HttpsError('failed-precondition', 'La declaración ya no está en la bandeja de Recursos Humanos.');
    const versionSnapshot = await transaction.get(declarationSnapshot.ref.collection('versions').doc(String(declaration.version)));
    const action = declaration.status === 'sentToHr' ? 'sentToHr' : 'hrReceived';
    const auditRevision = declaration.status === 'receivedByHr' && declaration.finalPdfPath
      ? (declaration.revision as number) - 1 : declaration.revision;
    const eventId = declaration.status === 'sentToHr'
      ? `sentToHr_v${declaration.version}_r${declaration.revision}`
      : `hrReceived_v${declaration.version}_r${auditRevision}`;
    const eventSnapshot = await transaction.get(declarationSnapshot.ref.collection('events').doc(eventId));
    if (!versionSnapshot.exists || !isDeepStrictEqual(versionSnapshot.data(), declaration) ||
        !eventSnapshot.exists || eventSnapshot.get('action') !== action ||
        !(eventSnapshot.get('occurredAt') as Timestamp | undefined)?.isEqual(
          action === 'sentToHr' ? declaration.updatedAt : declaration.hrReceivedAt,
        )) {
      throw new HttpsError('failed-precondition', 'La declaración no conserva una transición íntegra hacia Recursos Humanos.');
    }
    return { id: declarationSnapshot.id, personId: declaration.personId,
      periodId: declaration.periodId, status: declaration.status, version: declaration.version,
      revision: declaration.revision, createdAt: declaration.createdAt instanceof Timestamp ? declaration.createdAt.toDate().toISOString() : null,
      updatedAt: declaration.updatedAt.toDate().toISOString(), payload: declaration.payload,
      hrReceivedAt: declaration.hrReceivedAt instanceof Timestamp ? declaration.hrReceivedAt.toDate().toISOString() : null,
      finalizedAt: declaration.finalizedAt instanceof Timestamp ? declaration.finalizedAt.toDate().toISOString() : null,
      finalPdfPath: declaration.finalPdfPath ?? null,
      declarantSignedAt: declaration.declarantSignedAt instanceof Timestamp ? declaration.declarantSignedAt.toDate().toISOString() : null,
      declarantSignature: declaration.declarantSignature ?? null,
      superiorSignedAt: declaration.superiorSignedAt instanceof Timestamp ? declaration.superiorSignedAt.toDate().toISOString() : null,
      superiorSignature: declaration.superiorSignature ?? null };
  });
});

/** Sends a completed superior signature to the HR queue. */
export const sendDeclarationToHr = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarationId !== 'string' || !data.declarationId.trim() ||
      !Number.isSafeInteger(data.expectedVersion) || (data.expectedVersion as number) < 1 ||
      !Number.isSafeInteger(data.expectedRevision) || (data.expectedRevision as number) < 0 || data.confirmed !== true) {
    throw new HttpsError('invalid-argument', 'Confirme el envío e indique versión y revisión.');
  }
  const declarationRef = db.doc(`declarations/${data.declarationId}`);
  const version = data.expectedVersion as number;
  const revision = data.expectedRevision as number;
  const nextRevision = revision + 1;
  const versionRef = declarationRef.collection('versions').doc(String(version));
  const eventId = `sentToHr_v${version}_r${nextRevision}`;
  const eventRef = declarationRef.collection('events').doc(eventId);
  return db.runTransaction(async (transaction) => {
    const [profileSnapshot, declarationSnapshot, versionSnapshot, eventSnapshot] = await Promise.all([
      transaction.get(db.doc(`users/${uid}`)), transaction.get(declarationRef),
      transaction.get(versionRef), transaction.get(eventRef),
    ]);
    const profile = profileSnapshot.data();
    if (profile?.role !== 'supervisor' || profile.active !== true) throw new HttpsError('permission-denied', 'Se requiere un perfil supervisor activo.');
    if (!declarationSnapshot.exists) throw new HttpsError('not-found', 'No existe la declaración.');
    const declaration = declarationSnapshot.data()!;
    const details = `version=${version};revision=${nextRevision}`;
    const prior = eventSnapshot.data();
    const alreadySent = ['sentToHr', 'receivedByHr', 'finalized'].includes(String(declaration.status)) &&
      declaration.version === version && declaration.revision >= nextRevision &&
      prior?.id === eventId && prior.actorId === uid &&
      prior.action === 'sentToHr' && prior.details === details && prior.occurredAt instanceof Timestamp &&
      isDeepStrictEqual(versionSnapshot.data(), declaration);
    if (alreadySent) {
      const signatureRevision = superiorSignatureRevision(declaration);
      const signedEventSnapshot = signatureRevision === null ? null : await transaction.get(
        declarationRef.collection('events').doc(`superiorSigned_v${version}_r${signatureRevision}`),
      );
      if (!signedEventSnapshot?.exists ||
          !matchesSuperiorSignatureEvent(signedEventSnapshot.data(), declarationRef.id, declaration, uid)) {
        throw new HttpsError('permission-denied', 'El envío fue registrado por otro superior.');
      }
      return { declarationId: declarationRef.id, version, revision: nextRevision, eventId, alreadySent: true };
    }
    const signatureRevision = superiorSignatureRevision(declaration);
    if (signatureRevision !== null) {
      const signatureEventSnapshot = await transaction.get(
        declarationRef.collection('events').doc(`superiorSigned_v${declaration.version}_r${signatureRevision}`),
      );
      const signatureEvent = signatureEventSnapshot.data();
      const signatureActorId = signatureEvent?.actorId;
      if (signatureEventSnapshot.exists && typeof signatureActorId === 'string' &&
          signatureActorId !== uid &&
          matchesSuperiorSignatureEvent(signatureEvent, declarationRef.id, declaration, signatureActorId)) {
        throw new HttpsError('permission-denied', 'El envío corresponde al superior que firmó la declaración.');
      }
    }
    if (declaration.version !== version || declaration.revision !== revision) throw new HttpsError('failed-precondition', 'La declaración cambió; vuelva a abrirla.');
    if (eventSnapshot.exists) throw new HttpsError('already-exists', 'El evento de envío existe sin una transición íntegra.');
    if (declaration.status !== 'signedBySuperior' || !(declaration.superiorSignedAt instanceof Timestamp) ||
        declaration.superiorSignature !== `superiorSignature_v${version}_r${revision}` ||
        !versionSnapshot.exists || !isDeepStrictEqual(versionSnapshot.data(), declaration)) {
      throw new HttpsError('failed-precondition', 'La declaración no tiene una firma del superior verificable.');
    }
    const historicalSignature = signatureRevision === null ? null : await transaction.get(
      declarationRef.collection('events').doc(`superiorSigned_v${version}_r${signatureRevision}`),
    );
    if (!historicalSignature?.exists ||
        !matchesSuperiorSignatureEvent(historicalSignature.data(), declarationRef.id, declaration, uid)) {
      throw new HttpsError('permission-denied', 'La firma fue registrada por otro superior.');
    }
    const superiorEvent = await transaction.get(
      declarationRef.collection('events').doc(`superiorSigned_v${version}_r${revision}`),
    );
    if (!superiorEvent.exists || superiorEvent.get('action') !== 'superiorSigned' ||
        superiorEvent.get('actorId') !== uid || !(superiorEvent.get('occurredAt') instanceof Timestamp) ||
        !(superiorEvent.get('occurredAt') as Timestamp).isEqual(declaration.superiorSignedAt)) {
      throw new HttpsError('failed-precondition', 'La firma del superior no tiene un evento histórico verificable.');
    }
    const now = FieldValue.serverTimestamp();
    const updated = { ...declaration, status: 'sentToHr', revision: nextRevision, updatedAt: now };
    transaction.set(declarationRef, updated); transaction.set(versionRef, updated);
    transaction.create(eventRef, { id: eventId, declarationId: declarationRef.id,
      actorId: uid, action: 'sentToHr', occurredAt: now, details,
      ...declarationAuditState(version, 'signedBySuperior', 'sentToHr') });
    return { declarationId: declarationRef.id, version, revision: nextRevision, eventId, alreadySent: false };
  });
});

/** HR/admin records receipt only after the current version was sent to HR. */
export const receiveDeclarationAtHr = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarationId !== 'string' || !data.declarationId.trim() ||
      !Number.isSafeInteger(data.expectedVersion) || (data.expectedVersion as number) < 1 ||
      !Number.isSafeInteger(data.expectedRevision) || (data.expectedRevision as number) < 0 || data.confirmed !== true) {
    throw new HttpsError('invalid-argument', 'Confirme la recepción e indique versión y revisión.');
  }
  const declarationRef = db.doc(`declarations/${data.declarationId}`);
  const version = data.expectedVersion as number;
  const revision = data.expectedRevision as number;
  const nextRevision = revision + 1;
  const versionRef = declarationRef.collection('versions').doc(String(version));
  const eventId = `hrReceived_v${version}_r${nextRevision}`;
  const eventRef = declarationRef.collection('events').doc(eventId);
  return db.runTransaction(async (transaction) => {
    const [profileSnapshot, declarationSnapshot, versionSnapshot, eventSnapshot] = await Promise.all([
      transaction.get(db.doc(`users/${uid}`)), transaction.get(declarationRef),
      transaction.get(versionRef), transaction.get(eventRef),
    ]);
    const profile = profileSnapshot.data();
    if (!reviewerRoles.has(profile?.role) || profile?.active !== true) throw new HttpsError('permission-denied', 'Se requiere un perfil activo de administración o Recursos Humanos.');
    if (!declarationSnapshot.exists) throw new HttpsError('not-found', 'No existe la declaración.');
    const declaration = declarationSnapshot.data()!;
    const details = `version=${version};revision=${nextRevision}`;
    const prior = eventSnapshot.data();
    const alreadyReceived = ['receivedByHr', 'finalized'].includes(String(declaration.status)) &&
      declaration.version === version && declaration.revision >= nextRevision &&
      declaration.hrReceivedAt instanceof Timestamp &&
      prior?.id === eventId && prior.actorId === uid && prior.action === 'hrReceived' &&
      prior.details === details && prior.occurredAt instanceof Timestamp &&
      declaration.hrReceivedAt.isEqual(prior.occurredAt) &&
      isDeepStrictEqual(versionSnapshot.data(), declaration);
    if (alreadyReceived) return { declarationId: declarationRef.id, version, revision: nextRevision, eventId, alreadyReceived: true };
    if (declaration.version !== version || declaration.revision !== revision) throw new HttpsError('failed-precondition', 'La declaración cambió; actualice la bandeja.');
    if (eventSnapshot.exists) throw new HttpsError('already-exists', 'El evento de recepción existe sin una transición íntegra.');
    if (declaration.status !== 'sentToHr' || !(declaration.superiorSignedAt instanceof Timestamp) ||
        !versionSnapshot.exists || !isDeepStrictEqual(versionSnapshot.data(), declaration)) {
      throw new HttpsError('failed-precondition', 'Solo se puede recibir una declaración enviada a Recursos Humanos y firmada por el superior.');
    }
    const now = FieldValue.serverTimestamp();
    const updated = { ...declaration, status: 'receivedByHr', revision: nextRevision,
      hrReceivedAt: now, updatedAt: now };
    transaction.set(declarationRef, updated); transaction.set(versionRef, updated);
    transaction.create(eventRef, { id: eventId, declarationId: declarationRef.id,
      actorId: uid, action: 'hrReceived', occurredAt: now, details,
      ...declarationAuditState(version, 'sentToHr', 'receivedByHr') });
    return { declarationId: declarationRef.id, version, revision: nextRevision, eventId, alreadyReceived: false };
  });
});

/** Finalization deliberately fails closed until a trusted PDF object is present. */
export const generateFinalDeclarationPdf = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarationId !== 'string' || !data.declarationId.trim() ||
      !Number.isSafeInteger(data.expectedVersion) || (data.expectedVersion as number) < 1 ||
      !Number.isSafeInteger(data.expectedRevision) || (data.expectedRevision as number) < 0 || data.confirmed !== true) {
    throw new HttpsError('invalid-argument', 'Confirme la generación del PDF e indique versión y revisión.');
  }
  const declarationId = data.declarationId;
  const version = data.expectedVersion as number;
  const revision = data.expectedRevision as number;
  const declarationRef = db.doc(`declarations/${declarationId}`);
  const versionRef = declarationRef.collection('versions').doc(String(version));
  const receivedEventId = `hrReceived_v${version}_r${revision}`;
  const receivedEventRef = declarationRef.collection('events').doc(receivedEventId);
  const [profileSnapshot, declarationSnapshot, versionSnapshot, receivedEventSnapshot] = await Promise.all([
    db.doc(`users/${uid}`).get(), declarationRef.get(), versionRef.get(), receivedEventRef.get(),
  ]);
  const profile = profileSnapshot.data();
  if (!reviewerRoles.has(profile?.role) || profile?.active !== true) throw new HttpsError('permission-denied', 'Se requiere un perfil activo de administración o Recursos Humanos.');
  if (!declarationSnapshot.exists) throw new HttpsError('not-found', 'No existe la declaración.');
  const declaration = declarationSnapshot.data()!;
  const path = `final-declarations/${declarationId}/v${version}.pdf`;
  if (declaration.version === version && declaration.revision === revision + 1 &&
      declaration.status === 'receivedByHr' && declaration.finalPdfPath === path) {
    const generatedId = `pdfGenerated_v${version}_r${revision + 1}`;
    const generatedSnapshot = await declarationRef.collection('events').doc(generatedId).get();
    const generated = generatedSnapshot.data();
    const generatedDetails = `version=${version};revision=${revision + 1};sourceRevision=${revision};path=${path}`;
    if (generatedSnapshot.exists && generated?.id === generatedId && generated.actorId === uid &&
        generated.action === 'pdfGenerated' && generated.details === generatedDetails &&
        generated.occurredAt instanceof Timestamp && isDeepStrictEqual(versionSnapshot.data(), declaration)) {
      await requireFinalPdfObject(declarationId, version, revision);
      return { declarationId, version, revision: revision + 1, eventId: generatedId,
        finalPdfPath: path, alreadyGenerated: true };
    }
  }
  if (declaration.version !== version || declaration.revision !== revision || declaration.status !== 'receivedByHr' ||
      !(declaration.hrReceivedAt instanceof Timestamp) || !versionSnapshot.exists ||
      !isDeepStrictEqual(versionSnapshot.data(), declaration) || !receivedEventSnapshot.exists ||
      receivedEventSnapshot.get('action') !== 'hrReceived' ||
      !(receivedEventSnapshot.get('occurredAt') as Timestamp | undefined)?.isEqual(declaration.hrReceivedAt)) {
    throw new HttpsError('failed-precondition', 'Solo se puede generar PDF para una versión íntegra recibida por Recursos Humanos.');
  }
  const validation = validateSchedulePayload(declaration.payload);
  if (!validation.valid) throw new HttpsError('failed-precondition', `El contenido no supera la validación del servidor: ${validation.reason}`);
  const declarantSignatureId = declaration.declarantSignature;
  const superiorSignatureId = declaration.superiorSignature;
  if (typeof declarantSignatureId !== 'string' || typeof superiorSignatureId !== 'string') {
    throw new HttpsError('failed-precondition', 'Falta una firma requerida para generar el PDF.');
  }
  const declarantMatch = /^declarantSignature_v(\d+)_r(\d+)$/.exec(declarantSignatureId);
  const superiorMatch = /^superiorSignature_v(\d+)_r(\d+)$/.exec(superiorSignatureId);
  if (!declarantMatch || !superiorMatch || Number(declarantMatch[1]) !== version || Number(superiorMatch[1]) !== version) {
    throw new HttpsError('failed-precondition', 'Los identificadores de firma no corresponden a la versión.');
  }
  const [declarantEventSnapshot, superiorEventSnapshot] = await Promise.all([
    declarationRef.collection('events').doc(`declarantSigned_v${version}_r${declarantMatch[2]}`).get(),
    declarationRef.collection('events').doc(`superiorSigned_v${version}_r${superiorMatch[2]}`).get(),
  ]);
  const declarantEvent = declarantEventSnapshot.data();
  const superiorEvent = superiorEventSnapshot.data();
  const declarantEventId = `declarantSigned_v${version}_r${declarantMatch[2]}`;
  const declarantEventDetails =
    `version=${version};revision=${declarantMatch[2]};signatureId=${declarantSignatureId}`;
  const superiorEventId = `superiorSigned_v${version}_r${superiorMatch[2]}`;
  const superiorEventDetails =
    `version=${version};revision=${superiorMatch[2]};signatureId=${superiorSignatureId}`;
  const signedPayloadHash = computeDeclarationContentHash({
    payload: declaration.payload, version, personId: declaration.personId as string,
    periodId: declaration.periodId as string,
  });
  const declarantHashValid =
    (declarantEvent?.contentHash === undefined && declaration.declarantContentHash == null) ||
    (declarantEvent?.contentHash === signedPayloadHash &&
      declaration.declarantContentHash === signedPayloadHash);
  const superiorHashValid =
    (superiorEvent?.contentHash === undefined && declaration.superiorContentHash == null) ||
    (superiorEvent?.contentHash === signedPayloadHash &&
      declaration.superiorContentHash === signedPayloadHash);
  if (!declarantEventSnapshot.exists || declarantEvent?.action !== 'declarantSigned' ||
      declarantEvent.id !== declarantEventId || declarantEvent.declarationId !== declarationId ||
      declarantEvent.actorId !== declaration.personId || declarantEvent.details !== declarantEventDetails ||
      !(declarantEvent.occurredAt instanceof Timestamp) ||
      !declarantEvent.occurredAt.isEqual(declaration.declarantSignedAt) ||
      !declarantHashValid ||
      !superiorEventSnapshot.exists || superiorEvent?.action !== 'superiorSigned' ||
      superiorEvent.id !== superiorEventId || superiorEvent.declarationId !== declarationId ||
      typeof superiorEvent.actorId !== 'string' || !superiorEvent.actorId.trim() ||
      superiorEvent.details !== superiorEventDetails ||
      !(superiorEvent.occurredAt instanceof Timestamp) ||
      !superiorEvent.occurredAt.isEqual(declaration.superiorSignedAt) ||
      !superiorHashValid) {
    throw new HttpsError('failed-precondition', 'No se pudieron verificar las firmas históricas requeridas.');
  }
  const oathRevision = Number(declarantMatch[2]) - 1;
  const oathEventId = `oathAccepted_v${version}_r${oathRevision}`;
  const oathEventSnapshot = Number.isSafeInteger(oathRevision) && oathRevision >= 1
    ? await declarationRef.collection('events').doc(oathEventId).get() : null;
  const oathEvent = oathEventSnapshot?.data();
  const oathDetails = typeof oathEvent?.details === 'string'
    ? /^version=(\d+);revision=(\d+);oathTextVersion=(\d+)$/.exec(oathEvent.details)
    : null;
  const oathTextVersion = oathDetails ? Number(oathDetails[3]) : 0;
  const oathTextSnapshot = oathTextVersion > 0
    ? await db.doc(`institutional_texts/declarant_oath/versions/${oathTextVersion}`).get()
    : null;
  const oathTextRecord = oathTextSnapshot?.data();
  if (!oathEventSnapshot?.exists || oathEvent?.id !== oathEventId ||
      oathEvent.declarationId !== declarationId || oathEvent.actorId !== declaration.personId ||
      oathEvent.action !== 'oathAccepted' || oathDetails?.[1] !== String(version) ||
      oathDetails?.[2] !== String(oathRevision) || !(oathEvent.occurredAt instanceof Timestamp) ||
      !(declaration.oathAcceptedAt instanceof Timestamp) ||
      !oathEvent.occurredAt.isEqual(declaration.oathAcceptedAt) ||
      !oathTextSnapshot?.exists || !oathTextRecord ||
      !isDeepStrictEqual(Object.keys(oathTextRecord).sort(), ['approvedAt', 'status', 'text', 'version']) ||
      oathTextRecord.status !== 'approved' || oathTextRecord.version !== oathTextVersion ||
      typeof oathTextRecord.text !== 'string' || !oathTextRecord.text.trim() ||
      !(oathTextRecord.approvedAt instanceof Timestamp) ||
      oathTextRecord.approvedAt.toMillis() > oathEvent.occurredAt.toMillis()) {
    throw new HttpsError('failed-precondition', 'No se pudo verificar el texto institucional que aceptó el declarante.');
  }

  const bucket = storageBucket();
  const file = bucket.file(path);
  const [exists] = await file.exists();
  if (exists) {
    const [metadata] = await file.getMetadata();
    const custom = metadata.metadata ?? {};
    if (metadata.contentType !== 'application/pdf' || custom.declarationId !== declarationId ||
        custom.formalVersion !== String(version) || custom.sourceRevision !== String(revision)) {
      throw new HttpsError('already-exists', 'Existe un PDF previo que no corresponde a esta revisión; no se sobrescribirá.');
    }
  } else {
    const bytes = buildFinalDeclarationPdf({
      declarationId,
      declaration: {
        ...declaration,
        declarantSignedAt: declaration.declarantSignedAt.toDate(),
        superiorSignedAt: declaration.superiorSignedAt.toDate(),
      },
      declarantSignatureEvent: declarantEvent,
      superiorSignatureEvent: superiorEvent,
      oathTextVersion,
      oathText: oathTextRecord.text,
    });
    try {
      await file.save(bytes, {
        resumable: false,
        preconditionOpts: { ifGenerationMatch: 0 },
        metadata: {
          contentType: 'application/pdf',
          cacheControl: 'private, no-store',
          metadata: { declarationId, formalVersion: String(version), sourceRevision: String(revision) },
        },
      });
    } catch (error) {
      const [appeared] = await file.exists();
      if (!appeared) throw new HttpsError('unavailable', `No se pudo guardar el PDF en Storage: ${String(error)}`);
      const [metadata] = await file.getMetadata();
      const custom = metadata.metadata ?? {};
      if (custom.declarationId !== declarationId || custom.formalVersion !== String(version) || custom.sourceRevision !== String(revision)) {
        throw new HttpsError('already-exists', 'Otro intento creó un objeto PDF incompatible.');
      }
    }
  }

  const nextRevision = revision + 1;
  const eventId = `pdfGenerated_v${version}_r${nextRevision}`;
  const eventRef = declarationRef.collection('events').doc(eventId);
  const details = `version=${version};revision=${nextRevision};sourceRevision=${revision};path=${path}`;
  return db.runTransaction(async (transaction) => {
    const [currentProfileSnapshot, currentSnapshot, currentVersionSnapshot, existingEventSnapshot] = await Promise.all([
      transaction.get(db.doc(`users/${uid}`)), transaction.get(declarationRef),
      transaction.get(versionRef), transaction.get(eventRef),
    ]);
    const currentProfile = currentProfileSnapshot.data();
    if (!reviewerRoles.has(currentProfile?.role) || currentProfile?.active !== true) throw new HttpsError('permission-denied', 'Se requiere un perfil activo de administración o Recursos Humanos.');
    if (!currentSnapshot.exists) throw new HttpsError('not-found', 'No existe la declaración.');
    const current = currentSnapshot.data()!;
    const existingEvent = existingEventSnapshot.data();
    const alreadyGenerated = current.version === version && current.revision === nextRevision &&
      current.status === 'receivedByHr' && current.finalPdfPath === path &&
      existingEvent?.id === eventId && existingEvent.actorId === uid &&
      existingEvent.action === 'pdfGenerated' && existingEvent.details === details &&
      existingEvent.occurredAt instanceof Timestamp &&
      current.updatedAt instanceof Timestamp && existingEvent.occurredAt.isEqual(current.updatedAt) &&
      isDeepStrictEqual(currentVersionSnapshot.data(), current);
    if (alreadyGenerated) return { declarationId, version, revision: nextRevision, eventId, finalPdfPath: path, alreadyGenerated: true };
    if (current.version !== version || current.revision !== revision || current.status !== 'receivedByHr' ||
        !current.hrReceivedAt || !currentVersionSnapshot.exists ||
        !isDeepStrictEqual(currentVersionSnapshot.data(), current)) {
      throw new HttpsError('failed-precondition', 'La declaración cambió mientras se generaba el PDF.');
    }
    if (current.finalPdfPath != null || existingEventSnapshot.exists) throw new HttpsError('already-exists', 'La versión ya tiene una ruta PDF o un evento de generación.');
    const now = FieldValue.serverTimestamp();
    const updated = { ...current, finalPdfPath: path, revision: nextRevision, updatedAt: now };
    transaction.set(declarationRef, updated);
    transaction.set(versionRef, updated);
    transaction.create(eventRef, { id: eventId, declarationId, actorId: uid,
      action: 'pdfGenerated', occurredAt: now, details,
      ...declarationAuditState(version, 'receivedByHr', 'receivedByHr') });
    return { declarationId, version, revision: nextRevision, eventId, finalPdfPath: path, alreadyGenerated: false };
  });
});

/** Returns PDF bytes only after a fresh server-side authorization check. */
export const downloadFinalDeclarationPdf = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarationId !== 'string' || !data.declarationId.trim() ||
      !Number.isSafeInteger(data.expectedVersion) || (data.expectedVersion as number) < 1) {
    throw new HttpsError('invalid-argument', 'Indique la declaración y su versión.');
  }
  const [profileSnapshot, declarationSnapshot] = await Promise.all([
    db.doc(`users/${uid}`).get(), db.doc(`declarations/${data.declarationId}`).get(),
  ]);
  const profile = profileSnapshot.data();
  if (profile?.active !== true) throw new HttpsError('permission-denied', 'El perfil no está activo.');
  if (!declarationSnapshot.exists) throw new HttpsError('not-found', 'No existe la declaración.');
  const declaration = declarationSnapshot.data()!;
  const version = data.expectedVersion as number;
  if (declaration.version !== version || !['receivedByHr', 'finalized'].includes(String(declaration.status)) ||
      declaration.finalPdfPath !== `final-declarations/${declarationSnapshot.id}/v${version}.pdf`) {
    throw new HttpsError('failed-precondition', 'No hay un PDF final disponible para esta versión.');
  }
  let allowed = declaration.personId === uid || reviewerRoles.has(profile.role);
  if (profile.role === 'supervisor') {
    const assignmentSnapshot = await db.doc(`supervisor_assignments/${declaration.personId}`).get();
    const assignment = assignmentSnapshot.data();
    if (!assignmentSnapshot.exists || !isValidSupervisorAssignment(assignment, declaration.personId)) {
      throw new HttpsError('failed-precondition', 'La asignación vigente está incompleta o es inconsistente.');
    }
    allowed = assignment.supervisorId === uid;
  }
  if (!allowed) throw new HttpsError('permission-denied', 'No tiene permiso para descargar este PDF.');
  const pdfRevision = declaration.status === 'finalized'
    ? (declaration.revision as number) - 1 : declaration.revision as number;
  if (!Number.isSafeInteger(pdfRevision) || pdfRevision < 1) {
    throw new HttpsError('failed-precondition', 'La revisión del PDF final es inconsistente.');
  }
  const [versionSnapshot, pdfEventSnapshot] = await Promise.all([
    declarationSnapshot.ref.collection('versions').doc(String(version)).get(),
    declarationSnapshot.ref.collection('events').doc(`pdfGenerated_v${version}_r${pdfRevision}`).get(),
  ]);
  const pdfEvent = pdfEventSnapshot.data();
  const pdfDetails = `version=${version};revision=${pdfRevision};sourceRevision=${pdfRevision - 1};path=${declaration.finalPdfPath}`;
  if (!versionSnapshot.exists || !isDeepStrictEqual(versionSnapshot.data(), declaration) ||
      !pdfEventSnapshot.exists || pdfEvent?.id !== `pdfGenerated_v${version}_r${pdfRevision}` ||
      pdfEvent.declarationId !== declarationSnapshot.id ||
      typeof pdfEvent.actorId !== 'string' || !pdfEvent.actorId.trim() ||
      pdfEvent.action !== 'pdfGenerated' || pdfEvent.details !== pdfDetails ||
      !(pdfEvent.occurredAt instanceof Timestamp)) {
    throw new HttpsError('failed-precondition', 'El espejo o el historial del PDF final está inconsistente.');
  }
  const stored = await requireFinalPdfObject(declarationSnapshot.id, version, pdfRevision - 1);
  const [bytes] = await stored.file.download();
  if (bytes.length > 7_000_000) throw new HttpsError('resource-exhausted', 'El PDF supera el tamaño máximo de descarga.');
  return { fileName: `declaracion-${declarationSnapshot.id}-v${version}.pdf`, base64: bytes.toString('base64') };
});

/** Finalizes only after a trusted PDF object and generation event are verified. */
export const finalizeDeclaration = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarationId !== 'string' || !data.declarationId.trim() ||
      !Number.isSafeInteger(data.expectedVersion) || (data.expectedVersion as number) < 1 ||
      !Number.isSafeInteger(data.expectedRevision) || (data.expectedRevision as number) < 0 || data.confirmed !== true) {
    throw new HttpsError('invalid-argument', 'Confirme la finalización e indique versión y revisión.');
  }
  const declarationRef = db.doc(`declarations/${data.declarationId}`);
  const version = data.expectedVersion as number;
  const revision = data.expectedRevision as number;
  const nextRevision = revision + 1;
  const versionRef = declarationRef.collection('versions').doc(String(version));
  const eventId = `finalized_v${version}_r${nextRevision}`;
  const eventRef = declarationRef.collection('events').doc(eventId);
  const preflightProfile = (await db.doc(`users/${uid}`).get()).data();
  if (!reviewerRoles.has(preflightProfile?.role) || preflightProfile?.active !== true) {
    throw new HttpsError('permission-denied', 'Se requiere un perfil activo de administración o Recursos Humanos.');
  }
  const preflight = await declarationRef.get();
  if (!preflight.exists) throw new HttpsError('not-found', 'No existe la declaración.');
  const preflightData = preflight.data()!;
  const expectedPath = `final-declarations/${declarationRef.id}/v${version}.pdf`;
  if (preflightData.finalPdfPath !== expectedPath) {
    throw new HttpsError('failed-precondition', 'Primero debe generarse el PDF final en el almacenamiento seguro.');
  }
  const storedPdf = await requireFinalPdfObject(declarationRef.id, version);
  const sourceRevision = Number(storedPdf.metadata.metadata?.sourceRevision);
  if (!Number.isSafeInteger(sourceRevision) || sourceRevision < 0) {
    throw new HttpsError('failed-precondition', 'El PDF no conserva metadatos válidos de versión.');
  }
  const pdfGenerationRevision = sourceRevision + 1;
  const pdfGeneratedEventId = `pdfGenerated_v${version}_r${pdfGenerationRevision}`;
  const pdfGeneratedEventRef = declarationRef.collection('events').doc(pdfGeneratedEventId);
  const pdfDetails = `version=${version};revision=${pdfGenerationRevision};sourceRevision=${sourceRevision};path=${expectedPath}`;
  return db.runTransaction(async (transaction) => {
    const [profileSnapshot, declarationSnapshot, versionSnapshot, eventSnapshot, pdfEventSnapshot] = await Promise.all([
      transaction.get(db.doc(`users/${uid}`)), transaction.get(declarationRef),
      transaction.get(versionRef), transaction.get(eventRef), transaction.get(pdfGeneratedEventRef),
    ]);
    const profile = profileSnapshot.data();
    if (!reviewerRoles.has(profile?.role) || profile?.active !== true) throw new HttpsError('permission-denied', 'Se requiere un perfil activo de administración o Recursos Humanos.');
    if (!declarationSnapshot.exists) throw new HttpsError('not-found', 'No existe la declaración.');
    const declaration = declarationSnapshot.data()!;
    if (!versionSnapshot.exists || !isDeepStrictEqual(versionSnapshot.data(), declaration)) throw new HttpsError('failed-precondition', 'El espejo de la versión formal está inconsistente.');
    const event = eventSnapshot.data();
    const details = `version=${version};revision=${nextRevision};pdf=${declaration.finalPdfPath}`;
    const pdfEvent = pdfEventSnapshot.data();
    const pdfEventIsValid = pdfEventSnapshot.exists && pdfEvent?.id === pdfGeneratedEventId &&
      pdfEvent.declarationId === declarationRef.id && typeof pdfEvent.actorId === 'string' &&
      pdfEvent.actorId.trim().length > 0 && pdfEvent.action === 'pdfGenerated' &&
      pdfEvent.details === pdfDetails && pdfEvent.occurredAt instanceof Timestamp;
    const alreadyFinalized = declaration.status === 'finalized' && declaration.revision === nextRevision &&
      declaration.finalizedAt instanceof Timestamp && event?.id === eventId && event.actorId === uid &&
      event.action === 'finalized' && event.details === details && event.occurredAt instanceof Timestamp &&
      event.occurredAt.isEqual(declaration.finalizedAt) && pdfEventIsValid &&
      isDeepStrictEqual(versionSnapshot.data(), declaration);
    if (alreadyFinalized) return { declarationId: declarationRef.id, version, revision: nextRevision, eventId, alreadyFinalized: true };
    if (declaration.version !== version || declaration.revision !== revision) throw new HttpsError('failed-precondition', 'La declaración cambió; actualice la información.');
    if (declaration.status !== 'receivedByHr' || !(declaration.hrReceivedAt instanceof Timestamp)) throw new HttpsError('failed-precondition', 'Solo se puede finalizar una declaración recibida por Recursos Humanos.');
    if (!pdfEventIsValid || declaration.finalPdfPath !== expectedPath ||
        declaration.revision !== pdfGenerationRevision) {
      throw new HttpsError('failed-precondition', 'No se pudo verificar el PDF final generado para esta revisión.');
    }
    if (eventSnapshot.exists) throw new HttpsError('already-exists', 'El evento de finalización existe sin una transición íntegra.');
    const now = FieldValue.serverTimestamp();
    const updated = { ...declaration, status: 'finalized', revision: nextRevision, finalizedAt: now, updatedAt: now };
    transaction.set(declarationRef, updated); transaction.set(versionRef, updated);
    transaction.create(eventRef, { id: eventId, declarationId: declarationRef.id,
      actorId: uid, action: 'finalized', occurredAt: now, details,
      ...declarationAuditState(version, 'receivedByHr', 'finalized') });
    return { declarationId: declarationRef.id, version, revision: nextRevision, eventId, alreadyFinalized: false };
  });
});

/** Lists bounded metadata for an administrator's explicit annulment selection. */
export const findDeclarationsForAnnulment = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap;
  if (!isMap(data) || typeof data.periodId !== 'string' || !data.periodId.trim() ||
      (data.after != null && (typeof data.after !== 'string' || !data.after || data.after.includes('/')))) {
    throw new HttpsError('invalid-argument', 'Seleccione un período válido.');
  }
  // Recheck the persisted role on every page; client visibility is not authority.
  return db.runTransaction(async (tx) => {
    const profile = (await tx.get(db.doc(`users/${uid}`))).data();
    if (profile?.role !== 'administrator' || profile.active !== true) {
      throw new HttpsError('permission-denied', 'Se requiere un perfil activo de administración.');
    }
    let query = db.collection('declarations').where('periodId', '==', data.periodId)
      .orderBy(FieldPath.documentId()).limit(51);
    if (typeof data.after === 'string') query = query.startAfter(data.after);
    const snapshot = await tx.get(query);
    const page = snapshot.docs.slice(0, 50);
    return {
      declarations: page.map(doc => {
        const d = doc.data();
        const profile = isMap(d.payload) && isMap(d.payload.profile) ? d.payload.profile : {};
        return { id: doc.id, personId: d.personId, periodId: d.periodId,
          name: typeof profile.name === 'string' ? profile.name : '',
          status: d.status, version: d.version, revision: d.revision ?? 0 };
      }),
      next: snapshot.docs.length > 50 ? page[page.length - 1].id : null,
    };
  });
});

/** Annuls a declaration through an explicit, revision-checked admin action. */
export const annulDeclaration = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Debe iniciar sesión.');
  const data = request.data as JsonMap | null;
  if (!isMap(data) || typeof data.declarationId !== 'string' || !data.declarationId.trim() ||
      typeof data.reason !== 'string' || !data.reason.trim() || data.reason.trim().length > 2000 ||
      !Number.isSafeInteger(data.expectedVersion) || (data.expectedVersion as number) < 1 ||
      !Number.isSafeInteger(data.expectedRevision) || (data.expectedRevision as number) < 0 ||
      data.confirmed !== true) {
    throw new HttpsError('invalid-argument', 'Indique el motivo, confirme la anulación y proporcione versión y revisión.');
  }
  const declarationId = data.declarationId.trim();
  const version = data.expectedVersion as number;
  const revision = data.expectedRevision as number;
  const reason = data.reason.trim();
  const declarationRef = db.doc(`declarations/${declarationId}`);
  const versionRef = declarationRef.collection('versions').doc(String(version));
  const nextRevision = revision + 1;
  const eventId = `annulled_v${version}_r${nextRevision}`;
  const eventRef = declarationRef.collection('events').doc(eventId);
  return db.runTransaction(async (transaction) => {
    const [profileSnapshot, declarationSnapshot] = await Promise.all([
      transaction.get(db.doc(`users/${uid}`)), transaction.get(declarationRef),
    ]);
    const profile = profileSnapshot.data();
    if (!reviewerRoles.has(profile?.role) || profile?.active !== true) {
      throw new HttpsError('permission-denied', 'Se requiere un perfil activo de administración o Recursos Humanos.');
    }
    if (!declarationSnapshot.exists) throw new HttpsError('not-found', 'No existe la declaración.');
    const declaration = declarationSnapshot.data()!;
    if (declaration.status === 'finalized') {
      throw new HttpsError('failed-precondition', 'No se puede anular una declaración finalizada.');
    }
    if (declaration.status === 'annulled') {
      throw new HttpsError('failed-precondition', 'La declaración ya está anulada.');
    }
    if (declaration.version !== version || declaration.revision !== revision) {
      throw new HttpsError('failed-precondition', 'La declaración cambió; actualice la información antes de anular.');
    }
    const [versionSnapshot, eventSnapshot] = await Promise.all([
      transaction.get(versionRef), transaction.get(eventRef),
    ]);
    if (!versionSnapshot.exists || !isDeepStrictEqual(versionSnapshot.data(), declaration)) {
      throw new HttpsError('failed-precondition', 'El espejo de la versión está inconsistente.');
    }
    if (eventSnapshot.exists) throw new HttpsError('already-exists', 'Ya existe el evento de anulación para esta revisión.');
    const now = FieldValue.serverTimestamp();
    const updated = { ...declaration, status: 'annulled', revision: nextRevision,
      annulmentReason: reason, annulledAt: now, updatedAt: now };
    transaction.set(declarationRef, updated);
    transaction.set(versionRef, updated);
    transaction.create(eventRef, { id: eventId, declarationId, actorId: uid,
      action: 'annulled', occurredAt: now, details: reason,
      ...declarationAuditState(version, declaration.status as string, 'annulled') });
    return { declarationId, version, revision: nextRevision, eventId, annulled: true };
  });
});
