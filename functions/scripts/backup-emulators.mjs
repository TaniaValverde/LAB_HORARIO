import { mkdir, readFile, readdir, cp, writeFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const project = 'demo-declara-horario';
const base = path.join(root, 'firebase-export-backups');
async function verify(dir) {
  const m = JSON.parse(await readFile(path.join(dir, 'firebase-export-metadata.json'), 'utf8'));
  for (const key of ['auth', 'firestore', 'storage']) {
    if (!m[key] || m[key].path !== `${key}_export`) throw Error(`Missing ${key} export`);
    if (!(await stat(path.join(dir, m[key].path))).isDirectory()) throw Error('Invalid export');
  }
  JSON.parse(await readFile(path.join(dir, 'auth_export/accounts.json'), 'utf8'));
  await stat(path.join(dir, 'firestore_export/firestore_export.overall_export_metadata'));
}
async function inventory(dir, prefix = '') {
  const result = {};
  for (const entry of await readdir(path.join(dir, prefix), {withFileTypes:true})) {
    const relative = path.join(prefix, entry.name);
    if (entry.isDirectory()) Object.assign(result, await inventory(dir, relative));
    else if (entry.isFile()) result[relative] = createHash('sha256').update(await readFile(path.join(dir, relative))).digest('hex');
    else throw Error('Unexpected entry in backup');
  }
  return result;
}
async function backup() {
  const info = await fetch('http://127.0.0.1:4400/emulators').then(r => r.json());
  for (const name of ['auth','firestore','storage']) if (!info[name]) throw Error(`Emulator missing: ${name}`);
  // Verify the project served by the local hub before requesting an export.
  const locator = JSON.parse(await readFile(path.join((await import('node:os')).tmpdir(), `hub-${project}.json`), 'utf8'));
  if (!locator.origins?.some(x => x === 'http://127.0.0.1:4400')) throw Error('Unexpected emulator hub');
  await mkdir(base, {recursive:true});
  const target = path.join(base, `snapshot-${Date.now()}`);
  const response = await fetch('http://127.0.0.1:4400/_admin/export', {
    method:'POST', headers:{'Content-Type':'application/json'},
    body:JSON.stringify({path:target, initiatedBy:'emulators:export', targets:['auth','firestore','storage']})
  });
  if (!response.ok) {
    const error = await response.json();
    const match = /EPERM:.*rename '([^']+)' -> '([^']+)'/.exec(error.message ?? '');
    if (!match || path.resolve(match[2]) !== target) throw Error(error.message ?? 'Export failed');
    const source = path.resolve(match[1]);
    if (path.dirname(source) !== root || !/^firebase-export-\d+/.test(path.basename(source))) throw Error('Unexpected recovery directory');
    await verify(source);
    await cp(source, target, {recursive:true, errorOnExist:true, force:false});
    const original = await inventory(source);
    const copied = await inventory(target);
    if (JSON.stringify(original) !== JSON.stringify(copied)) throw Error('Recovery copy differs');
    console.log('Export recovered by copying; original retained.');
  }
  await verify(target);
  await writeFile(path.join(target, 'checksums.json'), JSON.stringify(await inventory(target), null, 2));
  // Marker written only after all three exports have been checked.
  await writeFile(path.join(target, 'COMPLETE'), new Date().toISOString());
  console.log(`Backup complete: ${target}`);
}
let busy = false;
async function run() {
  if (busy) return;
  busy = true;
  try { await backup(); } catch(e) { console.error(`BACKUP FAILED: ${e.message}`); if (!process.argv.includes('--watch')) process.exitCode=1; }
  finally { busy=false; }
}
await run();
if (process.argv.includes('--watch')) {
  console.log('Automatic backup every 60 seconds. Keep this terminal open.');
  setInterval(run, 60000);
}
