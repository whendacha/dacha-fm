import { setupWalletSelector } from "@near-wallet-selector/core";
import { setupMeteorWallet } from "@near-wallet-selector/meteor-wallet";
import { Buffer } from "buffer";
import { parseInput, nonceBytes, callbackURL, attemptGate } from "./protocol.mjs";

const status = document.querySelector("#status");
const prepareButton = document.querySelector("#prepare");
const signButton = document.querySelector("#sign");
const cancelButton = document.querySelector("#cancel");
const returnLink = document.querySelector("#return");
const gate = attemptGate();
const input = parseInput(new URLSearchParams(window.location.search), window.location);
let wallet = null;
let token = 0;
let phase = "ready";
const expiresAt = Date.now() + 300_000;

function update(next, detail) {
  phase = next;
  status.textContent = detail;
  status.dataset.phase = phase;
  prepareButton.hidden = !input || !["ready", "error"].includes(phase);
  signButton.hidden = phase !== "prepared";
  cancelButton.hidden = ["cancelled", "complete"].includes(phase);
  prepareButton.disabled = phase !== "ready" && phase !== "error";
  signButton.disabled = phase !== "prepared";
}

if (!input) {
  update("invalid", "Open sign-in from Dacha FM on your iPhone. This link is missing a valid one-time request.");
} else {
  // Remove the challenge from browser history/referrers after parsing it. Its
  // exact values remain only in this page's memory for the current attempt.
  window.history.replaceState(null, "", window.location.pathname);
  update("ready", "Prepare the wallet, then confirm your identity in Meteor.");
}

prepareButton.addEventListener("click", async () => {
  if (!input || !["ready", "error"].includes(phase)) return;
  if (Date.now() >= expiresAt) { update("invalid", "This sign-in request expired. Open a new request from Dacha FM."); return; }
  token = gate.begin();
  const current = token;
  wallet = null;
  returnLink.hidden = true;
  update("preparing", "Preparing Meteor Wallet…");
  try {
    const selector = await setupWalletSelector({ network: "mainnet", modules: [setupMeteorWallet()] });
    if (!gate.current(current)) return;
    const candidate = await selector.wallet("meteor-wallet");
    if (!gate.current(current)) return;
    if (!candidate.signMessage) throw new Error("This version of Meteor cannot sign identity messages.");
    wallet = candidate;
    update("prepared", "Ready. Tap Confirm in Meteor to approve the identity message.");
  } catch (error) {
    if (!gate.current(current)) return;
    update("error", error instanceof Error ? error.message : "Meteor Wallet could not be prepared. Try again.");
  }
});

signButton.addEventListener("click", async () => {
  if (!input || !wallet?.signMessage || phase !== "prepared") return;
  if (Date.now() >= expiresAt) { update("invalid", "This sign-in request expired. Open a new request from Dacha FM."); return; }
  const current = token;
  let timeout;
  update("signing", "Approve the identity message in Meteor, then return here. No transaction or wallet permission is requested.");
  try {
    // No awaited work precedes this call: the wallet popup belongs to the
    // explicit button tap. Do not call signIn, which requests contract access.
    const pending = wallet.signMessage({ message: input.message, nonce: Buffer.from(nonceBytes(input.nonce)), recipient: input.recipient });
    const signed = await Promise.race([pending, new Promise((_, reject) => {
      timeout = setTimeout(() => reject(new Error("Meteor did not return an identity proof in time. Close its window, then try again from Dacha FM.")), Math.min(120_000, expiresAt - Date.now()));
    })]);
    if (!gate.current(current)) return;
    const callback = callbackURL(signed, input.state);
    if (!callback) throw new Error("Meteor returned an incomplete or invalid identity proof. Return to Dacha FM and try again.");
    returnLink.href = callback;
    returnLink.hidden = false;
    update("complete", "Identity proof received. Return to Dacha FM to verify your account on this device.");
    window.location.assign(callback);
  } catch (error) {
    if (!gate.current(current)) return;
    wallet = null;
    update("error", error instanceof Error ? error.message : "Meteor sign-in failed. Return to Dacha FM and try again.");
  } finally {
    clearTimeout(timeout);
  }
});

cancelButton.addEventListener("click", () => {
  gate.cancel();
  wallet = null;
  returnLink.hidden = true;
  returnLink.removeAttribute("href");
  update("cancelled", "Sign-in cancelled. Close this page to continue in Dacha FM as a guest.");
});

window.addEventListener("pagehide", () => { gate.cancel(); wallet = null; });
