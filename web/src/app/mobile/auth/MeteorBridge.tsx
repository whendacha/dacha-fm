"use client";

import { useEffect, useRef, useState } from "react";
import { setupWalletSelector } from "@near-wallet-selector/core";
import type { Wallet } from "@near-wallet-selector/core";
import { setupMeteorWallet } from "@near-wallet-selector/meteor-wallet";
import { Buffer } from "buffer";
import { callbackURL, parseBridgeInput, parseChallenge } from "./protocol";
import type { Challenge } from "./protocol";

type Phase = "ready" | "preparing" | "prepared" | "signing" | "unavailable" | "cancelled" | "error";

async function post(operation: "challenge" | "verify", body: Record<string, unknown>): Promise<unknown> {
  const response = await fetch(`/mobile/auth/api/${operation}`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body), cache: "no-store",
  });
  const data: unknown = await response.json().catch(() => null);
  if (!response.ok) {
    const message = data && typeof data === "object" && "error" in data && typeof data.error === "string" ? data.error : "Sign-in failed";
    throw new Error(message);
  }
  return data;
}

export function MeteorBridge({ network, configured }: { network: "mainnet" | "testnet" | null; configured: boolean }) {
  const [input, setInput] = useState<ReturnType<typeof parseBridgeInput>>(null);
  const [phase, setPhase] = useState<Phase>(configured ? "ready" : "unavailable");
  const [detail, setDetail] = useState(configured ? "" : "Mobile sign-in is not configured on this site.");
  const prepared = useRef<{ wallet: Wallet; challenge: Challenge } | null>(null);
  const attempt = useRef(0);

  useEffect(() => {
    const parsed = parseBridgeInput(new URLSearchParams(window.location.search));
    setInput(parsed);
    if (!parsed) { setPhase("error"); setDetail("This sign-in link is invalid. Return to the app and try again."); }
  }, []);

  async function prepare() {
    if (!input || !network || phase === "preparing" || phase === "signing") return;
    const current = ++attempt.current;
    prepared.current = null;
    setPhase("preparing"); setDetail("Preparing a one-time identity challenge…");
    try {
      const selector = await setupWalletSelector({ network, modules: [setupMeteorWallet()] });
      if (attempt.current !== current) return;
      const wallet = await selector.wallet("meteor-wallet");
      if (attempt.current !== current) return;
      // The adapter's signIn requests contract access. Its signMessage forwards
      // an optional accountId to Meteor, so it can be called without signIn.
      if (!wallet.signMessage) {
        setPhase("unavailable"); setDetail("This Meteor wallet cannot sign identity messages."); return;
      }

      const challenge = parseChallenge(await post("challenge", { code_challenge: input.codeChallenge }));
      if (attempt.current !== current) return;
      if (!challenge) throw new Error("The identity challenge was invalid or expired.");
      prepared.current = { wallet, challenge };
      setPhase("prepared");
      setDetail("Ready. Tap below to open Meteor and approve the identity message.");
    } catch (error) {
      if (attempt.current !== current) return;
      setPhase("error");
      setDetail(error instanceof Error ? error.message : "Could not prepare Meteor sign-in.");
    }
  }

  async function sign() {
    const ready = prepared.current;
    if (!ready || !input || phase !== "prepared") return;
    const current = attempt.current;
    const { wallet, challenge } = ready;
    if (!wallet.signMessage) return;
    if (Date.parse(challenge.expires_at) <= Date.now() + 1000) {
      prepared.current = null;
      setPhase("error"); setDetail("The identity challenge expired. Prepare a new one.");
      return;
    }
    setPhase("signing");
    setDetail("Approve the identity message in Meteor. No transfer or contract permission is requested.");
    // Invoke the wallet before the first await in this click handler so its
    // popup retains browser user activation.
    const signaturePromise = wallet.signMessage({
        message: challenge.message,
        nonce: Buffer.from(challenge.nonce),
        recipient: challenge.recipient,
    });
    try {
      const signed = await signaturePromise;
      if (attempt.current !== current) return;
      if (!signed || !signed.accountId || !signed.publicKey || !signed.signature) {
        throw new Error("Meteor returned an incomplete identity signature.");
      }
      setDetail("Verifying your signature…");
      const verification = await post("verify", {
        challenge_id: challenge.id, account_id: signed.accountId,
        public_key: signed.publicKey, signature: signed.signature,
      });
      if (attempt.current !== current) return;
      if (!verification || typeof verification !== "object" || !("code" in verification) || typeof verification.code !== "string") throw new Error("Verification did not return a one-time code.");
      const target = callbackURL(verification.code, input.state);
      if (!target) throw new Error("Verification returned an invalid code.");
      window.location.assign(target);
    } catch (error) {
      if (attempt.current !== current) return;
      prepared.current = null;
      setPhase("error");
      setDetail(error instanceof Error ? error.message : "Meteor sign-in failed. Return to the app and try again.");
    }
  }

  function cancel() {
    ++attempt.current;
    prepared.current = null;
    setPhase("cancelled");
    setDetail("Sign-in cancelled. Return to the app to continue as a guest.");
    window.close();
  }

  return <div className="min-h-screen bg-[#0e0e15] text-white px-5 py-14 flex items-center justify-center">
    <section className="w-full max-w-md rounded-3xl border border-white/10 bg-[#1a1a27] p-7 shadow-2xl" aria-live="polite">
      <div className="text-sm font-semibold tracking-[0.2em] text-violet-300">DACHA FM</div>
      <h1 className="mt-6 text-3xl font-bold">Sign in with Meteor Wallet</h1>
      <p className="mt-4 leading-7 text-white/70">Confirm your Meteor Wallet account for your private listener library. Meteor will ask you to sign one identity message. This does not send funds or request contract access.</p>
      <p className="mt-6 min-h-12 text-sm leading-6 text-white/80" role="status">{detail}</p>
      {phase === "ready" || phase === "error" ? <button type="button" onClick={prepare} disabled={!input || !configured} className="mt-5 w-full rounded-xl bg-violet-500 px-5 py-3 font-semibold text-white hover:bg-violet-400 disabled:opacity-40">Prepare Meteor sign-in</button> : null}
      {phase === "prepared" ? <button type="button" onClick={sign} className="mt-5 w-full rounded-xl bg-violet-500 px-5 py-3 font-semibold text-white hover:bg-violet-400">Confirm identity in Meteor</button> : null}
      {phase === "preparing" || phase === "signing" ? <div className="mt-5 rounded-xl bg-violet-500/20 px-5 py-3 text-center">{phase === "preparing" ? "Preparing…" : "Waiting for Meteor…"}</div> : null}
      {phase !== "cancelled" ? <button type="button" onClick={cancel} className="mt-3 w-full rounded-xl border border-white/15 px-5 py-3 text-white/80 hover:bg-white/5">Cancel</button> : null}
      <p className="mt-6 text-xs leading-5 text-white/45">Never enter a recovery phrase here. The app receives only a short-lived sign-in code.</p>
    </section>
  </div>;
}
