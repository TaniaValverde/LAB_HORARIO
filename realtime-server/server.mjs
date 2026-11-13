import { createServer } from 'node:http';
import { Server } from 'socket.io';

// Firebase is injected so authorization and isolation can be tested without credentials.
export function createRealtime({ origins, verify, profile, watch, watchProfile, watchSupervisor, authorizeSupervisor, watchHr, authorizeHr }) {
  const http = createServer((req, res) => { res.writeHead(404); res.end(); });
  const io = new Server(http, {
    cors: { origin: origins }, maxHttpBufferSize: 16384,
    allowRequest: (req, done) => done(null, origins.includes(req.headers.origin)),
  });
  const active = p => p?.active === true && ['declarant', 'DECLARANTE', 'supervisor', 'humanResources'].includes(p.role);
  io.use(async (socket, next) => {
    try {
      const token = socket.handshake.auth?.token;
      if (typeof token !== 'string' || token.length > 12000) throw Error();
      const account = await verify(token);
      const userProfile = await profile(account.uid);
      if (!account.uid || !Number.isFinite(account.exp) || account.exp * 1000 <= Date.now() || !active(userProfile)) throw Error();
      socket.data.account = account;
      socket.data.role = userProfile.role;
      next();
    } catch { next(new Error('unauthorized')); }
  });
  io.on('connection', socket => {
    const { uid, exp } = socket.data.account;
    let previous = new Map();
    let initial = true;
    let stopped = false;
    const stops = [];
    const stop = () => {
      if (stopped) return;
      stopped = true;
      clearTimeout(expiry);
      for (const unsubscribe of stops) unsubscribe();
    };
    const fail = () => { socket.disconnect(true); stop(); };
    const expiry = setTimeout(fail, Math.min(exp * 1000 - Date.now(), 2147483647));
    socket.on('disconnect', stop);
    const add = unsubscribe => stopped ? unsubscribe() : stops.push(unsubscribe);
    try {
      add(watchProfile(uid, p => { if (!active(p) || p.role !== socket.data.role) fail(); }, fail));
      if (stopped) return;
      const supervisor = socket.data.role === 'supervisor';
      const hr = socket.data.role === 'humanResources';
      const subscribe = hr ? watchHr : supervisor ? watchSupervisor : watch;
      add(subscribe(uid, rows => {
        if (stopped) return;
        const current = new Map();
        for (const row of rows) {
          if ((!supervisor && !hr && row.personId !== uid) || (hr && row.status !== 'sentToHr') || (supervisor && row.status !== 'pendingSuperiorSignature') || typeof row.id !== 'string' || typeof row.status !== 'string' || !Number.isInteger(row.version) || !Number.isInteger(row.revision)) continue;
          current.set(row.id, row.status);
          if (!initial && (supervisor || hr || previous.has(row.id)) && previous.get(row.id) !== row.status) {
            const message = { id: row.id, status: row.status, version: row.version, revision: row.revision };
            if (supervisor || hr) {
              Promise.resolve((hr ? authorizeHr : authorizeSupervisor)(uid, row)).then(allowed => {
                if (allowed && !stopped && previous.get(row.id) === row.status) socket.emit('declaration:changed', message);
              }).catch(fail);
            } else socket.emit('declaration:changed', message);
          }
        }
        previous = current;
        initial = false;
      }, fail));
    } catch { fail(); }
  });
  return { http, io };
}
