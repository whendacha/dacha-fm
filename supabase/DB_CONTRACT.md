# Dacha FM cloud database contract

The migration creates only `dacha_cloud` and eight specifically named `public.dacha_cloud_*` RPCs. It does not expose private tables or change unrelated project privileges. All functions use `SECURITY INVOKER` with an empty `search_path`; `PUBLIC`, `anon`, and `authenticated` cannot execute them. The Edge API uses its server-only `service_role` credential. Private tables use forced RLS and an explicit policy for that role.

The API must verify NEP-413 signatures, PKCE, and account FullAccess ownership before calling `finish_auth`. It must validate deep library content and HTTPS audio/image URLs before `library_put`. No wallet private key, seed phrase, plaintext session token, Apple identifier, or user Supabase credential is stored here. Session tokens enter SQL only as lowercase 64-character SHA256 hex hashes. Account identity is the validated, case-sensitive lowercase wallet account string.

| RPC | Arguments | JSON result |
| --- | --- | --- |
| `dacha_cloud_auth_rate` | none | `{ "allowed": true, "retry_after_seconds": 0 }`; denial has `allowed:false` and 1–60 seconds |
| `dacha_cloud_create_challenge` | `p_id uuid`, `p_nonce text`, `p_code_challenge text` | `{ "id": "uuid", "nonce": "base64url", "code_challenge": "base64url", "expires_at": "timestamp" }` |
| `dacha_cloud_get_challenge` | `p_id uuid` | Same object; missing/expired challenges raise `PT401` |
| `dacha_cloud_finish_auth` | `p_id uuid`, `p_account_id text`, `p_token_hash text` | `{ "account_id": "listener.near", "expires_at": "timestamp" }` |
| `dacha_cloud_library_get` | `p_token_hash text` | Direct library snapshot, including authoritative `version` |
| `dacha_cloud_library_put` | `p_token_hash text`, `p_snapshot jsonb` | Direct saved snapshot, with `version` incremented by one |
| `dacha_cloud_logout` | `p_token_hash text` | `{ "ok": true }` |
| `dacha_cloud_delete_account` | `p_token_hash text` | `{ "ok": true }` |

Both nonce and PKCE challenge are canonical 43-character base64url encodings of 32 bytes. The Edge API supplies all randomness. Challenge lifetime is five minutes. Successful redemption atomically consumes the challenge, preserves any existing library, and creates a session valid for 30 days. Only one concurrent redemption can succeed.

A returned snapshot has `version`, `favorites`, `playlists`, `blocked_artist_ids`, and `hidden_tracks`. GET supplies `hidden_tracks: []` for older stored snapshots. Version is a nonnegative integer; the remaining values are arrays. PUT requires the four original fields and accepts optional `hidden_tracks` for backward compatibility. SQL rejects other top-level fields and snapshots exceeding 1 MiB of JSON text. The API enforces deeper field/count/URL limits.

`hidden_tracks` contains at most 2,000 full track objects, validated like favorites and deduplicated by track ID by the Edge API. Hiding a song preserves its favorite and playlist memberships so unhiding is reversible; hidden songs are not removed from those arrays on the server. Existing blocked-artist filtering of favorites and playlist tracks is unchanged. Hidden-song metadata itself is retained even when its author is blocked.

New clients send `hidden_tracks`, including `[]` to explicitly clear it. A legacy client's omission preserves the current stored hidden tracks. SQL merges that field only while holding the account lock, after reading the stored version and checking compare-and-swap. Both the input and merged snapshot must fit the 1 MiB limit. A conflict or oversized merge fails atomically instead of overwriting newer preferences. The additive migration keeps older stored snapshots valid without rewriting them; newly created libraries include the empty field by default.

Error SQLSTATEs are `PT401` for invalid, expired, revoked, or missing authorization; `PT409` for version/replay-identifier conflicts; and `PT400` for invalid input shape. The Edge API should map these to their matching HTTP status. Logout and account deletion require a still-valid token; after a successful deletion, retries return `PT401`. The client can clear local credentials for either success or `401`.

Session operations share one per-account advisory lock and account row lock, then recheck the token under that lock. A pending save cannot recreate an account after logout/deletion, and a save that completes before deletion is removed by the same cascading delete. Account deletion removes its library and every session. A later fully verified wallet sign-in may create a new empty profile; no account tombstone or old library is retained. The challenge is not bound to an account until proof verification.

The rate RPC uses one global window row: 120 allowed calls per 60-second window. Call it separately before challenge creation/redemption, so denied requests are committed as denials rather than rolled back with another RPC. It cleans up at most 500 expired challenges and 500 expired sessions per call. The singleton counter never grows with request volume. This is shared backpressure for the free-tier service, not a substitute for per-client traffic controls.

## Local verification

Use a disposable local PostgreSQL database named `dacha_cloud_test` (or `dacha_cloud_test_<suffix>`). Create `anon`, `authenticated`, and `service_role` roles and apply both migrations in filename order as its database owner. For stronger policy verification, create the local `service_role` with `NOBYPASSRLS`.

```sh
cd supabase/tests
pnpm install --frozen-lockfile
DACHA_CLOUD_TEST_URL=postgresql://LOCAL_USER:LOCAL_PASSWORD@127.0.0.1:5432/dacha_cloud_test pnpm test
```

The test runner refuses remote hosts and unrelated database names. Its 15 tests verify forced RLS, RPC/table access denial for client roles, nonce shape, one-time concurrent redemption, private libraries, invalid snapshots, concurrent compare-and-swap, both save/delete orderings, logout/expiry, rate denial/reset, and bounded cleanup. Hidden-song regressions cover legacy reads, explicit clear, retained memberships, cross-session persistence, isolation, stale versions, an observed account-lock wait, schema/count limits, and the merged-size limit. It creates only namespaced fixture accounts and removes them afterward. It intentionally resets the singleton rate row, so run it only against a disposable database.

Migration filenames were generated with Supabase CLI `2.118.0` using `supabase migration new dacha_cloud_library` and `supabase migration new dacha_cloud_hidden_tracks`. Deploy the additive hidden-track migration before the updated Edge function. Reference: [Database functions](https://supabase.com/docs/guides/database/functions), [Data API security](https://supabase.com/docs/guides/api/securing-your-api). The current September 2026 changelog has no breaking change affecting these plain tables/functions; they use no optional extension or legacy cipher.
