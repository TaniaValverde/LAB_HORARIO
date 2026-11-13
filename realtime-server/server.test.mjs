import test from 'node:test';
import assert from 'node:assert/strict';
import { io as client } from 'socket.io-client';
import { createRealtime } from './server.mjs';
const pause = () => new Promise(r => setTimeout(r, 80));
const once = (socket, event) => new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(Error(`Timeout ${event}`)), 3000);
  socket.once(event, value => { clearTimeout(timer); resolve(value); });
});
test('auth, owner isolation, status changes, deactivation and cleanup', async t => {
  const watchers = new Map();
  const profiles = new Map();
  let unsubscribed = 0;
  const { http, io } = createRealtime({
    origins: ['http://localhost:5200'],
    verify: async token => { if (!['alice', 'bob', 'inactive'].includes(token)) throw Error(); return { uid: token, exp: Math.floor(Date.now()/1000)+60 }; },
    profile: async uid => ({ role: 'declarant', active: uid !== 'inactive' }),
    watchProfile: (uid, next) => { profiles.set(uid, next); return () => { profiles.delete(uid); unsubscribed++; }; },
    watch: (uid, next) => { watchers.set(uid, next); next([{ id: uid, personId: uid, status: 'validated', version: 1, revision: 1 }]); return () => { watchers.delete(uid); unsubscribed++; }; },
  });
  await new Promise(r => http.listen(0, '127.0.0.1', r));
  t.after(() => new Promise(r => io.close(r)));
  const connect = token => {
    const s = client(`http://127.0.0.1:${http.address().port}`, { transports: ['websocket'], extraHeaders: { origin: 'http://localhost:5200' }, auth: { token }, reconnection: false, autoConnect: false });
    t.after(() => s.close()); return s;
  };
  for (const token of ['bad', 'inactive']) {
    const s = connect(token); const rejected = once(s, 'connect_error'); s.connect(); assert.equal((await rejected).message, 'unauthorized');
  }
  const a = connect('alice'); const b = connect('bob');
  const ready = Promise.all([once(a, 'connect'), once(b, 'connect')]); a.connect(); b.connect(); await ready;
  const notices = []; const other = [];
  a.on('declaration:changed', x => notices.push(x)); b.on('declaration:changed', x => other.push(x));
  await pause(); assert.equal(notices.length, 0);
  const row = { id: 'alice', personId: 'alice', status: 'signedByDeclarant', version: 1, revision: 2, payload: 'private' };
  watchers.get('alice')([row, { ...row, id: 'bob', personId: 'bob' }]);
  await pause(); assert.deepEqual(notices, [{ id: 'alice', status: 'signedByDeclarant', version: 1, revision: 2 }]); assert.equal(other.length, 0);
  watchers.get('alice')([row]); a.emit('declaration:changed', row); await pause(); assert.equal(notices.length, 1); assert.equal(other.length, 0);
  const disconnected = once(a, 'disconnect'); profiles.get('alice')({ active: false, role: 'declarant' }); await disconnected;
  assert.equal(watchers.has('alice'), false); assert.equal(unsubscribed, 2);
  b.close(); await pause(); assert.equal(unsubscribed, 4);
});
test('rejects foreign origins and expired tokens before subscribing', async t => {
  const { http, io } = createRealtime({
    origins: ['http://localhost:5200'],
    verify: async () => ({ uid: 'alice', exp: 1 }),
    profile: async () => ({ active: true, role: 'declarant' }),
    watch: () => { throw Error('must not subscribe'); },
    watchProfile: () => { throw Error('must not subscribe'); },
  });
  await new Promise(r => http.listen(0, '127.0.0.1', r));
  t.after(() => new Promise(r => io.close(r)));
  for (const origin of ['http://localhost:5200', 'http://foreign.test']) {
    const socket = client(`http://127.0.0.1:${http.address().port}`, { transports: ['websocket'], extraHeaders: { origin }, auth: { token: 'expired' }, reconnection: false, autoConnect: false });
    t.after(() => socket.close());
    const rejected = once(socket, 'connect_error'); socket.connect(); await rejected;
    assert.equal(socket.connected, false);
  }
});


