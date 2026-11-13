# Isolated emulator testing

The working demonstration uses `demo-declara-horario`. Do not run destructive suites against its active dataset. Rules tests call `clearFirestore`; oath fixtures delete/replace shared registry documents.

For ordinary operation, use the [four-terminal startup](../README.md#local-startup-four-terminals) and [safe shutdown](../README.md#safe-shutdown-and-backups).

## Checks without emulator data mutation

From the repository root:

```powershell
flutter analyze
flutter test
npm.cmd --prefix functions run build
node --test functions/test/content_hash.test.mjs functions/test/schedule_validation.test.mjs functions/test/final_declaration_pdf.test.mjs functions/test/annulment_lookup.test.mjs
npm.cmd --prefix realtime-server test
```

The lookup unit test intercepts Firestore reads. Socket.IO tests use simulated authorization/persistence. Neither substitutes for real callable integration testing.

## Firestore and Storage rules

Install test dependencies once with `npm.cmd --prefix security-tests ci`. Use an isolated project ID, explicitly overriding the suite's demo default:

```powershell
$env:FIRESTORE_TEST_PROJECT_ID = 'demo-cierre-reglas'
npm.cmd --prefix security-tests test
```

The configured Firestore and Storage emulators must be reachable at the suite's expected ports. These tests clear Firestore for the selected project. Verify the environment variable in the same terminal before running. The recorded closure used `demo-cierre-reglas`; emulator project-mismatch warnings do not justify switching the tests to the working demo ID.

If a separate emulator process is required, first back up and safely stop the working suite to release its ports. Use a disposable test environment with no imported demo backup. Never stop unidentified processes to free ports.

## Functions integration

The current `accept_oath`, `administration`, `supervisor_inbox` and `workflow` fixtures hardcode `demo-declara-horario`. Setting `FIRESTORE_TEST_PROJECT_ID` does not isolate them.

Run these only against a disposable emulator instance, with the working demo safely backed up and stopped. Do not use `emulators:restore`, import a live backup or run the backup monitor for that disposable instance: a fixture snapshot must not become the newest restore candidate.

After inspecting the selected fixtures and installing dependencies, start a fresh disposable suite from the repository root:

```powershell
npm.cmd --prefix functions run build
firebase.cmd emulators:start --project demo-declara-horario --only auth,firestore,functions,storage
```

In another terminal, run only the intended fixtures, for example:

```powershell
node --test functions/test/accept_oath.test.mjs functions/test/administration.test.mjs functions/test/supervisor_inbox.test.mjs functions/test/workflow.test.mjs
```

These are test-environment commands, not normal startup instructions. They seed users/documents with Admin SDK and invoke local callable endpoints; oath tests alter global test configuration. On completion, stop the disposable suite without exporting it. Restore the working demonstration using the normal README procedure and its preserved COMPLETE backup.

No test command authorizes remote deployment. Never run fixtures with production credentials or repoint them to the remote project. The test oath is not approved institutional wording.
