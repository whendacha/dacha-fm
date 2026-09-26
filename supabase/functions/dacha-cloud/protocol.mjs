export const CLOUD_MESSAGE = 'Dacha FM cloud sign-in\nSign in to sync your favorites and playlists across your devices. No transaction or wallet permission is requested.';
export const RECIPIENT = 'whendacha.github.io';
export const MAX_BODY = 1_048_576;
const encoder = new TextEncoder();
export class HTTPError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
export function requireValue(value, status = 400, code = 'invalid_request') {
  if (!value) throw new HTTPError(status, code);
}
export function b64url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}
export function randomToken() { return b64url(crypto.getRandomValues(new Uint8Array(32))); }
export function decodeRandom(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(value)) return null;
  const bytes = Uint8Array.from(atob(value.replaceAll('-', '+').replaceAll('_', '/') + '='), x => x.charCodeAt(0));
  return bytes.length === 32 && b64url(bytes) === value ? bytes : null;
}
export async function digestHex(text) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(text)))].map(x => x.toString(16).padStart(2, '0')).join('');
}
export async function verifyPKCE(challenge, verifier) {
  if (typeof verifier !== 'string' || !/^[A-Za-z0-9._~-]{43,128}$/.test(verifier) || !decodeRandom(challenge)) return false;
  return b64url(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(verifier)))) === challenge;
}
function base58(value) {
  requireValue(typeof value === 'string' && value.length <= 44 && value.length > 0);
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  let n = 0n;
  for (const char of value) { const i = alphabet.indexOf(char); requireValue(i >= 0); n = n * 58n + BigInt(i); }
  const result = []; while (n > 0n) { result.unshift(Number(n & 255n)); n >>= 8n; }
  for (const char of value) { if (char !== '1') break; result.unshift(0); }
  requireValue(result.length === 32); return Uint8Array.from(result);
}
function nepDigestPayload(nonce) {
  const output = [];
  const u32 = n => output.push(n & 255, (n >>> 8) & 255, (n >>> 16) & 255, (n >>> 24) & 255);
  const string = x => { const bytes = encoder.encode(x); u32(bytes.length); output.push(...bytes); };
  u32(2147484061); string(CLOUD_MESSAGE); output.push(...nonce); string(RECIPIENT); output.push(0);
  return Uint8Array.from(output);
}
export async function verifyProof(challenge, proof) {
  requireValue(typeof proof.account_id === 'string' && proof.account_id.length >= 2 && proof.account_id.length <= 64 && /^[a-z0-9]+(?:[._-][a-z0-9]+)*$/.test(proof.account_id));
  const nonce = decodeRandom(challenge.nonce); requireValue(nonce);
  requireValue(typeof proof.public_key === 'string' && proof.public_key.startsWith('ed25519:'));
  const keyBytes = base58(proof.public_key.slice(8));
  requireValue(typeof proof.signature === 'string' && /^[A-Za-z0-9+/]{86}==$/.test(proof.signature));
  const signature = Uint8Array.from(atob(proof.signature), x => x.charCodeAt(0));
  requireValue(signature.length === 64 && btoa(String.fromCharCode(...signature)) === proof.signature);
  try {
    const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'Ed25519' }, false, ['verify']);
    const digest = await crypto.subtle.digest('SHA-256', nepDigestPayload(nonce));
    requireValue(await crypto.subtle.verify('Ed25519', key, signature, digest), 401, 'invalid_proof');
  } catch (error) {
    if (error instanceof HTTPError) throw error;
    throw new HTTPError(401, 'invalid_proof');
  }
  return proof.account_id;
}
function text(value, maximum, allowEmpty = false) {
  requireValue(typeof value === 'string'); const cleaned = value.trim();
  requireValue((allowEmpty || cleaned.length > 0) && [...cleaned].length <= maximum);
  return cleaned;
}
function mediaURL(value, optional = false) {
  if (optional && value == null) return null;
  requireValue(typeof value === 'string' && value.length <= 2048);
  let url; try { url = new URL(value); } catch { throw new HTTPError(400, 'invalid_media_url'); }
  const host = url.hostname.toLowerCase();
  requireValue(url.protocol === 'https:' && !url.username && !url.password && !url.port &&
    host.includes('.') && !host.endsWith('.') && !/^\d[\d.]*$/.test(host) && !host.includes(':') &&
    !['localhost', 'local', 'internal', 'test', 'invalid'].some(x => host === x || host.endsWith('.' + x)), 400, 'invalid_media_url');
  return url.href;
}
function track(value) {
  requireValue(value && typeof value === 'object' && !Array.isArray(value));
  const id = text(value.id, 64); requireValue(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id));
  const artist = text(value.artist_id, 20); requireValue(/^[0-9]+$/.test(artist));
  const duration = value.duration ?? null;
  requireValue(duration === null || (typeof duration === 'number' && Number.isFinite(duration) && duration >= 0 && duration <= 86400));
  return { id, title: text(value.title, 500), artist_id: artist, artist_name: text(value.artist_name, 200),
    audio_url: mediaURL(value.audio_url), artwork_url: mediaURL(value.artwork_url, true), duration };
}
export function normalizeLibrary(value) {
  requireValue(value && typeof value === 'object' && !Array.isArray(value));
  requireValue(Number.isSafeInteger(value.version) && value.version >= 0 && value.version < 2147483647);
  requireValue(Array.isArray(value.favorites) && value.favorites.length <= 2000 && Array.isArray(value.playlists) && value.playlists.length <= 100 && Array.isArray(value.blocked_artist_ids) && value.blocked_artist_ids.length <= 1000);
  const blocked = [...new Set(value.blocked_artist_ids.map(x => { requireValue(typeof x === 'string' && /^[0-9]{1,20}$/.test(x)); return x; }))].sort();
  const blockedSet = new Set(blocked);
  const tracks = items => {
    requireValue(Array.isArray(items) && items.length <= 2000); const seen = new Set();
    return items.map(track).filter(x => !blockedSet.has(x.artist_id) && !seen.has(x.id) && seen.add(x.id));
  };
  const seen = new Set(); let total = 0;
  const playlists = value.playlists.map(x => {
    requireValue(x && typeof x === 'object'); const id = text(x.id, 100);
    requireValue(/^[A-Za-z0-9_-]+$/.test(id) && !seen.has(id)); seen.add(id);
    requireValue(Array.isArray(x.tracks)); total += x.tracks.length; requireValue(total <= 10000);
    return { id, name: text(x.name, 100), tracks: tracks(x.tracks) };
  });
  return { version: value.version, favorites: tracks(value.favorites), playlists, blocked_artist_ids: blocked };
}
