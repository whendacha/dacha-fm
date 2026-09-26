import test from "node:test";
import assert from "node:assert/strict";
import { IDENTITY_MESSAGE, parseInput, nonceBytes, callbackURL, attemptGate } from "./protocol.mjs";

const state = "A".repeat(43);
const nonce = "B".repeat(42) + "A";
const location = new URL("https://whendacha.github.io/dacha-fm/mobile/auth/");
const parameters = () => new URLSearchParams({ mode: "identity", state, nonce, message: IDENTITY_MESSAGE, recipient: location.hostname });

test("accepts exact Dacha identity request with a canonical 32-byte nonce", () => {
  assert.deepEqual(parseInput(parameters(), location), { state, nonce, message: IDENTITY_MESSAGE, recipient: location.hostname });
  assert.equal(nonceBytes(nonce).length, 32);
});

test("rejects duplicate, missing, unknown and noncanonical inputs", () => {
  for (const field of ["mode", "state", "nonce", "message", "recipient"]) {
    const duplicate = parameters(); duplicate.append(field, duplicate.get(field));
    assert.equal(parseInput(duplicate, location), null);
    const missing = parameters(); missing.delete(field);
    assert.equal(parseInput(missing, location), null);
  }
  const unexpected = parameters(); unexpected.set("callback", "https://example.org");
  assert.equal(parseInput(unexpected, location), null);
  const invalid = parameters(); invalid.set("nonce", "A".repeat(42) + "B");
  assert.equal(parseInput(invalid, location), null);
  assert.throws(() => nonceBytes("short"));
});

test("does not sign arbitrary text or a request for a different recipient", () => {
  const message = parameters(); message.set("message", IDENTITY_MESSAGE + " additional content");
  assert.equal(parseInput(message, location), null);
  const recipient = parameters(); recipient.set("recipient", "another.example");
  assert.equal(parseInput(recipient, location), null);
  assert.equal(parseInput(parameters(), new URL("http://whendacha.github.io/dacha-fm/mobile/auth/")), null);
  assert.equal(parseInput(parameters(), new URL("https://whendacha.github.io:8443/dacha-fm/mobile/auth/")), null);
});

test("allows an explicitly local preview, retaining its actual recipient", () => {
  const local = new URL("http://localhost:8080/mobile/auth/");
  const query = parameters(); query.set("recipient", "localhost");
  assert.ok(parseInput(query, local));
  assert.equal(parseInput(parameters(), local), null);
});

test("fails closed on an unexpected page path or initial fragment", () => {
  for (const path of ["/", "/dacha-fm/mobile/auth/other", "/mobile/auth/", "/dacha-fm/mobile/auth/#extra", "/dacha-fm/mobile/%61uth/"]) {
    assert.equal(parseInput(parameters(), new URL(path, location.origin)), null);
  }
  assert.ok(parseInput(parameters(), new URL("/dacha-fm/mobile/auth", location.origin)));
});

test("returns only bounded proof fields to the fixed app destination in fragment", () => {
  const signed = { accountId: "listener.near", publicKey: "ed25519:" + "1".repeat(32), signature: "A".repeat(86) + "==" };
  const callback = new URL(callbackURL(signed, state));
  assert.equal(callback.protocol, "dachafm:");
  assert.equal(callback.host, "auth");
  assert.equal(callback.pathname, "/callback");
  assert.equal(callback.search, "");
  const proof = new URLSearchParams(callback.hash.slice(1));
  assert.deepEqual([...proof.keys()], ["mode", "state", "account_id", "public_key", "signature"]);
  assert.equal(proof.get("signature"), signed.signature);
  for (const change of [{ accountId: "../evil" }, { accountId: "A.NEAR" }, { publicKey: "bad" }, { signature: "short" }, { signature: "A".repeat(85) + "B==" }]) {
    assert.equal(callbackURL({ ...signed, ...change }, state), null);
  }
  assert.equal(callbackURL(signed, "http://evil"), null);
});

test("cancellation and restart prevent an earlier sign-in from redirecting", () => {
  const gate = attemptGate();
  const first = gate.begin();
  assert.ok(gate.current(first));
  gate.cancel();
  assert.equal(gate.current(first), false);
  const second = gate.begin();
  assert.ok(gate.current(second));
  assert.equal(gate.current(first), false);
});
