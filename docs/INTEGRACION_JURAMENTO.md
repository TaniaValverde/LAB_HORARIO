# Oath acceptance and internal signatures

The integrated application performs oath acceptance and declarant signing as separate callables. Protected transition fields, formal mirrors and events are not written directly by Flutter.

## Approved text registry

Both documents are required:

- `system_config/declarant_oath`: `{status: "approved", approvedVersion: 1}`.
- `institutional_texts/declarant_oath/versions/1`: `{status: "approved", version: 1, text: "<approved text>", approvedAt: <Timestamp>}`.

Version identifiers are positive integers. Preserve accepted wording; publish a new version instead of editing text already accepted. Clients cannot write these documents.

Official institutional wording is not supplied by this repository. Local demonstrations may use clearly marked test wording provisioned only in the emulator. `functions/test/fixtures/declarant_oath_v1_0_draft.json` has editorial identifier `1.0` and draft status; it is neither institutional approval nor an accepted registry version. Official use requires trusted approval/publication and a mapping to the integer version schema.

## Acceptance

1. `getApprovedDeclarantOath` returns the approved active text.
2. Flutter displays it and requires explicit confirmation.
3. `acceptOath` verifies authenticated UID, active declarant profile, ownership, validated state, version, revision, confirmation and requested text version.
4. A transaction updates the declaration, `versions/{version}` mirror and canonical `oathAccepted_v{version}_r{revision}` event. Valid retries are idempotent.

## Declarant signature

`signDeclaration` rechecks identity, active role, ownership, expected state/version/revision, historical oath evidence and schedule validity. A transaction records signature identity, server timestamp, content hash and canonical signature event together with the declaration/mirror.

This is an internal electronic signature, not a certified external digital-signature service. Historical signature audit revisions are resolved from persisted signature identity, not the latest declaration revision.

## Local operation

Use the [four-terminal startup](../README.md#local-startup-four-terminals). If retrieval fails, inspect both registry documents and Functions logs. Do not overwrite declaration states, hashes or signatures to bypass checks.

An October 28, 2026 incident involved missing registry documents while declarations remained present. Only the configuration/text documents were restored from backup; the rest of the dataset was preserved. The cause was not established. This is historical evidence, not an instruction to overwrite current configuration.

`functions/test/accept_oath.test.mjs` can remove shared configuration in its fixtures. Run it only in a disposable isolated environment; see the [test guide](../security-tests/LOCAL_EMULATORS.md).
