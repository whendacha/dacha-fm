import { CLOUD_MESSAGE, RECIPIENT, MAX_BODY, HTTPError, requireValue, decodeRandom, randomToken, digestHex, verifyPKCE, verifyProof, normalizeLibrary } from './protocol.mjs';

const ORIGIN = 'https://whendacha.github.io';
const ROOT = '/api/mobile/v1/';
export async function boundedJSON(input, limit) {
  const size = Number(input.headers.get('Content-Length') ?? 0);
  requireValue(Number.isFinite(size) && size >= 0 && size <= limit, 413, 'body_too_large');
  requireValue(input.body, 400, 'invalid_json');
  const reader = input.body.getReader(); let sizeRead = 0; const chunks = [];
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      sizeRead += value.length;
      if (sizeRead > limit) { await reader.cancel(); throw new HTTPError(413, 'body_too_large'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const data = new Uint8Array(sizeRead); let offset = 0;
  for (const chunk of chunks) { data.set(chunk, offset); offset += chunk.length; }
  try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(data)); }
  catch { throw new HTTPError(400, 'invalid_json'); }
}
function exactFields(body, fields) {
  requireValue(body && typeof body === 'object' && !Array.isArray(body));
  requireValue(Object.keys(body).length === fields.length && fields.every(x => Object.hasOwn(body, x)));
}
async function ownedMainnetKey(proof, fetcher) {
  let response;
  try {
    response = await fetcher('https://rpc.mainnet.fastnear.com', {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(15000),
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 'dacha-cloud-key', method: 'query', params: {
        request_type: 'view_access_key', finality: 'final', account_id: proof.account_id, public_key: proof.public_key,
      } }),
    });
  } catch { throw new HTTPError(503, 'wallet_verification_unavailable'); }
  requireValue(response.status === 200, 503, 'wallet_verification_unavailable');
  let body; try { body = await boundedJSON(response, 131072); } catch { throw new HTTPError(503, 'wallet_verification_unavailable'); }
  requireValue(body?.jsonrpc === '2.0' && body.id === 'dacha-cloud-key' && !body.error && body.result?.permission === 'FullAccess', 401, 'unowned_key');
}
export function createHandler({ db, fetcher = fetch }) {
  return async function handle(request) {
    const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'X-Dacha-Cloud-Version': '1' };
    try {
      const origin = request.headers.get('Origin');
      requireValue(!origin || origin === ORIGIN, 403, 'origin_not_allowed');
      if (origin === ORIGIN) Object.assign(headers, { 'Access-Control-Allow-Origin': ORIGIN, Vary: 'Origin' });
      if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: { ...headers, 'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS', 'Access-Control-Allow-Headers': 'Authorization, Content-Type' } });
      const pathname = new URL(request.url).pathname;
      const start = pathname.indexOf(ROOT);
      requireValue(start >= 0 && ['/functions/v1/dacha-cloud', '/dacha-cloud', ''].includes(pathname.slice(0, start)), 404, 'not_found');
      const path = pathname.slice(start + ROOT.length);
      if (path === 'config' && request.method === 'GET') return Response.json({ meteor_enabled: true, apple_enabled: false, cloud_enabled: true, privacy_url: ORIGIN + '/dacha-fm/privacy.html', support_url: ORIGIN + '/dacha-fm/support.html' }, { headers });
      if (path === 'auth/meteor/challenge' && request.method === 'POST') {
        requireValue(request.headers.get('Content-Type')?.split(';')[0].trim() === 'application/json', 415, 'json_required');
        const body = await boundedJSON(request, 4096); exactFields(body, ['code_challenge']); requireValue(decodeRandom(body.code_challenge));
        requireValue((await db('dacha_cloud_auth_rate'))?.allowed === true, 429, 'rate_limited');
        const stored = await db('dacha_cloud_create_challenge', { p_id: crypto.randomUUID(), p_nonce: randomToken(), p_code_challenge: body.code_challenge });
        const nonce = decodeRandom(stored.nonce); requireValue(nonce, 503, 'service_unavailable');
        const expires = new Date(stored.expires_at); requireValue(Number.isFinite(expires.getTime()), 503, 'service_unavailable');
        return Response.json({ id: stored.id, nonce: [...nonce], message: CLOUD_MESSAGE, recipient: RECIPIENT, expires_at: expires.toISOString().replace(/\.\d{3}Z$/, 'Z') }, { headers });
      }
      if (path === 'auth/meteor/verify' && request.method === 'POST') {
        requireValue(request.headers.get('Content-Type')?.split(';')[0].trim() === 'application/json', 415, 'json_required');
        const body = await boundedJSON(request, 4096); exactFields(body, ['challenge_id', 'account_id', 'public_key', 'signature', 'code_verifier']);
        requireValue(typeof body.challenge_id === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.challenge_id));
        requireValue((await db('dacha_cloud_auth_rate'))?.allowed === true, 429, 'rate_limited');
        const challenge = await db('dacha_cloud_get_challenge', { p_id: body.challenge_id });
        requireValue(challenge && new Date(challenge.expires_at).getTime() > Date.now(), 401, 'invalid_challenge');
        requireValue(await verifyPKCE(challenge.code_challenge, body.code_verifier), 401, 'invalid_proof');
        const accountID = await verifyProof(challenge, body);
        await ownedMainnetKey(body, fetcher);
        const token = randomToken();
        const result = await db('dacha_cloud_finish_auth', { p_id: body.challenge_id, p_account_id: accountID, p_token_hash: await digestHex(token) });
        requireValue(result.account_id === accountID, 503, 'service_unavailable');
        return Response.json({ access_token: token, user_id: accountID, kind: 'verified-cloud-wallet' }, { headers });
      }
      const route = request.method + ' ' + path;
      requireValue(['GET library', 'PUT library', 'POST auth/logout', 'DELETE account'].includes(route), 404, 'not_found');
      const authorization = request.headers.get('Authorization') ?? '';
      requireValue(authorization.startsWith('Bearer ') && decodeRandom(authorization.slice(7)), 401, 'unauthorized');
      const hash = await digestHex(authorization.slice(7));
      if (route === 'GET library') return Response.json(await db('dacha_cloud_library_get', { p_token_hash: hash }), { headers });
      if (route === 'PUT library') {
        requireValue(request.headers.get('Content-Type')?.split(';')[0].trim() === 'application/json', 415, 'json_required');
        const snapshot = normalizeLibrary(await boundedJSON(request, MAX_BODY));
        return Response.json(await db('dacha_cloud_library_put', { p_token_hash: hash, p_snapshot: snapshot }), { headers });
      }
      await db(route === 'POST auth/logout' ? 'dacha_cloud_logout' : 'dacha_cloud_delete_account', { p_token_hash: hash });
      return new Response(null, { status: 204, headers });
    } catch (error) {
      const status = error instanceof HTTPError ? error.status : 503;
      const code = error instanceof HTTPError ? error.code : 'service_unavailable';
      if (status === 429) headers['Retry-After'] = '60';
      // Do not log requests, wallet proofs, bearer tokens or database errors.
      return Response.json({ error: code }, { status, headers });
    }
  };
}

export function createPostgrestRPC(url, secret, fetcher = fetch) {
  requireValue(typeof url === 'string' && url.startsWith('https://') && typeof secret === 'string' && secret.length > 0, 503, 'service_unavailable');
  return async (name, args = {}) => {
    requireValue(/^dacha_cloud_[a-z_]+$/.test(name), 503, 'service_unavailable');
    const headers = { 'Content-Type': 'application/json', apikey: secret };
    if (!secret.startsWith('sb_secret_')) headers.Authorization = 'Bearer ' + secret;
    let response;
    try { response = await fetcher(url + '/rest/v1/rpc/' + name, { method: 'POST', headers, body: JSON.stringify(args), redirect: 'error', signal: AbortSignal.timeout(15000) }); }
    catch { throw new HTTPError(503, 'service_unavailable'); }
    if (!response.ok) {
      const status = [400, 401, 409, 429].includes(response.status) ? response.status : 503;
      throw new HTTPError(status, ({400:'invalid_request',401:'unauthorized',409:'conflict',429:'rate_limited'})[status] ?? 'service_unavailable');
    }
    if (response.status === 204) return null;
    try { return await boundedJSON(response, MAX_BODY + 8192); } catch { throw new HTTPError(503, 'service_unavailable'); }
  };
}
