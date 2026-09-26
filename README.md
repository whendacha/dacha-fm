# Dacha FM

A native iPhone music listener with author-only playback, playlists, favorites, guest listening, and optional Meteor Wallet or Apple sign-in.

- [iOS build and configuration](ios/README.md)
- [Mobile API and moderation operations](docs/mobile-api.md)
- [Release status and verification](docs/release/status.md)

The application is in `ios/`, its isolated Rust API in `server/src/mobile/`, and its web authentication bridge in `web/src/app/mobile/auth/`. This is a development implementation: production services and live identity flows must be configured and verified before App Review.

## Source provenance

This repository was forked from [fastnear/near-fm](https://github.com/fastnear/near-fm) at commit `7aa4bad`. Dacha FM is the product name for this fork; upstream product names, protocol names and source attributions are retained only where they identify their original source or technology. No affiliation with the upstream brand is claimed. The inspected upstream revision has no explicit license; distribution rights for the source and music remain a release requirement.

The original web application and contract remain in the repository as upstream source. Deploy the dedicated mobile API using `MOBILE_ONLY=true` and the isolated `/mobile/auth` bridge for this listener, with owned service origins and approved content.
