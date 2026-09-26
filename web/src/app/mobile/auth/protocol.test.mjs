import test from "node:test";
import assert from "node:assert/strict";
import { parseBridgeInput, parseChallenge, callbackURL } from "./protocol.ts";

const token = "a".repeat(43);
const input = () => new URLSearchParams({ code_challenge: token, state: token });

test("accepts only one well-shaped PKCE challenge and state", () => {
  assert.deepEqual(parseBridgeInput(input()), { codeChallenge: token, state: token });
  const duplicate = input(); duplicate.append("state", token);
  assert.equal(parseBridgeInput(duplicate), null);
  const short = input(); short.set("code_challenge", "short");
  assert.equal(parseBridgeInput(short), null);
  const injected = input(); injected.set("state", "https://other.example/");
  assert.equal(parseBridgeInput(injected), null);
});

test("challenge requires 32-byte nonce and a future expiry", () => {
  const challenge = { id: "63c5d451-22ae-4d99-884a-32644c233284", message: "Sign in", nonce: Array(32).fill(0), recipient: "listener.example", expires_at: new Date(Date.now() + 60_000).toISOString() };
  assert.deepEqual(parseChallenge(challenge), challenge);
  assert.equal(parseChallenge({ ...challenge, nonce: [1] }), null);
  assert.equal(parseChallenge({ ...challenge, expires_at: new Date(Date.now() - 1).toISOString() }), null);
});

test("callback has fixed destination and only code plus state", () => {
  const callback = callbackURL(token, token);
  assert.equal(callback, `dachafm://auth/callback?code=${token}&state=${token}`);
  assert.equal(callbackURL("invalid", token), null);
  assert.equal(callbackURL(token, "https://evil.example"), null);
});
