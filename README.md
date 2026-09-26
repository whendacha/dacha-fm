# Dacha FM

A native iPhone music listener with author-only playback, playlists, favorites, guest listening, and optional Meteor Wallet identity verification.

- [iOS build and configuration](ios/README.md)
- [Mobile API and moderation operations](docs/mobile-api.md)
- [Release status and verification](docs/release/status.md)

Build 2 connects directly to the public HTTPS music catalog and streams audio from the URLs returned by that catalog. It does not require a Dacha FM backend for listening. Favorites, playlists and blocked authors stay on the iPhone, with separate guest and wallet libraries. Meteor signs a one-time identity message; the native app verifies its signature and mainnet account-key ownership before opening that wallet's local library. This mode has no cloud synchronization or Sign in with Apple.

The iPhone application is in `ios/`. The static Meteor bridge is built from `mobile-bridge/` into `docs/mobile/auth/` and deployed on GitHub Pages. Native signature tests, all three simulator UI tests, live audio playback and the bridge-to-Meteor entry flow have passed; actual Meteor approval and the signed return on a physical iPhone still need verification. Apple received **1.0.0 (2)** at **07:50:32 MSK on 26 September 2026** and completed processing. The build is available to the existing internal TestFlight group and its invited tester. See the release status for the receipt and test evidence.

An optional owned-service implementation remains in `server/src/mobile/` and `web/src/app/mobile/auth/`. It provides separate Apple/Meteor server accounts, cloud libraries and an operator-approved catalog when configured and deployed; it is not the default build 2 mode.

## Source provenance

This repository was forked from [fastnear/near-fm](https://github.com/fastnear/near-fm) at commit `7aa4bad`. Dacha FM is the product name for this fork; upstream product names, protocol names and source attributions are retained only where they identify their original source or technology. No affiliation with the upstream brand is claimed. The inspected upstream revision has no explicit license; distribution rights for the source and music remain a release requirement.

The original web application and contract remain in the repository as upstream source. Public streaming uses existing source URLs; this fork does not copy or rehost the audio catalog. Technical accessibility and AI generation do not establish a license grant, and no content-rights declaration or App Review approval is asserted here.