test('supervisor notices require current authorization and disconnect on role change', async t => {
  let publish, changeProfile;
  let allowed = false, cleaned = 0;
  const {http, io} = createRealtime({
    origins: ['http://localhost:5200'],
    verify: async () => ({uid:'superior', exp:Math.floor(Date.now()/1000)+60}),
    profile: async () => ({role:'supervisor', active:true}),
    watchProfile: (_, next) => {changeProfile=next; return () => cleaned++;},
    watch: () => {throw Error('owner subscription must not be used');},
    watchSupervisor: (_, next) => {publish=next; next([]); return () => cleaned++;},
    authorizeSupervisor: async () => allowed,
  });
  await new Promise(r => http.listen(0,'127.0.0.1',r));
  t.after(() => new Promise(r => io.close(r)));
  const s = client(`http://127.0.0.1:${http.address().port}`, {transports:['websocket'], extraHeaders:{origin:'http://localhost:5200'}, auth:{token:'test'}, reconnection:false, autoConnect:false});
  t.after(() => s.close());
  const connected = once(s,'connect'); s.connect(); await connected;
  const notices=[]; s.on('declaration:changed', x => notices.push(x));
  const row={id:'doc',personId:'owner',status:'pendingSuperiorSignature',version:1,revision:4,payload:'secret'};
  publish([row]); await pause(); assert.equal(notices.length,0);
  publish([]); allowed=true; publish([row]); await pause();
  assert.deepEqual(notices,[{id:'doc',status:row.status,version:1,revision:4}]);
  publish([row]); await pause(); assert.equal(notices.length,1);
  const disconnected=once(s,'disconnect'); changeProfile({role:'declarant',active:true}); await disconnected;
  assert.equal(cleaned,2);
});


test('HR receives only new sent declarations, rechecks access and cleans up', async t => {
  let publish, changeProfile, allowed = true, cleaned = 0;
  const {http, io} = createRealtime({
    origins:['http://localhost:5200'],
    verify:async token => ({uid:token,exp:Math.floor(Date.now()/1000)+60}),
    profile:async uid => ({role:'humanResources',active:uid !== 'inactive'}),
    watchProfile:(_,next) => {changeProfile=next;return () => cleaned++;},
    watch:() => {throw Error('wrong subscription');},
    watchHr:(_,next) => {publish=next;next([]);return () => cleaned++;},
    authorizeHr:async () => allowed,
  });
  await new Promise(r => http.listen(0,'127.0.0.1',r));
  t.after(() => new Promise(r => io.close(r)));
  const connect = token => {
    const s=client(`http://127.0.0.1:${http.address().port}`,{transports:['websocket'],extraHeaders:{origin:'http://localhost:5200'},auth:{token},reconnection:false,autoConnect:false});
    t.after(() => s.close());return s;
  };
  const inactive=connect('inactive');const denied=once(inactive,'connect_error');inactive.connect();assert.equal((await denied).message,'unauthorized');
  const s=connect('hr');const ready=once(s,'connect');s.connect();await ready;
  const notices=[];s.on('declaration:changed',x => notices.push(x));
  const row={id:'doc',personId:'owner',status:'sentToHr',version:1,revision:8,payload:'private'};
  publish([{...row,status:'draft'}]);await pause();assert.equal(notices.length,0);
  publish([row]);await pause();assert.deepEqual(notices,[{id:'doc',status:'sentToHr',version:1,revision:8}]);
  publish([row]);await pause();assert.equal(notices.length,1);
  allowed=false;publish([row,{...row,id:'denied'}]);await pause();assert.equal(notices.length,1);
  const stopped=once(s,'disconnect');changeProfile({role:'humanResources',active:false});await stopped;assert.equal(cleaned,2);
});
