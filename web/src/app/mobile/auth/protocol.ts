const base64url32 = /^[A-Za-z0-9_-]{43}$/;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type BridgeInput = { codeChallenge: string; state: string };
export type Challenge = {
  id: string;
  message: string;
  nonce: number[];
  recipient: string;
  expires_at: string;
};

export function parseBridgeInput(query: URLSearchParams): BridgeInput | null {
  const challenges = query.getAll("code_challenge");
  const states = query.getAll("state");
  if (challenges.length !== 1 || states.length !== 1) return null;
  if (!base64url32.test(challenges[0]) || !base64url32.test(states[0])) return null;
  return { codeChallenge: challenges[0], state: states[0] };
}

export function parseChallenge(value: unknown): Challenge | null {
  if (!value || typeof value !== "object") return null;
  const v = value as Record<string, unknown>;
  if (typeof v.id !== "string" || !uuid.test(v.id)) return null;
  if (typeof v.message !== "string" || !v.message || v.message.length > 1000) return null;
  if (!Array.isArray(v.nonce) || v.nonce.length !== 32 || !v.nonce.every((x) => Number.isInteger(x) && x >= 0 && x <= 255)) return null;
  if (typeof v.recipient !== "string" || !v.recipient || v.recipient.length > 255) return null;
  if (typeof v.expires_at !== "string" || !Number.isFinite(Date.parse(v.expires_at)) || Date.parse(v.expires_at) <= Date.now()) return null;
  return v as Challenge;
}

export function callbackURL(code: string, state: string): string | null {
  if (!base64url32.test(code) || !base64url32.test(state)) return null;
  const url = new URL("dachafm://auth/callback");
  url.searchParams.set("code", code);
  url.searchParams.set("state", state);
  return url.toString();
}
