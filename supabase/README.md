# Dacha FM cloud library

`dacha-cloud` is an optional private-library API for the native listener. It stores favorites, playlists, hidden author IDs and associated track metadata. It does not host the music catalog or audio files. Guest listening remains available without signing in.

The configured project is `clxaqzlecqiypyiwgkxd`; the base URL is `https://clxaqzlecqiypyiwgkxd.supabase.co/functions/v1/dacha-cloud`. Migration `20260926050001_dacha_cloud_library.sql` and Edge function version 1 were deployed on 26 September 2026. Deployment does not establish a completed real-wallet sign-in. See [build 3 verification](../docs/release/build-3-cloud.md).

## Authentication boundary

The app creates a PKCE verifier and requests a five-minute challenge. Meteor signs the fixed cloud-library statement through the static HTTPS bridge. The app verifies the callback, then sends the proof and its private verifier directly to this API. The handler independently verifies the Ed25519 NEP-413 signature, PKCE, challenge expiry and the claimed account's mainnet FullAccess key. Successful redemption consumes the challenge once and issues a random 30-day bearer session. SQL stores only its SHA256 hash.

`supabase/config.toml` sets `verify_jwt = false` only for `dacha-cloud`. Its native bearer tokens are opaque Dacha sessions, not Supabase Auth JWTs, so the platform's JWT gate cannot validate them. The handler performs its own authentication for every private route; only configuration and challenge/proof entry routes are callable before a session exists. Do not remove those handler/SQL checks. This per-function setting follows Supabase's [function configuration](https://supabase.com/docs/guides/functions/function-configuration) and [authorization-header](https://supabase.com/docs/guides/functions/auth-headers) model.

The server uses `SUPABASE_URL` and the hosted `SUPABASE_SECRET_KEYS` default secret, falling back to `SUPABASE_SERVICE_ROLE_KEY` for compatibility. These values stay in the function environment. The native app and static bridge receive no Supabase service credential, database password or publishable key. The modern secret travels to PostgREST as `apikey`; the legacy service-role JWT also uses `Authorization`. Request bodies, signatures, bearer tokens and database errors are not logged by this handler.

Private tables are isolated in `dacha_cloud`, use forced RLS, and grant access only to `service_role`. Public RPCs are `SECURITY INVOKER`, have empty search paths, and revoke execution from `PUBLIC`, `anon` and `authenticated`. See the exact [database contract](DB_CONTRACT.md).

## HTTP surface

Append `/api/mobile/v1` to the function base URL.

| Method and path | Purpose |
| --- | --- |
| `GET /config` | Public flags and privacy/support URLs; Meteor/cloud enabled, Apple disabled |
| `POST /auth/meteor/challenge` | JSON `{code_challenge}`; returns server nonce and fixed cloud statement |
| `POST /auth/meteor/verify` | JSON `{challenge_id,account_id,public_key,signature,code_verifier}`; returns `{access_token,user_id,kind:"verified-cloud-wallet"}` |
| `GET /library` | Authenticated snapshot with server version |
| `PUT /library` | Authenticated compare-and-swap save; returns incremented version |
| `POST /auth/logout` | Revokes the current session; returns 204 |
| `DELETE /account` | Deletes profile/library and all sessions; returns 204 |

Private routes require `Authorization: Bearer <Dacha session>`. Unauthorized, invalid, conflicting and oversized requests receive appropriate 4xx responses. Network/backend failures produce a generic 503. The API accepts a browser origin only from `https://whendacha.github.io`; native requests without an `Origin` header use the same authentication rules.

Both auth routes consume a shared 120-calls-per-minute window. Requests and snapshots are bounded to 1 MiB; auth bodies to 4 KiB. The handler validates nested tracks and HTTPS media URLs, with limits of 2,000 favorites, 100 playlists, 2,000 tracks per playlist, 10,000 playlist entries total and 1,000 hidden author IDs. It deduplicates tracks and filters hidden authors before storage. Limits are enforced server-side even when a client is modified.

## Deploy

Use Supabase CLI 2.118.0 or a compatible version and authenticate with the deployment account outside source files. From the repository root, inspect the migration plan before applying pending migrations:

```sh
supabase --version
supabase db push --help
supabase functions deploy --help
supabase link --project-ref clxaqzlecqiypyiwgkxd
supabase db push --linked --dry-run
supabase db push --linked
supabase functions deploy dacha-cloud --project-ref clxaqzlecqiypyiwgkxd --use-api
```

The repository configuration supplies the custom-auth setting. Do not use `--prune` or apply unrelated migrations when updating this function. If the database migration was applied through the management tool, check its remote history before attempting a CLI push; do not run the same `CREATE SCHEMA` migration twice. Keep `dacha_cloud` out of Data API exposed schemas. The service-only public RPCs are the database entry points.

For a different deployment, update `CLOUD_API_BASE_URL` in the iOS configuration. Changing the bridge origin also requires matching changes to the handler's allowed origin, the protocol recipient, the native challenge expectations and the published bridge's allowed path. The current bridge is built and published separately from [mobile-bridge](../mobile-bridge/README.md).

## Test

From the repository root, using Node.js 22+ and Swift/Xcode:

```sh
node --test supabase/functions/dacha-cloud/crypto.test.mjs supabase/functions/dacha-cloud/handler.test.mjs
swift test --package-path ios/Packages/NearFMCore
cd mobile-bridge
pnpm install --frozen-lockfile
pnpm test
```

The Edge suite passed 10 tests, the bridge suite passed 8, and the combined Swift core suite passed 31 at the build 3 checkpoint. For DB tests, apply the migration to a disposable local PostgreSQL database, then follow [DB_CONTRACT.md](DB_CONTRACT.md#local-verification). Its 11 tests passed with `service_role NOBYPASSRLS`, including concurrent redemption, CAS and observed lock-wait deletion/logout races. They intentionally refuse remote databases.

Nine deployed HTTPS checks also passed using four temporary sessions for two isolated test accounts: cross-session libraries, edits/deletions, hidden authors, CAS conflicts, isolation and session/account revocation. The test data was removed and absence of remaining test accounts/sessions confirmed. Real challenge creation and invalid-PKCE rejection passed; security advisors reported zero security lints. These checks did not add a bypass route and did not complete a real wallet approval.

A public availability probe needs no credential:

```sh
curl --fail --silent --show-error \
  https://clxaqzlecqiypyiwgkxd.supabase.co/functions/v1/dacha-cloud/api/mobile/v1/config
```

This proves only reachability. Generated signature fixtures and controlled database/RPC tests do not establish a completed Meteor approval, device-to-device synchronization, or account deletion through the shipped app. Complete those checks using a real test wallet before claiming end-to-end success. Never paste a wallet seed or service credential into the browser bridge, app configuration or committed test files.
