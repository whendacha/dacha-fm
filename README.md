# Dacha FM

A native iPhone music listener with artist-only playback, playlists, favorites, reversible song hiding, guest listening, and optional Meteor-authenticated cloud synchronization.

- [iOS build and configuration](ios/README.md)
- [Release status and verification](docs/release/status.md)
- [Cloud service and tests](supabase/README.md)
- [Optional mobile API and moderation operations](docs/mobile-api.md)

Dacha FM streams from the public HTTPS catalog's audio URLs. Guest libraries stay on the iPhone; optional Meteor sign-in opens a separate private cloud library. Build 5 adds **Hide song** and **Settings → Hidden songs → Unhide**. Hiding preserves favorite and playlist membership for restoration and leaves other songs by the artist available. The cloud service preserves hidden songs when older clients save their libraries.

The native application is in `ios/`. The static Meteor bridge is built from `mobile-bridge/` into `docs/mobile/auth/` and deployed on GitHub Pages; the private cloud service is in `supabase/`. Fresh build 5 validation includes 48 core tests, seven simulator UI tests, 15 Edge tests, 15 PostgreSQL tests and 14 deployed cloud checks. Live audio and the real Meteor entry screen were verified; actual wallet approval and two-device synchronization remain physical-device acceptance checks. See the release status for confirmed Apple delivery receipts. No public App Review submission or approval is claimed.

An optional owned-service implementation remains in `server/src/mobile/` and `web/src/app/mobile/auth/`. It provides separate Apple/Meteor server accounts and an operator-approved catalog when configured and deployed; it is separate from the default public-catalog/cloud-library mode.

## Source provenance

This repository was forked from [fastnear/near-fm](https://github.com/fastnear/near-fm) at commit `7aa4bad`. Dacha FM is the product name for this fork; upstream product names, protocol names and source attributions are retained only where they identify their original source or technology. No affiliation with the upstream brand is claimed. The inspected upstream revision has no explicit license; distribution rights for the source and music remain a release requirement.

The original web application and contract remain in the repository as upstream source. Public streaming uses existing source URLs; this fork does not copy or rehost the audio catalog. Technical accessibility and AI generation do not establish a license grant, and no content-rights declaration or App Review approval is asserted here.
