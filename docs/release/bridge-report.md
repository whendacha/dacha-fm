# Meteor bridge modes — 26 September 2026

## Build 2 static local-identity bridge

The current public-catalog build uses `mobile-bridge/` to generate static files under `docs/mobile/auth/`. The configured location is `https://whendacha.github.io/dacha-fm/mobile/auth/`. This bridge needs no Dacha API or database. Its job is to return a signed identity proof for a separate on-device wallet library; it cannot create a cloud account or bearer session.

The native app creates a random 32-byte nonce and state and keeps the exact expected statement, recipient and creation time. The page accepts only its fixed Dacha FM statement, matching HTTPS hostname, canonical nonce/state and known nonduplicated input fields. It removes the challenge from the displayed browser URL after parsing. After SDK preparation, a second explicit tap calls only `signMessage` before any asynchronous wait. No wallet `signIn`, contract permission or transfer is requested.

The callback destination is fixed to `dachafm://auth/callback`. The URL fragment contains only mode, original state, account ID, public key and signature. Cancellation invalidates pending continuations. Native code—not the page's success text—checks the Ed25519 signature over the original NEP-413 payload, callback/state/expiry and current mainnet FullAccess-key ownership. RPC redirects and error responses fail verification. Only then is the account ID accepted into local Keychain state.

Pinned wallet packages are bundled at build time; no unpinned runtime CDN script is used. Protocol tests cover canonical inputs, duplicate/missing/unknown fields, fixed-message/recipient constraints, bounded callback fields and cancellation. See [mobile-bridge/README.md](../../mobile-bridge/README.md) for the build/test commands and deployment configuration. Native core validation passed five wallet tests as part of the 19-test suite on 26 September 2026 at 07:46 MSK.

Deployment was verified by `python3 ios/scripts/preflight_public_release.py --json`: the bridge page/assets and privacy/support pages returned HTTP 200, and served `bridge.js` matched the generated local file exactly, SHA-256 `9a3a110692b88cda42f1c378d9003260efd07f90de9814e7d0ca81b8dee9a2fa`. The bridge protocol suite passed **seven tests, zero failures**.

The build 2 iOS simulator suite passed all three UI tests at **07:48:48 MSK**, with results at `/tmp/DachaFM-Build2-UITests.xcresult`. Its actual `ASWebAuthenticationSession` opened the deployed bridge, exercised Prepare/Confirm, and reached `wallet.meteorwallet.app` with the clean-wallet “Get Started” screen. This verifies the native browser and popup entry path. It does **not** establish approval of a real signature, RPC verification of an actual wallet, or the signed return on a physical iPhone. No real wallet signature or approval is claimed in this report.

## Optional server/PKCE bridge

The separate Next.js route `web/src/app/mobile/auth/` remains for the owned-backend mode. It accepts a PKCE challenge and state, obtains the server's NEP-413 challenge, sends the returned wallet proof to the API, then returns a one-time code and original state. The native app exchanges the code with its private verifier. This server bridge is not interchangeable with the static local-identity page.

Its earlier implementation checks passed three protocol tests, TypeScript and a Next.js production build. It requires deployed `MOBILE_API_URL`, `MOBILE_NEAR_NETWORK`, and corresponding mobile API authentication/RPC configuration. Those historical implementation checks do not establish a deployed service or completed real-provider flow.

Both bridges deliberately avoid `signIn`: the pinned Meteor adapter maps that operation to `requestSignIn` and may request `ALL_METHODS` when methods are omitted. The listener needs identity verification only, so it uses direct message signing with explicit user activation.
