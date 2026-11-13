# Codex instructions — DeclaraHorario

## Start here
- Read `CONTEXTO_PROYECTO.md`, then the relevant source and README sections before changing behavior. The context file records a dated snapshot, not a substitute for inspecting current code.
- Check Git branch, status and existing user changes. Preserve unrelated edits and local emulator data. Do not commit, push, deploy or publish unless requested.
- Work in this repository, not an unrelated default workspace. Explain work to the user in Spanish; guide manual checks one step at a time.

## Scope and conventions
- The agreed delivery is local Flutter Web with Firebase emulators and Socket.IO. Use project `demo-declara-horario`; do not enable billing or deploy to the remote Firebase project without an explicit new request.
- Write new or changed code comments in English, explaining contracts or reasons rather than obvious syntax. Keep user-facing messages in Spanish. Existing Spanish comments do not justify a broad rewrite.
- Preserve feature/domain/data/presentation boundaries. `main.dart` is the integrated application; `main_demo.dart` and in-memory repositories are prototypes.
- Prefer focused changes and meaningful regression checks. Do not refactor a working workflow merely for style. For documentation-only work, do not alter runtime logic or dependencies.

## Contracts that must remain intact
- A person has one declaration chain per academic period. A correction creates a new document/version, preserving the previous signed/returned document.
- Formal `version` and optimistic-concurrency `revision` are different. Preserve atomic declaration + version mirror + audit writes and expected-version/revision guards.
- Resolve historical signature audit revisions from the persisted signature identity, not the latest declaration revision. Preserve canonical hashes, actors, timestamps, oath evidence and version-mirror checks.
- Privileged transitions belong to callable Functions. UI visibility is not authorization. Preserve active-profile, role, ownership and supervisor-assignment checks in Functions, rules and Socket.IO. Admin SDK bypasses security rules.
- Keep approved oath text/version configuration checks. Test text is not an official institutional oath. Internal signature evidence is not a certified external digital-signature service.
- Keep final PDF access through authorized callables; Storage rules deny direct client reads and writes.
- Socket.IO is a notification channel, not authority for state changes. Emit only the existing minimal event contract; re-read authorized data through the existing services. Dispose listeners, reject stale identities and preserve role/assignment revalidation.
- Do not return a Future from a Flutter `setState` callback. Perform asynchronous work outside the synchronous state mutation.

## Local operation and data safety
- Use the local startup/backup procedure in CONTEXTO_PROYECTO.md and README. Always include `FIREBASE_EMULATORS=true` when running the local app; the default uses remote options.
- On Windows prefer `npm.cmd` and `firebase.cmd`. Do not restart emulators unnecessarily while troubleshooting Flutter or Socket.IO.
- Back up while emulators are running; wait for `Backup complete` before stopping them. Do not rely on the legacy `--export-on-exit` command after the observed Windows EPERM failures.
- Never delete export folders, overwrite backups, kill all Java/Node processes or free a port without identifying its owner. Preserve recoverable temporary exports.
- Never commit emulator accounts, exports, generated backups, local `.env` files or private credentials. Inspect untracked files before staging; do not use blanket staging when exports are present.

## Verification and handoff
- Select checks appropriate to the change: Flutter analyze/tests, Functions build/integration tests, realtime tests, or security rule tests. Record commands and actual results; do not present historical results as a fresh run.
- Security tests clear Firestore in the selected test project. Use an isolated project (the closure used `FIRESTORE_TEST_PROJECT_ID=demo-cierre-reglas`), never the live demo dataset. Inspect other integration fixtures before running them: oath tests can alter shared configuration.
- Keep CONTEXTO_PROYECTO.md and relevant docs aligned when contracts or startup procedures change. Separate implemented behavior, user-confirmed manual results, historical automated results and unverified work.
