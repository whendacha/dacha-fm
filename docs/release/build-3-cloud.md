# Dacha FM 1.0.0 (3): cloud library

Build 3 adds optional synchronization of favorites, playlists and hidden authors through the same verified Meteor account on each device. Guest listening and the public streaming catalog remain available without an account. Music requests continue to use the separate public adapter; cloud credentials and library contents are not sent to the catalog source.

The configured cloud base is `https://clxaqzlecqiypyiwgkxd.supabase.co/functions/v1/dacha-cloud`. The Dacha database migration has been applied to that project and Edge function version 1 has been deployed. This records deployment of the service, not successful real-wallet sign-in or Apple delivery of build 3.

## Listener behavior

- Sign in with the same Meteor mainnet account on both devices. The cloud signature statement explicitly mentions synchronization. Existing build 2 local profiles require this new confirmation to enable cloud synchronization.
- Favorites, playlists and hidden authors save on the device before upload. Pending changes persist across relaunch; retry occurs on another edit, app activation, or the Settings sync control.
- When devices have different edits, choose the complete cloud or iPhone version in Settings. Server version checking rejects stale writes rather than silently replacing newer data.
- Expired sessions preserve local edits and ask for another wallet confirmation. Logout revokes the current session; account deletion requires the cloud server to confirm deletion before clearing the current device's profile.
- Cloud account deletion removes its library and revokes every server session. The wallet, guest library and other devices' cached files are not deleted. Another verified sign-in may create an empty cloud profile.

## Verification checkpoint

| Check | Current evidence |
| --- | --- |
| Swift core | 31/31 passed in the combined build 3 suite |
| PostgreSQL | 11/11 passed locally with `service_role NOBYPASSRLS`, including actual lock-wait races around deletion/logout and pending saves |
| Edge protocol and handler | 10/10 passed with generated cryptographic fixtures and controlled database/RPC dependencies |
| Static bridge | 8/8 protocol tests passed, including separate fixed local/cloud statements |
| Deployed HTTPS API | Nine checks passed with four temporary sessions across two isolated test accounts; no authentication-bypass route was added |
| Live challenge rejection | Real challenge creation and invalid-PKCE rejection passed |
| Supabase security advisors | Zero security lints reported after deployment |
| Build 3 simulator UI | 3/3 passed: guest library and author queue, live audio at 0:05, and cloud Meteor flow reaching the real wallet screen |
| Real Meteor approval and signed return | Not verified on a physical iPhone; no completed live wallet login claimed |
| Apple delivery | Build 3 Release archive passed; export is blocked by Xcode reporting No Accounts. Build 3 has not been uploaded; build 2 remains the last confirmed TestFlight delivery |

The DB suite checks service-only permissions, forced RLS, challenge expiry and single use, account isolation, invalid snapshots, compare-and-swap conflicts, deletion/logout races, session expiry, rate limits and cleanup. Live HTTPS checks covered favorites/playlists across sessions, rename/removal/deletion, hidden authors, version-conflict 409 responses, account isolation, current-session logout and all-session revocation after account deletion. All temporary test account/session rows were confirmed removed. Those sessions were seeded specifically for verification; neither they nor generated signature fixtures replace a real mainnet wallet confirmation. No music download or wallet transaction is needed for these automated checks.

## Remaining acceptance checks

Complete a real cloud sign-in, make a favorite and playlist on one device, and verify them after signing in with the same wallet on another. Edit while offline, relaunch, then retry synchronization. Make conflicting edits on both devices and verify each explicit version choice. Check logout, expired-session reauthentication and deletion from one device with the other still signed in. Confirm that guest data and another wallet's library remain separate.

Re-run the deployed bridge checksum and public endpoint checks, then record the build 3 simulator/device results and Apple's actual upload/processing receipt in [release status](status.md). This note does not claim App Review submission or approval.

Implementation and commands: [iOS README](../../ios/README.md), [Supabase README](../../supabase/README.md), [database contract](../../supabase/DB_CONTRACT.md), [bridge README](../../mobile-bridge/README.md).
