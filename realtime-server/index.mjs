import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { createRealtime } from './server.mjs';
const projectId = process.env.FIREBASE_PROJECT_ID;
const origins = (process.env.ALLOWED_ORIGINS ?? '').split(',').map(s => s.trim()).filter(Boolean);
if (!projectId || !origins.length || origins.includes('*')) throw Error('Configure FIREBASE_PROJECT_ID y ALLOWED_ORIGINS explícitos.');
const authEmulator = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const dbEmulator = process.env.FIRESTORE_EMULATOR_HOST;
const emulator = Boolean(authEmulator || dbEmulator);
if (emulator && (!authEmulator || !dbEmulator || !projectId.startsWith('demo-'))) throw Error('Use ambos emuladores y un proyecto demo-.');
if (!emulator && projectId.startsWith('demo-')) throw Error('El proyecto demo requiere emuladores.');
initializeApp(emulator ? { projectId } : { projectId, credential: applicationDefault() });
const db = getFirestore();
const { http, io } = createRealtime({
  origins,
  verify: token => getAuth().verifyIdToken(token, true),
  profile: async uid => (await db.doc(`users/${uid}`).get()).data(),
  watchProfile: (uid, next, error) => db.doc(`users/${uid}`).onSnapshot(s => next(s.data()), error),
  watchHr: (_uid, next, error) => db.collection('declarations')
    .where('status', '==', 'sentToHr')
    .onSnapshot(s => next(s.docs.map(d => ({...d.data(), id:d.id}))), error),
  authorizeHr: async (uid, row) => {
    const [user, current] = await Promise.all([
      db.doc(`users/${uid}`).get(), db.doc(`declarations/${row.id}`).get(),
    ]);
    return user.get('active') === true && user.get('role') === 'humanResources' &&
      current.get('status') === 'sentToHr' && current.get('revision') === row.revision &&
      current.get('version') === row.version && current.get('personId') === row.personId;
  },
  authorizeSupervisor: async (uid, row) => {
    const [assignment, user, current] = await Promise.all([
      db.doc(`supervisor_assignments/${row.personId}`).get(),
      db.doc(`users/${uid}`).get(), db.doc(`declarations/${row.id}`).get(),
    ]);
    const a = assignment.data();
    return user.get('active') === true && user.get('role') === 'supervisor' &&
      a?.declarantId === row.personId && a.supervisorId === uid &&
      Number.isSafeInteger(a.revision) && a.revision >= 1 && a.updatedAt?.toDate &&
      typeof a.updatedBy === 'string' && a.updatedBy.trim().length > 0 &&
      current.get('personId') === row.personId && current.get('status') === row.status &&
      current.get('revision') === row.revision;
  },
  watchSupervisor: (uid, next, error) => {
    const subscriptions = new Map();
    const rows = new Map();
    let closed = false;
    const publish = () => { if (!closed) next([...rows.values()].flat()); };
    next([]);
    const assignments = db.collection('supervisor_assignments').where('supervisorId', '==', uid)
      .onSnapshot(snapshot => {
        if (closed) return;
        const owners = new Set(snapshot.docs.filter(d => d.get('declarantId') === d.id).map(d => d.id));
        for (const [owner, stop] of subscriptions) if (!owners.has(owner)) {
          stop(); subscriptions.delete(owner); rows.delete(owner);
        }
        publish();
        for (const owner of owners) if (!subscriptions.has(owner)) {
          subscriptions.set(owner, db.collection('declarations').where('personId', '==', owner)
            .onSnapshot(s => {
              if (closed || !subscriptions.has(owner)) return;
              rows.set(owner, s.docs.map(d => ({...d.data(), id:d.id})).filter(d => d.status === 'pendingSuperiorSignature'));
              publish();
            }, error));
        }
      }, error);
    return () => { closed = true; assignments(); for (const stop of subscriptions.values()) stop(); subscriptions.clear(); rows.clear(); };
  },
  watch: (uid, next, error) => db.collection('declarations').where('personId', '==', uid).onSnapshot(s => next(s.docs.map(d => ({ ...d.data(), id: d.id }))), error),
});
http.listen(Number(process.env.PORT ?? 3001), process.env.HOST ?? '127.0.0.1', () => console.log('Servidor de avisos iniciado.'));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => io.close(() => process.exit(0)));
