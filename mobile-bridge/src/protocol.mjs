export const IDENTITY_MESSAGE = "Dacha FM sign-in\nVerify your Meteor account for the library on this device. No transaction or wallet permission is requested.";
export const CALLBACK = "dachafm://auth/callback";
const tokenPattern = /^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/;
const accountPattern = /^(([a-z0-9]+[-_])*[a-z0-9]+\.)*([a-z0-9]+[-_])*[a-z0-9]+$/;
const publicKeyPattern = /^ed25519:[1-9A-HJ-NP-Za-km-z]{32,44}$/;
const signaturePattern = /^[A-Za-z0-9+/]{85}[AQgw]==$/;
const queryKeys = ["mode", "state", "nonce", "message", "recipient"];

export function isToken(value) {
  return typeof value === "string" && tokenPattern.test(value);
}

// This page signs only the one fixed identity statement understood by the app.
// It is never a general-purpose message signing or redirect endpoint.
export function parseInput(query, location) {
  const localPreview = ["localhost", "127.0.0.1"].includes(location.hostname);
  if (location.protocol !== "https:" && !(localPreview && location.protocol === "http:")) return null;
  const expectedPath = localPreview ? "/mobile/auth" : "/dacha-fm/mobile/auth";
  if (![expectedPath, expectedPath + "/"].includes(location.pathname)) return null;
  if (location.hash) return null;
  if ([...query.keys()].some((key) => !queryKeys.includes(key))) return null;
  if (queryKeys.some((key) => query.getAll(key).length !== 1)) return null;
  const values = Object.fromEntries(query);
  if (values.mode !== "identity" || !isToken(values.state) || !isToken(values.nonce)) return null;
  if (values.message !== IDENTITY_MESSAGE || values.recipient !== location.hostname) return null;
  // Production links never contain a non-default port. A local preview is the
  // only exception and cannot be used by the production app.
  if (location.port && !localPreview) return null;
  return { state: values.state, nonce: values.nonce, message: values.message, recipient: values.recipient };
}

export function nonceBytes(nonce) {
  if (!isToken(nonce)) throw new Error("The sign-in nonce is invalid.");
  const decoded = atob(nonce.replace(/-/g, "+").replace(/_/g, "/") + "=");
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

export function callbackURL(signed, state) {
  if (!isToken(state) || !signed || typeof signed !== "object") return null;
  const { accountId, publicKey, signature } = signed;
  if (typeof accountId !== "string" || accountId.length < 2 || accountId.length > 64 || !accountPattern.test(accountId)) return null;
  if (typeof publicKey !== "string" || !publicKeyPattern.test(publicKey)) return null;
  if (typeof signature !== "string" || !signaturePattern.test(signature)) return null;
  const parameters = new URLSearchParams({ mode: "identity", state, account_id: accountId, public_key: publicKey, signature });
  return `${CALLBACK}#${parameters}`;
}

// A cancellation or a new attempt invalidates every asynchronous continuation.
export function attemptGate() {
  let generation = 0;
  return { begin: () => ++generation, cancel: () => ++generation, current: (value) => value === generation };
}
