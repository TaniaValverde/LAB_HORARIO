# Socket.IO notifications

The local notification server complements Firebase persistence and callable workflows. It never signs, saves or changes declarations. Without `SOCKET_URL`, regular data access and manual/periodic refresh paths remain available.

## Startup

Follow [Terminals 1–4](../README.md#local-startup-four-terminals). Terminal 3 starts `realtime-server`; Terminal 4 supplies `SOCKET_URL=http://localhost:3001`. The example environment targets `demo-declara-horario`, Auth at 127.0.0.1:9099 and Firestore at 127.0.0.1:8180.

`ALLOWED_ORIGINS` must match the exact Flutter origin, including port: `http://localhost:5200`. No remote deployment or remote credentials are required for this delivery.

## Contract and authorization

The client sends a Firebase token in `handshake.auth.token`, not a chosen UID/role. The server verifies the token, expiration/revocation and active persisted profile. Role/activation changes disconnect the session.

The state-change notification is:

```text
declaration:changed { id, status, version, revision }
```

It contains no form, email, oath or observations. Recipients re-read data through authorized services. Admin SDK bypasses Firestore rules; server authorization and assignment checks remain mandatory.

| Role | Scope |
| --- | --- |
| Declarant | Owned declaration state changes; initial snapshots establish a baseline |
| Supervisor | Assigned declarations pending signature; profile, assignment and declaration rechecked before emission |
| Human Resources | Entries into `sentToHr`; active role and state/version/revision rechecked |
| Administrator | No notification channel implemented |

Existing pending items may notify a supervisor on connection or new assignment. HR initial snapshots do not replay historical notices. Active HR users share the existing institutional inbox scope.

## Client lifecycle and limits

Flutter displays connection state, refreshes inboxes on notices and reconnects with fresh tokens and progressive delay up to 30 seconds. Recent events are deduplicated; listeners are disposed on exit/session change. Notices are transient: missed messages are not replayed, so authoritative data must be refreshed.

Subscription cost depends on role and assignments; supervisors maintain per-declarant listeners. Production-scale capacity and load testing are not certified.

## Verification

`npm.cmd --prefix realtime-server test` uses real Socket.IO connections with simulated authentication/persistence. It checks isolation, rejection, minimal payloads, duplicates and cleanup; it is not an end-to-end Firebase test.

Manual checks: keep the recipient inbox open, perform a permitted transition in another browser and confirm refresh. Repeat with an unassigned account and check reconnection. Do not clear/restart emulators merely to test notifications.

Historical results are recorded in [technical verification](CIERRE_TECNICO.md).
