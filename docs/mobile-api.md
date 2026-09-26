# Mobile listener API

Base `/api/mobile/v1`; same-origin Meteor bridge uses the configured API deployment. JSON fields follow the shared iOS contract. No listener login provisions an upstream user or custody wallet. Apple and Meteor are separate identities; account linking is not implemented and matching emails never links accounts.

All personal endpoints use `Authorization: Bearer <opaque token>`. Tokens contain 256 random bits, only SHA-256 hashes persist, expire in 30 days and are revoked by logout or account deletion. Reauthenticate after expiry. No refresh endpoint is promised. Guest libraries remain local.

| Route | Behavior |
| --- | --- |
| GET `/config` | `meteor_enabled`, `apple_enabled`, optional privacy/support HTTPS URLs |
| GET `/tracks` | `q`, `artist_id`, `page` (1–10000), `limit` (1–100), response `tracks,page,has_more` |
| GET `/artists` | `q,page,limit`, response `artists,page,has_more`; stable artist IDs are decimal upstream `users.id`, not names or account IDs |
| GET `/library` | Canonical current catalog metadata, version, favorites, playlists, blocked artist IDs |
| PUT `/library` | Complete snapshot; version compare-and-swap; 409 requires explicit client fetch/merge; canonicalizes track metadata and removes blocked content |
| POST `/reports` | Optional track/artist and required reason; 201 only after persistent insert; guest supported |
| POST `/auth/meteor/challenge` | S256 PKCE challenge; server nonce/message/recipient; expires in five minutes |
| POST `/auth/meteor/verify` | Stored NEP-413 payload with callback `None`, signature, NEAR full-access key ownership; consumes challenge atomically; returns one-time code |
| POST `/auth/exchange` | Code plus 43–128 character verifier; 60-second code TTL; one-time atomic exchange |
| POST `/auth/apple` | Raw nonce, identity token, authorization code; verifies Apple signature/issuer/audience/expiry/hashed nonce; exchanges code and validates returned token before creating session |
| POST `/auth/logout` | 204; revokes current token |
| DELETE `/account` | Revokes Apple provider refresh token first, then deletes listener account/library/identities/sessions/codes; 204 only after completion |

Tracks: `id,title,artist_id,artist_name,audio_url,artwork_url,duration`. Artists: `id,name,artwork_url,track_count`. Library snapshot: `version,favorites,playlists,blocked_artist_ids`; playlist `id,name,tracks`. All canonical track metadata is derived on server; client metadata cannot substitute a malicious playback URL. Playlists are nested in the owner's snapshot, so IDs never grant access to another owner. Limits: 2000 favorites, 100 playlists, 2000 tracks each, 10000 combined playlist tracks, 1000 blocks, 100 Unicode characters per playlist name, 1 MiB request bodies.

## Configuration

Use `MOBILE_ONLY=true` for the owned listener deployment. This serves only `/api/mobile/v1`, skips the upstream feed/reputation/audio-validation/credit jobs, and applies shared CORS/Trace with a 1 MiB request body limit. All unused upstream wallet/admin/generation endpoints return 404. With the flag absent or `false`, upstream behavior is preserved; other flag values stop startup. Existing shared startup configuration still requires `DATABASE_URL` and `JWT_SECRET` (the latter is unused for mobile session verification).

Integrations fail closed with 503 when required settings are absent. Config booleans mean required settings are present, not that live credentials were tested.

- `MOBILE_AUTH_DOMAIN`: owned HTTPS application origin used in the signed message.
- `MOBILE_NEP413_RECIPIENT`: exact expected recipient, normally the owned domain hostname; must match bridge request returned by server.
- `MOBILE_NEAR_RPC_URL`: trusted HTTPS RPC matching the chosen NEAR network. Ownership requires a full-access Ed25519 key; function-call keys are rejected.
- `MOBILE_APPLE_CLIENT_ID`: native bundle identifier/audience configured with Sign in with Apple; the Dacha FM application uses `com.whendacha.dachafm`.
- `MOBILE_APPLE_CLIENT_SECRET`: valid Apple ES256 client-secret JWT generated using the developer team's private key. Rotate before expiry; never commit it.
- `MOBILE_TOKEN_ENCRYPTION_KEY`: base64url without padding encoding of 32 cryptographically random bytes. Encrypts Apple refresh tokens with AES-256-GCM. Back up securely. Rotation requires explicit decrypt/re-encrypt migration; losing this key prevents token revocation.
- `MOBILE_PRIVACY_URL`, `MOBILE_SUPPORT_URL`: real published HTTPS URLs.

Configure the existing server's `CORS_ORIGINS` for the owned bridge origin. Mobile routes do not rely on upstream JWT middleware or browser cookies. Native raw nonce must be cryptographically random and at least 32 characters; Apple request sends its lowercase hex SHA-256 and API request sends the original raw nonce.

Both Apple JWKS and token/revoke calls use fixed Apple HTTPS endpoints with bounded timeouts. Tokens and authorization codes are never logged by this module. A failed external revocation leaves the local account intact and returns an error; retry deletion. Reports survive deletion with the account reference set NULL to preserve moderation records.

## Moderation and operations

Apply migration `043_mobile_listener.sql`. The mobile catalog starts **empty**. `is_validated` only means audio validation; a separate explicit human approval is mandatory. Visibility additionally requires a non-hidden, non-deleted track, a non-banned artist, and HTTPS audio. Library reads re-check these conditions so removed content is not served through saved metadata. Signed-in catalog queries omit blocked artists; guest blocking is client-side.

After verifying content and distribution rights, an authorized operator can approve a track with a parameterized query:

```sql
INSERT INTO mobile_catalog_approvals(song_id, approved_by)
SELECT id, $2 FROM songs WHERE uuid = $1
ON CONFLICT(song_id) DO UPDATE SET approved_at=now(), approved_by=excluded.approved_by;
```

Remove approval immediately to withdraw a track. Review `SELECT * FROM mobile_reports WHERE resolved_at IS NULL ORDER BY created_at`. Investigate each complaint, hide/remove approval or ban the upstream artist as appropriate, then record `resolved_at`. An operational moderation UI and staffed response policy remain deployment prerequisites; this change supplies persistent storage and documented operator workflow, not a staffed service.

A bounded process-global throttle allows 120 auth operations/minute and 30 reports/minute; client forwarding headers cannot bypass it. Deploy additional trusted edge per-IP rate limits, TLS, database least privilege, backups and connection limits. Multi-instance deployments must apply shared edge limits. The global limit intentionally trades availability for abuse resistance. Restrict direct server ingress to the edge.

Schedule cleanup of expired `mobile_sessions`, `mobile_codes`, and `mobile_challenges`; otherwise expired records accumulate (they cannot authenticate). Reports have a retention policy chosen by the operator; publish that policy. Do not delete provider tokens before revocation.

## Verification and external prerequisites

Run `cargo test --manifest-path server/Cargo.toml mobile::`. Set `TEST_DATABASE_URL` to a migrated, disposable PostgreSQL database to enable database tests; never point tests at production. Database tests roll back their fixtures. Unit tests cover PKCE, pagination, library validation, NEP-413 domain/callback binding, challenge expiry and authenticated token encryption.

Live Apple developer configuration, secret rotation, Apple code/revocation behavior, a real Meteor wallet/physical-iPhone return flow, owned deployment, content rights, operational moderation and review credentials must be verified before release. No production URL or successful provider login is claimed here.
