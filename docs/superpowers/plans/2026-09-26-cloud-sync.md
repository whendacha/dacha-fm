# Cloud Library Implementation Plan

> For agentic workers: use subagent-driven-development for the independent native, identity and database tasks. Root owns the Edge Function, deployment and release.

**Goal:** Synchronize a verified Meteor account's favorites and playlists across iPhones and deliver build 3 to the existing TestFlight group.

**Architecture:** An isolated Supabase Edge Function authenticates wallet proofs and uses service-only transactional PostgreSQL RPCs. SwiftUI retains public music streaming and adds an independent cloud endpoint. Static Meteor signing supports both existing local and new cloud messages.

**Tech Stack:** Swift/CryptoKit, dependency-free JavaScript/WebCrypto, Supabase Edge/PostgreSQL, existing bundled Meteor SDK.

## Global constraints

- Dacha FM branding, iOS 17+, existing bundle ID and TestFlight group.
- No payment, transaction permission, private key, audio upload or new paid subscription.
- Never send cloud credentials to the public music service.
- Preserve local data and reject stale asynchronous results after account changes.

## 1. Database transactions

- [x] Create migration using `supabase migration new dacha_cloud_library`.
- [x] Add private accounts/libraries/sessions/challenges and service-only `dacha_cloud_*` RPCs.
- [x] Verify role grants, RLS, atomic challenge consumption, CAS, isolation and deletion with SQL tests and advisors.

## 2. Edge authentication and library routes

- [x] Write Node tests for NEP-413 cloud scope, PKCE, invalid requests and isolated API requests; run to observe missing implementation.
- [x] Implement `POST /api/mobile/v1/auth/meteor/challenge` with `{code_challenge}` and response `{id,message,nonce,recipient,expires_at}`.
- [x] Implement `POST /api/mobile/v1/auth/meteor/verify` with `{challenge_id,account_id,public_key,signature,code_verifier}` and response `{access_token,user_id,kind:"verified-cloud-wallet"}`.
- [x] Implement config, versioned library GET/PUT, logout and account deletion using hashed tokens and bounded JSON.
- [x] Run `node --test supabase/functions/dacha-cloud/*.test.mjs`, deploy, then verify real HTTPS and two disposable accounts/sessions with concurrent writes.

## 3. Native and bridge integration

- [x] Add `AuthenticationService.signInWithMeteorCloud(api:bridgeURL:)` and fixed cloud-signature scope tests.
- [x] Preserve build 2 local bridge flow while explaining the cloud scope for build 3.
- [x] Add `CloudAPIBaseURL` independently from the catalog. Serialize sync, persist pending edits and offer explicit conflicts.
- [x] Test migration, offline/restart, concurrent edits, stale responses, account switch and foreground refresh.

## 4. Delivery

- [x] Update privacy/support and release instructions to describe cloud data and deletion.
- [x] Run core, bridge, Edge, live service and iOS UI checks; verify archive source hashes and compiled cloud URL.
- [x] Publish the cloud-aware bridge, archive and upload `1.0.0 (3)`; Apple accepted the package at `2026-09-26T07:34:11Z`.
- [x] Publish the final source/documentation updates.
- [x] Verify Apple's completed processing and assign build 3 to the existing internal TestFlight group with one invited tester; save Russian testing instructions.
- [x] Record the evidence and clearly distinguish tested cloud operations from real-wallet approval.

**Delivery checkpoint:** Source, deployed cloud and simulator UI checks are verified. Build 3 archive/export/upload succeeded; Apple accepted `1.0.0 (3)` at **10:34:11 MSK (07:34:11 UTC) on 26 September 2026**. Apple processing is complete, the build is assigned to the existing internal TestFlight group with one invited tester, and Russian testing instructions are saved. Real wallet approval and signed return on a physical iPhone remain unverified; no App Review submission or approval is claimed.
