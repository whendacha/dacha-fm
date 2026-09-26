# Mobile backend implementation report

Implemented isolated `/api/mobile/v1` routes and migration `043_mobile_listener.sql`; the upstream entrypoint adds the router and an explicit `MOBILE_ONLY=true` startup branch. Added one dependency, AES-GCM, for Apple refresh-token encryption. Listener accounts never invoke custody wallet provisioning, public votes, Premium playlists, credits or transfers.

Security/business behavior: explicit mobile content approval defaults to empty catalog; hidden/deleted/banned/technically unvalidated songs excluded; stable numeric artist IDs; private canonicalized versioned libraries; owner scoping; persistent rate-limited guest reports; hashed 30-day sessions; one-time NEP-413 and PKCE flow; Apple JWKS/nonce/code exchange and revoke-before-delete; encrypted Apple refresh tokens. All mobile responses use `Cache-Control: no-store`.

Validation performed on macOS with installed stable Rust toolchain:

- Initial pre-implementation test invocation was blocked because Cargo was absent, so no successful pre-implementation red test run is claimed.
- Full server compiled successfully with `cargo test --manifest-path server/Cargo.toml mobile::`.
- Unit tests passed for PKCE RFC vector, pagination, library validation, expiry, independently Borsh-serialized NEP-413 recipient/callback binding and authenticated encryption.
- Initialized disposable PostgreSQL 18.4 on localhost, applied all migrations through the real server startup, and reran with `TEST_DATABASE_URL`: **10/10 tests passed**, including all three database tests. The first DB fixture failed on upstream required `users.slug`; corrected the fixture and reran successfully.
- Live local HTTP smoke assertions passed: default-deny moderation, artist/track queries, pagination validation, missing auth, canonical track metadata, version 409, owner isolation, blocked-author filtering, persisted anonymous reports, disabled provider 503, account deletion and logout revocation.
- A second HTTP smoke test rejected a wrong PKCE verifier and raced two exchanges of the same code: exactly one returned 200 and the other 401; subsequent replay returned 401.
- These tests used explicitly seeded disposable listener sessions/codes, not fake Apple or Meteor provider success. A locally generated one-second sine tone exists only as a development asset; the metadata URL is example.invalid because no owned HTTPS media host was configured. No live audio playback is claimed.
- Existing upstream warnings remain (unused imports/variables/functions); sqlx-postgres 0.7.4 emits a future-incompatibility warning.

The clean upstream schema exposed an existing unrelated background feed error: missing `songs.top_score` column. Added the requested `MOBILE_ONLY=true` deployment mode, which skips all upstream feed/reputation/validation/credit jobs and serves only mobile routes. Rebuilt and reran both HTTP suites successfully in that mode; wallet/admin/legacy-auth routes return 404, an oversized body returns 413, and no background feed error occurs. Default upstream mode remains unchanged. The existing upstream schema issue still affects upstream deployments, not the isolated listener process.

Production deployment and live provider identity flows have **not** been executed. Required external prerequisites: owned HTTPS API/bridge, real Apple client configuration/rotating secret and encryption key, Meteor full-access signing and actual iPhone browser return flow, trusted NEAR RPC, content/brand/source distribution rights, an operator-staffed moderation workflow, real privacy/support URLs and App Review access. Account linking and token refresh are not claimed; users reauthenticate after session expiry. Database schema supports separate Apple or Meteor identities without merging by email.

See [mobile API operations](../mobile-api.md) for configuration and approval/review SQL. NEP-413 uses [the official specification](https://github.com/near/NEPs/blob/master/neps/nep-0413.md); Apple revocation uses [Apple's token endpoint](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens).
