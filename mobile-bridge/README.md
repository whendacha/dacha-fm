# Dacha FM mobile identity bridge

Static Meteor identity page, published from `docs/mobile/auth/` on GitHub Pages. The production URL is `https://whendacha.github.io/dacha-fm/mobile/auth/`. It has no backend, analytics, wallet transaction, or contract-permission flow. The iOS app validates the signed proof and on-chain account key before accepting the identity. Listener libraries remain on the device in this mode.

## Build and test

Use Node.js 22 or newer and the pinned pnpm version from `package.json`.

```sh
cd mobile-bridge
pnpm install --frozen-lockfile
pnpm test
pnpm build
pnpm preview
```

The generated assets are committed under `docs/mobile/auth/`. `pnpm build` replaces only those assets and the Pages `.nojekyll` marker. Dependencies are pinned in `pnpm-lock.yaml`; do not load a wallet SDK from an unpinned CDN.

Open `http://localhost:8080/mobile/auth/` to inspect the invalid-link state. For a valid local preparation screen, use a query with `mode=identity`, a canonical 32-byte base64url `nonce` and `state`, `recipient=localhost`, and `message` equal to `IDENTITY_MESSAGE` in `src/protocol.mjs`. Production links require HTTPS, the exact hostname recipient, and no custom port. A test wallet is needed to exercise real Meteor approval; structural protocol tests do not establish a successful live sign-in.

The page prepares the wallet on the first tap and calls only `signMessage` on a second explicit tap, preserving popup activation. It never invokes `signIn`. Cancelling invalidates pending asynchronous work. Returned proof fields go in the fragment of the fixed `dachafm://auth/callback` URL, never to a query-controlled callback. The native app binds the signature to its stored statement, nonce, state, recipient, and expiration, verifies the signature, and checks a mainnet FullAccess key. The page cannot establish an authenticated session by itself.

The wallet packages retain their own licenses and protocol names as dependency attribution; Dacha FM is the product name.
