# Build 5 cloud verification: hidden songs

The backward-compatible cloud update was deployed to project `clxaqzlecqiypyiwgkxd` on **26 September 2026 at 10:27 UTC**. Local source commit: `ed945d8`. This records backend verification only; it does not establish an Apple upload, App Review submission, real Meteor approval, or physical-device synchronization.

## Deployed versions

| Component | Verified deployment |
| --- | --- |
| Local migration | `supabase/migrations/20260926102151_dacha_cloud_hidden_tracks.sql` |
| Remote migration | `20260926102744`, named `dacha_cloud_hidden_tracks` |
| Migration SHA-256 | `8b6c95f10c8a0ce2f8ff840207823e18bcfa400782864317ad8fb16ee889a3ac` |
| Edge function | `dacha-cloud`, version **2**, `ACTIVE` |
| Edge bundle SHA-256 | `f59164462a3cb197504b07b6fdfbb9db8481090560ccccc48c3113592a1937e7` |

Remote migration history was inspected first. Only the new additive migration was applied, using `supabase_apply_migration`, before `supabase_deploy_edge_function`. The management tool assigned the remote timestamp above; do not replay the migration under the local filename. All three retrieved deployed source files matched the local files exactly. The entry point, authentication handler, signing statement, recipient and body limit were unchanged. `verify_jwt=false` remains scoped to this function's existing independently authenticated opaque sessions.

## Evidence

- **Local:** 15/15 Edge tests and 15/15 disposable PostgreSQL 18 tests passed with `service_role NOBYPASSRLS`. New regressions were observed failing before implementation. The database tests include an actual account-lock wait, stale CAS, legacy snapshot/default handling, schema/count limits and the merged snapshot size limit.
- **Live:** 14 checks passed at `2026-09-26T10:29:27Z`, using 25 asserted HTTPS requests and four short-lived fixture sessions across two isolated fixture accounts. Hidden tracks retained full metadata, were deduplicated and appeared in a second session. A legacy PUT omitted `hidden_tracks` without erasing it; explicit `[]` cleared it while preserving favorites and playlist tracks. Malformed data returned 400, stale writes returned 409 without mutation, another account stayed isolated, and the existing artist-block behavior was unchanged.
- **Revocation and cleanup:** logout revoked only its session; account deletion revoked both sessions. Both fixture accounts were deleted through the API. An exact-fixture database query confirmed **0 accounts, 0 libraries and 0 sessions** remaining. The temporary local bearer-token file was removed. No real user data was used or changed by these checks.
- **Security:** five private tables still enforce forced RLS; all eight public Dacha RPCs remain `SECURITY INVOKER` with empty search paths; none can be called by `anon` or `authenticated`. Post-deployment Supabase security advisors returned **0 lints**. No authentication bypass or new route was added.

The redacted local receipt is `/tmp/dacha-build5-cloud-receipt.json`; it contains timestamps, hashes and named outcomes, with no bearer tokens, wallet account IDs or service credentials. Fixture sessions were seeded through authorized database administration, so these checks do not replace a real wallet approval or two-device acceptance test.

Contract and limits: [database contract](../../supabase/DB_CONTRACT.md). Deployment configuration and commands: [Supabase README](../../supabase/README.md).
