# Dacha FM cloud library

The user requests cloud synchronization in addition to the delivered public-catalog listener and has authorized implementation, hosting and TestFlight upload without repeated approval questions.

Use the existing free Supabase project with an isolated `dacha_cloud` schema and a `dacha-cloud` Edge Function. Keep public music requests entirely separate from the owned cloud origin. Alternatives considered: the existing Rust service needs additional container hosting and an owned catalog copy; iCloud would bind libraries to Apple IDs instead of the requested Meteor identity. Neither serves this release as directly.

Cloud login uses a server-created 32-byte nonce, a five-minute challenge and native-only S256 PKCE verifier. The fixed NEP-413 message explicitly authorizes cloud sign-in. The existing static bridge remains compatible with build 2's local identity message. Native and server verify the signature; the server independently checks the mainnet FullAccess key. Consuming the challenge and creating the opaque 30-day session is one database transaction. Only token hashes persist. Cloud user IDs are the verified wallet account string, preserving existing local filenames.

An authenticated library snapshot contains favorites, ordered playlists and blocked author IDs. Version compare-and-swap prevents concurrent overwrites. The native client serializes pull/push work, persists dirty state with the library, retries offline edits and refreshes on foreground. If two devices changed the same base, offer explicit cloud/device choices. Never silently use additive merging that resurrects deleted tracks. Existing wallet data migrates on verified cloud login; guest merging remains explicit.

The cloud service validates bounded metadata and HTTPS URLs; it does not fetch client-supplied URLs or store audio. Publicly exposed database RPC functions are SECURITY INVOKER and executable only by service_role; private tables have RLS and no client grants. Each protected HTTP route checks the opaque session. Logout revokes one session; account deletion removes its library and all sessions.

Verification covers signature scope/nonce/PKCE/replay, account isolation, CAS, logout/deletion, persistence, offline changes and migration. Live cloud tests use isolated disposable fixtures through privileged tools, never an authentication bypass endpoint. A real Meteor approval remains a physical-wallet verification limitation unless the user performs it.
